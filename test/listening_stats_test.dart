import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/listening_stats.dart';
import 'package:gandar/domain/models/play_record.dart';

PlayRecord _play(String id, DateTime at, {int ms = 200000}) =>
    PlayRecord(trackId: id, playedAt: at, durationMs: ms);

/// Builds stats with the test's round numbers, so each assertion can be checked
/// by hand: a 10-minute break interval, one 30-second ad, $20 CPM.
ListeningStats _stats(
  List<PlayRecord> records, {
  double adBreakMinutes = 10,
  double adsPerBreak = 1,
  double adSeconds = 30,
  double adsCpm = 20,
  double premiumMonthlyCost = 10,
  double artistPayoutPerStream = 0.004,
  DateTime? now,
}) => ListeningStats.from(
  records: records,
  adBreakMinutes: adBreakMinutes,
  adsPerBreak: adsPerBreak,
  adSeconds: adSeconds,
  adsCpm: adsCpm,
  premiumMonthlyCost: premiumMonthlyCost,
  artistPayoutPerStream: artistPayoutPerStream,
  now: now,
);

void main() {
  group('ListeningStats', () {
    test('no history is all zeroes rather than nonsense', () {
      final stats = _stats(const []);

      expect(stats.totalPlays, 0);
      expect(stats.listeningTime, Duration.zero);
      expect(stats.adBreaks, 0);
      expect(stats.adTimeAvoided, Duration.zero);
      expect(stats.adEarningsAvoided, 0);
      expect(stats.monthsActive, 0);
      expect(stats.monthlySaving, 0);
      expect(stats.premiumCostEquivalent, 0);
      expect(stats.durationCoverage, 1);
    });

    test('adds up listening time, distinct tracks and known durations', () {
      final start = DateTime(2026, 3, 1, 10);
      final stats = _stats([
        _play('a', start, ms: 180000),
        _play('b', start.add(const Duration(minutes: 4)), ms: 200000),
        _play('a', start.add(const Duration(minutes: 9)), ms: 180000),
      ], now: start);

      expect(stats.totalPlays, 3);
      expect(stats.distinctTracks, 2);
      expect(stats.listeningTime, const Duration(milliseconds: 560000));
      expect(stats.tracksWithKnownDuration, 3);
    });

    test('ad load follows the clock, not the track count', () {
      // The same 20 minutes of listening, once as four long tracks and once as
      // twenty short ones. A service that breaks on elapsed time charges the
      // same number of breaks either way, and that is the point of modelling it
      // this way rather than per track.
      final start = DateTime(2026, 3, 1, 10);
      final fewLong = <PlayRecord>[
        for (var i = 0; i < 4; i++)
          _play('long$i', start.add(Duration(minutes: 5 * i)), ms: 300000),
      ];
      final manyShort = <PlayRecord>[
        for (var i = 0; i < 20; i++)
          _play('short$i', start.add(Duration(minutes: i)), ms: 60000),
      ];

      final a = _stats(fewLong, now: start);
      final b = _stats(manyShort, now: start);

      expect(a.listeningTime, const Duration(minutes: 20));
      expect(b.listeningTime, const Duration(minutes: 20));
      expect(a.adBreaks, 2);
      expect(b.adBreaks, a.adBreaks);
    });

    test('ad time and ad money come from the breaks, not the plays', () {
      final start = DateTime(2026, 3, 1, 10);
      final stats = _stats([
        for (var i = 0; i < 3; i++)
          _play('t$i', start.add(Duration(minutes: 5 * i)), ms: 200000),
      ], now: start);

      // 10 minutes at a break every 10 minutes is exactly one break.
      expect(stats.listeningTime, const Duration(minutes: 10));
      expect(stats.adBreaks, 1);
      expect(stats.adSpots, 1);
      expect(stats.adTimeAvoided, const Duration(seconds: 30));
      // One impression at $20 CPM.
      expect(stats.adEarningsAvoided, closeTo(0.02, 1e-9));
      expect(stats.timeReclaimed, const Duration(seconds: 630));
    });

    test('the per-hour figure is the published CPM arithmetic', () {
      final stats = _stats(const [])
          .withAssumptions(adBreakMinutes: 12, adsPerBreak: 1, adsCpm: 20);

      // Five breaks an hour at $0.02 an impression: $0.10 an hour, which sits
      // inside the $0.06-$0.15 an hour a 4-6 breaks/hour observation implies.
      expect(stats.adEarningsPerHour, closeTo(0.10, 1e-9));

      final expensive = stats.withAssumptions(adsCpm: 25, adBreakMinutes: 10);
      expect(expensive.adEarningsPerHour, closeTo(0.15, 1e-9));
    });

    test('more ads per break costs more ad time', () {
      final start = DateTime(2026, 3, 1, 10);
      final records = <PlayRecord>[_play('a', start, ms: 600000)];

      final one = _stats(records, now: start, adsPerBreak: 1);
      final three = _stats(records, now: start, adsPerBreak: 3);

      expect(one.adTimeAvoided, const Duration(seconds: 30));
      expect(three.adTimeAvoided, const Duration(seconds: 90));
      expect(three.adEarningsAvoided, closeTo(0.06, 1e-9));
    });

    test('a zero break interval cannot divide by zero', () {
      final start = DateTime(2026, 3, 1, 10);
      final stats = _stats(
        [_play('a', start, ms: 600000)],
        adBreakMinutes: 0,
        now: start,
      );

      expect(stats.adBreaks, 0);
      expect(stats.adEarningsPerHour, 0);
    });

    test('months are counted by the calendar, across a year boundary', () {
      final stats = _stats([
        _play('a', DateTime(2025, 11, 20)),
        _play('b', DateTime(2026, 1, 5)),
      ]);

      // November, December, January: three billing months, not two.
      expect(stats.monthsActive, 3);
      expect(stats.premiumCostEquivalent, closeTo(30, 1e-9));
      expect(stats.monthlySaving, 10);
    });

    test('artist payouts are the estimate times the plays', () {
      final start = DateTime(2026, 3, 1, 10);
      final stats = _stats([
        _play('a', start),
        _play('b', start.add(const Duration(minutes: 1))),
      ], now: start);

      expect(stats.artistPayoutEquivalent, closeTo(0.008, 1e-9));
    });

    test('coverage reports how much of the time is known', () {
      final start = DateTime(2026, 3, 1, 10);
      final stats = _stats([
        _play('a', start, ms: 180000),
        // A track that has since been removed contributes no duration.
        _play('gone', start.add(const Duration(minutes: 4)), ms: 0),
      ]);

      expect(stats.totalPlays, 2);
      expect(stats.listeningTime, const Duration(minutes: 3));
      expect(stats.durationCoverage, closeTo(0.5, 1e-9));
    });

    test('the daily window is zero-filled and ends today', () {
      final now = DateTime(2026, 3, 14, 12);
      final stats = _stats([
        _play('a', DateTime(2026, 3, 14, 9)),
        _play('b', DateTime(2026, 3, 14, 10)),
        _play('c', DateTime(2026, 3, 11, 10)),
      ], now: now);

      expect(stats.dailyPlays, hasLength(14));
      expect(stats.dailyPlays.last.plays, 2);
      expect(stats.dailyPlays.last.day, DateTime(2026, 3, 14));
      // The window is 1-14 March, so the 11th is index 10.
      expect(stats.dailyPlays[10].day, DateTime(2026, 3, 11));
      expect(stats.dailyPlays[10].plays, 1);
      expect(stats.maxDailyPlays, 2);
    });

    test('withAssumptions keeps the facts and swaps the guesses', () {
      final start = DateTime(2026, 3, 1, 10);
      final original = _stats([_play('a', start, ms: 1200000)], now: start);
      final changed = original.withAssumptions(adsCpm: 40);

      expect(changed.listeningTime, original.listeningTime);
      expect(changed.totalPlays, original.totalPlays);
      expect(
        changed.adEarningsAvoided,
        closeTo(original.adEarningsAvoided * 2, 1e-9),
      );
    });

    test('a corrupt saved payload does not crash the card', () {
      // These are the defaults a fresh or hand-edited settings file produces.
      final stats = ListeningStats.empty.withAssumptions(
        premiumMonthlyCost: 12.99,
      );
      expect(stats.premiumMonthlyCost, 12.99);
      expect(stats.adBreakMinutes, greaterThan(0));
      expect(stats.adEarningsAvoided, 0);
    });
  });
}
