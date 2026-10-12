import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine.dart';
import '../../data/usage/app_usage.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Discord Rich Presence: what other people see next to your name.
///
/// The card is honest about two things the feature cannot hide. First, Discord
/// has to be *open and signed in* — the presence is a local conversation with
/// the desktop client, and a closed client is not an error worth a dialog
/// either, so the status line simply says so. Second, an Application ID is
/// required before any of it works, and that is a five-minute job on Discord's
/// Developer Portal rather than something this app can do for you.
class DiscordCard extends ConsumerStatefulWidget {
  const DiscordCard({super.key});

  @override
  ConsumerState<DiscordCard> createState() => _DiscordCardState();
}

class _DiscordCardState extends ConsumerState<DiscordCard> {
  late final TextEditingController _clientId;

  @override
  void initState() {
    super.initState();
    _clientId = TextEditingController(
      text: ref.read(playbackSettingsProvider).discordClientId,
    );
  }

  @override
  void dispose() {
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _saveClientId(String value) async {
    final settings = ref.read(playbackSettingsProvider);
    await ref
        .read(playbackSettingsProvider.notifier)
        .update(settings.copyWith(discordClientId: value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);
    final discord = ref.watch(discordPresenceProvider);
    final usage = ref.watch(appUsageProvider);
    final supported = Platform.isWindows;

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_esports_outlined),
              const SizedBox(width: 8),
              Text('Discord', style: theme.textTheme.titleMedium),
              const Spacer(),
              _StatusChip(state: discord, supported: supported),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Show what you are listening to on your Discord profile, with the '
            'time you have spent in Gandar.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),

          if (!supported)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Only Windows is implemented so far. Elsewhere Discord listens '
                'on a unix domain socket rather than a named pipe, which needs '
                'its own transport before this can work — the settings are '
                'here so they survive until then.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.accentAltColor,
                ),
              ),
            ),

          SettingSwitchTile(
            title: 'Show what I am playing',
            description: supported
                ? 'Updates your Discord profile while Gandar is open.'
                : 'Has no effect on this platform yet.',
            value: settings.discordEnabled,
            onChanged: (v) =>
                notifier.update(settings.copyWith(discordEnabled: v)),
          ),

          const SizedBox(height: 4),
          Text('Application ID', style: theme.textTheme.titleSmall),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _clientId,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '1558961358882607236',
                    helperText:
                        'From Discord Developer Portal → your app → General '
                        'Information. Public, not a secret.',
                    helperMaxLines: 3,
                  ),
                  onSubmitted: _saveClientId,
                  onTapOutside: (_) => _saveClientId(_clientId.text),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _saveClientId(_clientId.text),
                child: const Text('Save'),
              ),
            ],
          ),

          const SizedBox(height: 8),
          SettingSwitchTile(
            title: 'Show the song and artist',
            description:
                'Off leaves the profile saying only that you are in Gandar.',
            value: settings.discordShowTrack,
            onChanged: (v) =>
                notifier.update(settings.copyWith(discordShowTrack: v)),
          ),
          SettingSwitchTile(
            title: 'Show time in Gandar',
            description:
                'Adds how long this app has been open to the profile line.',
            value: settings.discordShowAppTime,
            onChanged: (v) =>
                notifier.update(settings.copyWith(discordShowAppTime: v)),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ---- Time in Gandar -------------------------------------------
          Text('Time in Gandar', style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            'Counted from launch, including time with nothing playing. It is '
            'writing to disk every minute, so a crash costs at most that much.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _UsageMetric(
                label: 'This session',
                value: describeShortDuration(usage.session),
              ),
              const SizedBox(width: 24),
              _UsageMetric(
                label: 'All time',
                value: describeShortDuration(usage.lifetimeIncludingSession),
              ),
            ],
          ),

          if (discord.detail != null) ...[
            const SizedBox(height: 12),
            Text(
              discord.detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSecondaryColor,
              ),
            ),
          ],

          // Most Discord problems are solved by changing something outside
          // this app — starting Discord, or starting it the same way Gandar
          // was started. The automatic retry backs off, so without this button
          // the wait after fixing it is the app's, not the user's.
          if (discord.status == DiscordStatus.failed) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(discordPresenceProvider.notifier).retry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one-word answer to "is this working", so the card does not have to be
/// read to find out.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state, required this.supported});

  final DiscordState state;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    final (label, color) = switch (state.status) {
      DiscordStatus.connected => ('Connected', tokens.accentColor),
      DiscordStatus.connecting => ('Connecting', tokens.textSecondaryColor),
      DiscordStatus.failed => ('Not connected', tokens.accentAltColor),
      DiscordStatus.needsClientId => ('No ID', tokens.accentAltColor),
      DiscordStatus.off => ('Off', tokens.textSecondaryColor),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _UsageMetric extends StatelessWidget {
  const _UsageMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: context.gandarTokens.accentColor,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
