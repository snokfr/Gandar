import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/logging/app_logger.dart';
import '../net/request_gate.dart';

/// One YouTube video, enough to show a row and start playback.
class YouTubeVideo {
  const YouTubeVideo({
    required this.videoId,
    required this.title,
    this.author,
    this.duration,
    this.thumbnailUrl,
  });

  final String videoId;
  final String title;
  final String? author;
  final Duration? duration;
  final String? thumbnailUrl;

  /// Track id that plays this exact video without a search.
  String get trackId => '$youTubeTrackPrefix$videoId';

  String get url => 'https://www.youtube.com/watch?v=$videoId';

  @override
  String toString() => 'YouTubeVideo($videoId, $title)';
}

/// Prefix marking a [Track] whose audio is a specific YouTube video.
///
/// It lets a YouTube search result flow through the normal queue, play history
/// and crossfade paths, resolving straight to that video instead of searching.
const String youTubeTrackPrefix = 'youtube:';

/// The video id encoded in a track id, or null when it is a Spotify track.
String? youTubeVideoIdOf(String trackId) {
  if (!trackId.startsWith(youTubeTrackPrefix)) return null;
  final id = trackId.substring(youTubeTrackPrefix.length);
  return id.isEmpty ? null : id;
}

/// Fetches search results; injectable so the service is testable offline.
///
/// Returns the app's own [YouTubeVideo] rather than the package's `Video`, so
/// tests never have to construct a thirteen-argument library type.
typedef YouTubeSearchFetch = Future<List<YouTubeVideo>> Function(
  String query,
  int limit,
);

/// Searches YouTube, politely.
///
/// Failures never throw into the UI: a search section that cannot load shows
/// as empty with a logged reason, because YouTube being flaky should not take
/// the whole search screen down.
class YouTubeSearcher {
  YouTubeSearcher({
    YouTubeSearchFetch? fetch,
    RequestGate? gate,
    YoutubeExplode? client,
  }) : _gate =
           gate ??
           RequestGate(
             defaultMaxConcurrent: 2,
             defaultBurst: 3,
             defaultRefillPerSecond: 1.5,
           ),
       _client = client ?? YoutubeExplode(),
       fetchOverride = fetch;

  final RequestGate _gate;
  final YoutubeExplode _client;

  /// Replaces the real YouTube call, used by tests.
  final YouTubeSearchFetch? fetchOverride;

  /// Most recent failure, for the diagnostics panel.
  Object? lastError;

  Future<List<YouTubeVideo>> search(String query, {int limit = 15}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <YouTubeVideo>[];

    try {
      final videos = await _gate
          .forHost('www.youtube.com')
          .schedule(() => (fetchOverride ?? _defaultFetch)(trimmed, limit));
      lastError = null;
      AppLogger.instance.debug(
        'youtube',
        'search "$trimmed" -> ${videos.length} results',
      );
      return videos;
    } catch (e, s) {
      lastError = e;
      AppLogger.instance.warn('youtube', 'search "$trimmed" failed', error: e);
      AppLogger.instance.debug('youtube', 'search stack: $s');
      return const <YouTubeVideo>[];
    }
  }

  Future<List<YouTubeVideo>> _defaultFetch(String query, int limit) async {
    final results = await _client.search.search(query);
    return results.take(limit).map(_toVideo).toList(growable: false);
  }

  YouTubeVideo _toVideo(Video video) => YouTubeVideo(
    videoId: video.id.value,
    title: video.title,
    author: video.author,
    duration: video.duration,
    thumbnailUrl: video.thumbnails.mediumResUrl,
  );
}
