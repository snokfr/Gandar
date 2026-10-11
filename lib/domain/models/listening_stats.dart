import 'play_record.dart';

/// What the play history adds up to, for the savings view.
///
/// Pure and deterministic so the arithmetic is unit-testable. Everything except
/// [listeningTime] and [totalPlays] is an *estimate*, and the two assumptions it
/// uses are surfaced to the user rather than buried: see [adSecondsPerTrack]
/// and [premiumMonthlyCost].
class ListeningStats {
  const ListeningStats({
    required this.totalPlays,
    required this.distinctTracks,
    required this.listeningTime,
    required this.firstPlayedAt,
    required this.lastPlayedAt,
    required this.adSecondsPerTrack,
    required this.premiumMonthlyCost,
    required this.tracksWithKnownDuration,
    required this.dailyPlays,
  });

  final int totalPlays;
  final int distinctTracks;

  /// Sum of the durations of tracks that are cached locally.
  final Duration listeningTime;
  final DateTime? firstPlayedAt;
  final DateTime? lastPlayedAt;

  /// Assumed ad seconds a free service plays per track.
  final double adSecondsPerTrack;

  /// Monthly price of the subscription being compared against.
  final double premiumMonthlyCost;

  /// How many plays contributed a known duration, so the UI can say how
  /// complete [listeningTime] is.
  final int tracksWithKnownDuration;

  /// Plays per calendar day, oldest first, for the last [dailyPlays] window.
  final List<({DateTime day, int plays})> dailyPlays;

  static const ListeningStats empty = ListeningStats(
    totalPlays: 0,
    distinctTracks: 0,
    listeningTime: Duration.zero,
    firstPlayedAt: null,
    lastPlayedAt: null,
    adSecondsPerTrack: 20,
    premiumMonthlyCost: 11.99,
    tracksWithKnownDuration: 0,
    dailyPlays: <({DateTime day, int plays})>[],
  );

  /// Ad time a free, ad-supported service would have played instead.
  Duration get adTimeAvoided =>
      Duration(seconds: (totalPlays * adSecondsPerTrack).round());

  /// Calendar months touched by the history, so the comparison matches how a
  /// subscription actually bills: using it from 1 Jan to 1 Mar is three
  /// charges, not two. Zero when unused.
  int get monthsActive {
    final first = firstPlayedAt;
    if (first == null || totalPlays == 0) return 0;
    final last = lastPlayedAt ?? first;
    final months =
        (last.year - first.year) * 12 + (last.month - first.month) + 1;
    return months.clamp(1, 1200);
  }

  /// What the paid equivalent would have cost over [monthsActive].
  double get premiumCostEquivalent => premiumMonthlyCost * monthsActive;

  /// The monthly figure, which is what a subscription actually charges.
  double get monthlySaving => totalPlays == 0 ? 0 : premiumMonthlyCost;

  /// Listening time plus the ad time that was skipped.
  Duration get timeReclaimed => listeningTime + adTimeAvoided;

  /// Fraction of plays whose duration was known, 0..1.
  double get durationCoverage =>
      totalPlays == 0 ? 1 : tracksWithKnownDuration / totalPlays;

  /// Busiest day in the window, for scaling a chart.
  int get maxDailyPlays =>
      dailyPlays.fold(0, (max, d) => d.plays > max ? d.plays : max);

  /// Builds the stats from raw history.
  ///
  /// [windowDays] controls the length of [dailyPlays]. Days with no plays are
  /// included as zeroes so a chart does not skew.
  factory ListeningStats.from({
    required List<PlayRecord> records,
    required double adSecondsPerTrack,
    required double premiumMonthlyCost,
    DateTime? now,
    int windowDays = 14,
  }) {
    if (records.isEmpty) {
      return ListeningStats.empty.copyWith(
        adSecondsPerTrack: adSecondsPerTrack,
        premiumMonthlyCost: premiumMonthlyCost,
      );
    }

    final reference = now ?? DateTime.now();
    var totalMs = 0;
    var known = 0;
    final distinct = <String>{};
    DateTime? first;
    DateTime? last;
    final perDay = <DateTime, int>{};

    for (final record in records) {
      distinct.add(record.trackId);
      if (record.durationMs > 0) {
        totalMs += record.durationMs;
        known++;
      }
      final at = record.playedAt;
      if (first == null || at.isBefore(first)) first = at;
      if (last == null || at.isAfter(last)) last = at;

      final day = DateTime(at.year, at.month, at.day);
      perDay[day] = (perDay[day] ?? 0) + 1;
    }

    // Built by calendar arithmetic, not by subtracting 24-hour periods: across
    // a DST change the latter lands on 23:00 of the previous day.
    final daily = <({DateTime day, int plays})>[
      for (var i = windowDays - 1; i >= 0; i--)
        () {
          final day = DateTime(
            reference.year,
            reference.month,
            reference.day - i,
          );
          return (day: day, plays: perDay[day] ?? 0);
        }(),
    ];

    return ListeningStats(
      totalPlays: records.length,
      distinctTracks: distinct.length,
      listeningTime: Duration(milliseconds: totalMs),
      firstPlayedAt: first,
      lastPlayedAt: last,
      adSecondsPerTrack: adSecondsPerTrack,
      premiumMonthlyCost: premiumMonthlyCost,
      tracksWithKnownDuration: known,
      dailyPlays: daily,
    );
  }

  ListeningStats copyWith({
    double? adSecondsPerTrack,
    double? premiumMonthlyCost,
  }) => ListeningStats(
    totalPlays: totalPlays,
    distinctTracks: distinctTracks,
    listeningTime: listeningTime,
    firstPlayedAt: firstPlayedAt,
    lastPlayedAt: lastPlayedAt,
    adSecondsPerTrack: adSecondsPerTrack ?? this.adSecondsPerTrack,
    premiumMonthlyCost: premiumMonthlyCost ?? this.premiumMonthlyCost,
    tracksWithKnownDuration: tracksWithKnownDuration,
    dailyPlays: dailyPlays,
  );
}
