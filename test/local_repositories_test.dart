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
}
