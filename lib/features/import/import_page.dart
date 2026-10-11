import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme_engine.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Gets music into Gandar without the Spotify Web API.
///
/// Two routes, because they solve different halves of the problem:
///
/// * a **link** reads a public playlist, album or track — anyone's, no account;
/// * a **file** reads an Exportify CSV or Spotify's own `YourLibrary.json`,
///   which is the only way to get *your* liked songs out now that the Web API
///   refuses Development-mode apps whose owner has no Premium.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final TextEditingController _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Import a library file',
        type: FileType.custom,
        allowedExtensions: const ['csv', 'json', 'txt'],
      );
      if (files.isEmpty) return;
      final file = files.single;
      final bytes = await file.xFile.readAsBytes();
      if (!mounted) return;
      await _importThenFetchArtwork(
        () => ref
            .read(libraryImportProvider.notifier)
            .importFile(file.name, utf8.decode(bytes, allowMalformed: true)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open that file: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryImportProvider);
    final controller = ref.read(libraryImportProvider.notifier);
    final artwork = ref.watch(artworkEnrichmentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Import music')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(
            title: 'Bring your music in',
            subtitle:
                'No Spotify sign-in required — and no way for Spotify to block '
                'it',
          ),
          const SizedBox(height: 16),

          _Card(
            title: 'Paste a Spotify link',
            body:
                'A public playlist, album or track. Works for links other '
                'people share with you too. Spotify exposes the first 50 '
                'tracks of a playlist this way.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _link,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _run(controller),
                  decoration: const InputDecoration(
                    labelText: 'Spotify link',
                    hintText: 'https://open.spotify.com/playlist/...',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: state.busy ? null : () => _run(controller),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Import from link'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _Card(
            title: 'Import a library file',
            body:
                'Your own liked songs. Export them once from '
                'exportify.net (CSV) or Spotify\'s "Download your data" page '
                '(YourLibrary.json), then pick the file here.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: state.busy ? null : _pickFile,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Choose a CSV or JSON file'),
              ),
            ),
          ),

          const SizedBox(height: 16),
          _Card(
            title: 'Album artwork',
            body:
                'Imported tracks get their own covers, looked up one at a time '
                'from Apple\'s public catalogue at about twenty a minute — '
                'slow on purpose, so neither service throttles the app. It can '
                'be stopped and resumed at any time without losing progress.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (artwork != null && artwork.running) ...[
                  LinearProgressIndicator(value: artwork.fraction),
                  const SizedBox(height: 6),
                  Text(
                    'Fetched ${artwork.updated} of ${artwork.total} '
                    '(${artwork.done} checked, ${artwork.missing} not found)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: ref
                        .read(artworkEnrichmentProvider.notifier)
                        .stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop'),
                  ),
                ] else ...[
                  if (artwork != null)
                    Text(
                      artwork.note ??
                          'Finished: ${artwork.updated} covers added, '
                              '${artwork.missing} not found.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(artworkEnrichmentProvider.notifier).start(),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Fetch missing artwork'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),
          if (state.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (state.error != null) ...[
            _Banner(
              icon: Icons.error_outline,
              tone: Theme.of(context).colorScheme.error,
              title: 'Import failed',
              body: state.error!,
            ),
            const SizedBox(height: 12),
          ],
          if (state.outcome != null) ...[
            _Banner(
              icon: Icons.check_circle_outline,
              tone: context.gandarTokens.accentColor,
              title: state.outcome!.headline,
              body: state.outcome!.detail,
              action: state.outcome!.playlistId == null
                  ? TextButton(
                      onPressed: () => context.go('/library'),
                      child: const Text('Open library'),
                    )
                  : TextButton(
                      onPressed: () =>
                          context.go('/playlists/${state.outcome!.playlistId}'),
                      child: const Text('Open playlist'),
                    ),
            ),
          ],

          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Why this exists',
            subtitle: 'What Spotify does and does not allow',
          ),
          const SizedBox(height: 12),
          const _Card(
            title: 'The supported path is closed to most people',
            body:
                'Since February 2026 Spotify refuses every Web API request '
                'from a Development-mode app whose owner has no Premium '
                'subscription. That is what leaves the library and playlist '
                'screens empty. Everything else in Gandar — themes, playback, '
                'the cache — never needed Spotify at all.',
          ),
          const SizedBox(height: 12),
          const _Card(
            title: 'What Gandar reads, and how',
            body:
                'Link imports read the same public page Spotify\'s own embed '
                'player uses, so they need no account — and they only ever '
                'see what any browser can see. Your liked songs are account '
                'data, never public, so they can only come from a file you '
                'export yourself. Imported playlists are stored locally and '
                'stay available offline.',
          ),
        ],
      ),
    );
  }

  void _run(LibraryImportController controller) {
    FocusScope.of(context).unfocus();
    final text = _link.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a Spotify link first.')),
      );
      return;
    }
    _importThenFetchArtwork(() => controller.importLink(text));
  }

  /// Runs an import, then starts the slow, throttled artwork pass behind it.
  ///
  /// Artwork is decoration: the import is reported as soon as the tracks are
  /// stored, and the covers arrive afterwards without holding anything up.
  Future<void> _importThenFetchArtwork(Future<void> Function() import) async {
    await import();
    if (!mounted) return;
    if (ref.read(libraryImportProvider).outcome != null) {
      unawaited(ref.read(artworkEnrichmentProvider.notifier).start());
    }
  }
}

/// A titled block of content.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, this.child});

  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodySmall),
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
  }
}

/// A result or error strip.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gandarTokens.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(context.gandarTokens.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
                if (action != null) ...[const SizedBox(height: 4), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
