import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/youtube/youtube_explode_resolver.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Serves one canned response to everything, and counts what was asked.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.statusCode, this.body);

  final int statusCode;
  final String body;
  final List<Uri> requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      contentLength: bytes.length,
      request: request,
      headers: const <String, String>{'content-type': 'text/html'},
    );
  }
}

class _NoMappings implements MappingRepository {
  @override
  Future<String?> findVideoId(String spotifyTrackId) async => null;

  @override
  Future<void> saveMapping(String spotifyTrackId, String videoId) async {}

  @override
  Future<void> clearMapping(String spotifyTrackId) async {}
}

/// A track that names its video, so no search request is made and the only
/// traffic is the stream request itself.
final Track _directTrack = Track(
  id: 'youtube:6NHt1ss8PNs',
  title: 'Buddy',
  artists: const <String>['Bobby S.'],
);

void main() {
  group('isYouTubeRefusal', () {
    test('counts rate limiting, bot walls and 5xx as refusals', () {
      expect(isYouTubeRefusal(RequestLimitExceededException('sorry')), isTrue);
      expect(isYouTubeRefusal(FatalFailureException('fatal', 404)), isTrue);
      expect(isYouTubeRefusal(TransientFailureException('5xx')), isTrue);
      expect(isYouTubeRefusal(HttpClientClosedException()), isTrue);
    });

    test('does not count one unusable video as a refusal', () {
      expect(isYouTubeRefusal(VideoUnplayableException('unplayable')), isFalse);
      expect(isYouTubeRefusal(VideoUnavailableException('gone')), isFalse);
      expect(isYouTubeRefusal(ArgumentError('bug')), isFalse);
    });

    test('counts a bot wall as a refusal, not as a bad video', () {
      // YouTube answers an untrusted request with this, and it would answer
      // every track in the queue the same way.
      final botWall = VideoUnplayableException.unplayable(
        VideoId('6NHt1ss8PNs'),
        reason: "Sign in to confirm you're not a bot",
      );

      expect(isYouTubeRefusal(botWall), isTrue);
      expect(refusalMessage(botWall), contains('not a bot'));
    });
  });

  group('the extraction client', () {
    test('is VISIONOS, the one whose URLs the CDN serves in full', () {
      final client = visionOsClient();

      expect(
        client.payload['context']['client']['clientName'],
        'VISIONOS',
        reason:
            'ios and android hand out URLs that 403 past their first '
            'megabyte; the other clients answer with a bot wall',
      );
      // YouTube identifies clients by number, and the library puts the *name*
      // in this header, so the number has to come from `headers`.
      expect(client.headers['X-Youtube-Client-Name'], '101');
      expect(client.headers['X-Youtube-Client-Version'], '1.02');
    });

    test('leads the candidate list, with the rest as fallbacks', () {
      final resolver = YoutubeExplodeResolver(mappings: _NoMappings());
      final names = resolver.clients
          .map((c) => c.payload['context']['client']['clientName'])
          .toList();

      expect(names.first, 'VISIONOS');
      expect(
        names,
        <String>['VISIONOS', 'ANDROID', 'IOS', 'TVHTML5'],
        reason:
            'the others are what is left if YouTube stops serving the one '
            'that is measured to work today',
      );
      expect(
        resolver.preferredClient,
        isNull,
        reason: 'a client is only preferred after its stream really served',
      );
    });

    test('a dead stream is worth a second look with a fresh URL', () {
      final resolver = YoutubeExplodeResolver(mappings: _NoMappings());

      expect(
        resolver.attemptsPerClient,
        greaterThan(1),
        reason:
            'the same client both served and refused a full file within one '
            'afternoon, so one refusal must not condemn it',
      );
    });
  });

  group('a refusal from YouTube', () {
    late _ScriptedClient client;
    late YoutubeExplodeResolver resolver;

    setUp(() {
      // 429 is what the extractor turns into RequestLimitExceededException.
      client = _ScriptedClient(429, 'too many requests');
      resolver = YoutubeExplodeResolver(
        mappings: _NoMappings(),
        client: YoutubeExplode(httpClient: YoutubeHttpClient(client)),
      );
    });

    test(
      'is reported with YouTube as the cause, not as a dead library',
      () async {
        await expectLater(
          resolver.resolve(_directTrack),
          throwsA(
            isA<AudioResolutionException>()
                .having((e) => e.message, 'message', contains('refusing'))
                .having((e) => e.cause, 'cause', isNotNull),
          ),
        );
        expect(client.requests, isNotEmpty);
      },
    );

    test('stops the extraction attempts instead of hammering', () async {
      await resolver.resolve(_directTrack).then<void>((_) {}, onError: (_) {});
      final afterFirst = client.requests.length;

      for (var i = 0; i < 5; i++) {
        await resolver
            .resolve(_directTrack)
            .then<void>((_) {}, onError: (_) {});
      }

      expect(
        client.requests.length,
        afterFirst,
        reason:
            'every further resolve should fail without touching the network',
      );
    });

    test('names the wait in the message so the UI can be honest', () async {
      await resolver.resolve(_directTrack).then<void>((_) {}, onError: (_) {});

      await expectLater(
        resolver.resolve(_directTrack),
        throwsA(
          isA<AudioResolutionException>().having(
            (e) => e.message,
            'message',
            contains('waiting'),
          ),
        ),
      );
    });

    test('asks again once the cool-down has passed', () async {
      var now = DateTime(2026, 1, 1);
      final clocked = YoutubeExplodeResolver(
        mappings: _NoMappings(),
        client: YoutubeExplode(httpClient: YoutubeHttpClient(client)),
        refusalCooldown: const Duration(minutes: 1),
        clock: () => now,
      );

      await clocked.resolve(_directTrack).then<void>((_) {}, onError: (_) {});
      final afterFirst = client.requests.length;
      await clocked.resolve(_directTrack).then<void>((_) {}, onError: (_) {});
      expect(
        client.requests.length,
        afterFirst,
        reason: 'inside the cool-down',
      );

      now = now.add(const Duration(minutes: 2));
      await clocked.resolve(_directTrack).then<void>((_) {}, onError: (_) {});
      expect(
        client.requests.length,
        greaterThan(afterFirst),
        reason: 'after the cool-down it is worth one more try',
      );
    });
  });
}
