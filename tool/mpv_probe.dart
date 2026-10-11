// Diagnostics for "the queue skips through tracks and nothing plays".
//
// Two experiments in one process:
//
//  1. which YouTube extraction client can still produce a stream manifest, with
//     and without the watch page (the watch page is the request YouTube rate
//     limits first);
//  2. whether mpv will actually play the URL that comes out, with mpv's own log
//     turned on.
//
// It imports nothing from `package:gandar/...` on purpose: those reach Flutter
// through path_provider, which a plain `dart run` cannot compile.
//
//   LIBMPV_LIBRARY_PATH=<bundle>/libmpv-2.dll \
//     dart run tool/mpv_probe.dart <videoId|"search query"> [--play]
import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

String _stamp() {
  final now = DateTime.now();
  return '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}

void log(String message) => stdout.writeln('${_stamp()} $message');

final List<YoutubeApiClient> _clients = <YoutubeApiClient>[
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.android,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.androidMusic,
  YoutubeApiClient.mediaConnect,
  YoutubeApiClient.ios,
  YoutubeApiClient.tv,
  YoutubeApiClient.mweb,
  YoutubeApiClient.safari,
];

/// A ranged GET, which is what a player does. A full GET is never needed to
/// judge whether a stream is playable.
Future<String> _probeUrl(String url, {required bool headers}) async {
  try {
    final request = await HttpClient().getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
    if (headers) {
      request.headers
        ..set(HttpHeaders.refererHeader, 'https://www.youtube.com/')
        ..set('Origin', 'https://www.youtube.com');
    }
    final response = await request.close();
    await response.drain<void>();
    return '${response.statusCode}';
  } catch (e) {
    return 'ERR ${e.runtimeType}';
  }
}

String _describe(Object error) {
  final text = error.toString().replaceAll('\n', ' ');
  return text.length > 130 ? '${text.substring(0, 130)}…' : text;
}

Future<StreamManifest?> _tryManifest(
  YoutubeExplode yt,
  String videoId,
  YoutubeApiClient client,
  bool requireWatchPage,
) async {
  final name = client.payload['context']['client']['clientName'];
  try {
    final manifest = await yt.videos.streamsClient
        .getManifest(
          videoId,
          ytClients: <YoutubeApiClient>[client],
          requireWatchPage: requireWatchPage,
        )
        .timeout(const Duration(seconds: 25));
    log(
      '  OK   $name (watchPage: $requireWatchPage): '
      '${manifest.audioOnly.length} audio, '
      '${manifest.videoOnly.length} video streams',
    );
    return manifest;
  } catch (e) {
    log(
      '  FAIL $name (watchPage: $requireWatchPage): '
      '${e.runtimeType} ${_describe(e)}',
    );
    return null;
  }
}

Future<void> main(List<String> args) async {
  final play = args.contains('--play');
  final localIndex = args.indexOf('--local');
  final target = args.where((a) => !a.startsWith('--')).join(' ').trim();
  if (target.isEmpty && localIndex < 0) {
    stderr.writeln(
      'usage: dart run tool/mpv_probe.dart <videoId|"query"> [--play]\n'
      '       dart run tool/mpv_probe.dart --local <file>',
    );
    exit(64);
  }

  log(
    'libmpv: ${Platform.environment['LIBMPV_LIBRARY_PATH'] ?? '(default paths)'}',
  );
  MediaKit.ensureInitialized();

  // `--local <file>` checks the player itself: mpv, the audio device and our
  // own engine path, with no network involved. A local file that plays while
  // googlevideo URLs do not is what separates "the player is broken" from
  // "YouTube is refusing us".
  if (localIndex >= 0) {
    final path = args[localIndex + 1];
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('no such file: $path');
      exit(66);
    }
    log('local file: ${file.path} (${file.lengthSync()} bytes)');
    final localPlayer = Player(
      configuration: const PlayerConfiguration(title: 'Gandar probe'),
    );
    localPlayer.stream.error.listen((e) => log('mpv ERROR $e'));
    await localPlayer.open(Media(file.uri.toString()), play: true);
    var advanced = false;
    for (var i = 1; i <= 6; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final position = localPlayer.state.position;
      if (position > Duration.zero) advanced = true;
      log(
        't=${i}s position=${position.inMilliseconds}ms '
        'duration=${localPlayer.state.duration.inMilliseconds}ms',
      );
    }
    await localPlayer.dispose();
    log(
      advanced
          ? 'RESULT: the player decodes and advances a local file'
          : 'RESULT: even a local file does not play',
    );
    exit(advanced ? 0 : 1);
  }

  final yt = YoutubeExplode();
  String videoId;
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(target)) {
    videoId = target;
  } else {
    final results = await yt.search.search(target);
    videoId = results.first.id.value;
    log('search "$target" -> $videoId "${results.first.title}"');
  }

  log('extraction clients:');
  StreamManifest? working;
  YoutubeApiClient? workingClient;
  var workingWatchPage = false;
  for (final client in _clients) {
    for (final requireWatchPage in <bool>[false, true]) {
      final manifest = await _tryManifest(
        yt,
        videoId,
        client,
        requireWatchPage,
      );
      if (manifest != null && working == null) {
        working = manifest;
        workingClient = client;
        workingWatchPage = requireWatchPage;
      }
    }
  }

  if (working == null) {
    log('no client could produce a manifest — extraction is being refused');
    yt.close();
    exit(1);
  }

  final audio = working.audioOnly.toList()
    ..sort(
      (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
    );
  if (audio.isEmpty) {
    log('manifest has no audio-only streams');
    yt.close();
    exit(1);
  }
  log(
    'working route: ${workingClient!.payload['context']['client']['clientName']} '
    '(watchPage: $workingWatchPage)',
  );

  // Which of the offered streams will the CDN actually serve? The library only
  // HEAD-checks its first stream, so a manifest can look healthy and still
  // contain nothing playable.
  String? playable;
  for (final stream in audio) {
    final plain = await _probeUrl(stream.url.toString(), headers: false);
    final withHeaders = await _probeUrl(stream.url.toString(), headers: true);
    log(
      '  itag=${stream.tag} ${stream.container.name} '
      '${(stream.bitrate.bitsPerSecond / 1000).round()} kbps '
      '${stream.audioCodec} -> GET $plain / $withHeaders (with headers)',
    );
    if ((plain == '200' || plain == '206') && playable == null) {
      playable = stream.url.toString();
    }
  }

  if (playable == null) {
    log('every audio URL is refused — the manifest is not playable');
    if (!play) {
      yt.close();
      exit(1);
    }
  }

  if (!play) {
    log('done (pass --play to test playback)');
    yt.close();
    exit(0);
  }

  // mpv is handed a URL with no Range header, and googlevideo answers that with
  // 403. These are the three ways out of that; the first one that actually
  // advances the position is the fix worth making in the app.
  final m4a = audio.firstWhere(
    (s) => s.container.name == 'mp4',
    orElse: () => audio.first,
  );
  final url = m4a.url.toString();

  Future<bool> tryMpv(String label, Media media) async {
    log('--- $label');
    final player = Player(
      configuration: const PlayerConfiguration(title: 'Gandar probe'),
    );
    final subs = <StreamSubscription<dynamic>>[
      player.stream.log.listen((e) {
        final text = e.text.trim();
        if (text.contains('Failed') || text.contains('error')) {
          log('mpv [${e.prefix}] $text');
        }
      }),
      player.stream.error.listen(
        (e) =>
            log('mpv ERROR ${e.length > 120 ? '${e.substring(0, 120)}…' : e}'),
      ),
    ];
    await player.open(media, play: true);
    var advanced = false;
    for (var i = 1; i <= 8; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final position = player.state.position;
      if (position > Duration.zero) advanced = true;
      log(
        '  t=${i}s position=${position.inMilliseconds}ms '
        'duration=${player.state.duration.inMilliseconds}ms',
      );
      if (advanced && i >= 3) break;
    }
    await player.dispose();
    for (final sub in subs) {
      await sub.cancel();
    }
    log(advanced ? '  RESULT: plays' : '  RESULT: does not play');
    return advanced;
  }

  if (await tryMpv('A. plain URL (what the app does today)', Media(url))) {
    yt.close();
    exit(0);
  }
  if (await tryMpv(
    'B. URL with an explicit Range header',
    Media(url, httpHeaders: const <String, String>{'Range': 'bytes=0-'}),
  )) {
    log('FIX: send Range: bytes=0- with the stream');
    yt.close();
    exit(0);
  }

  log('--- C. download first, then play the local file');
  final cacheDir = Directory('${Directory.systemTemp.path}/gandar-probe');
  await cacheDir.create(recursive: true);
  final file = File('${cacheDir.path}/${m4a.tag}.${m4a.container.name}');
  final request = await HttpClient().getUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
  final response = await request.close();
  log('  download status ${response.statusCode}');
  final sink = file.openWrite();
  final bytes = await response.fold<int>(0, (sum, chunk) {
    sink.add(chunk);
    return sum + chunk.length;
  });
  await sink.close();
  log(
    '  wrote ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB to ${file.path}',
  );
  final localPlays = await tryMpv('local file', Media(file.uri.toString()));
  if (localPlays) log('FIX: fetch with Dart, play the file');

  yt.close();
  log('done');
  exit(0);
}
