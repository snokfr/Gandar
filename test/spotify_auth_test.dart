import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/spotify/pkce.dart';
import 'package:gandar/data/spotify/spotify_auth.dart';
import 'package:gandar/data/spotify/spotify_tokens.dart';

import 'helpers.dart';

void main() {
  group('Pkce', () {
    test('generates a 43..128 character verifier from the unreserved set', () {
      final verifier = Pkce.generateVerifier(length: 64);
      expect(verifier.length, 64);
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]{43,128}$')));
    });

    test('rejects out-of-range verifier lengths', () {
      expect(
        () => Pkce.generateVerifier(length: 10),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Pkce.generateVerifier(length: 200),
        throwsA(isA<AssertionError>()),
      );
    });

    test('matches the RFC 7636 S256 test vector', () {
      // From RFC 7636 Appendix B.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(
        Pkce.challengeFor(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('challenge is base64url with no padding', () {
      final challenge = Pkce.challengeFor(Pkce.generateVerifier());
      expect(challenge, isNot(contains('=')));
      expect(challenge, isNot(contains('+')));
      expect(challenge, isNot(contains('/')));
    });

    test('state values are unique per call', () {
      final states = {for (var i = 0; i < 50; i++) Pkce.generateState()};
      expect(states.length, 50);
    });
  });

  group('SpotifyAuthConfig', () {
    test('builds a loopback redirect URI on the configured port', () {
      const config = SpotifyAuthConfig(clientId: 'abc', redirectPort: 8888);
      expect(config.redirectUri, 'http://127.0.0.1:8888/callback');
    });

    test('requests the scopes needed for library read and modify', () {
      const config = SpotifyAuthConfig(clientId: 'abc');
      expect(config.scopes, contains('user-library-read'));
      expect(config.scopes, contains('user-library-modify'));
      expect(config.scopes, contains('playlist-read-private'));
    });
  });

  group('SpotifyAuthService', () {
    test('authorize URL carries PKCE params and never a client secret', () {
      final service = SpotifyAuthService(
        config: const SpotifyAuthConfig(clientId: 'my-client'),
        tokenStore: InMemoryTokenStore(),
        browser: FakeOAuthBrowser((_) => Uri.parse('http://localhost/')),
      );
      final url = service.buildAuthorizeUrl(
        state: 'the-state',
        codeChallenge: 'the-challenge',
      );
      expect(url.host, 'accounts.spotify.com');
      expect(url.path, '/authorize');
      expect(url.queryParameters['client_id'], 'my-client');
      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      expect(url.queryParameters['code_challenge'], 'the-challenge');
      expect(url.queryParameters['state'], 'the-state');
      expect(
        url.queryParameters['redirect_uri'],
        'http://127.0.0.1:8888/callback',
      );
      expect(url.queryParameters.containsKey('client_secret'), isFalse);
    });

    test('signIn exchanges the code and stores tokens', () async {
      final store = InMemoryTokenStore();
      final adapter = FakeHttpAdapter(
        (_) => tokenBody({
          'access_token': 'AT',
          'refresh_token': 'RT',
          'expires_in': 3600,
          'scope': 'user-library-read',
        }),
      );
      final service = SpotifyAuthService(
        config: const SpotifyAuthConfig(clientId: 'my-client'),
        tokenStore: store,
        browser: FakeOAuthBrowser(
          (url) => Uri.parse(
            'http://127.0.0.1:8888/callback?code=the-code&state=${url.queryParameters['state']}',
          ),
        ),
        http: dioWith(adapter),
      );

      final tokens = await service.signIn();

      expect(tokens.accessToken, 'AT');
      expect(tokens.refreshToken, 'RT');
      expect(await store.read(), isNotNull);

      // The code exchange must send the verifier, never a secret.
      final body = Map<String, String>.from(
        adapter.requests.single.data as Map,
      );
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'the-code');
      expect(body['code_verifier'], isNotEmpty);
      expect(body.containsKey('client_secret'), isFalse);
    });

    test('signIn rejects a mismatched state', () async {
      final service = SpotifyAuthService(
        config: const SpotifyAuthConfig(clientId: 'c'),
        tokenStore: InMemoryTokenStore(),
        browser: FakeOAuthBrowser(
          (_) =>
              Uri.parse('http://127.0.0.1:8888/callback?code=x&state=tampered'),
        ),
        http: dioWith(FakeHttpAdapter((_) => tokenBody({}))),
      );
      await expectLater(service.signIn(), throwsA(isA<SpotifyAuthException>()));
    });

    test('signIn surfaces an authorization error from the callback', () async {
      final service = SpotifyAuthService(
        config: const SpotifyAuthConfig(clientId: 'c'),
        tokenStore: InMemoryTokenStore(),
        browser: FakeOAuthBrowser(
          (_) =>
              Uri.parse('http://127.0.0.1:8888/callback?error=access_denied'),
        ),
        http: dioWith(FakeHttpAdapter((_) => tokenBody({}))),
      );
      await expectLater(service.signIn(), throwsA(isA<SpotifyAuthException>()));
    });

    test(
      'validAccessToken refreshes when the stored token has expired',
      () async {
        final store = InMemoryTokenStore();
        await store.write(
          SpotifyTokens(
            accessToken: 'OLD',
            refreshToken: 'RT',
            expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        );
        final adapter = FakeHttpAdapter(
          (_) => tokenBody({'access_token': 'NEW', 'expires_in': 3600}),
        );
        final service = SpotifyAuthService(
          config: const SpotifyAuthConfig(clientId: 'c'),
          tokenStore: store,
          browser: FakeOAuthBrowser((_) => Uri.parse('http://localhost/')),
          http: dioWith(adapter),
        );

        expect(await service.validAccessToken(), 'NEW');
        final body = Map<String, String>.from(
          adapter.requests.single.data as Map,
        );
        expect(body['grant_type'], 'refresh_token');
        expect(body['refresh_token'], 'RT');

        // Spotify omits refresh_token on refresh; the old one must be kept.
        expect((await store.read())!.refreshToken, 'RT');
      },
    );

    test(
      'validAccessToken reuses a fresh token without a network call',
      () async {
        final store = InMemoryTokenStore();
        final service = await authedService(store: store);
        expect(await service.validAccessToken(), 'access-token');
      },
    );

    test('validAccessToken throws when not signed in', () async {
      final service = SpotifyAuthService(
        config: const SpotifyAuthConfig(clientId: 'c'),
        tokenStore: InMemoryTokenStore(),
        browser: FakeOAuthBrowser((_) => Uri.parse('http://localhost/')),
      );
      await expectLater(
        service.validAccessToken(),
        throwsA(isA<SpotifyAuthException>()),
      );
    });

    test('signOut clears stored tokens', () async {
      final store = InMemoryTokenStore();
      final service = await authedService(store: store);
      expect(await service.hasStoredTokens(), isTrue);
      await service.signOut();
      expect(await service.hasStoredTokens(), isFalse);
    });
  });

  group('SpotifyTokens', () {
    test('treats a token expiring within a minute as expired', () {
      final soon = SpotifyTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      expect(soon.isExpired, isTrue);

      final later = SpotifyTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(later.isExpired, isFalse);
    });

    test('JSON round-trips', () {
      final tokens = SpotifyTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
        scope: 'x y',
      );
      expect(
        SpotifyTokens.fromJson(
          jsonDecode(jsonEncode(tokens.toJson())) as Map<String, dynamic>,
        ).toJson(),
        tokens.toJson(),
      );
    });
  });
}
