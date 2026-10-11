import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/storage/app_directory.dart';
import '../../core/theme/theme_codec.dart';
import '../../core/theme/theme_tokens.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'theme_editor.dart';

/// Select, import, export and tweak themes.
class ThemesPage extends ConsumerStatefulWidget {
  const ThemesPage({super.key});

  @override
  ConsumerState<ThemesPage> createState() => _ThemesPageState();
}

class _ThemesPageState extends ConsumerState<ThemesPage> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final controller = ref.read(themeProvider.notifier);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionHeader(
            title: 'Themes',
            subtitle: '${themeState.all.length} available',
            action: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _importTheme,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _exportTheme(themeState.active),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export'),
                ),
              ],
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          for (final tokens in themeState.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ThemeCard(
                tokens: tokens,
                selected: tokens.id == themeState.active.id,
                onSelect: () => controller.select(tokens),
                onDelete: themeState.custom.any((t) => t.id == tokens.id)
                    ? () => controller.removeCustom(tokens.id)
                    : null,
              ),
            ),
          const SizedBox(height: 8),
          const SectionHeader(
            title: 'Customize',
            subtitle:
                'Every colour and radius the active theme uses, live. A '
                'built-in theme is copied rather than changed.',
          ),
          const SizedBox(height: 12),
          const ThemeEditor(),
        ],
      ),
    );
  }

  /// Where an exported theme goes when the native save dialog is unavailable.
  ///
  /// Documents first, because that is where a person would look for it. If even
  /// that lookup fails — it is the same platform channel that fails for the
  /// library and imports — the app's own data directory still works.
  Future<Directory> _exportDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return AppDirectory.support();
    }
  }

  Future<void> _importTheme() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Import a Gandar theme',
        type: FileType.custom,
        allowedExtensions: const ['json', 'yaml', 'yml'],
      );
      if (files.isEmpty) return;
      final bytes = await files.single.xFile.readAsBytes();
      final tokens = ThemeCodec.decode(utf8.decode(bytes));
      await ref.read(themeProvider.notifier).importTheme(tokens);
      if (mounted) setState(() => _status = 'Imported "${tokens.name}".');
    } catch (e) {
      if (mounted) setState(() => _status = 'Import failed: $e');
    }
  }

  Future<void> _exportTheme(ThemeTokens tokens) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(ThemeCodec.toJson(tokens)));
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Export theme',
        fileName: '${tokens.id}.gandar-theme.json',
        mimeType: 'application/json',
        bytes: bytes,
      );
      if (saved == null) {
        // User cancelled; also offer a copy in the documents directory so the
        // theme is never lost if the native dialog is unavailable.
        final dir = await _exportDirectory();
        final path = '${dir.path}/${tokens.id}.gandar-theme.json';
        await File(path).writeAsBytes(bytes);
        if (mounted) setState(() => _status = 'Exported to $path');
        return;
      }
      if (mounted) {
        setState(() => _status = 'Exported theme to ${saved.toFilePath()}');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Export failed: $e');
    }
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.tokens,
    required this.selected,
    required this.onSelect,
    this.onDelete,
  });

  final ThemeTokens tokens;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GandarCard(
      child: Row(
        children: [
          _Swatches(tokens: tokens),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tokens.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${tokens.brightness.name} · radius ${tokens.radiusMd.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete theme',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          if (selected)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.check_circle),
            )
          else
            TextButton(onPressed: onSelect, child: const Text('Apply')),
        ],
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.tokens});

  final ThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final color in [
          tokens.backgroundPrimaryColor,
          tokens.backgroundSecondaryColor,
          tokens.surfaceColor,
          tokens.accentColor,
          tokens.accentAltColor,
        ])
          Container(
            width: 22,
            height: 44,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: tokens.borderColor),
            ),
          ),
      ],
    );
  }
}
