import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/storage/app_directory.dart';

part 'app_database.g.dart';

/// Cached Spotify track metadata.
///
/// Indexed on `addedAt` because the library is always read newest-liked first,
/// and on `title` for the local search box.
@DataClassName('TrackRow')
@TableIndex(name: 'idx_tracks_added_at', columns: {#addedAt})
@TableIndex(name: 'idx_tracks_title', columns: {#title})
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artists => text()(); // newline-separated
  TextColumn get album => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get artworkUrl => text().nullable()();
  TextColumn get isrc => text().nullable()();
  DateTimeColumn get addedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached Spotify playlist summaries.
@DataClassName('PlaylistRow')
@TableIndex(name: 'idx_playlists_name', columns: {#name})
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  TextColumn get artworkUrl => text().nullable()();
  TextColumn get ownerName => text().nullable()();
  BoolColumn get isCollaborative =>
      boolean().withDefault(const Constant(false))();

  /// True for a playlist made inside Gandar, false for one read from a
  /// Spotify link or an exported file.
  ///
  /// The distinction is what lets the UI be honest about deleting: dropping a
  /// local playlist really does destroy it, while dropping an imported one
  /// only forgets a local copy of something that still exists on Spotify.
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tracks belonging to a locally imported playlist, in playlist order.
///
/// A playlist link is read once, at import time. The order it had then is the
/// order stored here, so the same playlist opens the same way offline, on a
/// later launch, or after whoever owns it edits it.
@DataClassName('PlaylistTrackRow')
@TableIndex(name: 'idx_playlist_tracks_playlist', columns: {#playlistId})
class PlaylistTracks extends Table {
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();

  /// Zero-based position in the playlist.
  IntColumn get position => integer()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

/// Permanent Spotify track id -> YouTube video id mapping.
///
/// This is the "instant playback" table: once resolved, a song never needs a
/// YouTube search again.
@DataClassName('MappingRow')
class Mappings extends Table {
  TextColumn get spotifyTrackId => text()();
  TextColumn get videoId => text()();
  TextColumn get container => text().withDefault(const Constant('m4a'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {spotifyTrackId};
}

/// Cached audio files on disk, ordered for LRU eviction.
@DataClassName('CacheEntryRow')
@TableIndex(name: 'idx_cache_last_played', columns: {#lastPlayedAt})
class CacheEntries extends Table {
  TextColumn get videoId => text()();
  TextColumn get filePath => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {videoId};
}

/// Play interaction history.
///
/// Indexed by track (smart shuffle looks up recent ids) and by time (the
/// savings view and recent-history queries scan a window).
@DataClassName('PlayHistoryRow')
@TableIndex(name: 'idx_history_track', columns: {#trackId})
@TableIndex(name: 'idx_history_played_at', columns: {#playedAt})
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text()();
  DateTimeColumn get playedAt => dateTime()();
}

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    PlaylistTracks,
    Mappings,
    CacheEntries,
    PlayHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test/desktop constructor for an explicit executor (e.g. in-memory).
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 4;

  /// Indexes introduced in v2, using the generated statements so the migration
  /// cannot drift from the schema definition.
  List<Index> get _v2Indexes => <Index>[
    idxTracksAddedAt,
    idxTracksTitle,
    idxPlaylistsName,
    idxCacheLastPlayed,
    idxHistoryTrack,
    idxHistoryPlayedAt,
  ];

  /// The names sqlite itself has on record for entities of [type] (`table`,
  /// `index`, `view`), read from the file rather than assumed from the version
  /// number. See [migration] for why that matters.
  Future<Set<String>> _existing(String type) async {
    final rows = await customSelect(
      'SELECT name FROM sqlite_master WHERE type = ?',
      variables: [Variable<String>(type)],
    ).get();
    return {for (final row in rows) row.read<String>('name')};
  }

  /// The columns [table] actually has right now, per `PRAGMA table_info`.
  Future<Set<String>> _columnsOf(String table) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return {for (final row in rows) row.read<String>('name')};
  }

  /// Creates [index] unless the file already has an index of that name.
  ///
  /// `CREATE INDEX` is not a no-op when the index exists, it is an error, so
  /// every index an upgrade creates goes through here. A failure is logged and
  /// swallowed: a missing index costs speed, never correctness, and an upgrade
  /// must never be left half-applied over one.
  Future<void> _createIndexIfMissing(
    Migrator m,
    Index index,
    Set<String> existing,
  ) async {
    if (existing.contains(index.entityName)) return;
    try {
      await m.createIndex(index);
    } catch (e) {
      AppLogger.instance.warn(
        'database',
        'could not create ${index.entityName}',
        error: e,
      );
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      AppLogger.instance.info('database', 'created schema v$schemaVersion');
    },
    onUpgrade: (m, from, to) async {
      AppLogger.instance.info('database', 'upgrading schema v$from -> v$to');

      // Every step below checks what the file already contains instead of
      // trusting `from` alone.
      //
      // A version number only moves once the upgrade as a whole has finished,
      // so one that dies part-way leaves work it already did to be repeated on
      // the next launch — and neither `ALTER TABLE ... ADD COLUMN` nor
      // `CREATE INDEX` is a no-op when its result is already there. That is
      // exactly how a single interrupted launch used to leave the library
      // permanently unopenable with 'duplicate column name: is_local': the
      // column was in the file, the version still said 3, and the upgrade
      // failed the same way every time. Reading the schema makes each step
      // safe to repeat, so a half-applied upgrade converges instead of
      // wedging.
      final tables = await _existing('table');
      final indexes = await _existing('index');

      if (from < 2) {
        // v2 adds indexes only: no table or column changes, so an existing
        // cache, mapping table and play history are all preserved.
        for (final index in _v2Indexes) {
          await _createIndexIfMissing(m, index, indexes);
        }
      }
      if (from < 3 && !tables.contains('playlist_tracks')) {
        // v3 adds the local playlist track list, used by imports. Additive:
        // existing tracks, mappings, cache entries and history are untouched.
        await m.createTable(playlistTracks);
      }
      // The index over that table, whether it was just created or was already
      // there. The [tables] snapshot above predates the `CREATE TABLE`, so it
      // cannot answer that on its own.
      await _createIndexIfMissing(m, idxPlaylistTracksPlaylist, indexes);
      if (from < 4) {
        // v4 marks which playlists the user made here. Additive: every
        // existing playlist defaults to false, i.e. imported, which is what
        // everything stored before this version was.
        final columns = await _columnsOf('playlists');
        if (!columns.contains('is_local')) {
          await m.addColumn(playlists, playlists.isLocal);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // WAL plus NORMAL sync is the standard fast-but-safe pairing for a local
      // database: writes stop blocking reads, which matters while the syncer
      // is bulk-inserting a library during playback.
      try {
        final mode = await customSelect('PRAGMA journal_mode=WAL')
            .getSingleOrNull();
        await customStatement('PRAGMA synchronous=NORMAL');
        AppLogger.instance.debug(
          'database',
          'journal_mode=${mode?.data.values.first} '
              'version=${details.versionNow}',
        );
      } catch (e) {
        AppLogger.instance.warn('database', 'pragmas not applied', error: e);
      }
    },
  );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    // [AppDirectory] rather than `getApplicationSupportDirectory`: the lookup
    // throws on this machine often enough that an unguarded call meant the
    // whole library failed to open. See [AppDirectory].
    final dir = await AppDirectory.support();
    final file = File(p.join(dir.path, 'gandar.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
