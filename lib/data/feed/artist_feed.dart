import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../net/request_gate.dart';
import '../youtube/youtube_search.dart';

/// One new upload in the feed.
class FeedVideo {
  const FeedVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    this.publishedAt,
    this.thumbnailUrl,
    this.artist,
  });

  final String videoId;
  final String title;

  /// The channel that published it, as the feed names it.
  final String channelTitle;

  final DateTime? publishedAt;
  final String? thumbnailUrl;

  /// The library artist this upload was fetched for.
  final String? artist;

  /// Track id that plays this exact video through the normal queue.
  String get trackId => '$youTubeTrackPrefix$videoId';

  String get url => 'https://www.youtube.com/watch?v=$videoId';

  @override
  String toString() => 'FeedVideo($videoId, $title)';
}

/// Parses YouTube's channel Atom feed.
///
/// Regex rather than an XML parser on purpose: the feed has a fixed, flat shape
/// and the repository has no XML dependency, so adding one for four element
/// names would be a dependency bought with nothing. Every extraction is
/// optional — a missing element produces a null field rather than a failure,
/// because a feed that changes shape should thin out the list, not break it.
class YouTubeFeedParser {
  const YouTubeFeedParser._();

  static final RegExp _entry = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
  static final RegExp _videoId = RegExp(r'<yt:videoId>([^<]+)</yt:videoId>');
  static final RegExp _title = RegExp(r'<title>([^<]*)</title>');
  static final RegExp _published = RegExp(r'<published>([^<]+)</published>');
  static final RegExp _authorName = RegExp(
    r'<author>\s*<name>([^<]*)</name>',
    dotAll: true,
  );
  static final RegExp _thumbnail = RegExp(
    r'<media:thumbnail[^>]*url="([^"]+)"',
  );

  /// The feed's own channel name, from the top-level `<title>`.
  static String? feedTitle(String xml) {
    final head = xml.split('<entry>').first;
    return _title.firstMatch(head)?.group(1)?.trim();
  }

  /// Parses every entry it can.
  static List<FeedVideo> parse(String xml, {String? artist}) {
    final out = <FeedVideo>[];
    for (final match in _entry.allMatches(xml)) {
      final body = match.group(1) ?? '';
      final videoId = _videoId.firstMatch(body)?.group(1)?.trim();
      if (videoId == null || videoId.isEmpty) continue;

      final rawTitle = _title.firstMatch(body)?.group(1)?.trim();
      if (rawTitle == null || rawTitle.isEmpty) continue;

      out.add(
        FeedVideo(
          videoId: videoId,
          title: unescape(rawTitle),
          channelTitle: unescape(
            _authorName.firstMatch(body)?.group(1)?.trim() ?? '',
          ),
          publishedAt: DateTime.tryParse(
            _published.firstMatch(body)?.group(1)?.trim() ?? '',
          ),
          thumbnailUrl: _thumbnail.firstMatch(body)?.group(1),
          artist: artist,
        ),
      );
    }
    return out;
  }

  /// Decodes the five entities an Atom feed actually uses, plus numeric ones.
  ///
  /// `<title>` is XML text, so an ampersand in a song title arrives as `&amp;`.
  /// Leaving it encoded would put "Troy &amp; Abed" in the list.
  static String unescape(String value) {
    if (!value.contains('&')) return value;
    return value
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        )
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }
}

/// Reads "new uploads" for the artists already in the library.
///
/// Nothing here needs a YouTube account: a channel's uploads are published as a
/// plain Atom feed at a predictable URL, and the only thing that has to be
/// discovered is *which* channel belongs to an artist. That is one ordinary
/// search per artist, and the answer is remembered for the session.
///
/// The whole feature is best-effort by construction. YouTube's search is a
/// guess at the right channel, feeds can be empty, and the network can be down;
/// none of that should do worse than produce a shorter list.
class ArtistFeed {
  ArtistFeed({
    YouTubeSearcher? searcher,
    Dio? http,
    RequestGate? gate,
    this.perArtist = 8,
    this.maxArtists = 10,
  }) : _searcher = searcher ?? YouTubeSearcher(),
       _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _gate = gate ?? RequestGate() {
    _governor = _gate.forHost('www.youtube.com');
  }

  final YouTubeSearcher _searcher;
  final Dio _http;
  final RequestGate _gate;
  late final HostGovernor _governor;

  /// How many uploads to take from each channel.
  final int perArtist;

  /// How many artists to build a feed for in one pass.
  final int maxArtists;

  /// Artist name (lowercased) -> channel id, or null once we know the search
  /// came up empty. Cached for the session so switching tabs is instant.
  final Map<String, String?> _channels = <String, String?>{};

  /// The channel ids resolved so far, for the diagnostics panel.
  Map<String, String?> get resolvedChannels => Map.unmodifiable(_channels);

  /// The most recent uploads across [artists], newest first.
  ///
  /// Artists are looked up concurrently but through the shared host governor,
  /// so this cannot turn into a burst of parallel requests at YouTube.
  Future<List<FeedVideo>> latestFor(
    Iterable<String> artists, {
    int? maxArtists,
  }) async {
    final wanted = <String>[];
    for (final artist in artists) {
      final trimmed = artist.trim();
      if (trimmed.isEmpty) continue;
      if (wanted.any((a) => a.toLowerCase() == trimmed.toLowerCase())) continue;
      wanted.add(trimmed);
      if (wanted.length >= (maxArtists ?? this.maxArtists)) break;
    }
    if (wanted.isEmpty) return const <FeedVideo>[];

    final perArtist = await Future.wait(wanted.map(_feedForArtist));
    return merge(perArtist);
  }

  /// Merges per-artist lists into one newest-first list with no duplicates.
  ///
  /// Public and static so the ordering rule — newest first, ties broken by
  /// artist so the order is stable — can be tested without any network.
  static List<FeedVideo> merge(List<List<FeedVideo>> lists) {
    final seen = <String>{};
    final all = <FeedVideo>[];
    for (final list in lists) {
      for (final video in list) {
        if (seen.add(video.videoId)) all.add(video);
      }
    }
    all.sort((a, b) {
      final aDate = a.publishedAt;
      final bDate = b.publishedAt;
      if (aDate != null && bDate != null) {
        final byDate = bDate.compareTo(aDate);
        if (byDate != 0) return byDate;
      } else if (aDate != null) {
        return -1;
      } else if (bDate != null) {
        return 1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return all;
  }

  Future<List<FeedVideo>> _feedForArtist(String artist) async {
    final channelId = await _channelFor(artist);
    if (channelId == null) return const <FeedVideo>[];

    final xml = await _fetchFeed(channelId);
    if (xml == null) return const <FeedVideo>[];

    final videos = YouTubeFeedParser.parse(xml, artist: artist);
    return videos.take(perArtist).toList(growable: false);
  }

  /// The channel id for [artist], remembered once found.
  ///
  /// The heuristic is deliberately conservative: the first search result whose
  /// channel *name* looks like the artist is preferred, and only if none does is
  /// the first result's channel used. That avoids handing a feed to whichever
  /// reaction video happens to rank first for a common name.
  Future<String?> _channelFor(String artist) async {
    final key = artist.toLowerCase();
    if (_channels.containsKey(key)) return _channels[key];

    final results = await _searcher.search(artist, limit: 8);
    if (results.isEmpty) {
      _channels[key] = null;
      return null;
    }

    String? exact;
    for (final video in results) {
      final channelId = video.channelId;
      final author = video.author;
      if (channelId == null || author == null) continue;
      if (author.toLowerCase().contains(key)) {
        exact = channelId;
        break;
      }
    }
    final chosen = exact ?? results.first.channelId;
    _channels[key] = chosen;
    AppLogger.instance.debug(
      'feed',
      'artist "$artist" -> channel ${chosen ?? "(none)"}'
          '${exact == null ? ' (best guess)' : ''}',
    );
    return chosen;
  }

  Future<String?> _fetchFeed(String channelId) async {
    final url =
        'https://www.youtube.com/feeds/videos.xml?channel_id=$channelId';
    try {
      final response = await _governor.schedule(
        () => _http.get<dynamic>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 600,
          ),
        ),
      );
      if ((response.statusCode ?? 0) != 200) {
        AppLogger.instance.debug(
          'feed',
          'channel $channelId feed -> HTTP ${response.statusCode}',
        );
        return null;
      }
      return response.data?.toString();
    } on DioException catch (e) {
      AppLogger.instance.debug('feed', 'feed fetch failed: ${e.message}');
      return null;
    }
  }
}
