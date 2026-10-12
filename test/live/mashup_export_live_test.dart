import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/mashup.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/playback/export/mashup_exporter.dart';
import 'package:gandar/playback/export/pcm.dart';
import 'package:gandar/playback/export/wav.dart';

/// A real export of a real mix, end to end.
///
/// Skipped by default, because it needs three things a build server does not
/// have: the built `libmpv-2.dll`, audio in the cache, and a few seconds of
/// patience. Run it deliberately:
///
/// ```bash
/// flutter test --dart-define=LIVE=true test/live/mashup_export_live_test.dart
/// ```
///
/// Everything else about the export is covered by unit tests with a stand-in
/// decoder, which is the right way to test the arithmetic. What those cannot
/// cover is the part that only works if the whole chain does: a *second* isolate
/// calling into libmpv through `dart:ffi` — mpv created, `ao=pcm` writing a WAV,
/// the samples read back, summed, and written out as a file a player can open.
/// `tool/export_probe.dart` checks the decode and the summing from a plain Dart
/// process; this checks the isolate the app actually uses.
const bool _live = bool.fromEnvironment('LIVE');

/// The bundled libmpv, or an override for a machine that keeps it elsewhere.
String? _library() {
  final override = Platform.environment['GANDAR_LIBMPV'];
  if (override != null && override.isNotEmpty) return override;
  final bundled = File(
    'build/windows/x64/runner/Release/libmpv-2.dll',
  ).absolute.path;
  return File(bundled).existsSync() ? bundled : null;
}

/// Two audio files from the cache — the real material a mix is made of.
List<File> _cachedAudio() {
  final roaming = Platform.environment['APPDATA'] ?? '';
  final cache = Directory('$roaming\\com.gandar\\gandar\\cache');
  if (!cache.existsSync()) return const <File>[];
  final files =
      cache
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.part'))
          .where(
            (f) => const <String>['.webm', '.m4a', '.mp3', '.opus'].any(
              f.path.endsWith,
            ),
          )
          .toList()
        ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
  return files.take(2).toList();
}

void main() {
  final library = _library();
  final audio = _cachedAudio();
  final skip = !_live
      ? 'live test: pass --dart-define=LIVE=true to run it'
      : library == null
      ? 'no libmpv-2.dll next to the app build (or set GANDAR_LIBMPV)'
      : audio.length < 2
      ? 'fewer than two playable files in the audio cache'
      : null;

  test('exports a real two-part mix through the isolate the app uses', () async {
    final directory = Directory.systemTemp.createTempSync('gandar-live-export');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    // Ten-second slices, overlapping by four: the smallest arrangement that is
    // actually a mix rather than two songs in a row.
    final tracks = <Track>[
      for (var i = 0; i < 2; i++)
        Track(
          id: 'live-$i',
          title: 'cached ${audio[i].uri.pathSegments.last}',
          artists: const <String>['test'],
          durationMs: 10000,
        ),
    ];
    final mix = Mashup(
      parts: <MashupPart>[
        MashupPart(
          track: tracks[0],
          start: const Duration(seconds: 20),
          end: const Duration(seconds: 30),
          offset: Duration.zero,
          gain: 0.8,
        ),
        MashupPart(
          track: tracks[1],
          start: const Duration(seconds: 40),
          end: const Duration(seconds: 50),
          offset: const Duration(seconds: 6),
          gain: 0.8,
        ),
      ],
    );

    final progress = <double>[];
    final exporter = buildMashupExporter(
      // The cached file *is* the stream: the resolver's job here is only to
      // hand over a path, and mpv opens a path the same way it opens a URL.
      resolve: (track) async => ResolvedStream(
        url: audio[int.parse(track.id.split('-').last)].path,
        videoId: 'live',
        container: 'webm',
      ),
      exportsDirectory: directory,
      library: library!,
    );

    final outcome = await exporter(
      mashup: mix,
      name: 'live mix',
      onProgress: (p) => progress.add(p.fraction),
    );

    expect(outcome.path, endsWith('live mix.wav'));
    expect(
      outcome.parts.every((p) => p.decoded > Duration.zero),
      isTrue,
      reason: 'both parts decoded; real music at 80 % twice may clip, and '
          'saying so is not a failure',
    );
    expect(
      outcome.warnings.where((w) => w.contains('could not be decoded')),
      isEmpty,
    );
    expect(outcome.duration, const Duration(seconds: 16));
    expect(
      outcome.clipped,
      outcome.peak > 1.0,
      reason: 'clipping is reported exactly when the sum went past full scale',
    );
    expect(outcome.peak, greaterThan(0.05), reason: 'not silence');
    expect(
      progress,
      isNotEmpty,
      reason: 'the screen is told how far along the export is',
    );
    expect(progress.last, 1.0);

    final file = File(outcome.path);
    expect(file.existsSync(), isTrue);
    final expectedFrames =
        outcome.duration.inMilliseconds * outcome.sampleRate ~/ 1000;
    expect(
      file.lengthSync(),
      44 + expectedFrames * outcome.channels * 2,
      reason: 'a 16-bit WAV of exactly the mix that was arranged',
    );

    final written = readWavPcm(file.readAsBytesSync());
    expect(written.sampleRate, outcome.sampleRate);
    expect(written.sampleRate, 48000, reason: 'what mpv decodes Opus to');
    expect(written.channels, 2);
    expect(written.frames, 16 * 48000);
    // The two parts really are both in it: the second half of the mix is where
    // only the second part sounds, and the first 6 s are the first part alone.
    expect(_loudness(written, 0, 5), greaterThan(0));
    expect(_loudness(written, 10, 15), greaterThan(0));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}

/// Mean absolute sample over a window of the recording, in seconds. Distinct
/// from zero means something is there.
double _loudness(PcmAudio audio, int fromSeconds, int toSeconds) {
  final from = fromSeconds * audio.sampleRate;
  final to = toSeconds * audio.sampleRate;
  var sum = 0.0;
  for (var frame = from; frame < to; frame++) {
    sum += audio.samples[frame * audio.channels].abs();
  }
  return sum / (to - from);
}
