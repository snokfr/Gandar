import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine.dart';
import '../../domain/models/listening_stats.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// "What you are saving" — money and time, from this device's play history.
///
/// Two numbers are facts ([ListeningStats.listeningTime] and
/// [ListeningStats.totalPlays]); the rest are estimates built on the two
/// assumptions shown at the bottom of the card, which the user can change. The
/// card says so rather than presenting a guess as a measurement.
class SavingsCard extends ConsumerWidget {
  const SavingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(listeningStatsProvider);
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);

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
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              data.totalPlays == 0
                  ? 'Play a few tracks and this fills in.'
                  : 'From ${data.totalPlays} plays on this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _Metric(
                  label: 'Money, this month',
                  value: data.totalPlays == 0
                      ? '—'
                      : '\$${data.monthlySaving.toStringAsFixed(2)}',
                  hint: 'a paid subscription instead',
                ),
                _Metric(
                  label: 'Money, all time',
                  value: data.totalPlays == 0
                      ? '—'
                      : '\$${data.premiumCostEquivalent.toStringAsFixed(2)}',
                  hint:
                      '${data.monthsActive} '
                      'month${data.monthsActive == 1 ? '' : 's'} of use',
                ),
                _Metric(
                  label: 'Ad time skipped',
                  value: _duration(data.adTimeAvoided),
                  hint:
                      'estimated at ${data.adSecondsPerTrack.round()}s per track',
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
                  label: 'Time reclaimed',
                  value: _duration(data.timeReclaimed),
                  hint: 'listening plus skipped ads',
                ),
                _Metric(
                  label: 'Different songs',
                  value: '${data.distinctTracks}',
                  hint: 'of ${data.totalPlays} plays',
                ),
              ],
            ),

            if (data.maxDailyPlays > 0) ...[
              const SizedBox(height: 20),
              Text(
                'Last 14 days',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              _PlaySparkline(data: data),
            ],

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Assumptions', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              'These are guesses, not measurements. Adjust them to match the '
              'service you are comparing against.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SettingSliderTile(
              title: 'Ad time per track',
              description: 'Ad seconds a free account would play per song.',
              value: settings.savingsAdSecondsPerTrack,
              min: 0,
              max: 60,
              divisions: 60,
              valueLabel: (v) => '${v.toStringAsFixed(0)} s',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsAdSecondsPerTrack: v),
              ),
            ),
            SettingSliderTile(
              title: 'Subscription price',
              description: 'Monthly cost of the paid service you did not buy.',
              value: settings.savingsPremiumMonthlyCost,
              min: 0,
              max: 30,
              divisions: 60,
              valueLabel: (v) => '\$${v.toStringAsFixed(2)}',
              onChanged: (v) => notifier.update(
                settings.copyWith(savingsPremiumMonthlyCost: v),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
      width: 170,
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
