import 'dart:io';

import '../../domain/models/cache_entry.dart';
import '../../domain/repositories/repositories.dart';

/// File operations the cache manager needs, abstracted so eviction policy can
/// be unit tested without touching the real disk.
abstract class AudioFileStore {
  Future<bool> exists(String path);
  Future<int> sizeOf(String path);
  Future<void> delete(String path);
}

/// Real filesystem implementation.
class IoAudioFileStore implements AudioFileStore {
  const IoAudioFileStore();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<int> sizeOf(String path) async {
    final f = File(path);
    return await f.exists() ? f.length() : 0;
  }

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// Outcome of one eviction pass.
class CachePurgeResult {
  const CachePurgeResult({
    required this.deleted,
    required this.freedBytes,
    required this.remainingBytes,
    required this.remainingCount,
  });

  final List<CacheEntry> deleted;
  final int freedBytes;
  final int remainingBytes;
  final int remainingCount;
}

/// Enforces the cache limits from the playback settings.
///
/// Two independent rules are applied, in order:
///  1. **Idle eviction** — anything not played within `maxIdleDays` goes.
///  2. **Size eviction (LRU)** — while the total exceeds `maxMegabytes`, the
///     least-recently-played file goes next.
///
/// Ordering by *last played* (not downloaded) means songs you replay survive
/// while one-off listens age out.
class CacheManager {
  CacheManager({
    required CacheRepository repository,
    AudioFileStore fileStore = const IoAudioFileStore(),
    DateTime Function()? clock,
  }) : _repo = repository,
       _files = fileStore,
       _now = clock ?? DateTime.now;

  final CacheRepository _repo;
  final AudioFileStore _files;
  final DateTime Function() _now;

  Future<CachePurgeResult> enforceLimits({
    required int maxMegabytes,
    required int maxIdleDays,
  }) async {
    final entries = List<CacheEntry>.of(await _repo.all());
    final now = _now();
    final idleCutoff = now.subtract(Duration(days: maxIdleDays));

    final deleted = <CacheEntry>[];
    var freed = 0;
    final survivors = <CacheEntry>[];

    // Pass 1: idle eviction.
    for (final e in entries) {
      if (e.lastPlayedAt.isBefore(idleCutoff)) {
        freed += await _evict(e);
        deleted.add(e);
      } else {
        survivors.add(e);
      }
    }

    // Pass 2: LRU size eviction.
    survivors.sort((a, b) => a.lastPlayedAt.compareTo(b.lastPlayedAt));
    var total = survivors.fold<int>(0, (sum, e) => sum + e.sizeBytes);
    final maxBytes = maxMegabytes * 1024 * 1024;

    var i = 0;
    while (total > maxBytes && i < survivors.length) {
      final victim = survivors[i];
      total -= victim.sizeBytes;
      freed += await _evict(victim);
      deleted.add(victim);
      i++;
    }
    final remaining = survivors.sublist(i);

    return CachePurgeResult(
      deleted: deleted,
      freedBytes: freed,
      remainingBytes: total,
      remainingCount: remaining.length,
    );
  }

  /// Total bytes currently tracked in the cache.
  Future<int> currentSizeBytes() async {
    final entries = await _repo.all();
    return entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
  }

  Future<int> _evict(CacheEntry entry) async {
    var size = entry.sizeBytes;
    if (await _files.exists(entry.filePath)) {
      final actual = await _files.sizeOf(entry.filePath);
      if (actual > 0) size = actual;
      await _files.delete(entry.filePath);
    }
    await _repo.remove(entry.videoId);
    return size;
  }
}
