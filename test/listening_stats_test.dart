import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/listening_stats.dart';
import 'package:gandar/domain/models/play_record.dart';

PlayRecord _play(String id, DateTime at, {int ms = 200000}) =>
    PlayRecord(trackId: id, playedAt: at, durationMs: ms);

void main() {
  group('ListeningStats', () {
    test('no history is all zeroes rather than nonsense', () {
      final stats = ListeningStats.from(
        records: const [],
        adSecondsPerTrack: 20,
        premiumMonthlyCost: 11.99,
      );

      expect(stats.totalPlays, 0);
      expect(stats.listeningTime, Duration.zero);
      expect(stats.adTimeAvoided, Duration.zero);
      expect(stats.monthsActive, 0);
      expect(stats.monthlySaving, 0);
      expect(stats.premiumCostEquivalent, 0);
      expect(stats.durationCoverage, 1);
    });

    test('adds up listening time and distinct tracks', () {
      final start = DateTime(2026, 3, 1, 10);
      final stats = ListeningStats.from(
        records: [
          _play('a', start, ms: 180000),
          _play('b', start.add(const Duration(minutes: 4)), ms: 200000),
          _play('a', start.add(const Duration(minutes: 9)), ms: 180000),
        ],
        adSecondsPerTrack: 20,
        premiumMonthlyCost: 10,
        now: start,
      );

      expect(stats.totalPlays, 3);
      expect(stats.distinctTracks, 2);
      expect(stats.listeningTime, const Duration(milliseconds: 560000));
      // 3 plays x 20 s of ads.
      expect(stats.adTimeAvoided, const Duration(seconds: 60));
      expect(stats.timeReclaimed, const Duration(seconds: 620));
      expect(stats.tracksWithKnownDuration, 3);
      expect(stats.durationCoverage, 1);
    });

    test('the assumption drives the ad estimate', () {
      final at = DateTime(2026, 3, 1);
      final stats = ListeningStats.from(
        records: [for (var i = 0; i < 10; i++) _play('t$i', at)],
        adSecondsPerTrack: 30,
        premiumMonthlyCost: 10,
        now: at,
      );

      expect(stats.adTimeAvoided, const Duration(seconds: 300));

      final doubled = stats.copyWith(adSecondsPerTrack: 60);
      expect(doubled.adTimeAvoided, const Duration(seconds: 600));
    });

    test('counts whole months of use from the first play', () {
      final stats = ListeningStats.from(
        records: [
          _play('a', DateTime(2026, 1, 1)),
          _play('b', DateTime(2026, 3, 1)),
        ],
        adSecondsPerTrack: 0,
        premiumMonthlyCost: 12,
        now: DateTime(2026, 3, 1),
      );

      // 59 days spans three calendar months.
      expect(stats.monthsActive, 3);
      expect(stats.premiumCostEquivalent, 36);
      expect(stats.monthlySaving, 12);
    });

    test('a single day of use still counts as one month', () {
      final at = DateTime(2026, 3, 1, 12);
      final stats = ListeningStats.from(
        records: [_play('a', at)],
        adSecondsPerTrack: 0,
        premiumMonthlyCost: 12,
        now: at,
      );

      expect(stats.monthsActive, 1);
      expect(stats.premiumCostEquivalent, 12);
    });

    test(
      'unknown durations lower the coverage instead of inflating totals',
      () {
        final at = DateTime(2026, 3, 1);
        final stats = ListeningStats.from(
          records: [
            _play('a', at, ms: 200000),
            _play('gone', at.add(const Duration(minutes: 1)), ms: 0),
          ],
          adSecondsPerTrack: 10,
          premiumMonthlyCost: 10,
          now: at,
        );

        expect(stats.listeningTime, const Duration(milliseconds: 200000));
        expect(stats.tracksWithKnownDuration, 1);
        expect(stats.durationCoverage, 0.5);
      },
    );

    test('the daily window has one entry per day, oldest first', () {
      final now = DateTime(2026, 3, 10, 12);
      final stats = ListeningStats.from(
        records: [
          _play('a', DateTime(2026, 3, 10, 9)),
          _play('b', DateTime(2026, 3, 10, 10)),
          _play('c', DateTime(2026, 3, 8, 10)),
        ],
        adSecondsPerTrack: 0,
        premiumMonthlyCost: 0,
        now: now,
        windowDays: 5,
      );

      expect(stats.dailyPlays, hasLength(5));
      expect(stats.dailyPlays.first.day, DateTime(2026, 3, 6));
      expect(stats.dailyPlays.last.day, DateTime(2026, 3, 10));
      expect(stats.dailyPlays.last.plays, 2);
      expect(stats.dailyPlays[2].plays, 1, reason: 'March 8 had one play');
      expect(stats.dailyPlays[3].plays, 0);
      expect(stats.maxDailyPlays, 2);
    });
  });
}
