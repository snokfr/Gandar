import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine.dart';
import '../../core/theme/theme_tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// A live editor for every token a theme is made of.
///
/// Editing is immediate: each change is written through the theme provider, so
/// the whole app — including this screen — repaints with it as the picker is
/// used. That is the point of editing a theme rather than filling in a form:
/// you are looking at the thing you are changing.
///
/// Editing a built-in theme produces a *copy*, named after its base, so the
/// presets stay pristine and can be returned to. Once the copy exists, every
/// further edit changes that one, which is why the derived id is computed from
/// the base rather than from the current id — otherwise each edit would append
/// another `_custom` and the theme list would fill up with its own history.
class ThemeEditor extends ConsumerWidget {
  const ThemeEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(themeProvider.select((state) => state.active));
    final theme = Theme.of(context);

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Editing "${active.name}"',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active.isBuiltIn
                          ? 'This is a built-in preset, so your changes are '
                                'saved as a copy of it.'
                          : 'Your saved theme. Changes apply as you make them.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _saveAs(context, ref, active),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save as theme'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final key in ThemeTokens.colorKeys)
            _ColorRow(
              label: ThemeTokens.labelFor(key),
              color: active.colorFor(key) ?? Colors.transparent,
              onPick: (value) =>
                  _apply(ref, active, active.withColor(key, value)),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('Shape', style: theme.textTheme.titleSmall),
          SettingSliderTile(
            title: 'Small radius',
            description: 'Chips, artwork, small controls.',
            value: active.radiusSm,
            min: 0,
            max: 24,
            divisions: 24,
            valueLabel: (v) => v.toStringAsFixed(0),
            onChanged: (v) => _apply(ref, active, active.copyWith(radiusSm: v)),
          ),
          SettingSliderTile(
            title: 'Medium radius',
            description: 'Cards and panels.',
            value: active.radiusMd,
            min: 0,
            max: 32,
            divisions: 32,
            valueLabel: (v) => v.toStringAsFixed(0),
            onChanged: (v) => _apply(ref, active, active.copyWith(radiusMd: v)),
          ),
          SettingSliderTile(
            title: 'Large radius',
            description: 'Sheets and overlays.',
            value: active.radiusLg,
            min: 0,
            max: 48,
            divisions: 48,
            valueLabel: (v) => v.toStringAsFixed(0),
            onChanged: (v) => _apply(ref, active, active.copyWith(radiusLg: v)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Text colours drive contrast; brightness tells the app which '
                  'way a very dark or very light accent has to be adjusted to '
                  'stay readable.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<Brightness>(
                segments: const [
                  ButtonSegment(
                    value: Brightness.dark,
                    label: Text('Dark'),
                  ),
                  ButtonSegment(
                    value: Brightness.light,
                    label: Text('Light'),
                  ),
                ],
                selected: {active.brightness},
                onSelectionChanged: (selection) => _apply(
                  ref,
                  active,
                  active.copyWith(brightness: selection.first),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Writes [next] into the theme store, deriving a stable copy identity.
  static void _apply(WidgetRef ref, ThemeTokens current, ThemeTokens next) {
    final builtIn = current.isBuiltIn;
    ref
        .read(themeProvider.notifier)
        .importTheme(
          next.copyWith(
            id: builtIn ? '${current.id}_custom' : current.id,
            name: builtIn ? '${current.name} (custom)' : current.name,
          ),
        );
  }

  /// Saves the current look under a name of its own.
  static Future<void> _saveAs(
    BuildContext context,
    WidgetRef ref,
    ThemeTokens active,
  ) async {
    final name = await promptForName(
      context,
      title: 'Save this theme',
      action: 'Save',
      initial: active.isBuiltIn ? '${active.name} (custom)' : active.name,
      hint: 'Late night green',
    );
    if (name == null || !context.mounted) return;

    // A fresh id each time: saving twice under different names should produce
    // two themes, not one theme whose name keeps changing.
    final saved = active.copyWith(
      id: 'theme-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    await ref.read(themeProvider.notifier).importTheme(saved);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "$name".')),
    );
  }
}

/// One colour: a label, a live swatch and the value in hex.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onPick,
  });

  final String label;
  final Color color;
  final ValueChanged<int> onPick;

  /// `#RRGGBB`, the form people paste from anywhere else.
  static String hexOf(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(context.gandarTokens.radiusSm),
      onTap: () async {
        final picked = await showColorPicker(
          context,
          title: label,
          initial: color,
        );
        if (picked != null) onPick(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(
                  context.gandarTokens.radiusSm,
                ),
                border: Border.all(color: context.gandarTokens.borderColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              hexOf(color),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.colorize_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Asks for a colour, live. Returns null when cancelled.
Future<int?> showColorPicker(
  BuildContext context, {
  required String title,
  required Color initial,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _ColorPickerDialog(title: title, initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late int _value;
  late final TextEditingController _hex;

  /// Swatches worth one tap. Not a full palette: these are the colours that
  /// suit a dark music player, which is what this editor is for.
  static const List<int> _swatches = <int>[
    0xFF000000, 0xFF121212, 0xFF181818, 0xFF282828, 0xFF3C3C3C,
    0xFFFFFFFF, 0xFFF3E9DE, 0xFFB3B3B3, 0xFF8A8A8A, 0xFF5A5A5A,
    0xFF1DB954, 0xFF1ED760, 0xFF14B8A6, 0xFF2D7FF9, 0xFF7C4DFF,
    0xFFC8763C, 0xFF8C4A2F, 0xFFE5484D, 0xFFF2B705, 0xFFB9A38E,
  ];

  @override
  void initState() {
    super.initState();
    _value = widget.initial.toARGB32();
    _hex = TextEditingController(text: _ColorRow.hexOf(widget.initial));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(int argb, {bool syncHex = true}) {
    setState(() {
      _value = (0xFF000000 | (argb & 0xFFFFFF));
      if (syncHex) _hex.text = _ColorRow.hexOf(Color(_value));
    });
  }

  /// Accepts `#RRGGBB`, `RRGGBB`, `#AARRGGBB` or `0x…`.
  void _setFromHex(String text) {
    var raw = text.trim();
    if (raw.startsWith('#')) raw = raw.substring(1);
    if (raw.toLowerCase().startsWith('0x')) raw = raw.substring(2);
    if (raw.length == 6 || raw.length == 8) {
      final parsed = int.tryParse(raw, radix: 16);
      if (parsed != null) _set(parsed, syncHex: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(_value);
    final swatchBorder = Theme.of(context).dividerColor;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: swatchBorder),
              ),
              alignment: Alignment.center,
              child: Text(
                _ColorRow.hexOf(color),
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final swatch in _swatches)
                  GestureDetector(
                    onTap: () => _set(swatch),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(swatch),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (_value & 0xFFFFFF) == (swatch & 0xFFFFFF)
                              ? Theme.of(context).colorScheme.primary
                              : swatchBorder,
                          width: (_value & 0xFFFFFF) == (swatch & 0xFFFFFF)
                              ? 2
                              : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(
                labelText: 'Hex',
                prefixIcon: Icon(Icons.tag),
              ),
              onSubmitted: _setFromHex,
              onChanged: _setFromHex,
            ),
            _ChannelSlider(
              label: 'Red',
              value: (color.r * 255).round(),
              onChanged: (v) => _set(
                Color.fromARGB(255, v, (color.g * 255).round(), (color.b * 255).round())
                    .toARGB32(),
              ),
            ),
            _ChannelSlider(
              label: 'Green',
              value: (color.g * 255).round(),
              onChanged: (v) => _set(
                Color.fromARGB(255, (color.r * 255).round(), v, (color.b * 255).round())
                    .toARGB32(),
              ),
            ),
            _ChannelSlider(
              label: 'Blue',
              value: (color.b * 255).round(),
              onChanged: (v) => _set(
                Color.fromARGB(255, (color.r * 255).round(), (color.g * 255).round(), v)
                    .toARGB32(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('Use this colour'),
        ),
      ],
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble().clamp(0, 255),
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
