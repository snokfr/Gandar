import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine.dart';
import '../../data/usage/app_usage.dart';
import '../../domain/models/listening_stats.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// "What you are saving" — money and time, from this device's play history.
///
/// Only two numbers here are facts: [ListeningStats.listeningTime] and
/// [ListeningStats.totalPlays]. Everything else is arithmetic on assumptions
/// printed at the bottom of the card, each of which the user can change. The
/// card says which is which rather than dressing a guess up as a measurement.
class SavingsCard extends ConsumerWidget {
  const SavingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(listeningStatsProvider);
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);
    final usage = ref.watch(appUsageProvider);
    final theme = Theme.of(context);

    return stats.when(
      loading: () => const GandarCard(
        child: SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) =>
          GandarCard(child: Text('Could not read your play history: $error')),
      data: (data) => GandarCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.savings_outlined),
                const SizedBox(width: 8),
                Text(
                  'What you have saved',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              data.totalPlays == 0
                  ? 'Play a few tracks and this fills in.'
                  : 'From ${data.totalPlays} plays on this device.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _Metric(
                  label: 'Subscription you did not buy',
                  value: data.totalPlays == 0
                      ? '—'
                      : '\$${data.premiumCostEquivalent.toStringAsFixed(2)}',
                  hint:
                      '${data.monthsActive} '
                      'month${data.monthsActive == 1 ? '' : 's'} at '
                      '\$${data.premiumMonthlyCost.toStringAsFixed(2)}/month',
                ),
                _Metric(
                  label: 'Ad money they did not earn',
                  value: data.totalPlays == 0
                      ? '—'
                      : '\$${data.adEarningsAvoided.toStringAsFixed(2)}',
                  hint:
                      'advertiser spend for ${data.adBreaks} ad '
                      'break${data.adBreaks == 1 ? '' : 's'}',
                ),
                _Metric(
                  label: 'Ad time skipped',
                  value: _duration(data.adTimeAvoided),
                  hint:
                      'at ${data.adBreakMinutes.toStringAsFixed(0)} min between '
                      'breaks',
                ),
                _Metric(
                  label: 'Music played',
                  value: _duration(data.listeningTime),
                  hint: data.durationCoverage < 1
                      ? 'partial: durations known for '
                            '${(data.durationCoverage * 100).round()}% of plays'
                      : 'every play had a known duration',
                ),
                _Metric(
                  label: 'Artist payouts generated',
                  value: data.totalPlays == 0
                      ? '—'
                      : '\$${data.artistPayoutEquivalent.toStringAsFixed(2)}',
                  hint:
                      'estimate at \$'
                      '${data.artistPayoutPerStream.toStringAsFixed(3)} a '
                      'stream',
                ),
                _Metric(
                  label: 'Different songs',
                  value: '${data.distinctTracks}',
                  hint: 'of ${data.totalPlays} plays',
                ),
                _Metric(
                  label: 'Time in Gandar',
                  value: describeShortDuration(usage.lifetimeIncludingSession),
                  hint:
                      '${describeShortDuration(usage.session)} this session, '
                      'counting from launch',
                ),
              ],
            ),

            if (data.totalPlays > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.gandarTokens.surfaceElevatedColor,
                  borderRadius: BorderRadius.circular(
                    context.gandarTokens.radiusSm,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: context.gandarTokens.textSecondaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A free account earns its service about '
                        '\$${data.adEarningsPerHour.toStringAsFixed(2)} an hour '
                        'from advertising at these settings — which is why the '
                        'ads are there.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (data.maxDailyPlays > 0) ...[
              const SizedBox(height: 20),
              Text('Last 14 days', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              _PlaySparkline(data: data),
            ],

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Assumptions', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'These are estimates, not measurements, and none of them is '
              'published by Spotify. Change them to match what you see and '
              'hear.',
              style: theme.textTheme.bodySmall,
            ),
            SettingSliderTile(
              title: 'Subscription price',
              description: 'Monthly cost of the plan you did not buy. Spotify '
                  'charges \$12.99 for its US Individual plan.',
              value: settings.savingsPremiumMonthlyCost,
              min: 0,
              max: 30,
              divisions: 60,
              valueLabel: (v) => '\$${v.toStringAsFixed(2)}',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsPremiumMonthlyCost: v),
              ),
            ),
            SettingSliderTile(
              title: 'Minutes between ad breaks',
              description:
                  'A free account plays a break every ten to fifteen minutes '
                  'of listening. Ads are counted against time, not tracks.',
              value: settings.savingsAdBreakMinutes,
              min: 2,
              max: 30,
              divisions: 28,
              valueLabel: (v) => '${v.toStringAsFixed(0)} min',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsAdBreakMinutes: v),
              ),
            ),
            SettingSliderTile(
              title: 'Length of one ad',
              description: 'Spotify\'s audio ads run up to 30 seconds.',
              value: settings.savingsAdSeconds,
              min: 0,
              max: 60,
              divisions: 60,
              valueLabel: (v) => '${v.toStringAsFixed(0)} s',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsAdSeconds: v),
              ),
            ),
            SettingSliderTile(
              title: 'Ads per break',
              description: 'How many spots play in one break.',
              value: settings.savingsAdsPerBreak,
              min: 0,
              max: 4,
              divisions: 8,
              valueLabel: (v) => v.toStringAsFixed(1),
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsAdsPerBreak: v),
              ),
            ),
            SettingSliderTile(
              title: 'Ad cost per thousand plays',
              description:
                  'What an advertiser pays per 1,000 impressions. Industry '
                  'guides put Spotify audio around \$15–\$25.',
              value: settings.savingsAdsCpm,
              min: 0,
              max: 60,
              divisions: 60,
              valueLabel: (v) => '\$${v.toStringAsFixed(0)}',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsAdsCpm: v),
              ),
            ),
            SettingSliderTile(
              title: 'Artist payout per stream',
              description:
                  'Industry estimates run \$0.003–\$0.005, and this is a '
                  'rights-holder payout rather than Spotify\'s revenue.',
              value: settings.savingsArtistPayoutPerStream,
              min: 0,
              max: 0.02,
              divisions: 20,
              valueLabel: (v) => '\$${v.toStringAsFixed(3)}',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsArtistPayoutPerStream: v),
              ),
            ),

            const SizedBox(height: 12),
            Text('Where these come from', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final source in _sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $source',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const List<String> _sources = <String>[
    'Spotify Premium US pricing (January 2026 increase): '
        'spotify.com/us/premium',
    'Audio ad formats and the 30-second spot: '
        'ads.spotify.com/en-US/ad-specs/audio-ad-specs/',
    'How Spotify pays rights holders (revenue share, not a per-stream rate): '
        'artists.spotify.com/royalties-guide',
    'Per-stream payout estimates of \$0.003–\$0.005: tunecore.com/guides/'
        'how-much-does-spotify-pay',
    'Reported ad-break frequency of roughly every 10–15 minutes in listening '
        'tests, and \$15–\$25 CPM benchmarks from agency guides. Both are '
        'third-party observations, not Spotify figures.',
  ];

  /// Compact duration: `2 h 14 m`, `45 m`, `30 s`.
  static String _duration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} m';
    final hours = d.inHours;
    final minutes = d.inMinutes - hours * 60;
    return minutes == 0 ? '$hours h' : '$hours h $minutes m';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: context.gandarTokens.accentColor,
            ),
          ),
          Text(label, style: theme.textTheme.bodyMedium),
          if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Fourteen bars, one per day, scaled to the busiest day.
class _PlaySparkline extends StatelessWidget {
  const _PlaySparkline({required this.data});

  final ListeningStats data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    final max = data.maxDailyPlays;
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in data.dailyPlays)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: '${day.plays} plays',
                  child: Container(
                    height: max == 0 ? 2 : 4 + (36 * day.plays / max),
                    decoration: BoxDecoration(
                      color: day.plays == 0
                          ? tokens.borderColor
                          : tokens.accentColor,
                      borderRadius: BorderRadius.circular(tokens.radiusSm / 2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
