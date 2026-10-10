import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/spotify/spotify_api.dart';
import 'package:gandar/data/spotify/spotify_auth.dart';
import 'package:gandar/data/spotify/spotify_tokens.dart';

import 'helpers.dart';

SpotifyTokens _freshTokens() => SpotifyTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

Future<SpotifyApi> _api(FakeHttpAdapter adapter) async {
  final store = InMemoryTokenStore();
  await store.write(_freshTokens());
  final auth = SpotifyAuthService(
    config: const SpotifyAuthConfig(clientId: 'c'),
    tokenStore: store,
    browser: FakeOAuthBrowser((_) => Uri.parse('http://localhost/')),
    http: dioWith(FakeHttpAdapter((_) => tokenBody({}))),
  );
  return SpotifyApi(auth: auth, http: dioWith(adapter));
}

Map<String, dynamic> _savedTrack({
  required String id,
  required String name,
  required String addedAt,
  int durationMs = 200000,
}) => {
  'added_at': addedAt,
  'track': {
    'id': id,
    'name': name,
    'duration_ms': durationMs,
    'artists': [
      {'name': 'Artist One'},
      {'name': 'Artist Two'},
    ],
    'album': {
      'name': 'Album',
      // Spotify returns images largest-first; we keep the smallest for
      // list rows.
      'images': [
        {'url': 'https://img.test/large.jpg'},
        {'url': 'https://img.test/small.jpg'},
      ],
    },
    'external_ids': {'isrc': 'US1234567890'},
  },
};

void main() {
  test('isAuthenticated reflects the token store', () async {
    final api = await _api(FakeHttpAdapter((_) => jsonBody({})));
    expect(await api.isAuthenticated(), isTrue);
  });

  test(
    'getLikedTracks parses saved tracks, artists, artwork and added_at',
    () async {
      final adapter = FakeHttpAdapter(
        (_) => jsonBody({
          'items': [
            _savedTrack(
              id: 't1',
              name: 'First',
              addedAt: '2026-01-02T03:04:05Z',
            ),
            _savedTrack(
              id: 't2',
              name: 'Second',
              addedAt: '2026-01-03T00:00:00Z',
            ),
          ],
          'next': null,
          'total': 2,
        }),
      );
      final api = await _api(adapter);

      final tracks = await api.getLikedTracks();

      expect(tracks, hasLength(2));
      expect(tracks.first.id, 't1');
      expect(tracks.first.title, 'First');
      expect(tracks.first.artists, ['Artist One', 'Artist Two']);
      expect(tracks.first.album, 'Album');
      expect(tracks.first.durationMs, 200000);
      expect(tracks.first.isrc, 'US1234567890');
      expect(tracks.first.artworkUrl, 'https://img.test/small.jpg');
      expect(tracks.first.addedAt, DateTime.parse('2026-01-02T03:04:05Z'));

      // Sends the bearer token and pagination params.
      final request = adapter.requests.single;
      expect(request.headers['Authorization'], 'Bearer access-token');
      expect(request.queryParameters['limit'], 50);
      expect(request.queryParameters['offset'], 0);
    },
  );

  test('getLikedTracks skips unusable entries', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonBody({
        'items': [
          _savedTrack(id: 'ok', name: 'Fine', addedAt: '2026-01-02T00:00:00Z'),
          {'track': null},
          {
            'added_at': null,
            'track': {'id': '', 'name': 'No id'},
          },
        ],
      }),
    );
    final api = await _api(adapter);
    final tracks = await api.getLikedTracks();
    expect(tracks.map((t) => t.id), ['ok']);
  });

  test('getPlaylists parses playlist summaries', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonBody({
        'items': [
          {
            'id': 'p1',
            'name': 'Road Trip',
            'description': 'Driving',
            'collaborative': true,
            'tracks': {'total': 42},
            'owner': {'display_name': 'Me'},
            'images': [
              {'url': 'https://img.test/p1.jpg'},
            ],
          },
        ],
      }),
    );
    final api = await _api(adapter);

    final playlists = await api.getPlaylists();
    expect(playlists.single.id, 'p1');
    expect(playlists.single.name, 'Road Trip');
    expect(playlists.single.trackCount, 42);
    expect(playlists.single.isCollaborative, isTrue);
    expect(playlists.single.ownerName, 'Me');
    expect(playlists.single.artworkUrl, 'https://img.test/p1.jpg');
  });

  test('getPlaylistTracks reads the current `item` shape', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonBody({
        'items': [
          {
            'item': {
              'id': 'x1',
              'name': 'Nested',
              'duration_ms': 1000,
              'artists': [
                {'name': 'A'},
              ],
            },
          },
        ],
      }),
    );
    final api = await _api(adapter);
    final tracks = await api.getPlaylistTracks('p1');

    expect(tracks.single.id, 'x1');
    expect(adapter.requests.single.path, endsWith('/playlists/p1/items'));
  });

  test(
    'getPlaylistTracks falls back to the legacy `track` shape and path',
    () async {
      final adapter = FakeHttpAdapter((options) {
        if (options.path.endsWith('/items')) {
          return jsonBody({
            'error': {'message': 'not found'},
          }, statusCode: 404);
        }
        return jsonBody({
          'items': [
            {
              'track': {
                'id': 'legacy1',
                'name': 'Legacy',
                'artists': [
                  {'name': 'B'},
                ],
              },
            },
          ],
        });
      });
      final api = await _api(adapter);

      final tracks = await api.getPlaylistTracks('p9');
      expect(tracks.single.id, 'legacy1');
      expect(adapter.requests.length, 2);
      expect(adapter.requests.last.path, endsWith('/playlists/p9/tracks'));
    },
  );

  test('saveTrack uses the modern library endpoint with a track URI', () async {
    final adapter = FakeHttpAdapter((_) => jsonBody({}, statusCode: 204));
    final api = await _api(adapter);

    await api.saveTrack('abc');

    final request = adapter.requests.single;
    expect(request.method, 'PUT');
    expect(request.path, endsWith('/me/library'));
    expect(request.queryParameters['uris'], 'spotify:track:abc');
  });

  test('saveTrack falls back to the legacy endpoint when the modern one is'
      ' unavailable', () async {
    final adapter = FakeHttpAdapter((options) {
      if (options.path.endsWith('/me/library')) {
        return jsonBody({
          'error': {'message': 'gone'},
        }, statusCode: 404);
      }
      return jsonBody({}, statusCode: 204);
    });
    final api = await _api(adapter);

    await api.saveTrack('abc');

    expect(adapter.requests.length, 2);
    final legacy = adapter.requests.last;
    expect(legacy.path, endsWith('/me/tracks'));
    expect(legacy.data, {
      'ids': ['abc'],
    });
  });

  test('removeTrack issues a DELETE', () async {
    final adapter = FakeHttpAdapter((_) => jsonBody({}, statusCode: 204));
    final api = await _api(adapter);

    await api.removeTrack('abc');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path, endsWith('/me/library'));
  });

  test(
    'surfaces a 403 as a SpotifyApiException flagged for Development mode',
    () async {
      final adapter = FakeHttpAdapter(
        (_) => jsonBody({
          'error': {'status': 403, 'message': 'User not registered'},
        }, statusCode: 403),
      );
      final api = await _api(adapter);

      try {
        await api.getLikedTracks();
        fail('expected a SpotifyApiException');
      } on SpotifyApiException catch (e) {
        expect(e.statusCode, 403);
        expect(e.message, 'User not registered');
        expect(e.isDevelopmentModeRestriction, isTrue);
      }
    },
  );

  test(
    'surfaces transport failures as SpotifyApiException without a status',
    () async {
      final adapter = FakeHttpAdapter((_) {
        throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/me/tracks'),
          reason: 'offline',
        );
      });
      final api = await _api(adapter);

      await expectLater(
        api.getLikedTracks(),
        throwsA(isA<SpotifyApiException>()),
      );
    },
  );
}
