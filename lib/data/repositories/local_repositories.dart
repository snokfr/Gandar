import 'package:drift/drift.dart';

import '../../domain/models/cache_entry.dart';
import '../../domain/models/play_record.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../domain/repositories/repositories.dart';
import '../storage/app_database.dart';

/// Splits/joins the newline-separated artist list stored in SQLite.
String _joinArtists(List<String> artists) =>
    artists.where((a) => a.isNotEmpty).join('\n');

List<String> _splitArtists(String raw) =>
    raw.isEmpty ? const [] : raw.split('\n');

Track _rowToTrack(TrackRow row) => Track(
  id: row.id,
  title: row.title,
  artists: _splitArtists(row.artists),
  album: row.album,
  durationMs: row.durationMs,
  artworkUrl: row.artworkUrl,
  isrc: row.isrc,
  addedAt: row.addedAt,
);

/// Permanently remembers Spotify -> YouTube mappings.
class DriftMappingRepository implements MappingRepository {
  DriftMappingRepository(this._db);
  final AppDatabase _db;

  @override
  Future<String?> findVideoId(String spotifyTrackId) async {
    final row = await (_db.select(
      _db.mappings,
    )..where((t) => t.spotifyTrackId.equals(spotifyTrackId))).getSingleOrNull();
    return row?.videoId;
  }

  @override
  Future<void> saveMapping(String spotifyTrackId, String videoId) async {
    await _db
        .into(_db.mappings)
        .insertOnConflictUpdate(
          MappingsCompanion.insert(
            spotifyTrackId: spotifyTrackId,
            videoId: videoId,
            createdAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> clearMapping(String spotifyTrackId) async {
    await (_db.delete(
      _db.mappings,
    )..where((t) => t.spotifyTrackId.equals(spotifyTrackId))).go();
  }
}

/// Tracks cached audio files for LRU eviction.
class DriftCacheRepository implements CacheRepository {
  DriftCacheRepository(this._db);
  final AppDatabase _db;

  CacheEntry _toEntry(CacheEntryRow r) => CacheEntry(
    videoId: r.videoId,
    filePath: r.filePath,
    sizeBytes: r.sizeBytes,
    lastPlayedAt: r.lastPlayedAt,
  );

  @override
  Future<List<CacheEntry>> all() async {
    final rows = await _db.select(_db.cacheEntries).get();
    return rows.map(_toEntry).toList(growable: false);
  }

  @override
  Future<CacheEntry?> find(String videoId) async {
    final row = await (_db.select(
      _db.cacheEntries,
    )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  @override
  Future<void> put(CacheEntry entry) async {
    await _db
        .into(_db.cacheEntries)
        .insertOnConflictUpdate(
          CacheEntriesCompanion.insert(
            videoId: entry.videoId,
            filePath: entry.filePath,
            sizeBytes: Value(entry.sizeBytes),
            lastPlayedAt: entry.lastPlayedAt,
          ),
        );
  }

  @override
  Future<void> touch(String videoId, DateTime at) async {
    await (_db.update(_db.cacheEntries)
          ..where((t) => t.videoId.equals(videoId)))
        .write(CacheEntriesCompanion(lastPlayedAt: Value(at)));
  }

  @override
  Future<void> remove(String videoId) async {
    await (_db.delete(
      _db.cacheEntries,
    )..where((t) => t.videoId.equals(videoId))).go();
  }
}

/// Offline-first cache of Spotify library metadata.
class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);
  final AppDatabase _db;

  @override
  Future<void> upsertTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(
        _db.tracks,
        tracks
            .map(
              (t) => TracksCompanion.insert(
                id: t.id,
                title: t.title,
                artists: _joinArtists(t.artists),
                album: Value(t.album),
                durationMs: Value(t.durationMs),
                artworkUrl: Value(t.artworkUrl),
                isrc: Value(t.isrc),
                addedAt: Value(t.addedAt),
                cachedAt: now,
              ),
            )
            .toList(),
      );
    });
  }

  /// The local library, most recently liked first.
  ///
  /// Ordering by `addedAt` (not by when the row was written) is what makes the
  /// order stable and identical to Spotify's: every row in one sync batch
  /// shares a `cachedAt`, so ordering by that was effectively random.
  @override
  Future<List<Track>> cachedLikedTracks() async {
    final rows =
        await (_db.select(_db.tracks)..orderBy([
              (t) => OrderingTerm.desc(t.addedAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return rows.map(_rowToTrack).toList(growable: false);
  }

  @override
  Future<void> upsertPlaylists(List<Playlist> playlists) async {
    if (playlists.isEmpty) return;
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(
        _db.playlists,
        playlists
            .map(
              (pl) => PlaylistsCompanion.insert(
                id: pl.id,
                name: pl.name,
                description: Value(pl.description),
                trackCount: Value(pl.trackCount),
                artworkUrl: Value(pl.artworkUrl),
                ownerName: Value(pl.ownerName),
                isCollaborative: Value(pl.isCollaborative),
                cachedAt: now,
              ),
            )
            .toList(),
      );
    });
  }

  @override
  Future<List<Playlist>> cachedPlaylists() async {
    final rows = await (_db.select(
      _db.playlists,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return rows
        .map(
          (r) => Playlist(
            id: r.id,
            name: r.name,
            description: r.description,
            trackCount: r.trackCount,
            artworkUrl: r.artworkUrl,
            ownerName: r.ownerName,
            isCollaborative: r.isCollaborative,
            isLocal: r.isLocal,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final clean = name.trim().isEmpty ? 'New playlist' : name.trim();
    final now = DateTime.now();
    // A plain, URL-safe id. It becomes a path segment (`/playlists/<id>`), so a
    // colon would have to be escaped on every navigation; a `local-` prefix
    // keeps it recognisable and makes a collision with Spotify's 22-character
    // ids impossible by construction.
    final id = '${Playlist.localPrefix}${now.microsecondsSinceEpoch}';
    await _db.into(_db.playlists).insert(
      PlaylistsCompanion.insert(
        id: id,
        name: clean,
        cachedAt: now,
        isLocal: const Value(true),
      ),
    );
    return Playlist(id: id, name: clean, isLocal: true);
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    await (_db.update(
      _db.playlists,
    )..where((t) => t.id.equals(playlistId))).write(
      PlaylistsCompanion(name: Value(clean), cachedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    // Only the membership rows go. A playlist is a view over the library, so
    // deleting one must leave every track it pointed at exactly where it was.
    await _db.transaction(() async {
      await (_db.delete(
        _db.playlistTracks,
      )..where((t) => t.playlistId.equals(playlistId))).go();
      await (_db.delete(
        _db.playlists,
      )..where((t) => t.id.equals(playlistId))).go();
    });
  }

  @override
  Future<bool> addTrackToPlaylist(String playlistId, String trackId) async {
    final existing =
        await (_db.select(_db.playlistTracks)..where(
              (t) =>
                  t.playlistId.equals(playlistId) & t.trackId.equals(trackId),
            ))
            .getSingleOrNull();
    if (existing != null) return false;

    final now = DateTime.now();
    await _db.transaction(() async {
      final current = await (_db.select(
        _db.playlistTracks,
      )..where((t) => t.playlistId.equals(playlistId))).get();
      // Append past the highest position rather than using `length`, so a
      // playlist whose positions have gaps (after a removal) still appends at
      // the end instead of overwriting a row's position.
      final next = current.fold<int>(-1, (max, row) {
        return row.position > max ? row.position : max;
      });
      await _db
          .into(_db.playlistTracks)
          .insert(
            PlaylistTracksCompanion.insert(
              playlistId: playlistId,
              trackId: trackId,
              position: next + 1,
              cachedAt: now,
            ),
          );
      await (_db.update(
        _db.playlists,
      )..where((t) => t.id.equals(playlistId))).write(
        PlaylistsCompanion(
          trackCount: Value(current.length + 1),
          cachedAt: Value(now),
        ),
      );
    });
    return true;
  }

  @override
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(_db.playlistTracks)..where(
            (t) =>
                t.playlistId.equals(playlistId) & t.trackId.equals(trackId),
          ))
          .go();

      // Renumber what is left so positions stay contiguous. The order query
      // sorts by position, so a gap is harmless to read but would let a later
      // append land in the middle.
      final rows =
          await (_db.select(_db.playlistTracks)
                ..where((t) => t.playlistId.equals(playlistId))
                ..orderBy([(t) => OrderingTerm.asc(t.position)]))
              .get();
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].position == i) continue;
        await (_db.update(_db.playlistTracks)..where(
              (t) =>
                  t.playlistId.equals(playlistId) &
                  t.trackId.equals(rows[i].trackId),
            ))
            .write(PlaylistTracksCompanion(position: Value(i)));
      }

      await (_db.update(
        _db.playlists,
      )..where((t) => t.id.equals(playlistId))).write(
        PlaylistsCompanion(
          trackCount: Value(rows.length),
          cachedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> replacePlaylistTracks(
    String playlistId,
    List<Track> tracks,
  ) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      // The tracks themselves first: the join rows point at them.
      await upsertTracks(tracks);
      await (_db.delete(
        _db.playlistTracks,
      )..where((t) => t.playlistId.equals(playlistId))).go();
      if (tracks.isEmpty) return;
      await _db.batch((b) {
        b.insertAll(_db.playlistTracks, [
          for (var i = 0; i < tracks.length; i++)
            PlaylistTracksCompanion.insert(
              playlistId: playlistId,
              trackId: tracks[i].id,
              position: i,
              cachedAt: now,
            ),
        ]);
      });
      await (_db.update(
        _db.playlists,
      )..where((t) => t.id.equals(playlistId))).write(
        PlaylistsCompanion(
          trackCount: Value(tracks.length),
          cachedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<List<Track>> cachedPlaylistTracks(String playlistId) async {
    final query = _db.select(_db.playlistTracks).join([
      innerJoin(
        _db.tracks,
        _db.tracks.id.equalsExp(_db.playlistTracks.trackId),
      ),
    ])..where(_db.playlistTracks.playlistId.equals(playlistId));
    query.orderBy([OrderingTerm.asc(_db.playlistTracks.position)]);

    final rows = await query.get();
    return rows
        .map((row) => _rowToTrack(row.readTable(_db.tracks)))
        .toList(growable: false);
  }

  @override
  Future<List<Track>> tracksMissingArtwork({int limit = 500}) async {
    final rows =
        await (_db.select(_db.tracks)
              ..where((t) => t.artworkUrl.isNull() | t.artworkUrl.equals(''))
              ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
              ..limit(limit))
            .get();
    return rows.map(_rowToTrack).toList(growable: false);
  }

  /// The first stored cover for a track on [album].
  ///
  /// Album names are matched exactly, which is deliberate: it is the same rule
  /// [Album.group] uses to build the Albums tab, so a cover the enricher
  /// borrows here is one the album view would have shown anyway.
  @override
  Future<String?> cachedArtworkForAlbum(String album) async {
    final name = album.trim();
    if (name.isEmpty) return null;
    // Bounded: an album with no cover is not worth scanning the whole table
    // for, and any of the first rows with a cover is as good as another.
    final rows =
        await (_db.select(_db.tracks)
              ..where((t) => t.album.equals(name) & t.artworkUrl.isNotNull())
              ..limit(20))
            .get();
    for (final row in rows) {
      final url = row.artworkUrl;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// Play history joined with cached durations, oldest first.
  ///
  /// A left join means a play of a track that is no longer cached still counts;
  /// its duration is reported as 0 and the savings view says so.
  @override
  Future<List<PlayRecord>> playHistory() async {
    final query = _db.select(_db.playHistory).join([
      leftOuterJoin(
        _db.tracks,
        _db.tracks.id.equalsExp(_db.playHistory.trackId),
      ),
    ])..orderBy([OrderingTerm.asc(_db.playHistory.playedAt)]);

    final rows = await query.get();
    return rows
        .map(
          (row) => PlayRecord(
            trackId: row.read(_db.playHistory.trackId) ?? '',
            playedAt: row.read(_db.playHistory.playedAt) ?? DateTime.now(),
            durationMs: row.read(_db.tracks.durationMs) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  /// Removes a track and its playlist memberships.
  ///
  /// Play history is deliberately left alone: the savings view counts what was
  /// played, and deleting a track should not rewrite that past. A history row
  /// whose track is gone reports a zero duration, which the stats already
  /// handle.
  @override
  Future<void> removeTrack(String trackId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.playlistTracks,
      )..where((t) => t.trackId.equals(trackId))).go();
      await (_db.delete(_db.tracks)..where((t) => t.id.equals(trackId))).go();
    });
  }

  @override
  Future<void> recordPlay(String trackId, DateTime at) async {
    await _db
        .into(_db.playHistory)
        .insert(PlayHistoryCompanion.insert(trackId: trackId, playedAt: at));
  }

  @override
  Future<List<String>> recentTrackIds({int limit = 50}) async {
    final rows =
        await (_db.select(_db.playHistory)
              ..orderBy([(t) => OrderingTerm.desc(t.playedAt)])
              ..limit(limit))
            .get();
    final seen = <String>{};
    final out = <String>[];
    for (final r in rows) {
      if (seen.add(r.trackId)) out.add(r.trackId);
    }
    return out;
  }
}
