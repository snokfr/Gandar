import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/eq_presets.dart';
import '../../core/settings/playback_settings.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'eq_graph.dart';

/// The equalizer, as a shape you drag plus the presets you keep.
class EqualizerCard extends ConsumerWidget {
  const EqualizerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);
    final theme = Theme.of(context);

    final custom = settings.customEqPresets;
    final selectedCustom = _customById(custom, settings.eqPreset);

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingSwitchTile(
            title: 'Equalizer',
            description: 'Shape the sound with a 10-band equalizer and presets.',
            value: settings.eqEnabled,
            onChanged: (value) =>
                notifier.update(settings.copyWith(eqEnabled: value)),
          ),
          if (settings.eqEnabled) ...[
            const SizedBox(height: 12),
            EqGraph(
              bands: settings.eqBands,
              // Any drag is a departure from the named preset, so the preset
              // becomes "custom" the moment the curve changes.
              onChanged: (bands) => notifier.update(
                settings.copyWith(eqPreset: 'custom', eqBands: bands),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _presetIds(
                      settings,
                    ).contains(settings.eqPreset)
                        ? settings.eqPreset
                        : 'custom',
                    decoration: const InputDecoration(labelText: 'Preset'),
                    items: [
                      for (final preset in EqPresets.all)
                        DropdownMenuItem(
                          value: preset.id,
                          child: Text(preset.label),
                        ),
                      for (final preset in custom)
                        DropdownMenuItem(
                          value: preset.id,
                          child: Text('${preset.name} (yours)'),
                        ),
                      if (!_hasBuiltIn('custom'))
                        const DropdownMenuItem(
                          value: 'custom',
                          child: Text('Custom'),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      final builtIn = EqPresets.byId(id);
                      if (builtIn != null) {
                        notifier.update(
                          settings.copyWith(
                            eqPreset: id,
                            eqBands: builtIn.apply(),
                          ),
                        );
                        return;
                      }
                      final mine = _customById(custom, id);
                      if (mine == null) return;
                      notifier.update(
                        settings.copyWith(
                          eqPreset: id,
                          eqBands: _applyGains(settings.eqBands, mine.gains),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Reset to flat',
                  onPressed: () => notifier.update(
                    settings.copyWith(
                      eqPreset: 'flat',
                      eqBands: const EqPreset('flat', 'Flat', <double>[
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                      ]).apply(),
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _savePreset(
                    context,
                    ref,
                    settings: settings,
                    suggestedName:
                        selectedCustom?.name ??
                        _currentPresetLabel(settings),
                  ),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save as preset'),
                ),
                if (selectedCustom != null)
                  OutlinedButton.icon(
                    onPressed: () => _deletePreset(
                      context,
                      ref,
                      settings: settings,
                      preset: selectedCustom,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Delete "${selectedCustom.name}"'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selectedCustom != null
                  ? 'Saved on this device. The curve above is "${selectedCustom.name}".'
                  : 'Drag the curve to shape the sound. The change reaches the '
                        'audio engine when you let go.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Every id the dropdown can show, so it never receives an unknown value.
  static List<String> _presetIds(PlaybackSettings settings) => <String>[
    for (final preset in EqPresets.all) preset.id,
    for (final preset in settings.customEqPresets) preset.id,
    'custom',
  ];

  static bool _hasBuiltIn(String id) => EqPresets.byId(id) != null;

  static CustomEqPreset? _customById(List<CustomEqPreset> presets, String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// The name shown in the save dialog for the curve currently on screen.
  static String _currentPresetLabel(PlaybackSettings settings) =>
      EqPresets.byId(settings.eqPreset)?.label ?? 'My preset';

  static List<EqBand> _applyGains(List<EqBand> bands, List<double> gains) =>
      <EqBand>[
        for (var i = 0; i < bands.length; i++)
          bands[i].copyWith(gain: i < gains.length ? gains[i] : 0.0),
      ];
}

/// Saves the current curve under a name, replacing a preset of the same name.
Future<void> _savePreset(
  BuildContext context,
  WidgetRef ref, {
  required PlaybackSettings settings,
  required String suggestedName,
}) async {
  final name = await promptForName(
    context,
    title: 'Save equalizer preset',
    action: 'Save',
    initial: suggestedName,
    hint: 'Bass for the car',
  );
  if (name == null) return;

  final notifier = ref.read(playbackSettingsProvider.notifier);
  final existing = settings.customEqPresets
      .where((p) => p.name.toLowerCase() == name.toLowerCase())
      .firstOrNull;
  final id =
      existing?.id ??
      'custom-${DateTime.now().microsecondsSinceEpoch}';
  final preset = CustomEqPreset(
    id: id,
    name: name,
    gains: <double>[for (final band in settings.eqBands) band.gain],
  );

  final next = <CustomEqPreset>[
    ...settings.customEqPresets.where((p) => p.id != id),
    preset,
  ];
  await notifier.update(
    settings.copyWith(customEqPresets: next, eqPreset: id),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        existing == null
            ? 'Saved "$name".'
            : 'Updated "$name".',
      ),
    ),
  );
}

/// Removes a saved preset, leaving the curve where it is.
Future<void> _deletePreset(
  BuildContext context,
  WidgetRef ref, {
  required PlaybackSettings settings,
  required CustomEqPreset preset,
}) async {
  final notifier = ref.read(playbackSettingsProvider.notifier);
  // The curve stays; only the name for it goes. Snapping the sound back to flat
  // because a preset was deleted would be a surprising thing to hear.
  await notifier.update(
    settings.copyWith(
      customEqPresets: settings.customEqPresets
          .where((p) => p.id != preset.id)
          .toList(growable: false),
      eqPreset: 'custom',
    ),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Deleted "${preset.name}".')),
  );
}
