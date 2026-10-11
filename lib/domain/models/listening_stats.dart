import 'play_record.dart';

/// What the play history adds up to, for the savings view.
///
/// Pure and deterministic, so the arithmetic is unit-testable. Two numbers here
/// are *facts* — [listeningTime] and [totalPlays]. Everything else is an
/// estimate built from assumptions the user can see and change, and the card
/// says so rather than presenting a guess as a measurement.
///
/// ## Where the assumptions come from
///
/// The model is Spotify's behaviour as it has been measured from outside, not a
/// figure Spotify publishes:
///
/// * **Ad load** — a break roughly every 10-15 minutes of listening, with ads up
///   to 30 seconds (Spotify's own audio ad specs allow 30-second music ads).
///   [adBreakMinutes] defaults to the 12-minute midpoint of that observation.
/// * **CPM** — third-party agency guides put Spotify audio inventory around
///   $15-$25 per thousand impressions; [adsCpm] defaults to $20.
/// * **Subscription price** — Spotify's US Individual plan, which rose to
///   $12.99/month in January 2026.
/// * **Payout per stream** — the industry estimate of $0.003-$0.005 a stream is
///   a *rights-holder* payout, not Spotify's revenue. [artistPayoutPerStream]
///   defaults to the $0.004 midpoint and is labelled as an estimate.
///
/// The one number Spotify does publish that is easy to confuse with these is
/// its per-subscriber revenue (about €4.89 a month in Q2 2026). That is what a
/// *paying* subscriber is worth to Spotify, so it is deliberately not used as
/// "what you cost them", because this app's users are the free tier.
class ListeningStats {
  const ListeningStats({
    required this.totalPlays,
    required this.distinctTracks,
    required this.listeningTime,
    required this.firstPlayedAt,
    required this.lastPlayedAt,
    required this.premiumMonthlyCost,
    required this.adBreakMinutes,
    required this.adSeconds,
    required this.adsPerBreak,
    required this.adsCpm,
    required this.artistPayoutPerStream,
    required this.tracksWithKnownDuration,
    required this.dailyPlays,
  });

  final int totalPlays;
  final int distinctTracks;

  /// Sum of the durations of the tracks that are cached locally. A floor, not a
  /// total: a play of a track that has since been removed contributes nothing.
  final Duration listeningTime;

  final DateTime? firstPlayedAt;
  final DateTime? lastPlayedAt;

  /// Monthly price of the subscription being compared against.
  final double premiumMonthlyCost;

  /// Minutes of listening between ad breaks on a free, ad-supported service.
  final double adBreakMinutes;

  /// Length of one ad spot, in seconds.
  final double adSeconds;

  /// How many ads play in one break.
  final double adsPerBreak;

  /// Gross advertiser cost per thousand impressions, in US dollars.
  final double adsCpm;

  /// Estimated rights-holder payout per stream, in US dollars.
  final double artistPayoutPerStream;

  /// How many plays contributed a known duration, so the UI can say how
  /// complete [listeningTime] is.
  final int tracksWithKnownDuration;

  /// Plays per calendar day, oldest first.
  final List<({DateTime day, int plays})> dailyPlays;

  /// The published range the per-stream estimate comes from.
  static const double artistPayoutLow = 0.003;
  static const double artistPayoutHigh = 0.005;

  static const ListeningStats empty = ListeningStats(
    totalPlays: 0,
    distinctTracks: 0,
    listeningTime: Duration.zero,
    firstPlayedAt: null,
    lastPlayedAt: null,
    premiumMonthlyCost: 12.99,
    adBreakMinutes: 12.0,
    adSeconds: 30.0,
    adsPerBreak: 1.0,
    adsCpm: 20.0,
    artistPayoutPerStream: 0.004,
    tracksWithKnownDuration: 0,
    dailyPlays: <({DateTime day, int plays})>[],
  );

  /// How many ad breaks a free account would have played over [listeningTime].
  ///
  /// Derived from *time listened*, not tracks played. That is the whole point of
  /// the model: a free account's ad load follows the clock, so a nine-minute
  /// album track and nine one-minute songs get the same number of breaks.
  int get adBreaks {
    if (adBreakMinutes <= 0) return 0;
    return (listeningTime.inSeconds / (adBreakMinutes * 60)).floor();
  }

  /// Individual ads across those breaks.
  double get adSpots => adBreaks * adsPerBreak;

  /// Ad time a free account would have played instead.
  Duration get adTimeAvoided =>
      Duration(seconds: (adSpots * adSeconds).round());

  /// Gross advertising spend a free listener would have generated, in dollars.
  ///
  /// This is the advertiser's side of the deal — what the free tier sells — so
  /// it is the honest answer to "how much money did they make off me". It is
  /// deliberately *not* presented as Spotify's profit: Spotify keeps a share,
  /// pays rights holders out of revenue, and carries the costs.
  double get adEarningsAvoided => adSpots * (adsCpm / 1000);

  /// The same figure expressed per hour listened, which is the number that can
  /// be checked against a published CPM rather than taken on trust.
  double get adEarningsPerHour {
    if (adBreakMinutes <= 0) return 0;
    return (60 / adBreakMinutes) * adsPerBreak * (adsCpm / 1000);
  }

  /// Calendar months touched by the history.
  ///
  /// Uses calendar arithmetic so the comparison matches how a subscription
  /// actually bills: using it from 1 Jan to 1 Mar is three charges, not two.
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

  /// Estimated rights-holder payouts the plays would have generated.
  double get artistPayoutEquivalent => totalPlays * artistPayoutPerStream;

  /// Fraction of plays whose duration was known, 0..1.
  double get durationCoverage =>
      totalPlays == 0 ? 1 : tracksWithKnownDuration / totalPlays;

  /// Busiest day in the window, for scaling a chart.
  int get maxDailyPlays =>
      dailyPlays.fold(0, (max, d) => d.plays > max ? d.plays : max);

  /// The same stats with different assumptions, for rebuilding on a settings
  /// change without re-reading the history.
  ListeningStats withAssumptions({
    double? premiumMonthlyCost,
    double? adBreakMinutes,
    double? adSeconds,
    double? adsPerBreak,
    double? adsCpm,
    double? artistPayoutPerStream,
  }) => ListeningStats(
    totalPlays: totalPlays,
    distinctTracks: distinctTracks,
    listeningTime: listeningTime,
    firstPlayedAt: firstPlayedAt,
    lastPlayedAt: lastPlayedAt,
    premiumMonthlyCost: premiumMonthlyCost ?? this.premiumMonthlyCost,
    adBreakMinutes: adBreakMinutes ?? this.adBreakMinutes,
    adSeconds: adSeconds ?? this.adSeconds,
    adsPerBreak: adsPerBreak ?? this.adsPerBreak,
    adsCpm: adsCpm ?? this.adsCpm,
    artistPayoutPerStream:
        artistPayoutPerStream ?? this.artistPayoutPerStream,
    tracksWithKnownDuration: tracksWithKnownDuration,
    dailyPlays: dailyPlays,
  );

  /// Builds the stats from raw history.
  ///
  /// [windowDays] controls the length of [dailyPlays]. Days with no plays are
  /// included as zeroes so a chart does not skew.
  factory ListeningStats.from({
    required List<PlayRecord> records,
    required double premiumMonthlyCost,
    required double adBreakMinutes,
    required double adSeconds,
    required double adsPerBreak,
    required double adsCpm,
    required double artistPayoutPerStream,
    DateTime? now,
    int windowDays = 14,
  }) {
    ListeningStats withAssumptionsOf(ListeningStats base) =>
        base.withAssumptions(
          premiumMonthlyCost: premiumMonthlyCost,
          adBreakMinutes: adBreakMinutes,
          adSeconds: adSeconds,
          adsPerBreak: adsPerBreak,
          adsCpm: adsCpm,
          artistPayoutPerStream: artistPayoutPerStream,
        );

    if (records.isEmpty) {
      return withAssumptionsOf(ListeningStats.empty);
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
      premiumMonthlyCost: premiumMonthlyCost,
      adBreakMinutes: adBreakMinutes,
      adSeconds: adSeconds,
      adsPerBreak: adsPerBreak,
      adsCpm: adsCpm,
      artistPayoutPerStream: artistPayoutPerStream,
      tracksWithKnownDuration: known,
      dailyPlays: daily,
    );
  }
}
