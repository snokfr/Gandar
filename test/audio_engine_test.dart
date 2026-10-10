import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/motion/motion.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/audio_engine/audio_filters.dart';
import 'package:gandar/playback/audio_engine/crossfade.dart';

void main() {
  group('AudioFilters', () {
    test('produces no chain when every processing option is off', () {
      expect(AudioFilters.buildAf(const PlaybackSettings()), isNull);
    });

    test('builds one equalizer term per non-zero band', () {
      final af = AudioFilters.buildAf(
        const PlaybackSettings(
          eqEnabled: true,
          eqBands: [
            EqBand(frequency: 31, gain: 6),
            EqBand(frequency: 1000, gain: 0),
            EqBand(frequency: 16000, gain: -3.5),
          ],
        ),
      );
      expect(af, isNotNull);
      expect(af!.split(',').length, 2);
      expect(af, contains('equalizer=f=31:t=q:w=1.0:g=6.0'));
      expect(af, contains('equalizer=f=16000:t=q:w=1.0:g=-3.5'));
      // A zero-gain band is skipped.
      expect(af, isNot(contains('f=1000')));
    });

    test('normalization maps levels to documented loudness targets', () {
      expect(AudioFilters.loudnessTarget(NormalizationLevel.quiet), -20.0);
      expect(AudioFilters.loudnessTarget(NormalizationLevel.normal), -16.0);
      expect(AudioFilters.loudnessTarget(NormalizationLevel.loud), -12.0);

      final af = AudioFilters.buildAf(
        const PlaybackSettings(
          normalizationEnabled: true,
          normalizationLevel: NormalizationLevel.loud,
        ),
      );
      expect(af, contains('loudnorm=I=-12.0:TP=-1.5:LRA=11'));
    });

    test('mono downmixes L+R with equal weights', () {
      final af = AudioFilters.buildAf(const PlaybackSettings(monoAudio: true));
      expect(af, 'pan=mono|c0=0.5*c0+0.5*c1');
    });

    test('combines EQ, normalization and mono into one chain', () {
      final af = AudioFilters.buildAf(
        const PlaybackSettings(
          eqEnabled: true,
          eqBands: [EqBand(frequency: 125, gain: 3)],
          normalizationEnabled: true,
          monoAudio: true,
        ),
      );
      expect(af!.split(',').length, 3);
      expect(af, startsWith('equalizer='));
      expect(af, endsWith('pan=mono|c0=0.5*c0+0.5*c1'));
    });
  });

  group('CrossfadeCurve', () {
    const curve = CrossfadeCurve();

    test('is an equal-power (constant-power) pairing', () {
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final power =
            curve.outgoingGain(t) * curve.outgoingGain(t) +
            curve.incomingGain(t) * curve.incomingGain(t);
        expect(power, closeTo(1.0, 1e-9), reason: 't=$t');
      }
    });

    test('starts fully on the outgoing track and ends on the incoming one', () {
      expect(curve.outgoingGain(0), closeTo(1, 1e-9));
      expect(curve.incomingGain(0), closeTo(0, 1e-9));
      expect(curve.outgoingGain(1), closeTo(0, 1e-9));
      expect(curve.incomingGain(1), closeTo(1, 1e-9));
    });

    test('clamps out-of-range and NaN progress', () {
      expect(curve.outgoingGain(-1), closeTo(1, 1e-9));
      expect(curve.incomingGain(5), closeTo(1, 1e-9));
      expect(curve.incomingGain(double.nan), closeTo(0, 1e-9));
    });
  });

  group('CrossfadePlan', () {
    test('progress and gains advance monotonically', () {
      var plan = CrossfadePlan(durationSeconds: 4, positionSeconds: 0);
      expect(plan.progress, 0);
      expect(plan.outgoingGain, closeTo(1, 1e-9));

      plan = plan.advance(2);
      expect(plan.progress, closeTo(0.5, 1e-9));
      expect(plan.incomingGain, closeTo(0.7071, 1e-3));

      plan = plan.advance(5);
      expect(plan.isComplete, isTrue);
      expect(plan.incomingGain, closeTo(1, 1e-9));
    });

    test('a zero-length crossfade is immediately complete', () {
      final plan = CrossfadePlan(durationSeconds: 0, positionSeconds: 0);
      expect(plan.progress, 1);
      expect(plan.isComplete, isTrue);
    });

    test('trigger offset is truncated by the remaining time', () {
      expect(
        CrossfadePlan.triggerOffsetSeconds(
          remainingSeconds: 10,
          crossfadeSeconds: 6,
        ),
        6,
      );
      expect(
        CrossfadePlan.triggerOffsetSeconds(
          remainingSeconds: 2,
          crossfadeSeconds: 6,
        ),
        2,
      );
      expect(
        CrossfadePlan.triggerOffsetSeconds(
          remainingSeconds: 10,
          crossfadeSeconds: 0,
        ),
        0,
      );
    });
  });

  group('Motion', () {
    test('momentum projection grows with release velocity', () {
      expect(Motion.projectMomentum(0), 0);
      expect(
        Motion.projectMomentum(1000),
        greaterThan(Motion.projectMomentum(100)),
      );
      // Exponential-decay form: v/1000 * d/(1-d) with d = 0.998.
      expect(Motion.projectMomentum(1000), closeTo(499, 1));
    });

    test('snap index is driven by projected momentum, not position alone', () {
      // A strong flick from index 0 lands further than the raw position.
      final near = Motion.snapIndex(
        currentIndex: 0,
        releaseVelocity: 0,
        itemCount: 10,
      );
      final flick = Motion.snapIndex(
        currentIndex: 0,
        releaseVelocity: 9000,
        itemCount: 10,
      );
      expect(near, 0);
      expect(flick, greaterThan(near));
    });

    test('snap index clamps to the list bounds', () {
      expect(
        Motion.snapIndex(
          currentIndex: 9,
          releaseVelocity: 100000,
          itemCount: 10,
        ),
        9,
      );
      expect(
        Motion.snapIndex(
          currentIndex: 0,
          releaseVelocity: -100000,
          itemCount: 10,
        ),
        0,
      );
    });

    test('rubber banding resists progressively past a boundary', () {
      final first = Motion.rubberBand(50, 300);
      final further = Motion.rubberBand(150, 300);
      // Each extra pixel of overshoot must move the element less than the last.
      expect(further, lessThan(150));
      expect(further - first, lessThan(100));
      expect(first, lessThan(50));
    });
  });

  group('FakeAudioEngine', () {
    test('tracks state transitions and records loads and filters', () async {
      final engine = FakeAudioEngine();
      final states = <EngineState>[];
      engine.stateStream.listen(states.add);

      expect(engine.state, EngineState.idle);
      await engine.load('https://example.test/a.m4a');
      await engine.play();
      await engine.pause();

      expect(engine.loadedUrls, ['https://example.test/a.m4a']);
      expect(engine.state, EngineState.paused);
      expect(engine.stateChangeCount, 3);

      const settings = PlaybackSettings(monoAudio: true);
      await engine.applyFilters(settings);
      expect(engine.lastAppliedFilters, settings);

      await engine.dispose();
    });
  });
}
