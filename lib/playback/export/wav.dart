import 'dart:typed_data';

import 'pcm.dart';

/// Reading and writing WAV files: the one format that needs no encoder.
///
/// An export cannot be an MP3, because nothing in this build can encode one —
/// the bundled libmpv has no `amix` to sum with and no encoder mode either (see
/// `tool/mashup_probe.dart`). WAV needs none of that: it is a header and the
/// samples, which is exactly what the mixer already has. So the mix is written
/// as 16-bit WAV, playable everywhere and importable by any editor that can then
/// turn it into whatever else is wanted.

/// Writes [audio] as a 16-bit PCM WAV file.
///
/// Samples past full scale are already clipped by the mixer, so this only has to
/// convert; the dither that a master would use is left out deliberately, because
/// a quantisation error at -96 dB is not what anyone is judging a mashup by.
Uint8List encodePcm16Wav(PcmAudio audio) {
  final channels = audio.channels <= 0 ? 1 : audio.channels;
  final frames = audio.frames;
  final dataBytes = frames * channels * 2;
  final out = Uint8List(44 + dataBytes);
  final view = ByteData.view(out.buffer);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      out[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  view.setUint16(20, 1, Endian.little); // 1 = PCM integers
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, audio.sampleRate, Endian.little);
  view.setUint32(28, audio.sampleRate * channels * 2, Endian.little);
  view.setUint16(32, channels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);

  var offset = 44;
  for (var i = 0; i < audio.samples.length && offset + 1 < out.length; i++) {
    final value = audio.samples[i].clamp(-1.0, 1.0);
    // 32767 rather than 32768: a full-scale negative sample is one step further
    // from zero, and using it would make the two halves of the waveform
    // unevenly loud.
    final scaled = (value < 0 ? value * 32768 : value * 32767).round();
    view.setInt16(offset, scaled, Endian.little);
    offset += 2;
  }
  return out;
}

/// Every sample in a WAV file, as floats.
///
/// The formats covered are the ones mpv's PCM writer can produce and the ones a
/// person is likely to hand back: 8, 16, 24 and 32-bit integers, and 32 and
/// 64-bit floats. Anything else throws, because a silently wrong export is worse
/// than a refused one.
///
/// A `data` chunk whose declared size runs past the end of the file is read for
/// as long as it actually goes, which happens when a writer was interrupted
/// before it could patch the header — and is the case where refusing would throw
/// away a usable recording.
PcmAudio readWavPcm(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const FormatException('not a WAV file: fewer than 12 bytes');
  }
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
    throw const FormatException('not a WAV file: no RIFF/WAVE header');
  }

  int? format;
  int? channels;
  int? sampleRate;
  int? bits;
  int? dataStart;
  int? dataLength;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _tag(bytes, offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      if (body + 16 > bytes.length) {
        throw const FormatException('WAV fmt chunk is truncated');
      }
      format = view.getUint16(body, Endian.little);
      channels = view.getUint16(body + 2, Endian.little);
      sampleRate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
      // `WAVE_FORMAT_EXTENSIBLE` is what mpv's PCM writer emits: the tag says
      // "see the extension", and the real format is the first two bytes of the
      // GUID at the end of the chunk. Reading the tag alone would refuse the
      // export's own decoder output, which is how this was found.
      if (format == 0xfffe && body + 26 <= bytes.length) {
        format = view.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      dataStart = body;
      final declared = body + size;
      dataLength = declared <= bytes.length ? size : bytes.length - body;
    }
    // Chunks are padded to an even length, and reading the size wrong here is
    // how a parser finds a "chunk" inside the audio itself.
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (format == null || channels == null || sampleRate == null || bits == null) {
    throw const FormatException('WAV file has no fmt chunk');
  }
  if (dataStart == null || dataLength == null) {
    throw const FormatException('WAV file has no data chunk');
  }
  if (channels <= 0) {
    throw const FormatException('WAV file declares no channels');
  }

  final bytesPerSample = bits ~/ 8;
  if (bytesPerSample <= 0) {
    throw FormatException('WAV file declares $bits-bit samples');
  }
  final frames = dataLength ~/ (bytesPerSample * channels);
  final samples = Float32List(frames * channels);
  final floats = format == 3;
  if (!floats && format != 1) {
    throw FormatException('unsupported WAV format $format (1 = PCM)');
  }
  if (floats && bits != 32 && bits != 64) {
    throw FormatException('unsupported float WAV of $bits bits');
  }
  if (!floats && bits != 8 && bits != 16 && bits != 24 && bits != 32) {
    throw FormatException('unsupported PCM WAV of $bits bits');
  }

  for (var i = 0; i < samples.length; i++) {
    final at = dataStart + i * bytesPerSample;
    samples[i] = switch ((floats, bits)) {
      (true, 32) => view.getFloat32(at, Endian.little),
      (true, _) => view.getFloat64(at, Endian.little),
      (false, 8) => (bytes[at] - 128) / 128,
      (false, 16) => view.getInt16(at, Endian.little) / 32768,
      (false, 24) => _int24(bytes, at) / 8388608,
      (false, _) => view.getInt32(at, Endian.little) / 2147483648,
    };
  }

  return PcmAudio(
    sampleRate: sampleRate,
    channels: channels,
    samples: samples,
  );
}

/// A 24-bit little-endian integer, sign-extended.
int _int24(Uint8List bytes, int offset) {
  final value =
      bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  return value >= 0x800000 ? value - 0x1000000 : value;
}

String _tag(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return '';
  return String.fromCharCodes(bytes.sublist(offset, offset + 4));
}
