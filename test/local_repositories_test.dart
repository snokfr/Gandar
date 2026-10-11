import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/domain/models/cache_entry.dart';
import 'package:gandar/domain/models/playlist.dart';
import 'package:gandar/domain/models/track.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('DriftMappingRepository', skip: sqliteSkipReason, () {
    test('stores and retrieves a Spotify -> YouTube mapping', () async {
      final repo = DriftMappingRepository(db);
      expect(await repo.findVideoId('sp1'), isNull);

      await repo.saveMapping('sp1', 'yt1');
      expect(await repo.findVideoId('sp1'), 'yt1');
    });

    test('upsert replaces the mapping for the same track', () async {
      final repo = DriftMappingRepository(db);
      await repo.saveMapping('sp1', 'yt1');
      await repo.saveMapping('sp1', 'yt2');
      expect(await repo.findVideoId('sp1'), 'yt2');
      expect(await db.select(db.mappings).get(), hasLength(1));
    });

    test('clearMapping removes it', () async {
      final repo = DriftMappingRepository(db);
      await repo.saveMapping('sp1', 'yt1');
      await repo.clearMapping('sp1');
      expect(await repo.findVideoId('sp1'), isNull);
    });
  });

  group('DriftCacheRepository', skip: sqliteSkipReason, () {
    CacheEntry entry(String id, int bytes) => CacheEntry(
      videoId: id,
      filePath: '/cache/$id.m4a',
      sizeBytes: bytes,
      lastPlayedAt: DateTime(2026, 1, 1),
    );

    test('put/find/all round-trip', () async {
      final repo = DriftCacheRepository(db);
      await repo.put(entry('a', 100));
      await repo.put(entry('b', 200));

      expect((await repo.find('a'))!.sizeBytes, 100);
      expect(await repo.all(), hasLength(2));
    });

    test('touch updates lastPlayedAt without changing the file', () async {
      final repo = DriftCacheRepository(db);
      await repo.put(entry('a', 100));
      final later = DateTime(2026, 6, 1);
      await repo.touch('a', later);

      final updated = await repo.find('a');
      expect(updated!.lastPlayedAt, later);
      expect(updated.filePath, '/cache/a.m4a');
      expect(updated.sizeBytes, 100);
    });

    test('remove deletes the row', () async {
      final repo = DriftCacheRepository(db);
      await repo.put(entry('a', 100));
      await repo.remove('a');
      expect(await repo.find('a'), isNull);
    });

    test('put is an upsert', () async {
      final repo = DriftCacheRepository(db);
      await repo.put(entry('a', 100));
      await repo.put(entry('a', 500));
      expect((await repo.find('a'))!.sizeBytes, 500);
      expect(await repo.all(), hasLength(1));
    });
  });

  group('DriftLibraryRepository', skip: sqliteSkipReason, () {
    test('upserts and reads back tracks with their artists intact', () async {
      final repo = DriftLibraryRepository(db);
      await repo.upsertTracks([
        const Track(
          id: 't1',
          title: 'Song',
          artists: ['Artist A', 'Artist B'],
          album: 'Album',
          durationMs: 1234,
          artworkUrl: 'https://img.test/a.jpg',
          isrc: 'ISRC1',
        ),
      ]);

      final cached = await repo.cachedLikedTracks();
      expect(cached, hasLength(1));
      expect(cached.single.title, 'Song');
      expect(cached.single.artists, ['Artist A', 'Artist B']);
      expect(cached.single.album, 'Album');
      expect(cached.single.durationMs, 1234);
      expect(cached.single.isrc, 'ISRC1');
    });

    test('re-upserting the same track does not duplicate it', () async {
      final repo = DriftLibraryRepository(db);
      await repo.upsertTracks([const Track(id: 't1', title: 'A', artists: [])]);
      await repo.upsertTracks([const Track(id: 't1', title: 'B', artists: [])]);

      final cached = await repo.cachedLikedTracks();
      expect(cached, hasLength(1));
      expect(cached.single.title, 'B');
    });

    test('upserts playlists and sorts them by name', () async {
      final repo = DriftLibraryRepository(db);
      await repo.upsertPlaylists([
        const Playlist(id: 'p2', name: 'Zed'),
        const Playlist(id: 'p1', name: 'Alpha', trackCount: 3),
      ]);

      final playlists = await repo.cachedPlaylists();
      expect(playlists.map((p) => p.name), ['Alpha', 'Zed']);
      expect(playlists.first.trackCount, 3);
    });

    test(
      'records play history and returns distinct recent track ids',
      () async {
        final repo = DriftLibraryRepository(db);
        await repo.recordPlay('t1', DateTime(2026, 1, 1));
        await repo.recordPlay('t2', DateTime(2026, 1, 3));
        await repo.recordPlay('t1', DateTime(2026, 1, 2));

        final recent = await repo.recentTrackIds(limit: 10);
        expect(recent, ['t2', 't1']);
        expect(recent.toSet().length, recent.length);
      },
    );

    test('playHistory joins cached durations, oldest first', () async {
      final repo = DriftLibraryRepository(db);
      await repo.upsertTracks([
        const Track(id: 't1', title: 'One', artists: ['A'], durationMs: 200000),
        const Track(id: 't2', title: 'Two', artists: ['B'], durationMs: 0),
      ]);
      await repo.recordPlay('t2', DateTime(2026, 1, 3));
      await repo.recordPlay('t1', DateTime(2026, 1, 1));
      // A play of a track that is not cached still counts.
      await repo.recordPlay('gone', DateTime(2026, 1, 2));

      final history = await repo.playHistory();

      expect(history.map((r) => r.trackId).toList(), ['t1', 'gone', 't2']);
      expect(history.first.durationMs, 200000);
      expect(history[1].durationMs, 0, reason: 'unknown duration');
    });

    test('cached tracks come back most recently liked first', () async {
      final repo = DriftLibraryRepository(db);
      // All three rows are written in one batch, so they share a cachedAt:
      // ordering can only come from addedAt.
      await repo.upsertTracks([
        Track(
          id: 'old',
          title: 'Oldest',
          artists: const ['A'],
          addedAt: DateTime(2026, 1, 1),
        ),
        Track(
          id: 'new',
          title: 'Newest',
          artists: const ['A'],
          addedAt: DateTime(2026, 3, 1),
        ),
        Track(
          id: 'mid',
          title: 'Middle',
          artists: const ['A'],
          addedAt: DateTime(2026, 2, 1),
        ),
      ]);

      final cached = await repo.cachedLikedTracks();
      expect(cached.map((t) => t.id).toList(), ['new', 'mid', 'old']);
    });

    test('recentTrackIds respects the limit', () async {
      final repo = DriftLibraryRepository(db);
      for (var i = 0; i < 5; i++) {
        await repo.recordPlay('t$i', DateTime(2026, 1, 1 + i));
      }
      expect(await repo.recentTrackIds(limit: 2), ['t4', 't3']);
    });

    test('empty input is a no-op', () async {
      final repo = DriftLibraryRepository(db);
      await repo.upsertTracks(const []);
      await repo.upsertPlaylists(const []);
      expect(await repo.cachedLikedTracks(), isEmpty);
      expect(await repo.cachedPlaylists(), isEmpty);
    });
  });

  group('making your own playlists', skip: sqliteSkipReason, () {
    Track song(String id, {String? album}) => Track(
      id: id,
      title: 'Song $id',
      artists: const ['An Artist'],
      album: album,
      addedAt: DateTime(2026, 1, 1),
    );

    test('a new playlist is empty, local and listed', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('Late Night');

      expect(playlist.name, 'Late Night');
      expect(playlist.isLocal, isTrue);
      expect(await repo.cachedPlaylistTracks(playlist.id), isEmpty);

      final all = await repo.cachedPlaylists();
      expect(all.single.name, 'Late Night');
      // The isLocal flag has to survive the round-trip through SQLite, or every
      // playlist would look imported after a restart.
      expect(all.single.isLocal, isTrue);
    });

    test('a blank name still produces a usable playlist', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('   ');
      expect(playlist.name, 'New playlist');
    });

    test('songs are appended in the order they were added', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('Order');
      await repo.upsertTracks([song('a'), song('b'), song('c')]);

      expect(await repo.addTrackToPlaylist(playlist.id, 'a'), isTrue);
      expect(await repo.addTrackToPlaylist(playlist.id, 'b'), isTrue);
      expect(await repo.addTrackToPlaylist(playlist.id, 'c'), isTrue);

      final tracks = await repo.cachedPlaylistTracks(playlist.id);
      expect(tracks.map((t) => t.id).toList(), ['a', 'b', 'c']);
      expect((await repo.cachedPlaylists()).single.trackCount, 3);
    });

    test('adding the same song twice is a no-op, not a duplicate', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('Once');
      await repo.upsertTracks([song('a')]);

      expect(await repo.addTrackToPlaylist(playlist.id, 'a'), isTrue);
      expect(await repo.addTrackToPlaylist(playlist.id, 'a'), isFalse);
      expect(await repo.cachedPlaylistTracks(playlist.id), hasLength(1));
    });

    test('removing a song renumbers, so the next add still goes last', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('Gaps');
      await repo.upsertTracks([song('a'), song('b'), song('c'), song('d')]);
      for (final id in ['a', 'b', 'c']) {
        await repo.addTrackToPlaylist(playlist.id, id);
      }

      // Remove from the middle, then append: the new song must land at the end
      // rather than inheriting position 1 from the row it displaced.
      await repo.removeTrackFromPlaylist(playlist.id, 'b');
      await repo.addTrackToPlaylist(playlist.id, 'd');

      final tracks = await repo.cachedPlaylistTracks(playlist.id);
      expect(tracks.map((t) => t.id).toList(), ['a', 'c', 'd']);
      expect((await repo.cachedPlaylists()).single.trackCount, 3);
    });

    test('deleting a playlist keeps the songs in the library', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('Doomed');
      await repo.upsertTracks([song('a'), song('b')]);
      await repo.addTrackToPlaylist(playlist.id, 'a');
      await repo.addTrackToPlaylist(playlist.id, 'b');

      await repo.deletePlaylist(playlist.id);

      // The whole point: a playlist is a view over the library, never the
      // library itself.
      expect(await repo.cachedPlaylists(), isEmpty);
      expect(await repo.cachedPlaylistTracks(playlist.id), isEmpty);
      expect((await repo.cachedLikedTracks()), hasLength(2));
    });

    test(
      'an imported playlist is deletable and its tracks survive too',
      () async {
        final repo = DriftLibraryRepository(db);
        await repo.upsertPlaylists([
          const Playlist(id: 'spotify1', name: 'Imported', trackCount: 1),
        ]);
        await repo.upsertTracks([song('a')]);
        await repo.replacePlaylistTracks('spotify1', [song('a')]);

        await repo.deletePlaylist('spotify1');

        expect(await repo.cachedPlaylists(), isEmpty);
        expect(await repo.cachedLikedTracks(), hasLength(1));
        // And it is not mistaken for one made here.
        expect(Playlist.isLocalId('spotify1'), isFalse);
      },
    );

    test('renaming ignores a blank name and keeps the old one', () async {
      final repo = DriftLibraryRepository(db);
      final playlist = await repo.createPlaylist('Original');

      await repo.renamePlaylist(playlist.id, '   ');
      expect((await repo.cachedPlaylists()).single.name, 'Original');

      await repo.renamePlaylist(playlist.id, '  Renamed  ');
      expect((await repo.cachedPlaylists()).single.name, 'Renamed');
    });

    test('an album cover is borrowed from any track on that album', () async {
      final repo = DriftLibraryRepository(db);
      await repo.upsertTracks([
        Track(
          id: 'plain',
          title: 'Plain',
          artists: const ['An Artist'],
          album: 'An Album',
        ),
        Track(
          id: 'covered',
          title: 'Covered',
          artists: const ['An Artist'],
          album: 'An Album',
          artworkUrl: 'https://art/album.jpg',
        ),
      ]);

      expect(
        await repo.cachedArtworkForAlbum('An Album'),
        'https://art/album.jpg',
      );
      expect(await repo.cachedArtworkForAlbum('Other Album'), isNull);
      expect(await repo.cachedArtworkForAlbum('  '), isNull);
    });
  });
}
