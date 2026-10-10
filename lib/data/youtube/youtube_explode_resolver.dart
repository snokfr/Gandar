import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../domain/models/resolved_stream.dart';
import '../../domain/models/track.dart';
import '../../domain/repositories/repositories.dart';
import 'audio_stream_selector.dart';

/// Raised when no playable audio stream could be resolved for a track.
class AudioResolutionException implements Exception {
  AudioResolutionException(this.message, {this.track, this.cause});
  final String message;
  final Track? track;
  final Object? cause;

  @override
  String toString() =>
      'AudioResolutionException: $message${track == null ? '' : ' (${track!.searchQuery})'}';
}

/// Resolves Spotify tracks to YouTube audio using `youtube_explode_dart`.
///
/// YouTube extraction is inherently fragile (signature deciphering, PO tokens,
/// SABR-only responses, 403s), so this resolver:
///   * reuses a permanently cached Spotify->YouTube mapping when available,
///   * tries several extraction clients in order,
///   * picks the best stream via [AudioStreamSelector],
///   * and tries the next candidate video if a video yields no usable audio.
class YoutubeExplodeResolver implements AudioResolver {
  YoutubeExplodeResolver({
    required this.mappings,
    YoutubeExplode? client,
    this.selector = const AudioStreamSelector(),
    List<YoutubeApiClient>? clients,
    this.searchResultLimit = 5,
  }) : _yt = client ?? YoutubeExplode(),
       _clients =
           clients ??
           const <YoutubeApiClient>[
             YoutubeApiClient.androidSdkless,
             YoutubeApiClient.tv,
             YoutubeApiClient.androidMusic,
             YoutubeApiClient.mweb,
           ];

  /// Cache of permanent Spotify -> YouTube mappings.
  final MappingRepository mappings;

  /// Chooses among the available audio-only streams.
  final AudioStreamSelector selector;

  final YoutubeExplode _yt;
  final List<YoutubeApiClient> _clients;
  final int searchResultLimit;

  @override
  Future<ResolvedStream> resolve(Track track) async {
    final candidates = await _candidateVideoIds(track);
    if (candidates.isEmpty) {
      throw AudioResolutionException('No YouTube match found', track: track);
    }

    Object? lastError;
    for (final videoId in candidates) {
      try {
        final stream = await _resolveVideo(videoId);
        // Cache the mapping so this track resolves instantly next time.
        await mappings.saveMapping(track.id, videoId);
        return stream;
      } catch (e) {
        lastError = e;
      }
    }
    throw AudioResolutionException(
      'All candidate videos failed to yield a playable audio stream',
      track: track,
      cause: lastError,
    );
  }

  /// The cached mapping first (instant path), else fresh search results.
  Future<List<String>> _candidateVideoIds(Track track) async {
    final cached = await mappings.findVideoId(track.id);
    if (cached != null && cached.isNotEmpty) return <String>[cached];

    final query = track.searchQuery;
    if (query.isEmpty) return const <String>[];

    final results = await _yt.search.search(query);
    return results
        .take(searchResultLimit)
        .map((v) => v.id.value)
        .toList(growable: false);
  }

  Future<ResolvedStream> _resolveVideo(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: _clients,
    );

    final options = manifest.audioOnly
        .map(
          (s) => AudioOption(
            url: s.url.toString(),
            container: s.container.name,
            bitrateBitsPerSecond: s.bitrate.bitsPerSecond,
            sizeBytes: s.size.totalBytes,
            audioCodec: s.audioCodec,
          ),
        )
        .toList(growable: false);

    final best = selector.selectBest(options);
    if (best == null) {
      throw AudioResolutionException('Video has no audio-only streams');
    }

    return ResolvedStream(
      url: best.url,
      videoId: videoId,
      container: best.extension,
      bitrate: best.bitrateBitsPerSecond,
      sizeBytes: best.sizeBytes,
    );
  }

  /// Releases the underlying HTTP client.
  void dispose() => _yt.close();
}
