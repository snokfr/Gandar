import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/data/youtube/audio_stream_selector.dart';

AudioOption _option(
  String url, {
  required int bitrate,
  String container = 'mp4',
  int size = 0,
  bool live = false,
}) => AudioOption(
  url: url,
  container: container,
  bitrateBitsPerSecond: bitrate,
  sizeBytes: size,
  isLive: live,
);

void main() {
  const selector = AudioStreamSelector();

  group('balanced (the default)', () {
    test('prefers m4a over a higher-bitrate webm', () {
      final best = selector.selectBest(<AudioOption>[
        _option('webm', bitrate: 160000, container: 'webm'),
        _option('m4a', bitrate: 128000, container: 'mp4'),
      ]);

      expect(best!.url, 'm4a');
    });

    test('takes the highest bitrate within the preferred container', () {
      final best = selector.selectBest(<AudioOption>[
        _option('low', bitrate: 64000),
        _option('high', bitrate: 131000),
      ]);

      expect(best!.url, 'high');
    });
  });

  group('best', () {
    test('ignores the container and takes the highest bitrate', () {
      final best = selector.selectBest(<AudioOption>[
        _option('m4a', bitrate: 128000, container: 'mp4'),
        // Opus streams routinely beat the m4a ones, which is exactly what
        // "best" is for.
        _option('opus', bitrate: 160000, container: 'webm'),
      ], quality: AudioQuality.best);

      expect(best!.url, 'opus');
    });
  });

  group('data saver', () {
    test('takes the smallest stream that is still music', () {
      final best = selector.selectBest(<AudioOption>[
        _option('big', bitrate: 160000),
        _option('small', bitrate: 70000),
        _option('tiny', bitrate: 48000),
      ], quality: AudioQuality.dataSaver);

      // 48 kbps is below the floor, so the 70 kbps stream wins rather than the
      // smallest one available.
      expect(best!.url, 'small');
    });

    test('when everything is below the floor, the best of them wins', () {
      final best = selector.selectBest(<AudioOption>[
        _option('worst', bitrate: 24000),
        _option('least bad', bitrate: 48000),
      ], quality: AudioQuality.dataSaver);

      expect(best!.url, 'least bad');
    });

    test('a stream exactly at the floor is acceptable', () {
      final best = selector.selectBest(<AudioOption>[
        _option(
          'at floor',
          bitrate: AudioStreamSelector.minimumDataSaverBitrate,
        ),
        _option('above', bitrate: 128000),
      ], quality: AudioQuality.dataSaver);

      expect(best!.url, 'at floor');
    });
  });

  group('rules that hold at every quality', () {
    for (final quality in AudioQuality.values) {
      test('a live stream is never chosen ($quality)', () {
        final best = selector.selectBest(<AudioOption>[
          _option('live', bitrate: 500000, live: true),
          _option('normal', bitrate: 64000),
        ], quality: quality);

        expect(best!.url, 'normal');
      });

      test('an empty list has no answer ($quality)', () {
        expect(selector.selectBest(const [], quality: quality), isNull);
      });

      test('a live stream is a last resort, not a refusal ($quality)', () {
        // Every level agrees on this: a live stream is never *preferred*, but
        // when it is the only thing the video publishes, it is still played.
        // The alternative would be a silent failure that depends on a setting.
        final best = selector.selectBest(<AudioOption>[
          _option('live', bitrate: 128000, live: true),
        ], quality: quality);
        expect(best!.url, 'live');
      });
    }

    test('exact ties are broken the same way every time', () {
      // Two streams at the same bitrate: the smaller known file wins, and if
      // that ties too, the URL decides. The answer must not depend on the
      // order they arrived in.
      final forward = selector.selectBest(<AudioOption>[
        _option('b', bitrate: 128000, size: 1000),
        _option('a', bitrate: 128000, size: 1000),
      ]);
      final backward = selector.selectBest(<AudioOption>[
        _option('a', bitrate: 128000, size: 1000),
        _option('b', bitrate: 128000, size: 1000),
      ]);

      expect(forward!.url, backward!.url);
      expect(forward.url, 'a');
    });

    test('a known file size beats an unknown one', () {
      final best = selector.selectBest(<AudioOption>[
        _option('unknown', bitrate: 128000),
        _option('known', bitrate: 128000, size: 999999),
      ]);

      expect(best!.url, 'known');
    });
  });
}
