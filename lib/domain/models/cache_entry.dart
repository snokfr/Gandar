/// A cached audio file on disk, tracked so it can be evicted by LRU policy.
class CacheEntry {
  const CacheEntry({
    required this.videoId,
    required this.filePath,
    required this.sizeBytes,
    required this.lastPlayedAt,
  });

  /// YouTube video id (the audio cache key).
  final String videoId;

  /// Absolute path to the cached audio file.
  final String filePath;

  final int sizeBytes;

  /// Last time this file was used for playback. LRU eviction is ordered by
  /// this value, not by download time, so frequently replayed songs survive.
  final DateTime lastPlayedAt;

  CacheEntry copyWith({
    String? videoId,
    String? filePath,
    int? sizeBytes,
    DateTime? lastPlayedAt,
  }) => CacheEntry(
    videoId: videoId ?? this.videoId,
    filePath: filePath ?? this.filePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
  );
}
