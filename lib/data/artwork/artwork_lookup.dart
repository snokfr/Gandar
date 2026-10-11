import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/track.dart';
import '../net/request_gate.dart';

/// Finds album artwork for a track.
abstract class ArtworkSource {
  /// The cover for [track] itself.
  Future<String?> artworkFor(Track track);

  /// The cover for the *album* [track] belongs to.
  ///
  /// Used when the per-track lookup comes back empty, which happens for
  /// compilations, for tracks whose title carries a feature suffix the
  /// catalogue does not use, and for anything that has never been released
  /// under its own name. An album cover is the right answer in all three
  /// cases: it is the picture the track is filed under.
  Future<String?> albumArtworkFor({required String album, required String artist});
}

/// Artwork from Apple's public iTunes Search API.
///
/// Why not Spotify: the artwork a playlist import can see is the *playlist
/// cover*, which is useless when it becomes the thumbnail of forty-six rows.
/// Per-track covers live behind the Web API, which is closed to Development
/// apps without Premium. The iTunes Search API needs no key, no account and no
/// OAuth, returns one cover per track, and is not subject to anyone's Premium
/// rules.
///
/// Its published guidance is about 20 requests per minute, which is what
/// [ArtworkEnricher] paces itself to.
class ITunesArtwork implements ArtworkSource {
  ITunesArtwork({Dio? http, RequestGate? gate})
    : _http =
          http ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          ),
      _gate = gate ?? RequestGate() {
    _governor = _gate.forHost('itunes.apple.com');
  }

  final Dio _http;
  final RequestGate _gate;
  late final HostGovernor _governor;

  /// The last lookup failure, for diagnostics.
  String? lastError;

  @override
  Future<String?> artworkFor(Track track) async {
    final term = track.searchQuery;
    if (term.isEmpty) return null;
    return _search(term: term, entity: 'song');
  }

  @override
  Future<String?> albumArtworkFor({
    required String album,
    required String artist,
  }) async {
    final term = [artist, album]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (term.isEmpty) return null;
    return _search(term: term, entity: 'album');
  }

  /// One rate-limited search. Both entities answer with the same
  /// `results[0].artworkUrl100` shape, so the parsing is shared.
  Future<String?> _search({required String term, required String entity}) async {
    try {
      final response = await _governor.schedule(
        () => _http.get<dynamic>(
          'https://itunes.apple.com/search',
          queryParameters: <String, String>{
            'term': term,
            'entity': entity,
            'limit': '1',
          },
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 600,
          ),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status == 403 || status == 429) {
        // Apple throttles by IP and does not always send Retry-After.
        _governor.notifyRateLimited(const Duration(seconds: 20));
        lastError = 'iTunes is rate limiting artwork lookups (HTTP $status)';
        AppLogger.instance.warn('artwork', lastError!);
        return null;
      }
      if (status != 200) {
        lastError = 'iTunes answered HTTP $status';
        return null;
      }
      return artworkFromSearchJson(response.data?.toString() ?? '');
    } on DioException catch (e) {
      lastError = e.message;
      AppLogger.instance.debug('artwork', 'lookup failed: ${e.message}');
      return null;
    }
  }

  /// Reads `results[0].artworkUrl100` out of an iTunes response.
  ///
  /// The URL embeds the size (`/100x100bb.jpg`), so asking for a bigger image
  /// is a matter of rewriting it — no second request.
  static String? artworkFromSearchJson(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    final url = first['artworkUrl100']?.toString();
    if (url == null || url.isEmpty) return null;
    return upscale(url, size: 600);
  }

  /// Rewrites an iTunes artwork URL to a larger render of the same image.
  static String upscale(String url, {int size = 600}) => url.replaceFirstMapped(
    RegExp(r'/\d+x\d+(bb)?\.(jpg|png)$'),
    (match) => '/${size}x$size${match[1] ?? ''}.${match[2]}',
  );
}
