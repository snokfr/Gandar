import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/playback/export/pcm.dart';

/// Audio of [seconds] seconds where every sample has the same value — the
/// simplest signal that still shows where a layer was placed and how loud it
/// was.
PcmAudio flat({
  required double value,
  int sampleRate = 48000,
  int channels = 2,
  double seconds = 1,
}) {
  final frames = (seconds * sampleRate).round();
  final samples = Float32List(frames * channels);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = value;
  }
  return PcmAudio(sampleRate: sampleRate, channels: channels, samples: samples);
}

double at(PcmAudio audio, int frame, [int channel = 0]) =>
    audio.samples[frame * audio.channels + channel];

void main() {
  group('mixing', () {
    test('layers land at their own offsets, at their own levels', () {
      final mixed = mixLayers(
        <MixLayer>[
          MixLayer(
            audio: flat(value: 0.5),
            offset: Duration.zero,
            gain: 1.0,
          ),
          MixLayer(
            audio: flat(value: 0.25),
            offset: const Duration(milliseconds: 500),
            gain: 0.8,
          ),
        ],
        sampleRate: 48000,
        channels: 2,
      );

      expect(mixed.audio.frames, 72000); // 1.5 s at 48 kHz
      // Before the second part enters: only the first.
      expect(at(mixed.audio, 100), closeTo(0.5, 1e-6));
      // Overlap: both, the second at 80 %.
      expect(at(mixed.audio, 36000), closeTo(0.5 + 0.25 * 0.8, 1e-6));
      // After the first has run out: only the second.
      expect(at(mixed.audio, 60000), closeTo(0.2, 1e-6));
      // Both channels, so a mix is not accidentally mono.
      expect(at(mixed.audio, 36000, 1), closeTo(0.7, 1e-6));
      expect(mixed.clippedSamples, 0);
    });

    test('a mix that runs past full scale is clipped, and says so', () {
      final mixed = mixLayers(
        <MixLayer>[
          MixLayer(audio: flat(value: 0.9), offset: Duration.zero, gain: 1.0),
          MixLayer(audio: flat(value: 0.9), offset: Duration.zero, gain: 1.0),
        ],
        sampleRate: 48000,
        channels: 1,
      );

      expect(mixed.clipped, isTrue);
      expect(mixed.peak, closeTo(1.8, 1e-6));
      expect(mixed.clippedSamples, mixed.audio.samples.length);
      expect(at(mixed.audio, 10), 1.0);
    });

    test('a negative sum is clipped at the bottom, not the top', () {
      final mixed = mixLayers(
        <MixLayer>[
          MixLayer(audio: flat(value: -0.9), offset: Duration.zero, gain: 1.0),
          MixLayer(audio: flat(value: -0.9), offset: Duration.zero, gain: 1.0),
        ],
        sampleRate: 48000,
        channels: 1,
      );

      expect(at(mixed.audio, 10), -1.0);
      expect(mixed.peak, closeTo(1.8, 1e-6));
    });

    test('mono is duplicated into every channel, and stereo averages down', () {
      final up = flat(value: 0.3, channels: 1).withChannels(2);
      expect(up.channels, 2);
      expect(at(up, 5, 0), closeTo(0.3, 1e-6));
      expect(at(up, 5, 1), closeTo(0.3, 1e-6));

      final down = PcmAudio(
        sampleRate: 48000,
        channels: 2,
        samples: Float32List.fromList(<double>[1.0, 0.0, 0.5, 0.5]),
      ).withChannels(1);
      expect(down.channels, 1);
      expect(at(down, 0), closeTo(0.5, 1e-6));
      expect(at(down, 1), closeTo(0.5, 1e-6));
    });

    test('a layer at its own sample rate is resampled into the mix', () {
      // 44.1 kHz into a 48 kHz mix: half a second each way.
      final mixed = mixLayers(
        <MixLayer>[
          MixLayer(
            audio: flat(value: 0.4, sampleRate: 44100, seconds: 0.5),
            offset: Duration.zero,
            gain: 1.0,
          ),
        ],
        sampleRate: 48000,
        channels: 2,
      );

      expect(mixed.audio.sampleRate, 48000);
      expect(mixed.audio.frames, 24000);
      expect(at(mixed.audio, 12000), closeTo(0.4, 1e-4));
    });

    test('a mix of nothing is empty rather than a crash', () {
      final mixed = mixLayers(
        const <MixLayer>[],
        sampleRate: 48000,
        channels: 2,
      );
      expect(mixed.audio.frames, 0);
      expect(mixed.peak, 0);
      expect(mixed.clipped, isFalse);
    });
  });

  group('resampling', () {
    test('audio already at the target rate is returned untouched', () {
      final input = flat(value: 0.25);
      expect(identical(resample(input, 48000), input), isTrue);
    });

    test('a flat signal stays flat, end to end', () {
      // The kernel is normalised, so a signal with no frequency content cannot
      // gain or lose level — including at the first and last samples, where the
      // kernel hangs off the end.
      final resampled = resample(
        flat(value: 0.5, sampleRate: 44100, seconds: 0.2),
        48000,
      );
      expect(resampled.sampleRate, 48000);
      expect(resampled.frames, closeTo(9600, 2));
      for (final frame in <int>[0, 1, 10, 4800, resampled.frames - 2]) {
        expect(at(resampled, frame), closeTo(0.5, 1e-4));
      }
    });

    test('a tone keeps its frequency and its level', () {
      const from = 48000;
      const to = 44100;
      const frequency = 1000.0;
      const seconds = 0.25;
      final frames = (seconds * from).round();
      final samples = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        samples[i] = math.sin(2 * math.pi * frequency * i / from);
      }
      final resampled = resample(
        PcmAudio(sampleRate: from, channels: 1, samples: samples),
        to,
      );

      expect(resampled.frames, (frames * to / from).round());
      // Compared against the same tone at the new rate: the resampler has to
      // agree on both phase and level, which a wrong cutoff or a misplaced
      // kernel cannot do. The ends are skipped, where any resampler is fitting
      // a kernel to audio that is not there.
      var worst = 0.0;
      for (var i = 64; i < resampled.frames - 64; i++) {
        final expected = math.sin(2 * math.pi * frequency * i / to);
        worst = math.max(worst, (at(resampled, i) - expected).abs());
      }
      expect(worst, lessThan(0.02), reason: 'a 1 kHz tone should survive');
    });

    test('upsampling a tone is just as faithful', () {
      const from = 44100;
      const to = 48000;
      const frequency = 2000.0;
      const frames = 11025; // 0.25 s
      final samples = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        samples[i] = math.sin(2 * math.pi * frequency * i / from);
      }
      final resampled = resample(
        PcmAudio(sampleRate: from, channels: 1, samples: samples),
        to,
      );

      var worst = 0.0;
      for (var i = 64; i < resampled.frames - 64; i++) {
        final expected = math.sin(2 * math.pi * frequency * i / to);
        worst = math.max(worst, (at(resampled, i) - expected).abs());
      }
      expect(worst, lessThan(0.02));
    });
  });

  group('slices', () {
    test('a short decode is padded with silence, not with the next part', () {
      // 0.4 s of audio asked to fill a 0.5 s slice: the last 0.1 s is the
      // silence that slice now is.
      final slice = flat(value: 0.6, seconds: 0.4).takeFrames(0, 24000);
      expect(slice.frames, 24000);
      expect(at(slice, 100), closeTo(0.6, 1e-6));
      expect(at(slice, 19199), closeTo(0.6, 1e-6));
      expect(at(slice, 23000), 0.0);
    });

    test('a long decode is cut to the arranged length', () {
      final slice = flat(value: 0.6, seconds: 1).takeFrames(0, 24000);
      expect(slice.frames, 24000);
    });
  });
}
