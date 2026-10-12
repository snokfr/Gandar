import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/theme_engine.dart';
import '../../playback/export/export_cancelled.dart';
import '../../playback/export/export_job.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../player/player_surface.dart' show formatDuration;

/// Writes the mix to a file, so it can be listened to, shared or edited
/// somewhere that is not this app.
///
/// ## What it writes, and why that
///
/// A WAV. Not because it is the best format for a finished mix but because it is
/// the one this app can actually produce: the bundled libmpv has no encoder and
/// no `amix` to sum layers with (see `tool/mashup_probe.dart`), so the mix is
/// built by decoding each part to PCM and adding it up in Dart — which is a WAV
/// by the time it is finished. Any editor can turn that into an MP3, and every
/// player can play it as it is.
///
/// ## What it says when it is done
///
/// Where the file went, how long it is, and whether anything had to be clipped
/// to get there. That last one is the honest part: two layers at a high level
/// sum past full scale on purpose, and the only way to know whether to pull a
/// level down is to be told.
class MashupExportCard extends ConsumerStatefulWidget {
  const MashupExportCard({super.key});

  @override
  ConsumerState<MashupExportCard> createState() => _MashupExportCardState();
}

class _MashupExportCardState extends ConsumerState<MashupExportCard> {
  bool _running = false;
  bool _cancelRequested = false;
  ExportProgress? _progress;
  ExportOutcome? _outcome;
  String? _error;

  Future<void> _export() async {
    final controller = ref.read(mashupControllerProvider);
    final arrangement = controller.arrangement;
    if (arrangement.isEmpty) return;

    // Held before the prompt: after an await the context may be gone, and a
    // message about a file that really was written is worth more than a clean
    // lint.
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptForName(
      context,
      title: 'Export this mashup',
      action: 'Export',
      hint: 'Late night blend',
      initial: controller.savedName ?? 'Mashup',
    );
    if (name == null) return;

    setState(() {
      _running = true;
      _cancelRequested = false;
      _progress = null;
      _outcome = null;
      _error = null;
    });

    try {
      final export = ref.read(mashupExportProvider);
      final outcome = await export(
        mashup: arrangement,
        name: name,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = null;
        _outcome = outcome;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Wrote “$name” — ${formatDuration(outcome.duration)} of audio.',
          ),
        ),
      );
    } on ExportCancelled {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = null;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('The export was cancelled.')),
      );
    } catch (e) {
      AppLogger.instance.warn('mashup', 'could not export the mix', error: e);
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = null;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final controller = ref.watch(mashupControllerProvider);
    final hasParts = !controller.arrangement.isEmpty;
    final outcome = _outcome;

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.save_alt_outlined),
              const SizedBox(width: 8),
              Text('Export', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_running)
                Text('Working…', style: theme.textTheme.bodySmall)
              else if (outcome != null)
                Text(
                  formatDuration(outcome.duration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.accentColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Writes the mix to a 16-bit WAV: every layer at its own entry '
            'point and level, summed the same way they are played. It lands in '
            'the app’s exports folder, and any editor can turn it into MP3 or '
            'whatever else you want.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),

          if (_running) ...[
            LinearProgressIndicator(
              value: _progress?.fraction,
              minHeight: 6,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _progress == null
                        ? 'Starting…'
                        : '${_progress!.stage} — part '
                              '${_progress!.partIndex} of '
                              '${_progress!.partCount}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                  ),
                ),
                TextButton(
                  onPressed: _cancelRequested
                      ? null
                      : () => setState(() => _cancelRequested = true),
                  child: Text(_cancelRequested ? 'Stopping…' : 'Cancel'),
                ),
              ],
            ),
          ] else
            FilledButton.icon(
              onPressed: hasParts ? _export : null,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export the mix'),
            ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              'Could not export: $_error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.accentAltColor,
              ),
            ),
          ],

          if (outcome != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Exported', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            SelectableText(outcome.path, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  '${formatDuration(outcome.duration)} · '
                  '${(outcome.sampleRate / 1000).toStringAsFixed(1)} kHz · '
                  '${outcome.channels == 1 ? 'mono' : 'stereo'} · 16-bit',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Peak ${outcome.peak.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (outcome.clipped) ...[
              const SizedBox(height: 6),
              Text(
                '${outcome.clippedSamples} samples ran past full level and '
                'were clipped — lower a level and export again to keep them.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.accentAltColor,
                ),
              ),
            ],
            for (final warning in outcome.warnings) ...[
              const SizedBox(height: 4),
              Text(warning, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _reveal(outcome.path),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Show in folder'),
            ),
          ],
        ],
      ),
    );
  }

  /// Opens the folder the file is in, with the file selected where the platform
  /// can do that. Best effort: failing to open a window is not worth an error
  /// message, since the path is on screen and selectable right above.
  Future<void> _reveal(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', <String>['/select,$path']);
      } else if (Platform.isMacOS) {
        await Process.run('open', <String>['-R', path]);
      } else {
        await Process.run('xdg-open', <String>[File(path).parent.path]);
      }
    } catch (e) {
      AppLogger.instance.warn('mashup', 'could not open the exports folder', error: e);
    }
  }
}
