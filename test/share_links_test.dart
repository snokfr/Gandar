import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/features/player/share_links.dart';

Track _track({
  required String id,
  String title = 'Stop The Wedding!',
  List<String> artists = const <String>['An Artist'],
}) => Track(id: id, title: title, artists: artists);

/// A real Spotify track id shape: 22 base-62 characters.
const String _spotifyId = '4cOdK2wGLETKBW3PvgPWqT';

void main() {
  group('share links', () {
    test('a YouTube-sourced track links to that exact video', () {
      final links = ShareLinks.forTrack(_track(id: 'youtube:dQw4w9WgXcQ'));

      final youTube = links.firstWhere((l) => l.source == 'youtube');
      expect(youTube.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(youTube.exact, isTrue);

      // The Spotify side falls back to a search, because a YouTube track has no
      // Spotify id. A disabled button would be a worse answer.
      final spotify = links.firstWhere((l) => l.source == 'spotify');
      expect(spotify.exact, isFalse);
      expect(spotify.url, startsWith('https://open.spotify.com/search/'));
      // Round-trip rather than a hard-coded escape: what matters is that the
      // query survives the URL, whatever encoding the platform chooses.
      expect(
        Uri.decodeQueryComponent(spotify.url.split('/search/').last),
        'An Artist Stop The Wedding!',
      );
    });

    test('a Spotify track links to itself, and YouTube to the mapping', () {
      final links = ShareLinks.forTrack(
        _track(id: _spotifyId),
        youtubeVideoId: 'dQw4w9WgXcQ',
      );

      expect(
        links.firstWhere((l) => l.source == 'spotify').url,
        'https://open.spotify.com/track/$_spotifyId',
      );
      // Without a resolved video there is no exact YouTube link; the cached
      // mapping is what makes it exact.
      expect(
        links.firstWhere((l) => l.source == 'youtube').url,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(links.every((l) => l.exact), isTrue);
    });

    test('without a mapping, YouTube becomes a search link', () {
      final links = ShareLinks.forTrack(_track(id: _spotifyId));
      final youTube = links.firstWhere((l) => l.source == 'youtube');

      expect(youTube.exact, isFalse);
      expect(youTube.label, 'YouTube search');
      expect(youTube.url, contains('youtube.com/results?search_query='));
    });

    test('text output carries the artist, title and both links', () {
      final track = _track(id: _spotifyId, artists: const <String>['A', 'B']);
      final text = ShareLinks.asText(
        track,
        ShareLinks.forTrack(track, youtubeVideoId: 'v1'),
      );

      expect(text.split('\n').first, 'A, B — Stop The Wedding!');
      expect(text, contains('YouTube: https://www.youtube.com/watch?v=v1'));
      expect(
        text,
        contains('Spotify: https://open.spotify.com/track/$_spotifyId'),
      );
    });

    test('spotify ids are recognised by shape alone', () {
      expect(ShareLinks.isSpotifyId(_spotifyId), isTrue);
      expect(ShareLinks.isSpotifyId('youtube:abc'), isFalse);
      expect(ShareLinks.isSpotifyId('short'), isFalse);
      expect(ShareLinks.isSpotifyId('not-base-62-due-to-!!!!'), isFalse);
    });
  });
}
