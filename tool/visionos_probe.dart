// The integration test for the fix: resolve a track with the VISIONOS client
// through `youtube_explode_dart`, then play the URL it hands back with the same
// engine the app uses, and watch the position move.
//
//   LIBMPV_LIBRARY_PATH=<bundle>/libmpv-2.dll \
//     dart run tool/visionos_probe.dart "search query"
import 'dart:async';
import 'dart:io';

import 'package:gandar/data/youtube/audio_stream_selector.dart';
import 'package:gandar/data/youtube/stream_health.dart';
import 'package:media_kit/media_kit.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

String _stamp() {
  final now = DateTime.now();
  return '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}

void log(String message) => stdout.writeln('${_stamp()} $message');

/// The VISIONOS client: yt-dlp's JS-less default, and the one client whose
/// stream URLs googlevideo still serves in full.
YoutubeApiClient visionOsClient() => YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice14,1',
        'osName': 'visionOS',
        'osVersion': '2.0.0.21O209',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 '
            '(KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)',
        'hl': 'en',
        'timeZone': 'UTC',
        'gl': 'US',
        'utcOffsetMinutes': 0,
      },
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  // The library sends the client *name* where YouTube wants its number, and
  // client.headers is spread last, so this is where the number gets set.
  headers: {
    'X-Youtube-Client-Name': '101',
    'X-Youtube-Client-Version': '1.02',
  },
);

Future<void> main(List<String> args) async {
  final target = args.join(' ').trim();
  final play = !args.contains('--no-play');
  MediaKit.ensureInitialized();

  final yt = YoutubeExplode();
  String videoId;
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(target)) {
    videoId = target;
  } else {
    final results = await yt.search.search(target);
    videoId = results.first.id.value;
    log('search "$target" -> $videoId "${results.first.title}"');
  }

  StreamManifest manifest;
  try {
    manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: <YoutubeApiClient>[visionOsClient()],
      requireWatchPage: false,
    );
    log('manifest: ${manifest.audioOnly.length} audio streams '
        '(requireWatchPage: false, no visitor data)');
  } catch (e) {
    log('manifest with requireWatchPage: false failed: ${e.runtimeType} $e');
    manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: <YoutubeApiClient>[visionOsClient()],
      requireWatchPage: true,
    );
    log('manifest: ${manifest.audioOnly.length} audio streams '
        '(requireWatchPage: true)');
  }

  final options = manifest.audioOnly
      .map(
        (s) => AudioOption(
          url: s.url.toString(),
          container: s.container.name,
          bitrateBitsPerSecond: s.bitrate.bitsPerSecond,
          sizeBytes: s.size.totalBytes,
          audioCodec: s.audioCodec,
        ),
      )
      .toList(growable: false);
  final best = const AudioStreamSelector().selectBest(options);
  if (best == null) {
    log('no selectable audio stream');
    exit(1);
  }
  log(
    'selected ${(best.bitrateBitsPerSecond / 1000).round()} kbps '
    '${best.extension} ${(best.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  );

  // The player must be able to reach the end, not just the first megabyte, so
  // every stream the app could choose gets the app's own verdict.
  var servable = 0;
  for (final option in options) {
    final verdict = await const StreamHealth().check(option.url);
    if (verdict == StreamVerdict.serves) servable++;
    final uri = Uri.parse(option.url);
    final query = uri.queryParameters;
    log(
      '  ${(option.bitrateBitsPerSecond / 1000).round()} kbps '
      '${option.extension} itag=${query['itag']} c=${query['c']} '
      'pot=${query['pot'] == null ? '-' : 'present'} '
      'n=${query['n'] == null ? '-' : 'present'} '
      'host=${uri.host} -> $verdict',
    );
  }
  log('$servable of ${options.length} streams are servable');
  yt.close();

  if (!play) exit(servable > 0 ? 0 : 1);

  final player = Player(
    configuration: const PlayerConfiguration(title: 'Gandar probe'),
  );
  player.stream.error.listen((e) => log('mpv ERROR $e'));
  final started = DateTime.now();
  await player.open(Media(best.url), play: true);
  var advanced = Duration.zero;
  for (var i = 1; i <= 8; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    advanced = player.state.position;
    log(
      't=${i}s position=${advanced.inMilliseconds}ms '
      'duration=${player.state.duration.inMilliseconds}ms',
    );
    if (advanced > const Duration(seconds: 3)) break;
  }
  await player.dispose();
  log(
    advanced > const Duration(seconds: 1)
        ? 'RESULT: audio plays (${advanced.inMilliseconds} ms of sound in '
              '${DateTime.now().difference(started).inMilliseconds} ms)'
        : 'RESULT: no audio',
  );
  exit(advanced > const Duration(seconds: 1) ? 0 : 1);
}
