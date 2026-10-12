import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/playback/export/pcm.dart';
import 'package:gandar/playback/export/wav.dart';

/// Builds a WAV by hand, so the reader is tested against a file it did not
/// write: the encoder and the decoder agreeing with each other would prove
/// nothing about either.
Uint8List handWrittenWav({
  required int format,
  required int bits,
  required int channels,
  required int sampleRate,
  required List<int> bytes,
  bool extensible = false,
  int? declaredDataLength,
}) {
  final fmtSize = extensible ? 40 : 16;
  final out = Uint8List(12 + 8 + fmtSize + 8 + bytes.length);
  final view = ByteData.view(out.buffer);

  void ascii(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      out[offset + i] = tag.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, out.length - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, fmtSize, Endian.little);
  view.setUint16(20, extensible ? 0xfffe : format, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
  view.setUint16(32, channels * bits ~/ 8, Endian.little);
  view.setUint16(34, bits, Endian.little);
  if (extensible) {
    view.setUint16(36, 22, Endian.little); // cbSize
    view.setUint16(38, bits, Endian.little); // valid bits
    view.setUint32(40, 3, Endian.little); // channel mask
    // The sub-format GUID: the format code, then the fixed tail.
    view.setUint16(44, format, Endian.little);
    view.setUint32(48, 0x00100000, Endian.little);
    view.setUint32(52, 0xaa000080, Endian.little);
    view.setUint32(56, 0x719b3800, Endian.little);
  }
  final dataTag = 12 + 8 + fmtSize;
  ascii(dataTag, 'data');
  view.setUint32(dataTag + 4, declaredDataLength ?? bytes.length, Endian.little);
  out.setRange(dataTag + 8, dataTag + 8 + bytes.length, bytes);
  return out;
}

void main() {
  group('writing', () {
    test('a written file reads back as the audio that went in', () {
      final samples = Float32List.fromList(<double>[
        0.0,
        0.5,
        -0.5,
        1.0,
        -1.0,
        0.2501,
      ]);
      final audio = PcmAudio(
        sampleRate: 44100,
        channels: 2,
        samples: samples,
      );
      final bytes = encodePcm16Wav(audio);

      expect(bytes.length, 44 + samples.length * 2);
      final read = readWavPcm(bytes);
      expect(read.sampleRate, 44100);
      expect(read.channels, 2);
      expect(read.frames, samples.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        expect(
          read.samples[i],
          closeTo(samples[i], 1 / 32767),
          reason: 'sample $i',
        );
      }
    });

    test('the header describes the audio rather than a fixed shape', () {
      final bytes = encodePcm16Wav(
        PcmAudio(
          sampleRate: 48000,
          channels: 1,
          samples: Float32List(48000),
        ),
      );
      final view = ByteData.view(bytes.buffer);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // channels
      expect(view.getUint32(24, Endian.little), 48000);
      expect(view.getUint32(28, Endian.little), 96000); // byte rate
      expect(view.getUint16(32, Endian.little), 2); // block align
      expect(view.getUint16(34, Endian.little), 16); // bits
      expect(view.getUint32(40, Endian.little), 96000); // data length
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    });

    test('an empty recording is still a valid file', () {
      final bytes = encodePcm16Wav(
        PcmAudio(sampleRate: 48000, channels: 2, samples: Float32List(0)),
      );
      expect(bytes.length, 44);
      expect(readWavPcm(bytes).frames, 0);
    });
  });

  group('reading', () {
    test('16-bit samples are read as -1..1', () {
      final bytes = handWrittenWav(
        format: 1,
        bits: 16,
        channels: 1,
        sampleRate: 8000,
        bytes: <int>[0x00, 0x00, 0xff, 0x7f, 0x00, 0x80, 0x00, 0xc0],
      );
      final audio = readWavPcm(bytes);
      expect(audio.sampleRate, 8000);
      expect(audio.frames, 4);
      expect(audio.samples[0], 0.0);
      // 32767 over 32768: full scale is one step short of 1.0 by design.
      expect(audio.samples[1], closeTo(1.0, 1e-4));
      expect(audio.samples[2], -1.0);
      expect(audio.samples[3], closeTo(-0.5, 1e-4));
    });

    test('24-bit and 32-bit integer samples are read too', () {
      final twentyFour = readWavPcm(
        handWrittenWav(
          format: 1,
          bits: 24,
          channels: 1,
          sampleRate: 8000,
          bytes: <int>[0x00, 0x00, 0x80, 0xff, 0xff, 0x7f],
        ),
      );
      expect(twentyFour.samples[0], -1.0);
      expect(twentyFour.samples[1], closeTo(1.0, 1e-6));

      final thirtyTwo = readWavPcm(
        handWrittenWav(
          format: 1,
          bits: 32,
          channels: 1,
          sampleRate: 8000,
          bytes: <int>[0x00, 0x00, 0x00, 0xc0, 0x00, 0x00, 0x00, 0x40],
        ),
      );
      expect(thirtyTwo.samples[0], closeTo(-0.5, 1e-6));
      expect(thirtyTwo.samples[1], closeTo(0.5, 1e-6));
    });

    test('the extensible format mpv writes is read, not refused', () {
      // This is the shape of the file the export's own decoder produces:
      // `WAVE_FORMAT_EXTENSIBLE` with a float sub-format. Reading only the tag
      // refused it, which is how the export was found to be broken.
      final view = ByteData(8);
      view.setFloat32(0, 0.75, Endian.little);
      view.setFloat32(4, -0.25, Endian.little);
      final bytes = handWrittenWav(
        format: 3,
        bits: 32,
        channels: 1,
        sampleRate: 48000,
        extensible: true,
        bytes: view.buffer.asUint8List(),
      );
      final audio = readWavPcm(bytes);
      expect(audio.sampleRate, 48000);
      expect(audio.samples[0], closeTo(0.75, 1e-6));
      expect(audio.samples[1], closeTo(-0.25, 1e-6));
    });

    test('a data chunk that runs past the end is read as far as it goes', () {
      // What an interrupted writer leaves behind: a header claiming more audio
      // than the file holds.
      final bytes = handWrittenWav(
        format: 1,
        bits: 16,
        channels: 1,
        sampleRate: 8000,
        bytes: <int>[0x00, 0x00, 0x00, 0x40],
        declaredDataLength: 64,
      );
      final audio = readWavPcm(bytes);
      expect(audio.frames, 2);
      expect(audio.samples[1], closeTo(0.5, 1e-6));
    });

    test('something that is not a WAV is refused rather than guessed at', () {
      expect(
        () => readWavPcm(Uint8List.fromList(List<int>.filled(64, 7))),
        throwsA(isA<FormatException>()),
      );
      final noData = handWrittenWav(
        format: 1,
        bits: 16,
        channels: 1,
        sampleRate: 8000,
        bytes: const <int>[],
      );
      // Zero-length audio is fine; a file with no data chunk at all is not.
      expect(readWavPcm(noData).frames, 0);
      final headerOnly = Uint8List.sublistView(noData, 0, 36);
      expect(
        () => readWavPcm(headerOnly),
        throwsA(isA<FormatException>()),
      );
    });

    test('a format this reader cannot convert is refused', () {
      final bytes = handWrittenWav(
        format: 1,
        bits: 12,
        channels: 1,
        sampleRate: 8000,
        bytes: <int>[0x00, 0x00],
      );
      expect(
        () => readWavPcm(bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
