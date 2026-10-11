import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/spotify/spotify_public.dart';

/// Fixtures are trimmed pages captured from Spotify itself, so the parser is
/// tested against the real payload shape rather than an invented one.
String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('SpotifyLink.parse', () {
    const id = '37i9dQZF1DXcBWIGoYBM5M';

    test('reads a playlist share link, with tracking parameters', () {
      final link = SpotifyLink.parse(
        'https://open.spotify.com/playlist/$id?si=abc123&pt=xyz',
      );
      expect(link!.kind, SpotifyLinkKind.playlist);
      expect(link.id, id);
      expect(link.uri, 'spotify:playlist:$id');
      expect(link.isReadable, isTrue);
    });

    test('reads the embed and locale-prefixed forms of the same link', () {
      for (final url in <String>[
        'https://open.spotify.com/embed/playlist/$id',
        'https://open.spotify.com/intl-de/playlist/$id',
        'open.spotify.com/playlist/$id',
        '  https://open.spotify.com/playlist/$id  ',
      ]) {
        final link = SpotifyLink.parse(url);
        expect(link?.kind, SpotifyLinkKind.playlist, reason: url);
        expect(link?.id, id, reason: url);
      }
    });

    test('reads track, album and legacy user-playlist URIs', () {
      expect(
        SpotifyLink.parse('spotify:track:4cOdK2wGLETKBW3PvgPWqT')?.kind,
        SpotifyLinkKind.track,
      );
      expect(
        SpotifyLink.parse('spotify:album:4aawyAB9vmqN3uQ7FjRGTy')?.kind,
        SpotifyLinkKind.album,
      );
      final legacy = SpotifyLink.parse('spotify:user:someone:playlist:$id');
      expect(legacy?.kind, SpotifyLinkKind.playlist);
      expect(legacy?.id, id);
    });

    test('knows what it cannot read', () {
      final artist = SpotifyLink.parse(
        'https://open.spotify.com/artist/0OdUWJ0sBjDrqHygGUXeCF',
      );
      expect(artist?.kind, SpotifyLinkKind.artist);
      expect(artist?.isReadable, isFalse);
    });

    test('rejects things that are not links', () {
      expect(SpotifyLink.parse(''), isNull);
      expect(SpotifyLink.parse('hello world'), isNull);
      expect(
        SpotifyLink.parse('https://example.com/playlist/whatever'),
        isNull,
      );
      expect(SpotifyLink.parse('spotify:playlist:tooshort'), isNull);
    });

    test('treats a bare id as a playlist, which is what people paste', () {
      final link = SpotifyLink.parse(id);
      expect(link?.kind, SpotifyLinkKind.playlist);
      expect(link?.id, id);
    });
  });

  group('SpotifyEmbedPage.parse', () {
    const link = SpotifyLink(
      kind: SpotifyLinkKind.playlist,
      id: '37i9dQZF1DXcBWIGoYBM5M',
    );

    test('reads name, artwork and tracks out of a real embed page', () {
      final collection = const SpotifyEmbedPage().parse(
        _fixture('spotify_embed_playlist.html'),
        link: link,
      );

      expect(collection.name, isNotEmpty);
      expect(collection.artworkUrl, startsWith('https://i.scdn.co/image/'));
      expect(collection.tracks, hasLength(3));
      final first = collection.tracks.first;
      expect(first.id, '3zOYmiNOuyDL0ClxJcEJ0T');
      expect(first.title, 'Stop The Wedding!');
      expect(first.artists, <String>['Ashe']);
      expect(first.durationMs, 198840);
      // A playlist's cover must not be stamped on every row; the per-track
      // artwork pass fills those in later.
      expect(first.artworkUrl, isNull);
      expect(collection.trackListTruncated, isFalse);
    });

    test('splits multi-artist credits on the non-breaking separator', () {
      final html = _fixture('spotify_embed_playlist.html').replaceFirst(
        '"subtitle": "Ashe"',
        '"subtitle": "Pitbull,\u00a0Sensato"',
      );
      final collection = const SpotifyEmbedPage().parse(html, link: link);
      expect(collection.tracks.first.artists, <String>['Pitbull', 'Sensato']);
    });

    test('says so in a sentence when the page has no data', () {
      expect(
        () => const SpotifyEmbedPage().parse(
          _fixture('spotify_embed_blocked.html'),
          link: link,
        ),
        throwsA(
          isA<SpotifyPublicException>().having(
            (e) => e.message,
            'message',
            contains('private'),
          ),
        ),
      );
    });

    test('flags a list that hit Spotify\'s page limit', () {
      final html = _fixture('spotify_embed_playlist.html').replaceFirst(
        '"trackList": [',
        '"trackList": [${List<String>.filled(50, 'null').join(',')},',
      );
      expect(html.contains('null,null'), isTrue, reason: 'fixture rewritten');
      final collection = const SpotifyEmbedPage().parse(html, link: link);
      expect(collection.trackListTruncated, isTrue);
    });

    test('album tracks do inherit the album cover, which is correct', () {
      const album = SpotifyLink(
        kind: SpotifyLinkKind.album,
        id: '4aawyAB9vmqN3uQ7FjRGTy',
      );
      final collection = const SpotifyEmbedPage().parse(
        _fixture('spotify_embed_playlist.html'),
        link: album,
      );
      expect(collection.tracks.first.artworkUrl, collection.artworkUrl);
    });

    test('the playlist summary matches what was imported', () {
      final collection = const SpotifyEmbedPage().parse(
        _fixture('spotify_embed_playlist.html'),
        link: link,
      );
      final playlist = collection.toPlaylist();
      expect(playlist.id, link.id);
      expect(playlist.name, collection.name);
      expect(playlist.trackCount, collection.tracks.length);
      expect(playlist.artworkUrl, collection.artworkUrl);
    });
  });

  group('SpotifyOEmbed', () {
    test('builds the documented URL', () {
      final uri = SpotifyOEmbed.urlFor(
        const SpotifyLink(kind: SpotifyLinkKind.track, id: 'abc'),
      );
      expect(uri.host, 'open.spotify.com');
      expect(uri.path, '/oembed');
      expect(uri.queryParameters['url'], 'https://open.spotify.com/track/abc');
    });

    test('reads a real response', () {
      final parsed = SpotifyOEmbed.parse(
        _fixture('spotify_oembed_playlist.json'),
      );
      expect(parsed, isNotNull);
      expect(parsed!.title, contains('Top Hits'));
      expect(parsed.thumbnailUrl, startsWith('https://'));
    });

    test('returns null rather than throwing on nonsense', () {
      expect(SpotifyOEmbed.parse('{"unexpected": true}'), isNull);
    });
  });
}
