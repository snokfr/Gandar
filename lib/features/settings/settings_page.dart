import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/eq_presets.dart';
import '../../core/settings/playback_settings.dart';
import '../../core/theme/theme_engine.dart';
import '../../domain/models/cache_entry.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../player/player_surface.dart';

/// Settings modeled on Spotify's playback menu plus Gandar's extra controls.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);
    final tokens = context.gandarTokens;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(
            title: 'Playback',
            subtitle: 'Audio processing and transition behaviour',
          ),
          const SizedBox(height: 16),

          // ---- Equalizer -------------------------------------------------
          GandarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingSwitchTile(
                  title: 'Equalizer',
                  description:
                      'Shape the sound with a 10-band equalizer and presets.',
                  value: settings.eqEnabled,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(eqEnabled: v)),
                ),
                if (settings.eqEnabled) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: settings.eqPreset,
                    decoration: const InputDecoration(labelText: 'Preset'),
                    items: [
                      for (final preset in EqPresets.all)
                        DropdownMenuItem(
                          value: preset.id,
                          child: Text(preset.label),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      final preset = EqPresets.byId(id);
                      if (preset == null) return;
                      notifier.update(
                        settings.copyWith(
                          eqPreset: id,
                          eqBands: preset.apply(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Bands', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  for (var i = 0; i < settings.eqBands.length; i++)
                    SettingSliderTile(
                      title: _bandLabel(settings.eqBands[i].frequency),
                      value: settings.eqBands[i].gain,
                      min: -12,
                      max: 12,
                      divisions: 24,
                      valueLabel: (v) =>
                          '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)} dB',
                      description: null,
                      onChanged: (v) {
                        final bands = List<EqBand>.of(settings.eqBands);
                        bands[i] = bands[i].copyWith(gain: v);
                        notifier.update(
                          settings.copyWith(eqPreset: 'custom', eqBands: bands),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Crossfade / automix --------------------------------------
          GandarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingSliderTile(
                  title: 'Crossfade',
                  description: 'Smoothly blend the end of one track into the next. Set to 0 to disable.',
                  value: settings.crossfadeSeconds,
                  min: 0,
                  max: 12,
                  divisions: 12,
                  valueLabel: (v) =>
                      v == 0 ? 'Off' : '${v.toStringAsFixed(0)} s',
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(crossfadeSeconds: v)),
                ),
                SettingSwitchTile(
                  title: 'Automix',
                  description: 'Use crossfade and beat-aware transitions between tracks.',
                  value: settings.automixEnabled,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(automixEnabled: v)),
                ),
                SettingSwitchTile(
                  title: 'Gapless playback',
                  description: 'Remove the silence between consecutive tracks in an album.',
                  value: settings.gaplessPlayback,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(gaplessPlayback: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Normalization / mono -------------------------------------
          GandarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingSwitchTile(
                  title: 'Volume level',
                  description: 'Normalize loudness across tracks (EBU R128 / ReplayGain style).',
                  value: settings.normalizationEnabled,
                  onChanged: (v) => notifier.update(
                    settings.copyWith(normalizationEnabled: v),
                  ),
                ),
                if (settings.normalizationEnabled)
                  SegmentedButton<NormalizationLevel>(
                    segments: const [
                      ButtonSegment(
                        value: NormalizationLevel.quiet,
                        label: Text('Quiet'),
                      ),
                      ButtonSegment(
                        value: NormalizationLevel.normal,
                        label: Text('Normal'),
                      ),
                      ButtonSegment(
                        value: NormalizationLevel.loud,
                        label: Text('Loud'),
                      ),
                    ],
                    selected: {settings.normalizationLevel},
                    onSelectionChanged: (selection) => notifier.update(
                      settings.copyWith(normalizationLevel: selection.first),
                    ),
                  ),
                const SizedBox(height: 8),
                SettingSwitchTile(
                  title: 'Mono audio',
                  description: 'Mix both channels into one. Useful with a single earbud or speaker.',
                  value: settings.monoAudio,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(monoAudio: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Shuffle / prefetch ---------------------------------------
          GandarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shuffle', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<ShuffleMode>(
                  segments: const [
                    ButtonSegment(value: ShuffleMode.off, label: Text('Off')),
                    ButtonSegment(
                      value: ShuffleMode.standard,
                      label: Text('Standard'),
                    ),
                    ButtonSegment(
                      value: ShuffleMode.smart,
                      label: Text('Smart'),
                    ),
                  ],
                  selected: {settings.shuffleMode},
                  onSelectionChanged: (s) =>
                      notifier.update(settings.copyWith(shuffleMode: s.first)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Smart shuffle avoids replaying tracks you heard recently.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SettingSwitchTile(
                  title: 'Pre-fetch next track',
                  description: 'Resolve and buffer the next track while the current one plays.',
                  value: settings.prefetchNextTrack,
                  onChanged: (v) =>
                      notifier.update(settings.copyWith(prefetchNextTrack: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Cache -----------------------------------------------------
          GandarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage & cache',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SettingSliderTile(
                  title: 'Maximum cached audio',
                  description: 'Least-recently-played files are deleted first when this limit is reached.',
                  value: settings.cacheMaxMegabytes.toDouble(),
                  min: 256,
                  max: 16384,
                  divisions: 63,
                  valueLabel: (v) => '${(v / 1024).toStringAsFixed(1)} GB',
                  onChanged: (v) => notifier.update(
                    settings.copyWith(cacheMaxMegabytes: v.round()),
                  ),
                ),
                SettingSliderTile(
                  title: 'Delete unused after',
                  description: 'Remove audio you have not played in this long.',
                  value: settings.cacheMaxIdleDays.toDouble(),
                  min: 1,
                  max: 365,
                  divisions: 364,
                  valueLabel: (v) => '${v.round()} days',
                  onChanged: (v) => notifier.update(
                    settings.copyWith(cacheMaxIdleDays: v.round()),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<int>(
                        future: ref
                            .read(appDependenciesProvider)
                            .cacheManager
                            .currentSizeBytes(),
                        builder: (context, snapshot) {
                          final bytes = snapshot.data ?? 0;
                          final mb = bytes / (1024 * 1024);
                          return Text(
                            'Currently cached: ${mb.toStringAsFixed(1)} MB',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final deps = ref.read(appDependenciesProvider);
                        final messenger = ScaffoldMessenger.of(context);
                        final result = await deps.cacheManager.enforceLimits(
                          maxMegabytes: settings.cacheMaxMegabytes,
                          maxIdleDays: settings.cacheMaxIdleDays,
                        );
                        ref.invalidate(cacheEntriesProvider);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Removed ${result.deleted.length} files '
                              '(${(result.freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Clean now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Diagnostics ----------------------------------------------
          GandarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Engine', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                PlaybackScope(
                  builder: (context, controller) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KeyValue(
                          label: 'State',
                          value: controller.engineState.name,
                        ),
                        _KeyValue(
                          label: 'Filters',
                          value: _describeFilters(settings),
                        ),
                        if (controller.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              controller.errorMessage!,
                              style: TextStyle(color: tokens.accentAltColor),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _bandLabel(double frequency) {
    if (frequency >= 1000) {
      return '${(frequency / 1000).toStringAsFixed(0)} kHz';
    }
    return '${frequency.toStringAsFixed(0)} Hz';
  }

  static String _describeFilters(PlaybackSettings s) {
    final parts = <String>[];
    if (s.eqEnabled) parts.add('EQ');
    if (s.normalizationEnabled) {
      parts.add('Normalize (${s.normalizationLevel.name})');
    }
    if (s.monoAudio) parts.add('Mono');
    if (s.gaplessPlayback) parts.add('Gapless');
    return parts.isEmpty ? 'None' : parts.join(' · ');
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// All cached audio entries, newest first.
final cacheEntriesProvider = FutureProvider<List<CacheEntry>>(
  (ref) => ref.watch(appDependenciesProvider).cacheRepository.all(),
);
