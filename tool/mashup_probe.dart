// Can Gandar play a *mashup* — two songs layered, each trimmed to the part you
// want, each entering where you say, at its own level?
//
// Two routes were measured before the mashup screen was built on either:
//
//  1. **One mpv, two sources, a `lavfi-complex` graph.** Impossible in this
//     build. `audio-add` does bring in a second decoded source and mpv feeds
//     the graph, but the libavfilter inside the shipped `libmpv-2.dll` has no
//     `atrim`, `amix`, `adelay`, `asetpts`, `acrossfade`, `afade`, `pan` or
//     `loudnorm` — the same reason the app's log says "Option af: loudnorm
//     doesn't exist". Only `volume`, `equalizer`, `concat` and `aresample` are
//     there. There is nothing to trim or sum with.
//  2. **Two mpv instances, one per part.** This is what the app does. Each
//     part is a player of its own: it is seeked to where the part starts, told
//     to end where it stops, set to its own volume, and started at its offset.
//     The layers are summed by the system mixer, which is exactly how a live
//     mashup is performed.
//
// This probe proves route 2: two players running together, both clocks moving,
// each honouring its own end point and level.
//
//   LIBMPV_LIBRARY_PATH=<bundle>/libmpv-2.dll \
//     dart run tool/mashup_probe.dart [<file-or-url> <file-or-url>]
import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

String _stamp() {
  final now = DateTime.now();
  return '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}

void log(String message) => stdout.writeln('${_stamp()} $message');

/// The two sources to layer: what was asked for, or two from the audio cache —
/// real googlevideo downloads, which is the material a mashup mixes.
List<String> _sources(List<String> args) {
  if (args.length >= 2) return args.sublist(0, 2);

  final roaming = Platform.environment['APPDATA'] ?? '';
  final cache = Directory('$roaming\\com.gandar\\gandar\\cache');
  if (!cache.existsSync()) return const <String>[];
  final files =
      cache
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.part'))
          .where(
            (f) =>
                const <String>['.webm', '.m4a', '.mp3', '.opus'].any(
                  f.path.endsWith,
                ),
          )
          .toList()
        ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
  return files.take(2).map((f) => f.path).toList();
}

/// One part of the mix, the way the app describes it.
class Part {
  const Part({
    required this.url,
    required this.startMs,
    required this.endMs,
    required this.offsetMs,
    required this.volume,
  });

  final String url;
  final int startMs;
  final int endMs;
  final int offsetMs;
  final double volume;
}

/// Plays [parts] together and reports what each player did.
Future<void> _run(List<Part> parts, {required Duration watch}) async {
  final players = <Player>[];
  final logs = <String>[];
  final subs = <StreamSubscription<dynamic>>[];

  try {
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final player = Player();
      players.add(player);
      subs.add(
        player.stream.error.listen((e) {
          if (e.isEmpty) return;
          logs.add('part ${i + 1}: $e');
          log('part ${i + 1} ERROR $e');
        }),
      );
      // Headless: this proves the two decoders run together; whether they are
      // audible together is the one thing a probe cannot check.
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('ao', 'null');
      }
      await player.open(Media(part.url), play: false);
      if (part.startMs > 0) {
        await player.seek(Duration(milliseconds: part.startMs));
      }
      await player.setVolume(part.volume * 100);
      // The end of the part is mpv's own business, so a trimmed part stops
      // where it was told to even if nobody is watching the clock.
      await player.setVolume(part.volume * 100);
      if (platform is NativePlayer) {
        await platform.setProperty('end', '${part.endMs / 1000}');
      }
      log(
        'part ${i + 1}: ${part.url.split(Platform.pathSeparator).last} '
        '${part.startMs}-${part.endMs} ms, offset ${part.offsetMs} ms, '
        'volume ${part.volume}',
      );
    }

    // Start each part at its offset, measured from the start of the mix.
    for (var i = 0; i < parts.length; i++) {
      final delay = parts[i].offsetMs - (i == 0 ? 0 : parts[0].offsetMs);
      if (delay > 0) {
        log('waiting ${delay}ms before part ${i + 1}');
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      await players[i].play();
      log('part ${i + 1} playing');
    }

    final steps = watch.inSeconds;
    for (var second = 1; second <= steps; second++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final states = <String>[];
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        states.add(
          '${i + 1}: ${p.state.position.inMilliseconds} ms '
          '${p.state.playing ? 'playing' : 'stopped'}',
        );
      }
      log('t=${second}s  ${states.join('  |  ')}');
    }

    log('');
    log('--- verdict ---');
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      final part = parts[i];
      log(
        'part ${i + 1}: position ${p.state.position.inMilliseconds} ms, '
        'trim was ${part.startMs}-${part.endMs} ms, '
        'playing ${p.state.playing}',
      );
    }
    log('errors: ${logs.isEmpty ? 'none' : logs.join(' | ')}');
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
    for (final p in players) {
      await p.dispose();
    }
  }
}

Future<void> main(List<String> args) async {
  final sources = _sources(args);
  if (sources.length < 2) {
    stderr.writeln(
      'need two sources: pass them, or let Gandar cache a couple of tracks '
      'first so the cache directory has files in it',
    );
    exit(2);
  }

  MediaKit.ensureInitialized();

  // A part of the first song (its first 12 seconds) and a later part of the
  // second (from 60 s for 12 s), the second entering 6 s into the mix — a real
  // overlap, which is what "blend" means here.
  final parts = <Part>[
    Part(
      url: sources[0],
      startMs: 0,
      endMs: 12000,
      offsetMs: 0,
      volume: 0.8,
    ),
    Part(
      url: sources[1],
      startMs: 60000,
      endMs: 72000,
      offsetMs: 6000,
      volume: 0.8,
    ),
  ];

  log('mixing two parts:');
  await _run(parts, watch: const Duration(seconds: 18));
}
