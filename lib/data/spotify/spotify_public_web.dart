import 'package:dio/dio.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/track.dart';
import '../net/request_gate.dart';
import 'spotify_public.dart';

/// Reads public Spotify collections without an account, a client id or the
/// Web API.
///
/// Why this exists: since February 2026 a Development-mode Spotify app is
/// refused outright unless its owner pays for Premium. That takes the whole
/// "sign in and read my library" path away from most users, but it says nothing
/// about *public* pages, which Spotify serves to anyone with a browser. So this
/// client fetches the same embed page Spotify's own widget uses.
///
/// What it can and cannot do, so the UI never over-promises:
///
/// * works for **public** playlists, albums and tracks;
/// * returns at most [PublicCollection.publicTrackLimit] tracks of a playlist
///   or album, because that is all the embed page carries;
/// * cannot read anyone's *liked songs* — that is account data, and the only
///   route to it is the file import;
/// * can stop working whenever Spotify changes the page, so every failure is a
///   sentence rather than a crash.
class SpotifyPublicWeb {
  SpotifyPublicWeb({Dio? http, RequestGate? gate, Duration? timeout})
    : _http =
          http ??
          Dio(
            BaseOptions(
              connectTimeout: timeout ?? const Duration(seconds: 20),
              receiveTimeout: timeout ?? const Duration(seconds: 20),
            ),
          ),
      _gate = gate ?? RequestGate() {
    _governor = _gate.forHost('open.spotify.com');
  }

  final Dio _http;
  final RequestGate _gate;
  late final HostGovernor _governor;

  /// A browser user agent, because Spotify serves a stripped page — or nothing
  /// at all — to clients that look like scripts.
  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// The embed page for [link].
  static Uri embedUrl(SpotifyLink link) =>
      Uri.https('open.spotify.com', '/embed/${link.kind.name}/${link.id}');

  /// Fetches a public collection: name, artwork and as many tracks as Spotify
  /// will hand over.
  Future<PublicCollection> fetchCollection(SpotifyLink link) async {
    if (!link.isReadable) {
      throw SpotifyPublicException(
        'Gandar can read public playlists, albums and tracks without signing '
        'in, but not a ${link.label}. Import a playlist or album link instead.',
        link: link,
      );
    }

    final fetched = await _fetchPage(embedUrl(link), link: link);

    final collection = const SpotifyEmbedPage().parse(fetched.body, link: link);

    // The embed page usually omits cover art for albums and tracks; oEmbed
    // has it, and its title is a good cross-check.
    if (collection.artworkUrl == null || collection.artworkUrl!.isEmpty) {
      final meta = await _fetchOEmbed(link);
      if (meta != null) {
        return PublicCollection(
          link: link,
          name: collection.name.isEmpty ? meta.title : collection.name,
          description: collection.description,
          artworkUrl: meta.thumbnailUrl,
          ownerName: collection.ownerName,
          tracks: collection.tracks,
          trackListTruncated: collection.trackListTruncated,
        );
      }
    }

    AppLogger.instance.info(
      'spotify',
      'public ${link.kind.name} ${link.id}: ${collection.tracks.length} tracks'
          '${collection.trackListTruncated ? ' (page limit reached)' : ''}',
    );
    return collection;
  }

  /// Imports a single track link, so a shared song can be added directly.
  Future<PublicCollection> fetchTrack(SpotifyLink link) async {
    if (link.kind != SpotifyLinkKind.track) {
      throw SpotifyPublicException('Not a track link.', link: link);
    }
    final fetched = await _fetchPage(embedUrl(link), link: link);
    final collection = const SpotifyEmbedPage().parse(fetched.body, link: link);
    if (collection.tracks.isNotEmpty) return collection;

    final meta = await _fetchOEmbed(link);
    if (meta == null) {
      throw SpotifyPublicException(
        'Spotify returned no details for this track.',
        link: link,
      );
    }
    return PublicCollection(
      link: link,
      name: meta.title,
      artworkUrl: meta.thumbnailUrl,
      tracks: <Track>[
        Track(id: link.id, title: meta.title, artists: const <String>[]),
      ],
    );
  }

  Future<({String body, int status})> _fetchPage(
    Uri url, {
    required SpotifyLink link,
  }) async {
    try {
      final response = await _governor.schedule(
        () => _http.get<dynamic>(
          url.toString(),
          options: Options(
            headers: <String, String>{
              'User-Agent': browserUserAgent,
              'Accept': 'text/html,application/xhtml+xml',
              'Accept-Language': 'en',
            },
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 600,
          ),
        ),
      );
      final status = response.statusCode ?? 0;
      final body = response.data?.toString() ?? '';
      AppLogger.instance.debug(
        'spotify',
        'public page ${url.path} -> $status (${body.length} bytes)',
      );

      if (status == 404) {
        throw SpotifyPublicException(
          'Spotify has nothing at that link. For a playlist, it must be public '
          '— private and made-for-you playlists are only visible to their '
          'owner.',
          link: link,
        );
      }
      if (status == 429) {
        throw SpotifyPublicException(
          'Spotify is rate limiting these page requests. Wait a minute and try '
          'again.',
          link: link,
        );
      }
      if (status >= 400) {
        throw SpotifyPublicException(
          'Spotify answered with HTTP $status for that link.',
          link: link,
        );
      }
      return (body: body, status: status);
    } on DioException catch (e) {
      final detail = e.error?.toString() ?? e.message ?? 'no detail';
      throw SpotifyPublicException(
        'Could not reach Spotify ($detail). Check the connection, VPN or '
        'firewall.',
        link: link,
      );
    }
  }

  Future<({String title, String? thumbnailUrl})?> _fetchOEmbed(
    SpotifyLink link,
  ) async {
    try {
      final response = await _governor.schedule(
        () => _http.get<dynamic>(
          SpotifyOEmbed.urlFor(link).toString(),
          options: Options(
            headers: <String, String>{
              'User-Agent': browserUserAgent,
              'Accept': 'application/json',
            },
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 600,
          ),
        ),
      );
      if ((response.statusCode ?? 0) != 200) return null;
      return SpotifyOEmbed.parse(response.data?.toString() ?? '');
    } on DioException catch (e) {
      AppLogger.instance.debug('spotify', 'oEmbed failed: ${e.message}');
      return null;
    } on FormatException catch (e) {
      AppLogger.instance.debug('spotify', 'oEmbed not JSON: $e');
      return null;
    }
  }
}
