import 'package:dio/dio.dart';

import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../domain/repositories/repositories.dart';
import 'spotify_auth.dart';

/// Raised for Spotify Web API failures, preserving the HTTP status.
class SpotifyApiException implements Exception {
  SpotifyApiException(this.statusCode, this.message, {this.body});

  final int? statusCode;
  final String message;
  final String? body;

  /// True when Spotify is refusing access because the app is in Development
  /// mode and the user has not been added to the app's user allowlist.
  bool get isDevelopmentModeRestriction =>
      statusCode == 403 || statusCode == 401;

  @override
  String toString() => 'SpotifyApiException($statusCode): $message';
}

/// Spotify Web API client.
class SpotifyApi implements SpotifyRepository {
  SpotifyApi({
    required this.auth,
    Dio? http,
    this.baseUrl = 'https://api.spotify.com/v1',
  }) : _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );

  /// The authorizing service used to obtain a valid access token.
  final SpotifyAuthService auth;
  final Dio _http;
  final String baseUrl;

  @override
  Future<bool> isAuthenticated() async {
    try {
      await auth.validAccessToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signIn() => auth.signIn();

  @override
  Future<void> signOut() => auth.signOut();

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final token = await auth.validAccessToken();
    try {
      final res = await _http.get<Map<String, dynamic>>(
        '$baseUrl$path',
        queryParameters: query,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return _unwrap(res);
    } on DioException catch (e) {
      throw SpotifyApiException(
        e.response?.statusCode,
        'Network error: ${e.message}',
      );
    }
  }

  Map<String, dynamic> _unwrap(Response<Map<String, dynamic>> res) {
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) {
      return res.data ?? const <String, dynamic>{};
    }
    final data = res.data;
    final message =
        (data?['error'] as Map?)?['message']?.toString() ??
        res.statusMessage ??
        'Request failed';
    throw SpotifyApiException(code, message, body: data?.toString());
  }

  /// Issues a request that may fall back to the legacy saved-tracks endpoint.
  Future<void> _mutateLibrary({
    required String method,
    required String trackId,
    required String modernPath,
    required String legacyPath,
  }) async {
    final token = await auth.validAccessToken();
    final uri = 'spotify:track:$trackId';

    Future<void> attempt(
      String path,
      Map<String, dynamic>? query,
      Object? body,
    ) async {
      final res = await _http.request<dynamic>(
        '$baseUrl$path',
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $token'},
          contentType: Headers.jsonContentType,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final code = res.statusCode ?? 0;
      if (code >= 200 && code < 300) return;
      throw SpotifyApiException(
        code,
        (res.data is Map<String, dynamic>
                    ? (res.data as Map<String, dynamic>)['error']
                    : null)
                ?.toString() ??
            'Library update failed',
        body: res.data?.toString(),
      );
    }

    try {
      // Current endpoint: Save/Remove Items to Library, keyed by URI.
      await attempt(modernPath, {'uris': uri}, null);
    } on SpotifyApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 400) rethrow;
      // Legacy endpoint: Save/Remove Tracks, keyed by id.
      await attempt(legacyPath, null, {
        'ids': <String>[trackId],
      });
    }
  }

  @override
  Future<List<Track>> getLikedTracks({int offset = 0, int limit = 50}) async {
    final json = await _getJson(
      '/me/tracks',
      query: {'offset': offset, 'limit': limit},
    );
    final items = json['items'] as List? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final trackJson = item['track'] as Map<String, dynamic>?;
          if (trackJson == null) return null;
          final track = Track.fromSpotify(Map<String, dynamic>.from(trackJson));
          final addedAt = item['added_at'];
          return addedAt is String
              ? Track(
                  id: track.id,
                  title: track.title,
                  artists: track.artists,
                  album: track.album,
                  durationMs: track.durationMs,
                  artworkUrl: track.artworkUrl,
                  isrc: track.isrc,
                  addedAt: DateTime.tryParse(addedAt),
                )
              : track;
        })
        .whereType<Track>()
        .where((t) => t.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<Playlist>> getPlaylists({int offset = 0, int limit = 50}) async {
    final json = await _getJson(
      '/me/playlists',
      query: {'offset': offset, 'limit': limit},
    );
    final items = json['items'] as List? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(Playlist.fromSpotify)
        .where((p) => p.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<Track>> getPlaylistTracks(
    String playlistId, {
    int offset = 0,
    int limit = 100,
  }) async {
    final path = '/playlists/$playlistId/items';
    Map<String, dynamic> json;
    try {
      json = await _getJson(path, query: {'offset': offset, 'limit': limit});
    } on SpotifyApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      // Older accounts/apps may still be served by the deprecated route.
      json = await _getJson(
        '/playlists/$playlistId/tracks',
        query: {'offset': offset, 'limit': limit},
      );
    }
    final items = json['items'] as List? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map((item) {
          // New shape nests under `item`, legacy under `track`.
          final t = (item['item'] ?? item['track']) as Map<String, dynamic>?;
          if (t == null) return null;
          return Track.fromSpotify(Map<String, dynamic>.from(t));
        })
        .whereType<Track>()
        .where((t) => t.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> saveTrack(String trackId) => _mutateLibrary(
    method: 'PUT',
    trackId: trackId,
    modernPath: '/me/library',
    legacyPath: '/me/tracks',
  );

  @override
  Future<void> removeTrack(String trackId) => _mutateLibrary(
    method: 'DELETE',
    trackId: trackId,
    modernPath: '/me/library',
    legacyPath: '/me/tracks',
  );
}
