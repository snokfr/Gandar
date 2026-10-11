import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/net/request_gate.dart';
import 'package:gandar/data/youtube/youtube_search.dart';

void main() {
  group('youTubeVideoIdOf', () {
    test('extracts the video id from a YouTube-origin track', () {
      expect(youTubeVideoIdOf('youtube:dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });

    test('returns null for Spotify tracks', () {
      expect(youTubeVideoIdOf('4cOdK2wGLETKBW3PvgPWqT'), isNull);
      expect(youTubeVideoIdOf(''), isNull);
    });

    test('returns null for an empty video id', () {
      expect(youTubeVideoIdOf('youtube:'), isNull);
    });
  });

  group('YouTubeSearcher', () {
    test('maps results and reports them', () async {
      final searcher = YouTubeSearcher(
        fetch: (query, limit) async => [
          YouTubeVideo(
            videoId: 'abc123',
            title: 'A Song',
            author: 'An Artist',
            duration: const Duration(minutes: 3, seconds: 20),
            thumbnailUrl: 'https://img.test/abc.jpg',
          ),
        ],
      );

      final results = await searcher.search('a song');

      expect(results, hasLength(1));
      expect(results.single.videoId, 'abc123');
      // The id is what makes the row playable without a search at runtime.
      expect(results.single.trackId, 'youtube:abc123');
      expect(results.single.url, 'https://www.youtube.com/watch?v=abc123');
      expect(searcher.lastError, isNull);
    });

    test('an empty query does not hit the network', () async {
      var calls = 0;
      final searcher = YouTubeSearcher(
        fetch: (query, limit) async {
          calls++;
          return const <YouTubeVideo>[];
        },
      );

      expect(await searcher.search('   '), isEmpty);
      expect(calls, 0);
    });

    test('a failure yields an empty list instead of throwing', () async {
      final searcher = YouTubeSearcher(
        fetch: (query, limit) async => throw StateError('yt is having a day'),
      );

      final results = await searcher.search('anything');

      expect(results, isEmpty, reason: 'search must not break the screen');
      expect(searcher.lastError, isA<StateError>());
    });

    test('passes the limit through to the fetch', () async {
      int? seenLimit;
      final searcher = YouTubeSearcher(
        fetch: (query, limit) async {
          seenLimit = limit;
          return const <YouTubeVideo>[];
        },
      );

      await searcher.search('x', limit: 7);
      expect(seenLimit, 7);
    });

    test('a retry clears the previous failure', () async {
      var attempt = 0;
      final searcher = YouTubeSearcher(
        fetch: (query, limit) async {
          attempt++;
          if (attempt == 1) throw StateError('first time unlucky');
          return const [YouTubeVideo(videoId: 'ok', title: 'Fine')];
        },
      );

      await searcher.search('x');
      expect(searcher.lastError, isNotNull);

      final second = await searcher.search('x');
      expect(second, hasLength(1));
      expect(searcher.lastError, isNull);
    });

    test('respects the gate concurrency limit', () async {
      var active = 0;
      var peak = 0;
      final searcher = YouTubeSearcher(
        // A gate that allows one request at a time, verified by peak usage.
        gate: RequestGate(
          defaultMaxConcurrent: 1,
          defaultBurst: 10,
          defaultRefillPerSecond: 100,
        ),
        fetch: (query, limit) async {
          active++;
          peak = active > peak ? active : peak;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return const <YouTubeVideo>[];
        },
      );

      await Future.wait([
        searcher.search('a'),
        searcher.search('b'),
        searcher.search('c'),
      ]);

      expect(peak, 1);
    });
  });
}
