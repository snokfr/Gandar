// Can Gandar export a mashup as an audio file — and is the file the mix?
//
// The export needs something the bundled libmpv can actually do: decode a
// source and write the samples to a WAV instead of to a speaker, because this
// build has no `amix` to sum two sources with and no encoder to write MP3. The
// route measured here is `--ao=pcm`, with the summing done in Dart by the same
// code the app runs.
//
// This probe exports a real two-part mix from the audio cache and then checks it
// two ways: that the file is a valid WAV of the expected length, and that its
// samples really are the two parts summed — by decoding both parts a second time
// and adding them up here, in this file, with loop code that shares nothing with
// the mixer. A mix that is silently only one part would pass the first check and
// fail the second.
//
//   GANDAR_LIBMPV=<bundle>/libmpv-2.dll \
//     dart run tool/export_probe.dart [<file-or-url> <file-or-url>]
import 'dart:io';
import 'dart:math' as math;

import 'package:gandar/playback/export/export_job.dart';
import 'package:gandar/playback/export/mpv_pcm.dart';
import 'package:gandar/playback/export/pcm.dart';
import 'package:gandar/playback/export/wav.dart';

/// The mix under test: two slices, overlapping for five seconds.
const Duration partALength = Duration(seconds: 20);
const Duration partBLength = Duration(seconds: 20);
const Duration partAOffset = Duration.zero;
const Duration partBOffset = Duration(seconds: 15);
const double gain = 0.8;

bool _failed = false;

void check(String what, bool ok, [String? detail]) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $what${detail == null ? '' : ' — $detail'}');
  if (!ok) _failed = true;
}

String _library() {
  final fromEnvironment = Platform.environment['GANDAR_LIBMPV'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  final bundled = File(
    'build/windows/x64/runner/Release/libmpv-2.dll',
  ).absolute.path;
  return File(bundled).existsSync() ? bundled : defaultMpvLibrary;
}

/// Two sources from the audio cache — real googlevideo downloads, which is the
/// material a mashup mixes.
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

/// Samples of a PCM buffer at [time], or null when that is off the end.
double? sampleAt(PcmAudio audio, Duration time, int channel) {
  final frame = (time.inMicroseconds * audio.sampleRate) ~/ 1000000;
  if (frame < 0 || frame >= audio.frames) return null;
  return audio.samples[frame * audio.channels + channel];
}

/// What one source contributes to mix channel [channel], as the mixer would have
/// converted it: mono is duplicated into every channel, and anything wider is
/// averaged down. Written out here rather than called, so that this check cannot
/// agree with a bug by sharing its code.
double? sourceSample(PcmAudio audio, Duration time, int mixChannels, int channel) {
  if (audio.channels == 1) return sampleAt(audio, time, 0);
  if (mixChannels == 1) {
    var sum = 0.0;
    var seen = 0;
    for (var c = 0; c < audio.channels; c++) {
      final value = sampleAt(audio, time, c);
      if (value == null) continue;
      sum += value;
      seen++;
    }
    return seen == 0 ? null : sum / seen;
  }
  if (channel >= audio.channels) return sampleAt(audio, time, 0);
  return sampleAt(audio, time, channel);
}

void main(List<String> args) {
  final sources = _sources(args);
  if (sources.length < 2) {
    stderr.writeln('need two audio files, or a cache with two in it');
    exitCode = 2;
    return;
  }
  final library = _library();
  stdout.writeln('library: $library');
  stdout.writeln('sources: ${sources.join(', ')}');

  final scratch = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}gandar-export-probe',
  );
  if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  scratch.createSync(recursive: true);
  final output = File(
    '${scratch.path}${Platform.pathSeparator}probe-mix.wav',
  );

  // ---- Decode both parts first, so a failure names its reason ------------
  // The job reports a part it could not decode as a warning and carries on, and
  // a mix of two silent parts is an empty mix. Decoding here first means a
  // broken decoder says so in its own words instead of as an empty file.
  final trace = Platform.environment['GANDAR_EXPORT_TRACE'] == '1';
  stdout.writeln('decoding both parts…');
  late PcmAudio a;
  late PcmAudio b;
  try {
    a = decodeSliceToPcm(
      url: sources[0],
      headers: const <String, String>{},
      start: const Duration(seconds: 30),
      end: const Duration(seconds: 30) + partALength,
      target: File('${scratch.path}${Platform.pathSeparator}check-a.wav'),
      library: library,
      trace: trace,
    );
    b = decodeSliceToPcm(
      url: sources[1],
      headers: const <String, String>{},
      start: const Duration(seconds: 60),
      end: const Duration(seconds: 60) + partBLength,
      target: File('${scratch.path}${Platform.pathSeparator}check-b.wav'),
      library: library,
      trace: trace,
    );
  } catch (e) {
    check('the decoder produced audio', false, '$e');
    stdout.writeln('the rest of the checks need a decode');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'part A ${a.duration.inMilliseconds} ms @ ${a.sampleRate} Hz '
    '${a.channels} ch, part B ${b.duration.inMilliseconds} ms @ '
    '${b.sampleRate} Hz ${b.channels} ch',
  );

  // ---- The export itself -------------------------------------------------
  final stopwatch = Stopwatch()..start();
  ExportOutcome outcome;
  try {
    outcome = runExportJob(
      parts: <ExportPart>[
        ExportPart(
          title: 'part A',
          url: sources[0],
          headers: const <String, String>{},
          start: const Duration(seconds: 30),
          end: const Duration(seconds: 30) + partALength,
          offset: partAOffset,
          gain: gain,
        ),
        ExportPart(
          title: 'part B',
          url: sources[1],
          headers: const <String, String>{},
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 60) + partBLength,
          offset: partBOffset,
          gain: gain,
        ),
      ],
      outputPath: output.path,
      scratch: scratch,
      library: library,
      onProgress: (progress) => stdout.writeln(
        '  [${(progress.fraction * 100).toStringAsFixed(0).padLeft(3)}%] '
        '${progress.stage}',
      ),
    );
  } catch (e) {
    check('the export ran at all', false, '$e');
    stdout.writeln('the rest of the checks need an export');
    exitCode = 1;
    return;
  }
  stopwatch.stop();
  final seconds = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);

  stdout.writeln(
    'exported ${outcome.path}: ${outcome.duration.inMilliseconds} ms, '
    '${outcome.sampleRate} Hz, ${outcome.channels} ch, '
    'peak ${outcome.peak.toStringAsFixed(3)}, '
    '${outcome.clippedSamples} clipped samples, in ${seconds}s',
  );
  for (final warning in outcome.warnings) {
    stdout.writeln('  warning: $warning');
  }

  // ---- Is it a WAV, and is it the right length? --------------------------
  final file = File(outcome.path);
  check('an audio file was written', file.existsSync(), outcome.path);
  if (!file.existsSync()) {
    exitCode = 1;
    return;
  }
  final bytes = file.readAsBytesSync();
  check(
    'the file is a RIFF/WAVE recording',
    bytes.length > 44 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE',
    '${bytes.length} bytes',
  );

  final mix = readWavPcm(bytes);
  final expected = partBOffset + partBLength;
  check(
    'the mix is as long as the arrangement (${expected.inSeconds} s)',
    (mix.duration - expected).abs() < const Duration(milliseconds: 40),
    '${mix.duration.inMilliseconds} ms',
  );
  check(
    'the file is not silence',
    mix.peak > 0.05,
    'peak ${mix.peak.toStringAsFixed(3)}',
  );
  check(
    'clipping in the mix is reported, not hidden',
    (outcome.clippedSamples > 0) == (outcome.peak > 1.0),
    'peak ${outcome.peak.toStringAsFixed(3)}, '
        '${outcome.clippedSamples} clipped samples',
  );

  // ---- Are both parts really in it? --------------------------------------
  // Summed here, in this file, with loop code that shares nothing with the
  // mixer: if the mix were one part, or the second were placed at the wrong
  // time, this would disagree with it. Three windows, two of them with a single
  // part sounding, so a disagreement says whether it is placement — which
  // affects the overlap — or something that affects both parts everywhere.
  // All of them are well inside the recording, away from the few milliseconds
  // at each part's end that the export has cut or padded to the arranged slice
  // and these decodes have not.
  const windows = <(String, Duration, Duration, bool, bool)>[
    ('part A alone', Duration(seconds: 2), Duration(seconds: 14), true, false),
    ('the overlap of both parts', Duration(seconds: 16), Duration(seconds: 19), true, true),
    ('part B alone', Duration(milliseconds: 20500), Duration(seconds: 34), false, true),
  ];
  for (final (label, from, to, withA, withB) in windows) {
    var worst = 0.0;
    var compared = 0;
    String? firstBad;
    var worstAt = Duration.zero;
    for (var channel = 0; channel < math.min(2, mix.channels); channel++) {
      for (var ms = 0; ms < (to - from).inMilliseconds; ms += 5) {
        final time = from + Duration(milliseconds: ms);
        var expectedSample = 0.0;
        if (withA) {
          expectedSample +=
              (sourceSample(a, time - partAOffset, mix.channels, channel) ??
                  0) *
              gain;
        }
        if (withB) {
          expectedSample +=
              (sourceSample(b, time - partBOffset, mix.channels, channel) ??
                  0) *
              gain;
        }
        final actual = sampleAt(mix, time, channel);
        if (actual == null) continue;
        compared++;
        // The mixer clips at full scale on purpose rather than limiting, so the
        // sum to compare against is the sum clipped the same way. Anything else
        // would call the export wrong for doing what it says it does.
        final clipped = expectedSample.clamp(-1.0, 1.0);
        final error = (actual - clipped).abs();
        if (error > worst) {
          worst = error;
          worstAt = time;
        }
        if (error > 3 / 32768 && firstBad == null) {
          firstBad = '$time ch$channel (${actual.toStringAsFixed(4)} vs '
              '${clipped.toStringAsFixed(4)})';
        }
      }
    }
    check(
      'the mix is the parts added up: $label',
      compared > 500 && firstBad == null,
      '$compared samples, worst disagreement '
          '${(worst * 32768).toStringAsFixed(1)} of a 16-bit step at $worstAt'
          '${firstBad == null ? '' : ', first at $firstBad'}',
    );
  }

  stdout.writeln(
    '\nkept for listening: ${output.path}\n'
    '${_failed ? 'FAILED' : 'ALL CHECKS PASSED'}',
  );
  exitCode = _failed ? 1 : 0;
}
