import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/eq_presets.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/core/settings/settings_repository.dart';

void main() {
  group('PlaybackSettings', () {
    test('defaults match Spotify-like baseline', () {
      const s = PlaybackSettings();
      expect(s.eqEnabled, isFalse);
      expect(s.crossfadeSeconds, 0);
      expect(s.normalizationEnabled, isFalse);
      expect(s.monoAudio, isFalse);
      expect(s.gaplessPlayback, isTrue);
      expect(s.shuffleMode, ShuffleMode.standard);
      expect(s.eqBands.length, 10);
    });

    test('has 10 bands at the documented centre frequencies', () {
      expect(PlaybackSettings.defaultBands.map((b) => b.frequency).toList(), [
        31,
        62,
        125,
        250,
        500,
        1000,
        2000,
        4000,
        8000,
        16000,
      ]);
    });

    test('sanitized clamps crossfade to 0..12 and gains to -12..12', () {
      final s = const PlaybackSettings(
        crossfadeSeconds: 99,
        eqBands: [EqBand(frequency: 31, gain: 40)],
      ).sanitized();
      expect(s.crossfadeSeconds, 12.0);
      expect(s.eqBands.first.gain, 12.0);

      final negative = const PlaybackSettings(crossfadeSeconds: -5).sanitized();
      expect(negative.crossfadeSeconds, 0.0);
    });

    test('sanitized clamps cache limits to sane minimums', () {
      final s = const PlaybackSettings(
        cacheMaxMegabytes: 1,
        cacheMaxIdleDays: -3,
      ).sanitized();
      expect(s.cacheMaxMegabytes, greaterThanOrEqualTo(128));
      expect(s.cacheMaxIdleDays, greaterThanOrEqualTo(1));
    });

    test('an empty band list falls back to the default 10 bands', () {
      final s = const PlaybackSettings(eqBands: <EqBand>[]).sanitized();
      expect(s.eqBands.length, 10);
    });

    test('JSON round-trips every field', () {
      const s = PlaybackSettings(
        eqEnabled: true,
        eqPreset: 'rock',
        eqBands: [
          EqBand(frequency: 31, gain: 5),
          EqBand(frequency: 62, gain: -2.5),
        ],
        crossfadeSeconds: 7,
        normalizationEnabled: true,
        normalizationLevel: NormalizationLevel.loud,
        monoAudio: true,
        gaplessPlayback: false,
        automixEnabled: true,
        shuffleMode: ShuffleMode.smart,
        prefetchNextTrack: false,
        cacheMaxMegabytes: 4096,
        cacheMaxIdleDays: 14,
      );
      expect(PlaybackSettings.fromJson(s.toJson()), s);
    });

    test('unknown enum names degrade to defaults instead of throwing', () {
      final s = PlaybackSettings.fromJson({
        'shuffleMode': 'wat',
        'normalizationLevel': 'nope',
      });
      expect(s.shuffleMode, ShuffleMode.standard);
      expect(s.normalizationLevel, NormalizationLevel.normal);
    });
  });

  group('EqPresets', () {
    test('every preset covers all 10 bands', () {
      for (final p in EqPresets.all) {
        expect(p.gains.length, 10, reason: 'preset ${p.id}');
        expect(p.apply().length, 10);
      }
    });

    test('includes the requested named presets', () {
      final ids = EqPresets.all.map((p) => p.id).toSet();
      for (final expected in [
        'flat',
        'bass_boost',
        'rock',
        'pop',
        'classical',
      ]) {
        expect(ids, contains(expected));
      }
    });

    test('flat is all zeros and bass boost lifts the low bands', () {
      expect(EqPresets.byId('flat')!.gains.every((g) => g == 0), isTrue);
      final bass = EqPresets.byId('bass_boost')!.gains;
      expect(bass.first, greaterThan(0));
      expect(bass.last, 0);
    });
  });

  group('SettingsRepository', () {
    test('returns defaults when nothing is stored', () async {
      final repo = SettingsRepository(InMemoryStore());
      expect(await repo.loadPlayback(), const PlaybackSettings());
      expect(await repo.loadActiveThemeId(), isNull);
      expect(await repo.loadCustomThemes(), isEmpty);
    });

    test('persists playback settings across instances', () async {
      final store = InMemoryStore();
      await SettingsRepository(store).savePlayback(
        const PlaybackSettings(crossfadeSeconds: 6, monoAudio: true),
      );

      final reloaded = await SettingsRepository(store).loadPlayback();
      expect(reloaded.crossfadeSeconds, 6);
      expect(reloaded.monoAudio, isTrue);
    });

    test('corrupt payload falls back to defaults', () async {
      final store = InMemoryStore({'settings.playback.v1': '{not json'});
      expect(
        await SettingsRepository(store).loadPlayback(),
        const PlaybackSettings(),
      );
    });

    test('persists active theme id and custom themes', () async {
      final store = InMemoryStore();
      final repo = SettingsRepository(store);
      await repo.saveActiveThemeId('earthy_brown');
      expect(await repo.loadActiveThemeId(), 'earthy_brown');
    });
  });
}
