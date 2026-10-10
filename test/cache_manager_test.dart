import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/cache/cache_manager.dart';
import 'package:gandar/domain/models/cache_entry.dart';
import 'package:gandar/domain/repositories/repositories.dart';

/// In-memory cache repository.
class FakeCacheRepository implements CacheRepository {
  FakeCacheRepository(Iterable<CacheEntry> seed) {
    for (final e in seed) {
      _entries[e.videoId] = e;
    }
  }

  final Map<String, CacheEntry> _entries = {};

  @override
  Future<List<CacheEntry>> all() async => _entries.values.toList();

  @override
  Future<CacheEntry?> find(String videoId) async => _entries[videoId];

  @override
  Future<void> put(CacheEntry entry) async => _entries[entry.videoId] = entry;

  @override
  Future<void> touch(String videoId, DateTime at) async {
    final e = _entries[videoId];
    if (e != null) _entries[videoId] = e.copyWith(lastPlayedAt: at);
  }

  @override
  Future<void> remove(String videoId) async => _entries.remove(videoId);
}

/// In-memory file store that records deletions.
class FakeFileStore implements AudioFileStore {
  FakeFileStore({this.size = 1024});

  final int size;
  final List<String> deleted = [];

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<int> sizeOf(String path) async => size;

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

CacheEntry entry(
  String id, {
  required int bytes,
  required DateTime lastPlayed,
}) => CacheEntry(
  videoId: id,
  filePath: '/cache/$id.m4a',
  sizeBytes: bytes,
  lastPlayedAt: lastPlayed,
);

void main() {
  final now = DateTime(2026, 1, 31, 12);

  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  test('deletes audio that has been idle longer than the threshold', () async {
    final repo = FakeCacheRepository([
      entry('fresh', bytes: 100, lastPlayed: daysAgo(2)),
      entry('stale', bytes: 100, lastPlayed: daysAgo(40)),
    ]);
    final files = FakeFileStore();
    final manager = CacheManager(
      repository: repo,
      fileStore: files,
      clock: () => now,
    );

    final result = await manager.enforceLimits(
      maxMegabytes: 1024,
      maxIdleDays: 30,
    );

    expect(result.deleted.map((e) => e.videoId), ['stale']);
    expect(await repo.find('stale'), isNull);
    expect(await repo.find('fresh'), isNotNull);
    expect(files.deleted, contains('/cache/stale.m4a'));
  });

  test('evicts least-recently-played first when over the size limit', () async {
    // 3 x 1 MB entries, 2 MB limit => the oldest must go.
    final repo = FakeCacheRepository([
      entry('oldest', bytes: 1024 * 1024, lastPlayed: daysAgo(10)),
      entry('middle', bytes: 1024 * 1024, lastPlayed: daysAgo(5)),
      entry('newest', bytes: 1024 * 1024, lastPlayed: daysAgo(1)),
    ]);
    final manager = CacheManager(
      repository: repo,
      fileStore: FakeFileStore(),
      clock: () => now,
    );

    final result = await manager.enforceLimits(
      maxMegabytes: 2,
      maxIdleDays: 365,
    );

    expect(result.deleted.map((e) => e.videoId), ['oldest']);
    expect(await repo.find('oldest'), isNull);
    expect(await repo.find('middle'), isNotNull);
    expect(await repo.find('newest'), isNotNull);
    expect(result.remainingCount, 2);
  });

  test('orders size eviction by last-played, not by insertion', () async {
    final repo = FakeCacheRepository([
      entry('replayed', bytes: 1024 * 1024, lastPlayed: daysAgo(1)),
      entry('ignored', bytes: 1024 * 1024, lastPlayed: daysAgo(20)),
      entry('forgotten', bytes: 1024 * 1024, lastPlayed: daysAgo(60)),
    ]);
    final manager = CacheManager(
      repository: repo,
      fileStore: FakeFileStore(),
      clock: () => now,
    );

    final result = await manager.enforceLimits(
      maxMegabytes: 2,
      maxIdleDays: 365,
    );

    // The long-unplayed file goes, even though it was added in the middle.
    expect(result.deleted.map((e) => e.videoId), ['forgotten']);
    expect(await repo.find('replayed'), isNotNull);
  });

  test('does nothing when under both limits', () async {
    final repo = FakeCacheRepository([
      entry('a', bytes: 1024, lastPlayed: daysAgo(1)),
    ]);
    final manager = CacheManager(
      repository: repo,
      fileStore: FakeFileStore(),
      clock: () => now,
    );

    final result = await manager.enforceLimits(
      maxMegabytes: 100,
      maxIdleDays: 30,
    );
    expect(result.deleted, isEmpty);
    expect(result.remainingCount, 1);
  });

  test('reports the current cache size', () async {
    final repo = FakeCacheRepository([
      entry('a', bytes: 2048, lastPlayed: now),
      entry('b', bytes: 1024, lastPlayed: now),
    ]);
    final manager = CacheManager(
      repository: repo,
      fileStore: FakeFileStore(),
      clock: () => now,
    );
    expect(await manager.currentSizeBytes(), 3072);
  });

  test('evicts repeatedly until under the limit', () async {
    final repo = FakeCacheRepository([
      for (var i = 0; i < 5; i++)
        entry('t$i', bytes: 1024 * 1024, lastPlayed: daysAgo(30 - i)),
    ]);
    final manager = CacheManager(
      repository: repo,
      fileStore: FakeFileStore(),
      clock: () => now,
    );

    final result = await manager.enforceLimits(
      maxMegabytes: 1,
      maxIdleDays: 365,
    );
    expect(result.deleted.length, 4);
    expect(result.remainingCount, 1);
    expect(result.remainingBytes, 1024 * 1024);
  });
}
