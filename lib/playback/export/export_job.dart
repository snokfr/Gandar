import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'export_cancelled.dart';
import 'mpv_pcm.dart';
import 'pcm.dart';
import 'wav.dart';

/// How far short a decode has to fall before the export says so.
///
/// Below this it is the millisecond rounding of mpv's own end-of-file trim
/// rather than a gap anyone could hear or act on.
const Duration minimumReportedShortfall = Duration(milliseconds: 100);

/// Everything about an export except resolving the songs: where the audio is,
/// which slice of it plays, where that slice enters the mix and how loud it is.
///
/// Deliberately a value with no tracks or players in it. The job below runs in a
/// background isolate, and a description of the work that can be copied there is
/// what makes that possible.
class ExportPart {
  const ExportPart({
    required this.title,
    required this.url,
    required this.headers,
    required this.start,
    required this.end,
    required this.offset,
    required this.gain,
  });

  /// For progress and for naming a part that could not be decoded.
  final String title;

  final String url;
  final Map<String, String> headers;

  /// Where the slice begins inside the song.
  final Duration start;

  /// Where it stops, or null to run to the end of the source.
  final Duration? end;

  /// When it enters the mix.
  final Duration offset;

  /// Its level, 0..1.
  final double gain;
}

/// How far an export has got, in words and in a fraction.
class ExportProgress {
  const ExportProgress({
    required this.stage,
    required this.partIndex,
    required this.partCount,
    required this.fraction,
  });

  /// What is happening right now, for the dialog: "Decoding “Buddy Holly”".
  final String stage;

  /// Which part, 1-based, and how many there are.
  final int partIndex;
  final int partCount;

  /// 0..1 across the whole export.
  final double fraction;
}

/// What one part contributed, including whether it came up short.
class ExportedPart {
  const ExportedPart({
    required this.title,
    required this.requested,
    required this.decoded,
    required this.warning,
  });

  final String title;

  /// Length the arrangement says this part plays for.
  final Duration requested;

  /// Length that actually arrived.
  final Duration decoded;

  /// Anything worth saying about this part, or null.
  final String? warning;
}

/// The finished recording.
class ExportOutcome {
  const ExportOutcome({
    required this.path,
    required this.sampleRate,
    required this.channels,
    required this.duration,
    required this.peak,
    required this.clippedSamples,
    required this.parts,
    required this.warnings,
  });

  final String path;
  final int sampleRate;
  final int channels;
  final Duration duration;

  /// Largest absolute sample in the mix, before clipping.
  final double peak;

  /// Interleaved samples that had to be clipped. Reported rather than hidden:
  /// two layers at full level sum to clipping on purpose, and knowing it is the
  /// only way to decide whether to pull a level down.
  final int clippedSamples;

  final List<ExportedPart> parts;
  final List<String> warnings;

  bool get clipped => clippedSamples > 0;
}

/// Decodes one slice to PCM. The real one writes through [decodeSliceToPcm];
/// tests hand in a function that returns a known waveform, so the arithmetic of
/// mixing can be checked without audio, mpv, or a network.
typedef SliceDecoder =
    PcmAudio Function({
      required String url,
      required Map<String, String> headers,
      required Duration start,
      required Duration? end,
      required File target,
      bool Function()? isCancelled,
    });

/// Decodes, mixes, and writes the mix to [outputPath] as a 16-bit WAV.
///
/// This is the whole export, and it is synchronous on purpose: it runs in a
/// background isolate (see `MashupExporter`), so the interface stays live while a
/// four-minute mix is decoded and summed, and nothing in here has to be
/// re-entrant.
///
/// The mix is exactly the arrangement. A part's slice is trimmed — or padded with
/// silence — to the length the arrangement gives it, so a decode that ran a few
/// milliseconds long cannot bleed into the part after it, and one that ran short
/// does not pull the next part's entry earlier. Levels are the arrangement's own,
/// not the playback volume: what is written is the mix, not this moment's
/// listening level.
ExportOutcome runExportJob({
  required List<ExportPart> parts,
  required String outputPath,
  required Directory scratch,
  String library = defaultMpvLibrary,
  SliceDecoder? decode,
  void Function(ExportProgress)? onProgress,
  bool Function()? isCancelled,
}) {
  if (parts.isEmpty) {
    throw StateError('there is nothing in this mix to export');
  }
  scratch.createSync(recursive: true);
  // The real decoder is bound to [library] here rather than given it per call:
  // the typedef stays about the slice, and a mix of six parts opens one module
  // by the path the caller asked for. Passing the library through the decode
  // signature instead would put an FFI detail in every stand-in decoder.
  final decoder =
      decode ??
      ({
        required String url,
        required Map<String, String> headers,
        required Duration start,
        required Duration? end,
        required File target,
        bool Function()? isCancelled,
      }) => decodeSliceToPcm(
        url: url,
        headers: headers,
        start: start,
        end: end,
        target: target,
        library: library,
        isCancelled: isCancelled,
      );
  final warnings = <String>[];
  final reports = <ExportedPart>[];
  final accumulator = _MixBuffer();
  final partCount = parts.length;
  var mixRate = 0;
  var failed = 0;

  void report(String stage, int index, double fraction) => onProgress?.call(
    ExportProgress(
      stage: stage,
      partIndex: index,
      partCount: partCount,
      fraction: fraction.clamp(0.0, 1.0),
    ),
  );

  // Decoding dominates an export's runtime; summing and writing are quick. The
  // fraction says so rather than pretending each stage is a third of the work.
  const decodeShare = 0.92;

  for (var index = 0; index < partCount; index++) {
    if (isCancelled?.call() ?? false) throw const ExportCancelled();
    final part = parts[index];
    // Progress is reported as the average across parts, so a long part moves the
    // bar slowly and a short one quickly — which is what is true.
    final base = index / partCount * decodeShare;
    report('Opening “${part.title}”', index + 1, base);

    final target = File(
      '${scratch.path}${Platform.pathSeparator}export-part-$index.wav',
    );
    PcmAudio decoded;
    try {
      decoded = decoder(
        url: part.url,
        headers: part.headers,
        start: part.start,
        end: part.end,
        target: target,
        isCancelled: isCancelled,
      );
    } on ExportCancelled {
      throw const ExportCancelled();
    } catch (e) {
      failed++;
      final reason = '$e'.replaceAll(RegExp(r'\s+'), ' ').trim();
      warnings.add('“${part.title}” could not be decoded and is silent: $reason');
      reports.add(
        ExportedPart(
          title: part.title,
          requested: _requestedLength(part),
          decoded: Duration.zero,
          warning: 'not decoded',
        ),
      );
      continue;
    }

    if (decoded.frames == 0) {
      failed++;
      warnings.add('“${part.title}” decoded to nothing and is silent.');
      reports.add(
        ExportedPart(
          title: part.title,
          requested: _requestedLength(part),
          decoded: Duration.zero,
          warning: 'no audio',
        ),
      );
      continue;
    }

    // The first part that decodes decides the mix's shape, because everything is
    // resampled to it from there on: one WAV has one rate and one channel count,
    // and the alternative — a rate chosen before anything was decoded — would be
    // a guess. The common case is that every part agrees, since every YouTube
    // audio stream is 48 kHz.
    if (mixRate == 0) {
      mixRate = decoded.sampleRate;
      accumulator.reshape(decoded.channels);
    } else if (decoded.channels > accumulator.channels) {
      accumulator.reshape(decoded.channels);
    }

    var slice = decoded;
    final requested = _requestedLength(part);
    String? warning;
    if (part.end != null) {
      final wantedFrames = _framesFor(requested, decoded.sampleRate);
      final gotFrames = decoded.frames;
      if (gotFrames != wantedFrames) {
        final shortfall = wantedFrames - gotFrames;
        // A millisecond or two short is what mpv's own end-of-file trim looks
        // like and is inaudible; only a real gap is worth telling anyone about,
        // or every export would come with a warning nobody can act on.
        final padded = Duration(
          microseconds: shortfall * 1000000 ~/ decoded.sampleRate,
        );
        if (shortfall > 0 && padded >= minimumReportedShortfall) {
          warning = '${_ms(padded)} of silence was added at the end';
        }
        // Trim or pad, so the part occupies exactly its own slice of the mix.
        slice = decoded.takeFrames(0, wantedFrames);
      }
    }
    reports.add(
      ExportedPart(
        title: part.title,
        requested: requested,
        decoded: decoded.duration,
        warning: warning,
      ),
    );
    if (warning != null) {
      warnings.add('“${part.title}”: $warning.');
    }

    report(
      'Placing “${part.title}”',
      index + 1,
      base + (1 / partCount) * decodeShare,
    );
    accumulator.add(slice, part.offset, part.gain, mixRate);
  }

  if (accumulator.frames == 0) {
    // The reasons are carried into the failure rather than left in the warnings
    // that go with a successful export: when *every* part fails there is no
    // outcome to hang them on, and "none of the songs could be decoded" on its
    // own is the beginning of a support thread rather than the end of one.
    final why = warnings.isEmpty ? '' : ' — ${warnings.join('; ')}';
    throw StateError(
      failed == parts.length
          ? 'none of the songs in this mix could be decoded$why'
          : 'the mix came out empty$why',
    );
  }
  if (isCancelled?.call() ?? false) throw const ExportCancelled();

  report('Writing the file', partCount, decodeShare + 0.02);

  final mixed = accumulator.finish(mixRate);
  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(encodePcm16Wav(mixed.audio), flush: true);
  report('Done', partCount, 1);
  if (mixed.clipped) {
    warnings.add(
      '${mixed.clippedSamples} samples ran past full level in the mix and were '
      'clipped — lower a level to keep them.',
    );
  }

  return ExportOutcome(
    path: output.path,
    sampleRate: mixed.audio.sampleRate,
    channels: mixed.audio.channels,
    duration: mixed.audio.duration,
    peak: mixed.peak,
    clippedSamples: mixed.clippedSamples,
    parts: reports,
    warnings: warnings,
  );
}

/// How long a part is meant to run, for the report.
Duration _requestedLength(ExportPart part) {
  final end = part.end;
  if (end == null) return Duration.zero;
  final span = end - part.start;
  return span > Duration.zero ? span : Duration.zero;
}

int _framesFor(Duration length, int sampleRate) =>
    (length.inMicroseconds * sampleRate) ~/ 1000000;

String _ms(Duration duration) {
  final ms = duration.inMilliseconds;
  return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
}

/// Grows as layers arrive, so a mix is summed in one pass and never held twice.
///
/// The length of a mix is not known in advance: a part whose source had no
/// length when it was arranged plays to wherever its source ends, which is only
/// discovered by decoding it. So the buffer grows on demand rather than being
/// sized by a guess.
class _MixBuffer {
  Float32List _samples = Float32List(0);
  int _frames = 0;
  int _channels = 1;

  int get frames => _frames;
  int get channels => _channels;

  /// Sets the channel count, converting what is already summed.
  void reshape(int channels) {
    if (channels <= _channels) return;
    final converted = PcmAudio(
      sampleRate: 1,
      channels: _channels,
      samples: _samples.sublist(0, _frames * _channels),
    ).withChannels(channels);
    _samples = Float32List(converted.samples.length + _slack * channels);
    _samples.setRange(0, converted.samples.length, converted.samples);
    _channels = channels;
  }

  static const int _slack = 1 << 16;

  void add(PcmAudio audio, Duration offset, double gain, int mixRate) {
    final placed = resample(audio.withChannels(_channels), mixRate);
    final offsetFrames = (offset.inMicroseconds * mixRate) ~/ 1000000;
    final end = (offsetFrames < 0 ? 0 : offsetFrames) + placed.frames;
    // Frames to values: the buffer holds `channels` samples per frame, and
    // forgetting that is a write past the end rather than a quiet bug.
    _ensure((end + _slack) * _channels);

    final voice = placed.samples;
    for (var frame = 0; frame < placed.frames; frame++) {
      final target = (offsetFrames + frame) * _channels;
      final source = frame * _channels;
      for (var channel = 0; channel < _channels; channel++) {
        _samples[target + channel] += voice[source + channel] * gain;
      }
    }
    if (end > _frames) _frames = end;
  }

  void _ensure(int needed) {
    if (_samples.length >= needed) return;
    final grown = Float32List(math.max(needed, _samples.length * 2));
    grown.setRange(0, _samples.length, _samples);
    _samples = grown;
  }

  /// The summed mix, with peak and clipping measured on the final result rather
  /// than on the way in.
  MixedAudio finish(int sampleRate) {
    final cut = _samples.sublist(0, _frames * _channels);
    var peak = 0.0;
    var clipped = 0;
    for (var i = 0; i < cut.length; i++) {
      final value = cut[i];
      final magnitude = value.abs();
      if (magnitude > peak) peak = magnitude;
      if (value > 1.0) {
        cut[i] = 1.0;
        clipped++;
      } else if (value < -1.0) {
        cut[i] = -1.0;
        clipped++;
      }
    }
    return MixedAudio(
      audio: PcmAudio(
        sampleRate: sampleRate,
        channels: _channels,
        samples: cut,
      ),
      peak: peak,
      clippedSamples: clipped,
    );
  }
}
