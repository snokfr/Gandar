import 'dart:async';

import '../domain/models/resolved_stream.dart';
import '../domain/models/track.dart';
import '../domain/repositories/repositories.dart';

/// Resolves audio streams ahead of playback so the next track starts with no
/// audible gap.
///
/// Successful resolutions are memoized per track id, deduplicated so the same
/// track is never resolved twice concurrently, and failures are *not* cached
/// (extractor failures are transient and must be retried).
class StreamPreloader {
  StreamPreloader({required this.resolver, this.capacity = 4});

  /// Resolves tracks to playable streams.
  final AudioResolver resolver;

  /// How many resolved streams to keep warm at once.
  final int capacity;

  final Map<String, ResolvedStream> _cache = <String, ResolvedStream>{};
  final List<String> _order = <String>[];
  final Map<String, Future<ResolvedStream>> _inFlight =
      <String, Future<ResolvedStream>>{};

  /// Number of tracks currently held in the resolved-stream cache.
  int get cachedCount => _cache.length;

  ResolvedStream? peek(String trackId) => _cache[trackId];

  /// Returns a cached stream or resolves it now.
  Future<ResolvedStream> resolve(Track track) async {
    final cached = _cache[track.id];
    if (cached != null && !cached.isExpired) return cached;

    final existing = _inFlight[track.id];
    if (existing != null) return existing;

    final future = _resolveAndStore(track);
    _inFlight[track.id] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(track.id);
    }
  }

  Future<ResolvedStream> _resolveAndStore(Track track) async {
    final stream = await resolver.resolve(track);
    _remember(track.id, stream);
    return stream;
  }

  /// Fires a background resolve; errors are intentionally swallowed here
  /// because this is a speculative optimization, not the playback path.
  void prefetch(Track? track) {
    if (track == null) return;
    if (_cache.containsKey(track.id) || _inFlight.containsKey(track.id)) return;
    final future = _resolveAndStore(track);
    _inFlight[track.id] = future;
    future
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() => _inFlight.remove(track.id));
  }

  void _remember(String trackId, ResolvedStream stream) {
    _order.remove(trackId);
    _order.add(trackId);
    _cache[trackId] = stream;
    while (_order.length > capacity) {
      final evicted = _order.removeAt(0);
      _cache.remove(evicted);
    }
  }

  void clear() {
    _cache.clear();
    _order.clear();
  }
}
