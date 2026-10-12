import 'dart:math' as math;
import 'dart:typed_data';

/// Decoded audio: interleaved samples as 32-bit floats in -1..1, plus the two
/// numbers that make them mean something.
///
/// This is the currency every stage of an export passes through — the decoder
/// writes it, the resampler converts it, the mixer sums it and the WAV writer
/// converts it back to integers — so that none of those stages has to know
/// what container the sound arrived in.
class PcmAudio {
  const PcmAudio({
    required this.sampleRate,
    required this.channels,
    required this.samples,
  });

  /// [frames] frames of silence, at the given shape.
  factory PcmAudio.silence({
    required int sampleRate,
    required int channels,
    required int frames,
  }) => PcmAudio(
    sampleRate: sampleRate,
    channels: channels,
    samples: Float32List(math.max(0, frames) * channels),
  );

  /// Samples per second.
  final int sampleRate;

  /// How many interleaved values make one frame. 1 is mono, 2 is stereo.
  final int channels;

  /// Interleaved samples: `channels` values per frame, in -1..1.
  final Float32List samples;

  int get frames => channels <= 0 ? 0 : samples.length ~/ channels;

  Duration get duration => sampleRate <= 0
      ? Duration.zero
      : Duration(microseconds: frames * 1000000 ~/ sampleRate);

  /// Largest absolute sample, for reporting what an export actually contains.
  double get peak {
    var peak = 0.0;
    for (final sample in samples) {
      final magnitude = sample.abs();
      if (magnitude > peak) peak = magnitude;
    }
    return peak;
  }

  /// Frames of [startFrame] onwards, cut or padded to [frameCount] frames.
  ///
  /// Padding is the point: a part is a slice of a mix at a moment that was
  /// decided in advance, so one that decodes slightly short is followed by the
  /// silence its own slice is now, rather than by the next part arriving early.
  PcmAudio takeFrames(int startFrame, int frameCount) {
    if (frameCount <= 0) {
      return PcmAudio(
        sampleRate: sampleRate,
        channels: channels,
        samples: Float32List(0),
      );
    }
    final out = Float32List(frameCount * channels);
    final from = startFrame < 0 ? 0 : startFrame;
    final available = frames;
    final copyFrames = math.min(frameCount, math.max(0, available - from));
    if (copyFrames > 0) {
      out.setRange(
        0,
        copyFrames * channels,
        samples,
        from * channels,
      );
    }
    return PcmAudio(
      sampleRate: sampleRate,
      channels: channels,
      samples: out,
    );
  }

  /// This audio with [target] channels, mixed up or down by averaging.
  ///
  /// Mono to stereo duplicates the one channel rather than averaging with
  /// silence, which is what makes a mono part audible in a stereo mix;
  /// anything to mono averages, which is the only downmix that cannot clip.
  PcmAudio withChannels(int target) {
    if (target <= 0 || target == channels) return this;
    final out = Float32List(frames * target);
    if (channels == 1) {
      for (var frame = 0; frame < frames; frame++) {
        final value = samples[frame];
        for (var channel = 0; channel < target; channel++) {
          out[frame * target + channel] = value;
        }
      }
      return PcmAudio(sampleRate: sampleRate, channels: target, samples: out);
    }
    for (var frame = 0; frame < frames; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        sum += samples[frame * channels + channel];
      }
      final value = sum / channels;
      for (var channel = 0; channel < target; channel++) {
        out[frame * target + channel] = value;
      }
    }
    return PcmAudio(sampleRate: sampleRate, channels: target, samples: out);
  }
}

/// One part of a mix: its audio, where it enters the mix, and its level.
class MixLayer {
  const MixLayer({
    required this.audio,
    required this.offset,
    required this.gain,
  });

  final PcmAudio audio;

  /// When this layer starts, measured from the top of the mix.
  final Duration offset;

  /// Level for this layer, 0..1.
  final double gain;
}

/// The summed mix, with the two facts an honest export has to report: how loud
/// it got, and how many samples had to be clipped to fit.
class MixedAudio {
  const MixedAudio({
    required this.audio,
    required this.peak,
    required this.clippedSamples,
  });

  final PcmAudio audio;

  /// Largest absolute sample before clipping.
  final double peak;

  /// How many interleaved samples ran past full scale. Two layers at 100 %
  /// sum to this on purpose: the mix is what the user arranged, and a limiter
  /// nobody asked for would change it.
  final int clippedSamples;

  bool get clipped => clippedSamples > 0;
}

/// Sums [layers] into one recording of [sampleRate] and [channels].
///
/// Each layer is converted to the output's shape first — up- or down-mixed, then
/// resampled — and then added at its own offset and level. The result is longer
/// than the arrangement's own duration when a part plays to the end of a source
/// whose length was never known, which is exactly what that part does when it is
/// played.
MixedAudio mixLayers(
  List<MixLayer> layers, {
  required int sampleRate,
  required int channels,
}) {
  var totalFrames = 0;
  final placed = <(PcmAudio, int, double)>[];
  for (final layer in layers) {
    final audio = resample(layer.audio.withChannels(channels), sampleRate);
    final offsetFrames =
        (layer.offset.inMicroseconds * sampleRate) ~/ 1000000;
    placed.add((audio, offsetFrames < 0 ? 0 : offsetFrames, layer.gain));
    final end = offsetFrames + audio.frames;
    if (end > totalFrames) totalFrames = end;
  }

  final out = Float32List(totalFrames * channels);
  for (final (audio, offsetFrames, gain) in placed) {
    for (var frame = 0; frame < audio.frames; frame++) {
      final target = (offsetFrames + frame) * channels;
      final source = frame * channels;
      for (var channel = 0; channel < channels; channel++) {
        out[target + channel] += audio.samples[source + channel] * gain;
      }
    }
  }

  var peak = 0.0;
  var clipped = 0;
  for (var i = 0; i < out.length; i++) {
    final value = out[i];
    final magnitude = value.abs();
    if (magnitude > peak) peak = magnitude;
    if (value > 1.0) {
      out[i] = 1.0;
      clipped++;
    } else if (value < -1.0) {
      out[i] = -1.0;
      clipped++;
    }
  }

  return MixedAudio(
    audio: PcmAudio(sampleRate: sampleRate, channels: channels, samples: out),
    peak: peak,
    clippedSamples: clipped,
  );
}

/// Resamples [input] to [targetRate], or returns it untouched when it is already
/// there — which is the common case, since every YouTube audio stream is 48 kHz
/// whatever container it arrives in.
///
/// The interpolator is a windowed sinc: a Blackman-windowed kernel of 16 taps,
/// with its cutoff pulled down to the output's Nyquist limit when the rate is
/// falling, so a downsample filters instead of aliasing. A table of 512 phases
/// stands in for evaluating the kernel per sample, which is a phase error of
/// 1/512 of a sample — two orders of magnitude below what the window itself
/// already costs. Edges are handled by dividing by the weight that actually
/// landed inside the recording, so the first and last few samples neither fade
/// in nor gain.
PcmAudio resample(PcmAudio input, int targetRate) {
  if (targetRate <= 0 || input.sampleRate <= 0) return input;
  if (targetRate == input.sampleRate || input.frames == 0) return input;

  final ratio = targetRate / input.sampleRate;
  final outFrames = (input.frames * ratio).round();
  final table = _SincTable(cutoff: ratio < 1 ? ratio : 1.0);
  final out = Float32List(outFrames * input.channels);
  final channels = input.channels;
  const taps = _SincTable.taps;
  const width = _SincTable.width;

  for (var channel = 0; channel < channels; channel++) {
    for (var frame = 0; frame < outFrames; frame++) {
      final position = frame / ratio;
      final base = position.floor();
      final fraction = position - base;
      final phase = (fraction * _SincTable.phases).round();
      final row = (phase >= _SincTable.phases ? _SincTable.phases - 1 : phase) *
          width;
      // Where the kernel's first tap reads from, and how much of it is inside
      // the recording. Clipping the kernel at the edges loses weight, and the
      // sum of the weights that survived is what restores the level.
      final firstIndex = base - (taps - 1);
      var sum = 0.0;
      var weight = 0.0;
      for (var tap = 0; tap < width; tap++) {
        final index = firstIndex + tap;
        if (index < 0 || index >= input.frames) continue;
        final coefficient = table.at(row + tap);
        sum += input.samples[index * channels + channel] * coefficient;
        weight += coefficient;
      }
      out[frame * channels + channel] = weight == 0 ? 0 : sum / weight;
    }
  }

  return PcmAudio(sampleRate: targetRate, channels: channels, samples: out);
}

/// A windowed-sinc kernel, sampled into [phases] sub-sample positions.
class _SincTable {
  _SincTable({required this.cutoff}) {
    for (var phase = 0; phase < phases; phase++) {
      final fraction = phase / phases;
      final row = phase * width;
      var sum = 0.0;
      for (var tap = 0; tap < width; tap++) {
        final distance = tap - (taps - 1) - fraction;
        final value =
            _sinc(cutoff * distance) * cutoff * _blackman(distance / taps);
        _values[row + tap] = value;
        sum += value;
      }
      // Normalised so a flat signal stays flat: without this the cutoff would
      // quieten everything it touches.
      if (sum != 0) {
        for (var tap = 0; tap < width; tap++) {
          _values[row + tap] /= sum;
        }
      }
    }
  }

  /// Coefficients either side of the interpolation point.
  static const int taps = 8;

  /// Sub-sample positions in the table. The rounding it introduces is 1/512 of
  /// a sample, well below the error the window itself contributes.
  static const int phases = 512;

  /// Where the kernel stops: a fraction of the input rate, 1.0 when upsampling.
  final double cutoff;

  final Float64List _values = Float64List(phases * width);

  static const int width = taps * 2;

  double at(int index) => _values[index];

  static double _sinc(double x) =>
      x == 0 ? 1 : math.sin(math.pi * x) / (math.pi * x);

  /// Blackman window over its support of -1..1, and zero outside it.
  static double _blackman(double u) {
    final x = u.abs();
    if (x >= 1) return 0;
    return 0.42 + 0.5 * math.cos(math.pi * x) + 0.08 * math.cos(2 * math.pi * x);
  }
}
