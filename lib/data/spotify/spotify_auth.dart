import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pkce.dart';
import 'spotify_tokens.dart';

/// Spotify OAuth configuration.
class SpotifyAuthConfig {
  const SpotifyAuthConfig({
    required this.clientId,
    this.redirectPort = 8888,
    this.scopes = defaultScopes,
    this.accountsBaseUrl = 'https://accounts.spotify.com',
  });

  final String clientId;
  final int redirectPort;
  final List<String> scopes;
  final String accountsBaseUrl;

  /// Scopes needed to read and modify the user's saved tracks and playlists.
  static const List<String> defaultScopes = <String>[
    'user-library-read',
    'user-library-modify',
    'playlist-read-private',
    'playlist-read-collaborative',
  ];

  /// Spotify requires an exact match, but permits any port on a loopback IP.
  String get redirectUri => 'http://127.0.0.1:$redirectPort/callback';
}

/// Opens the system browser and returns the redirect URI that was hit.
///
/// Abstracted so the sign-in flow can be tested without a browser.
abstract class OAuthBrowser {
  Future<Uri> authorize(
    Uri authorizeUrl, {
    required String redirectUri,
    required Duration timeout,
  });
}

/// Real implementation: binds a loopback HTTP server and launches the browser.
class LoopbackOAuthBrowser implements OAuthBrowser {
  LoopbackOAuthBrowser({this.port = 8888, Future<bool> Function(Uri)? launch})
    : _launch = launch ?? _launchExternal;

  final int port;
  final Future<bool> Function(Uri) _launch;

  static Future<bool> _launchExternal(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<Uri> authorize(
    Uri authorizeUrl, {
    required String redirectUri,
    required Duration timeout,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final completer = Completer<Uri>();

    final sub = server.listen((req) async {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_callbackHtml);
      await req.response.close();
      if (!completer.isCompleted) {
        final query = req.uri.queryParameters;
        // Build a normalized callback URI carrying the query parameters.
        completer.complete(
          Uri.parse(redirectUri).replace(queryParameters: query),
        );
      }
    });

    try {
      final launched = await _launch(authorizeUrl);
      if (!launched) {
        throw StateError('Could not open the system browser for sign-in.');
      }
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for the Spotify sign-in redirect.',
          timeout,
        ),
      );
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  static const String _callbackHtml = '''
<!doctype html><html><head><meta charset="utf-8">
<title>Gandar</title></head>
<body style="font-family:system-ui;background:#121212;color:#fff;display:grid;
place-items:center;height:100vh;margin:0">
<div style="text-align:center">
<h2 style="color:#1DB954">Signed in to Gandar</h2>
<p>You can close this tab and return to the app.</p>
</div></body></html>''';
}

/// Errors surfaced from the sign-in flow.
class SpotifyAuthException implements Exception {
  SpotifyAuthException(this.message);
  final String message;
  @override
  String toString() => 'SpotifyAuthException: $message';
}

/// Runs the Authorization Code + PKCE flow and manages token lifetime.
class SpotifyAuthService {
  SpotifyAuthService({
    required this.config,
    required this.tokenStore,
    required this.browser,
    Dio? http,
  }) : _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );

  final SpotifyAuthConfig config;

  /// Where tokens are persisted between launches.
  final TokenStore tokenStore;

  /// Opens the system browser and captures the redirect.
  final OAuthBrowser browser;

  final Dio _http;

  static const Duration authorizeTimeout = Duration(minutes: 3);

  /// Builds the `/authorize` URL for the given PKCE pair.
  Uri buildAuthorizeUrl({
    required String state,
    required String codeChallenge,
  }) {
    return Uri.parse('${config.accountsBaseUrl}/authorize').replace(
      queryParameters: <String, String>{
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': config.redirectUri,
        'scope': config.scopes.join(' '),
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': codeChallenge,
        'show_dialog': 'false',
      },
    );
  }

  /// Performs a full interactive sign-in and stores the resulting tokens.
  Future<SpotifyTokens> signIn() async {
    final verifier = Pkce.generateVerifier();
    final state = Pkce.generateState();
    final challenge = Pkce.challengeFor(verifier);
    final authorizeUrl = buildAuthorizeUrl(
      state: state,
      codeChallenge: challenge,
    );

    final callback = await browser.authorize(
      authorizeUrl,
      redirectUri: config.redirectUri,
      timeout: authorizeTimeout,
    );

    if (callback.queryParameters['error'] != null) {
      throw SpotifyAuthException(
        'Authorization denied: ${callback.queryParameters['error']}',
      );
    }
    final returnedState = callback.queryParameters['state'];
    if (returnedState != state) {
      throw SpotifyAuthException('State mismatch; possible CSRF attempt.');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw SpotifyAuthException('No authorization code returned.');
    }

    final tokens = await _exchange(<String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': config.redirectUri,
      'client_id': config.clientId,
      'code_verifier': verifier,
    });
    await tokenStore.write(tokens);
    return tokens;
  }

  Future<void> signOut() => tokenStore.clear();

  Future<bool> hasStoredTokens() async => (await tokenStore.read()) != null;

  /// Returns a non-expired access token, refreshing if necessary.
  Future<String> validAccessToken() async {
    final tokens = await tokenStore.read();
    if (tokens == null) {
      throw SpotifyAuthException('Not signed in.');
    }
    if (!tokens.isExpired) return tokens.accessToken;

    final refreshed = await _exchange(<String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': tokens.refreshToken,
      'client_id': config.clientId,
    });
    await tokenStore.write(refreshed);
    return refreshed.accessToken;
  }

  Future<SpotifyTokens> _exchange(Map<String, String> body) async {
    try {
      final res = await _http.post<Map<String, dynamic>>(
        '${config.accountsBaseUrl}/api/token',
        data: body,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final data = res.data;
      if (res.statusCode != 200 || data == null) {
        throw SpotifyAuthException(
          'Token endpoint returned ${res.statusCode}: ${data?['error_description'] ?? data?['error'] ?? ''}',
        );
      }
      final accessToken = data['access_token'] as String?;
      if (accessToken == null) {
        throw SpotifyAuthException('Token response missing access_token.');
      }
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      // Spotify omits refresh_token on refresh; keep the existing one.
      final previous = await tokenStore.read();
      final refreshToken =
          data['refresh_token'] as String? ?? previous?.refreshToken ?? '';
      return SpotifyTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
        scope: data['scope'] as String? ?? config.scopes.join(' '),
      );
    } on DioException catch (e) {
      throw SpotifyAuthException(
        'Network error contacting Spotify: ${e.message}',
      );
    }
  }
}
