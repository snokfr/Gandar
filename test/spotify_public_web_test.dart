import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/spotify/spotify_public.dart';
import 'package:gandar/data/spotify/spotify_public_web.dart';

import 'helpers.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const _playlist = SpotifyLink(
  kind: SpotifyLinkKind.playlist,
  id: '37i9dQZF1DXcBWIGoYBM5M',
);

/// Serves the recorded embed page for `/embed/...` and the recorded oEmbed
/// document for `/oembed`, so the client is exercised without the network.
FakeHttpAdapter _spotifyPages({
  String? embedBody,
  int embedStatus = 200,
  bool withArtwork = true,
}) {
  return FakeHttpAdapter((options) {
    if (options.path.contains('oembed')) {
      if (!withArtwork) {
        return ResponseBody.fromString('{}', 404);
      }
      return ResponseBody.fromString(
        _fixture('spotify_oembed_playlist.json'),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      embedBody ?? _fixture('spotify_embed_playlist.html'),
      embedStatus,
      headers: {
        Headers.contentTypeHeader: ['text/html'],
      },
    );
  });
}

void main() {
  test('requests the embed page Spotify itself uses', () {
    final adapter = _spotifyPages(withArtwork: false);
    final client = SpotifyPublicWeb(http: dioWith(adapter));

    expect(
      SpotifyPublicWeb.embedUrl(_playlist).toString(),
      'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
    );
    expect(client, isNotNull);
  });

  test('reads a public playlist end to end', () async {
    final adapter = _spotifyPages();
    final client = SpotifyPublicWeb(http: dioWith(adapter));

    final collection = await client.fetchCollection(_playlist);

    expect(collection.name, isNotEmpty);
    expect(collection.tracks, hasLength(3));
    expect(collection.link.id, _playlist.id);
    expect(adapter.requests.first.headers['User-Agent'], contains('Mozilla'));
  });

  test('falls back to oEmbed when the page carries no artwork', () async {
    // The embed page for an album has no coverArt at all.
    final page = _fixture('spotify_embed_playlist.html')
        .replaceFirst(RegExp(r'"coverArt":\{.*?\}'), '"coverArt":{}');
    final client = SpotifyPublicWeb(
      http: dioWith(_spotifyPages(embedBody: page)),
    );

    final collection = await client.fetchCollection(_playlist);

    expect(collection.artworkUrl, startsWith('https://i.scdn.co/image/'));
    expect(collection.tracks, hasLength(3));
  });

  test(
    'a private or missing playlist gets an explanation, not a stack',
    () async {
      final client = SpotifyPublicWeb(
        http: dioWith(_spotifyPages(embedBody: 'not found', embedStatus: 404)),
      );

      await expectLater(
        client.fetchCollection(_playlist),
        throwsA(
          isA<SpotifyPublicException>().having(
            (e) => e.message,
            'message',
            contains('public'),
          ),
        ),
      );
    },
  );

  test('a page with no data is reported in words', () async {
    final client = SpotifyPublicWeb(
      http: dioWith(
        _spotifyPages(embedBody: _fixture('spotify_embed_blocked.html')),
      ),
    );

    await expectLater(
      client.fetchCollection(_playlist),
      throwsA(isA<SpotifyPublicException>()),
    );
  });

  test('an unsupported kind is refused before any request', () async {
    final adapter = _spotifyPages();
    final client = SpotifyPublicWeb(http: dioWith(adapter));

    await expectLater(
      client.fetchCollection(
        const SpotifyLink(kind: SpotifyLinkKind.artist, id: 'abc'),
      ),
      throwsA(
        isA<SpotifyPublicException>().having(
          (e) => e.message,
          'message',
          contains('artist'),
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('a transport failure is a sentence, not a DioException', () async {
    final adapter = FakeHttpAdapter((options) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    });
    final client = SpotifyPublicWeb(http: dioWith(adapter));

    await expectLater(
      client.fetchCollection(_playlist),
      throwsA(
        isA<SpotifyPublicException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach Spotify'),
        ),
      ),
    );
  });
}
