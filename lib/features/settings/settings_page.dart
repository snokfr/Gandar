import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';

import '../../core/settings/eq_presets.dart';
import '../../core/settings/playback_settings.dart';
import '../../core/theme/theme_engine.dart';
import '../../domain/models/cache_entry.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../player/player_surface.dart';
import 'savings_card.dart';

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
            title: 'Music',
            subtitle: 'Where your songs and playlists come from',
          ),
          const SizedBox(height: 16),
          const _MusicSourceCard(),
          const SizedBox(height: 28),

          const SectionHeader(
            title: 'Savings',
            subtitle: 'What this app has saved you so far',
          ),
          const SizedBox(height: 16),
          const SavingsCard(),
          const SizedBox(height: 28),

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
          const SizedBox(height: 12),

          // ---- Logs and maintenance -------------------------------------
          const LogsCard(),
          const SizedBox(height: 24),
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

/// Log verbosity, where the log file lives, and a way to read it in-app.
class LogsCard extends ConsumerWidget {
  const LogsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logger = AppLogger.instance;
    final level = ref.watch(logLevelProvider);
    final theme = Theme.of(context);

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logs and data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            logger.fileLoggingFailed
                ? 'File logging is unavailable on this machine; recent lines '
                      'are kept in memory only.'
                : 'Every startup, request, playback and error is written to a '
                      'daily file in the logs folder.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LogLevel>(
            initialValue: level,
            decoration: const InputDecoration(labelText: 'Log level'),
            items: [
              for (final value in LogLevel.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    value.name[0].toUpperCase() + value.name.substring(1),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref.read(logLevelProvider.notifier).set(value);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openLogsFolder(context, logger),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open logs folder'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showRecentLog(context, logger),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Recent log'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(likedTracksProvider);
                  ref.invalidate(cachedLikedTracksProvider);
                  ref.invalidate(playlistsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reloaded the library.')),
                  );
                },
                icon: const Icon(Icons.sync),
                label: const Text('Reload library'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens the log directory in the platform file manager.
  static Future<void> _openLogsFolder(
    BuildContext context,
    AppLogger logger,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = logger.directory;
    if (dir == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Logging has not started yet.')),
      );
      return;
    }
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [dir.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [dir.path]);
      } else {
        await Process.start('xdg-open', [dir.path]);
      }
    } catch (e) {
      logger.warn('logger', 'could not open the logs folder', error: e);
      messenger.showSnackBar(
        SnackBar(content: Text('Logs are in ${dir.path}')),
      );
    }
  }

  /// Shows the tail of the log in a dialog, plus the path to copy.
  static Future<void> _showRecentLog(
    BuildContext context,
    AppLogger logger,
  ) async {
    final lines = logger.recent(120).map((e) => e.line).join('\n');
    final path = logger.file?.path ?? '(memory only)';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recent log'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                path,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.gandarTokens.borderColor),
                    borderRadius: BorderRadius.circular(
                      context.gandarTokens.radiusSm,
                    ),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      lines.isEmpty ? 'Nothing logged yet.' : lines,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: path)),
            child: const Text('Copy path'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Says plainly where the music comes from, now that there is no account.
///
/// This occupies the place a sign-in card used to, so nobody goes looking for
/// a Spotify account the app deliberately does not have.
class _MusicSourceCard extends StatelessWidget {
  const _MusicSourceCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    return GandarCard(
      child: Row(
        children: [
          Icon(Icons.library_music_outlined, color: tokens.accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public links and exported files',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Gandar has no Spotify account to sign into. It reads public '
                  'playlist pages, and the library files you export yourself, '
                  'then keeps everything on this machine.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => context.go('/import'),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Import music'),
          ),
        ],
      ),
    );
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
