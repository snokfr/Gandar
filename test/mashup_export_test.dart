import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/mashup.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/playback/export/export_cancelled.dart';
import 'package:gandar/playback/export/export_job.dart';
import 'package:gandar/playback/export/mashup_exporter.dart';
import 'package:gandar/playback/export/pcm.dart';
import 'package:gandar/playback/export/wav.dart';

const Track _songA = Track(
  id: 'a',
  title: 'Song A',
  artists: <String>['Artist'],
  durationMs: 1000,
);
const Track _songB = Track(
  id: 'b',
  title: 'Song B',
  artists: <String>['Artist'],
  durationMs: 1000,
);

/// A slice of flat audio, as a decoder would return it.
PcmAudio flatSlice({
  required double value,
  required Duration length,
  int sampleRate = 48000,
  int channels = 2,
}) {
  final frames = (length.inMicroseconds * sampleRate) ~/ 1000000;
  final samples = Float32List(frames * channels);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = value;
  }
  return PcmAudio(sampleRate: sampleRate, channels: channels, samples: samples);
}

ExportPart part({
  required String title,
  required double gain,
  Duration offset = Duration.zero,
  Duration start = Duration.zero,
  Duration? end = const Duration(seconds: 1),
}) => ExportPart(
  title: title,
  url: 'file:///$title',
  headers: const <String, String>{},
  start: start,
  end: end,
  offset: offset,
  gain: gain,
);

/// A decoder that hands back a known tone instead of decoding: the mixing is
/// what these tests are about, and it does not need a file to read.
SliceDecoder fakeDecoder(double Function(String title) level) =>
    ({
      required String url,
      required Map<String, String> headers,
      required Duration start,
      required Duration? end,
      required File target,
      bool Function()? isCancelled,
    }) {
      final length = (end ?? const Duration(seconds: 1)) - start;
      return flatSlice(
        value: level(url.replaceFirst('file:///', '')),
        length: length,
      );
    };

Directory _scratch() {
  final directory = Directory.systemTemp.createTempSync('gandar-export-test');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// The decoder the *isolate* runs, so it has to be a top-level function rather
/// than a closure over test state: only functions like this can be sent to
/// another isolate.
PcmAudio _isolateDecoder({
  required String url,
  required Map<String, String> headers,
  required Duration start,
  required Duration? end,
  required File target,
  bool Function()? isCancelled,
}) {
  if (url.contains('slow')) {
    // Slow enough that a test can cancel while it is running, and polite enough
    // to notice — the same contract the real decoder keeps.
    final until = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(until)) {
      if (isCancelled?.call() ?? false) throw const ExportCancelled();
      sleep(const Duration(milliseconds: 10));
    }
  }
  return flatSlice(
    value: url.contains('b') ? 0.25 : 0.5,
    length: (end ?? const Duration(seconds: 1)) - start,
  );
}

void main() {
  group('the export job', () {
    test('sums the layers at their own offsets and levels', () {
      final output = File('${_scratch().path}${Platform.pathSeparator}mix.wav');
      final outcome = runExportJob(
        parts: <ExportPart>[
          part(title: 'A', gain: 1.0),
          part(
            title: 'B',
            gain: 0.8,
            offset: const Duration(milliseconds: 500),
          ),
        ],
        outputPath: output.path,
        scratch: _scratch(),
        decode: fakeDecoder((title) => title == 'A' ? 0.5 : 0.25),
      );

      expect(outcome.sampleRate, 48000);
      expect(outcome.channels, 2);
      expect(outcome.duration, const Duration(milliseconds: 1500));
      expect(outcome.warnings, isEmpty);
      expect(outcome.clipped, isFalse);

      final mix = readWavPcm(output.readAsBytesSync());
      expect(mix.frames, 72000);
      expect(mix.samples[1000 * 2], closeTo(0.5, 1e-4));
      expect(mix.samples[40000 * 2], closeTo(0.5 + 0.25 * 0.8, 1e-4));
      expect(mix.samples[70000 * 2], closeTo(0.2, 1e-4));
    });

    test('trims a part to its arranged slice, and pads one that came short', () {
      final output = File('${_scratch().path}${Platform.pathSeparator}mix.wav');
      runExportJob(
        parts: <ExportPart>[
          // The decoder returns 1.5 s for a slice the arrangement says is 1 s.
          part(title: 'A', gain: 1.0),
        ],
        outputPath: output.path,
        scratch: _scratch(),
        decode: ({
          required String url,
          required Map<String, String> headers,
          required Duration start,
          required Duration? end,
          required File target,
          bool Function()? isCancelled,
        }) => flatSlice(value: 0.5, length: const Duration(milliseconds: 1500)),
      );

      final mix = readWavPcm(output.readAsBytesSync());
      expect(
        mix.frames,
        48000,
        reason: 'the mix stops where the arrangement says the part does',
      );

      // And the other way round: a decode three quarters of the slice long is
      // followed by silence rather than by the part after it arriving early.
      final short = File('${_scratch().path}${Platform.pathSeparator}short.wav');
      final outcomeShort = runExportJob(
        parts: <ExportPart>[
          part(title: 'A', gain: 1.0),
          part(title: 'B', gain: 1.0, offset: const Duration(seconds: 1)),
        ],
        outputPath: short.path,
        scratch: _scratch(),
        decode: ({
          required String url,
          required Map<String, String> headers,
          required Duration start,
          required Duration? end,
          required File target,
          bool Function()? isCancelled,
        }) => flatSlice(value: 0.5, length: const Duration(milliseconds: 750)),
      );
      expect(outcomeShort.duration, const Duration(seconds: 2));
      expect(
        outcomeShort.warnings,
        hasLength(2),
        reason: 'each short part says so rather than being quietly shortened',
      );
      expect(outcomeShort.warnings.first, contains('silence was added'));
      final mixShort = readWavPcm(short.readAsBytesSync());
      expect(mixShort.frames, 96000);
      // The first part's own 0.75 s, then the silence that fills its slice.
      expect(mixShort.samples[20000 * 2], closeTo(0.5, 1e-4));
      expect(mixShort.samples[40000 * 2], 0.0);
      // And the second part starting where it was placed, at 1 s.
      expect(mixShort.samples[50000 * 2], closeTo(0.5, 1e-4));
    });

    test('reports clipping rather than hiding it', () {
      final output = File('${_scratch().path}${Platform.pathSeparator}mix.wav');
      final outcome = runExportJob(
        parts: <ExportPart>[
          part(title: 'A', gain: 1.0),
          part(title: 'B', gain: 1.0),
        ],
        outputPath: output.path,
        scratch: _scratch(),
        decode: fakeDecoder((_) => 0.9),
      );

      expect(outcome.clipped, isTrue);
      expect(outcome.peak, closeTo(1.8, 1e-4));
      expect(
        outcome.warnings.single,
        contains('clipped'),
        reason: 'the level to change is the user’s to decide, not the app’s',
      );
      expect(readWavPcm(output.readAsBytesSync()).samples[0], closeTo(1.0, 1e-4));
    });

    test('a part that cannot be decoded is left silent, not fatal', () {
      final output = File('${_scratch().path}${Platform.pathSeparator}mix.wav');
      final outcome = runExportJob(
        parts: <ExportPart>[
          part(title: 'A', gain: 1.0),
          part(title: 'B', gain: 1.0),
        ],
        outputPath: output.path,
        scratch: _scratch(),
        decode: fakeDecoder((title) {
          if (title == 'A') throw StateError('the stream was refused');
          return 0.25;
        }),
      );

      expect(outcome.warnings.single, contains('could not be decoded'));
      expect(outcome.warnings.single, contains('the stream was refused'));
      expect(outcome.duration, const Duration(seconds: 1));
      expect(
        outcome.parts.map((p) => p.warning),
        <String?>['not decoded', null],
      );
    });

    test('a mix where nothing decodes fails rather than writing silence', () {
      expect(
        () => runExportJob(
          parts: <ExportPart>[part(title: 'A', gain: 1.0)],
          outputPath: '${_scratch().path}${Platform.pathSeparator}mix.wav',
          scratch: _scratch(),
          decode: fakeDecoder((_) => throw StateError('no')),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an empty mix is refused before any work is done', () {
      expect(
        () => runExportJob(
          parts: const <ExportPart>[],
          outputPath: '${_scratch().path}${Platform.pathSeparator}mix.wav',
          scratch: _scratch(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cancelling stops the export and leaves no file behind', () {
      final output = File('${_scratch().path}${Platform.pathSeparator}mix.wav');
      var cancelled = false;
      expect(
        () => runExportJob(
          parts: <ExportPart>[part(title: 'A', gain: 1.0)],
          outputPath: output.path,
          scratch: _scratch(),
          decode: ({
            required String url,
            required Map<String, String> headers,
            required Duration start,
            required Duration? end,
            required File target,
            bool Function()? isCancelled,
          }) {
            cancelled = true;
            throw const ExportCancelled();
          },
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ExportCancelled>()),
      );
      expect(output.existsSync(), isFalse);
    });

    test('progress runs from nothing to finished', () {
      final seen = <ExportProgress>[];
      runExportJob(
        parts: <ExportPart>[
          part(title: 'Song A', gain: 1.0),
          part(
            title: 'Song B',
            gain: 1.0,
            offset: const Duration(seconds: 1),
          ),
        ],
        outputPath: '${_scratch().path}${Platform.pathSeparator}mix.wav',
        scratch: _scratch(),
        decode: fakeDecoder((_) => 0.5),
        onProgress: seen.add,
      );

      expect(seen.first.fraction, 0.0);
      expect(seen.last.stage, 'Done');
      expect(seen.last.fraction, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(
          seen[i].fraction,
          greaterThanOrEqualTo(seen[i - 1].fraction),
          reason: 'a progress bar that goes backwards is worse than none',
        );
      }
      // Every stage names the part it is working on, so a long export says
      // which song it is stuck on rather than just moving a bar.
      expect(seen.map((p) => p.stage).join(' '), contains('Song A'));
      expect(seen.map((p) => p.stage).join(' '), contains('Song B'));
      expect(seen.every((p) => p.partCount == 2), isTrue);
    });
  });

  group('the exporter', () {
    test('writes the mix where it says it does, and reports progress', () async {
      final directory = _scratch();
      final export = buildMashupExporter(
        resolve: (track) async => ResolvedStream(
          url: 'https://cdn.test/${track.id}.m4a',
          videoId: 'v-${track.id}',
          container: 'm4a',
        ),
        exportsDirectory: directory,
        decode: _isolateDecoder,
      );

      final progress = <ExportProgress>[];
      final outcome = await export(
        mashup: Mashup.fromTracks(
          <Track>[_songA, _songB],
          blend: Duration.zero,
        ),
        name: 'Test mix',
        onProgress: progress.add,
      );

      expect(outcome.path, endsWith('Test mix.wav'));
      expect(File(outcome.path).existsSync(), isTrue);
      expect(outcome.duration, const Duration(seconds: 2));
      final mix = readWavPcm(File(outcome.path).readAsBytesSync());
      // 80 % is the level a new part is given by the arrangement, and the export
      // uses the arrangement's levels rather than this moment's playback volume.
      expect(mix.samples[1000 * 2], closeTo(0.5 * 0.8, 1e-4));
      expect(mix.samples[50000 * 2], closeTo(0.25 * 0.8, 1e-4));
      // Looking the songs up is the first thing the screen is told about, and
      // it happens before any audio exists.
      expect(progress.first.stage, contains('Looking up'));
      expect(progress.last.fraction, 1.0);
    });

    test('a name that is not a file name still lands somewhere', () async {
      final directory = _scratch();
      final export = buildMashupExporter(
        resolve: (track) async => ResolvedStream(
          url: 'https://cdn.test/${track.id}.m4a',
          videoId: 'x',
          container: 'm4a',
        ),
        exportsDirectory: directory,
        decode: _isolateDecoder,
      );
      final outcome = await export(
        mashup: Mashup.fromTracks(<Track>[_songA], blend: Duration.zero),
        name: 'late night / blend?',
      );

      expect(File(outcome.path).existsSync(), isTrue);
      expect(outcome.path, endsWith('late night - blend-.wav'));
    });

    test('a mix nobody can be found for is refused', () async {
      final export = buildMashupExporter(
        resolve: (track) async => throw StateError('nothing found'),
        exportsDirectory: _scratch(),
        decode: _isolateDecoder,
      );
      await expectLater(
        export(
          mashup: Mashup.fromTracks(<Track>[_songA], blend: Duration.zero),
          name: 'Empty',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cancelling reaches into the isolate and stops the work', () async {
      final directory = _scratch();
      final export = buildMashupExporter(
        resolve: (track) async => ResolvedStream(
          // The stand-in decoder treats a "slow" url as one that takes its
          // time — long enough for a cancel to arrive while it runs.
          url: 'https://cdn.test/slow-${track.id}.m4a',
          videoId: 'x',
          container: 'm4a',
        ),
        exportsDirectory: directory,
        decode: _isolateDecoder,
      );

      var cancelled = false;
      final running = export(
        mashup: Mashup.fromTracks(<Track>[_songA], blend: Duration.zero),
        name: 'Cancelled',
        isCancelled: () => cancelled,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      cancelled = true;

      await expectLater(running, throwsA(isA<ExportCancelled>()));
      expect(
        File('${directory.path}${Platform.pathSeparator}Cancelled.wav')
            .existsSync(),
        isFalse,
      );
      expect(
        Directory('${directory.path}${Platform.pathSeparator}.exporting')
            .existsSync(),
        isFalse,
        reason: 'the scratch folder is cleaned up on the way out',
      );
    });
  });
}
