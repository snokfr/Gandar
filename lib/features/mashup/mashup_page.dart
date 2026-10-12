import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/theme_engine.dart';
import '../../domain/models/mashup.dart';
import '../../playback/mix/mashup_mixer.dart';
import '../../state/mashup_controller.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/track_picker.dart';
import '../player/player_surface.dart' show formatDuration;
import 'mashup_export_card.dart';
import 'mashup_words.dart';

/// Builds and plays a real mashup: two or more records layered, each trimmed to
/// the part you want, each entering where you say, each at its own level.
///
/// ## How the sound is made
///
/// One player per part, all running at once. A single mpv cannot layer two
/// sources — the libavfilter in this build has no `amix`, `atrim`, `adelay` or
/// `acrossfade` (which is also why loudness normalization is unavailable) — so
/// each part gets its own player, its own trim (mpv's `end` option, which stops
/// the part where you told it to) and its own level, and the operating system's
/// audio mixer sums them. That is exactly how a live mashup is performed, and
/// `tool/mashup_probe.dart` is the measurement that established it.
///
/// ## Where the state lives
///
/// Not here. The arrangement and the players belong to [MashupController], so
/// leaving this tab to look something up neither stops the mix nor throws the
/// arrangement away, and coming back shows the same mix in the same place. This
/// screen is a view of that controller and holds nothing a navigation should
/// not destroy.
///
/// What that means in practice, said plainly on the screen as well: layers play
/// together and each one's start, end, entry and level are yours to set, but
/// this is not beat-matched — two independent players are not locked to a beat
/// grid, and claiming otherwise would be a lie.
class MashupPage extends ConsumerWidget {
  const MashupPage({super.key});

  /// Stops the queue, then plays the mix.
  ///
  /// Two things playing at once would be a mess nobody asked for, and the
  /// player bar below would be describing a track that is not what you can
  /// hear.
  static Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    MashupController controller,
  ) async {
    if (controller.isEmpty) return;
    final playback = ref.read(playbackControllerProvider);
    if (playback.isPlaying) await playback.togglePlayPause();
    await controller.play();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.watch(mashupControllerProvider);

    return Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final arrangement = controller.arrangement;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: SectionHeader(
                    title: controller.savedName == null
                        ? 'Mashup'
                        : 'Mashup · ${controller.savedName}',
                    subtitle: arrangement.isEmpty
                        ? 'Layer songs into one mix'
                        : _subtitle(arrangement),
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => showTrackPicker(
                            context,
                            title: 'Add to the mashup',
                            alreadyPicked: <String>{
                              for (final part in arrangement.parts)
                                part.track.id,
                            },
                            onPick: controller.add,
                          ),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Add songs'),
                        ),
                        if (arrangement.parts.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _saveAsMashup(context, ref, controller),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Clear the mix',
                            onPressed: () =>
                                _clear(context, controller),
                            icon: const Icon(Icons.delete_sweep_outlined),
                          ),
                        ],
                        if (arrangement.parts.length >= 2) ...[
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _saveAsPlaylist(context, ref, controller),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text('Save songs'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Every song below runs its own player, so the layers really '
                    'do play at the same time. Set where each one starts and '
                    'ends in its own recording, where it enters the mix, and how '
                    'loud it sits, then listen and move around: the timeline '
                    'takes you to any moment of the mix. When it sounds right, '
                    'export writes it to an audio file you can keep. Nothing '
                    'here is beat-matched — you place the parts, the players '
                    'follow.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
              if (arrangement.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                      icon: Icons.motion_photos_on_outlined,
                      title: 'Nothing to mix yet',
                      message:
                          'Add two songs. Trim each one to the part you want, '
                          'decide where it comes in, and blend them with the '
                          'amount of overlap you like.',
                      action: FilledButton.icon(
                        onPressed: () => showTrackPicker(
                          context,
                          title: 'Add to the mashup',
                          alreadyPicked: const <String>{},
                          onPick: controller.add,
                        ),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Add songs'),
                      ),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: _TransportCard(
                      controller: controller,
                      onPlay: () => _start(context, ref, controller),
                      onStop: controller.stop,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _BlendCard(controller: controller),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _TimelineCard(
                      controller: controller,
                      mix: arrangement,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: controller.position,
                      builder: (context, position, _) => MashupWordsCard(
                        mashup: arrangement,
                        playingIndex: _partAt(arrangement, position),
                        onJump: controller.jumpIntoPart,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: SectionHeader(
                      title: 'The songs',
                      subtitle: 'Trim each one, place it, then jump to it',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.builder(
                    itemCount: arrangement.parts.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PartCard(
                        index: index,
                        mix: arrangement,
                        part: arrangement.parts[index],
                        open: controller.editing == index,
                        onToggle: () => controller.openPart(
                          controller.editing == index ? null : index,
                        ),
                        onChanged: (part) =>
                            controller.replaceAt(index, part),
                        onJump: () => controller.jumpToPart(index),
                        onMoveUp: index == 0
                            ? null
                            : () => controller.move(index, -1),
                        onMoveDown: index == arrangement.parts.length - 1
                            ? null
                            : () => controller.move(index, 1),
                        onRemove: () => controller.removeAt(index),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
              // The two cards that are always here, empty mix or not. An empty
              // mix is exactly when opening a saved one is what you came to do,
              // a list that only appears once you have built something is a
              // list you cannot use to get back what you built — and the export
              // card has to be reachable in the same place whether or not there
              // is anything in the mix, so it is never the reason a layout
              // moved under someone’s finger.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _SavedMashupsCard(controller: controller),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: const MashupExportCard(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  /// The part the playhead is inside, or null between parts.
  static int? _partAt(Mashup mix, Duration position) {
    for (var i = 0; i < mix.parts.length; i++) {
      if (mix.parts[i].positionInSource(position) != null) return i;
    }
    return null;
  }

  static String _subtitle(Mashup mix) {
    final parts = mix.parts.length;
    final overlaps = <int>[
      for (var i = 1; i < mix.parts.length; i++)
        if (mix.overlapBefore(i) > Duration.zero) i,
    ].length;
    return '$parts song${parts == 1 ? '' : 's'} · '
        '${formatDuration(mix.duration)} mix'
        '${overlaps > 0 ? ' · $overlaps overlap${overlaps == 1 ? '' : 's'}' : ''}';
  }

  // ---- Actions -----------------------------------------------------------

  /// Writes the arrangement to a mashup file, so it can be reopened and edited.
  ///
  /// This is the difference between a mix and a playlist: the file keeps the
  /// slices, the entry points and the levels, which is everything that took
  /// time to get right.
  static Future<void> _saveAsMashup(
    BuildContext context,
    WidgetRef ref,
    MashupController controller,
  ) async {
    // Held before the prompt: after an await the context may be gone, and a
    // message about a save that did happen is worth more than a clean lint.
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptForName(
      context,
      title: 'Save this mashup',
      action: 'Save',
      hint: 'Late night blend',
      initial: controller.savedName ?? '',
    );
    if (name == null) return;
    try {
      final saved = await controller.saveAs(name);

      ref.invalidate(savedMashupsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Saved “${saved.name}” — ${saved.partCount} '
            'song${saved.partCount == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (e) {
      AppLogger.instance.warn('mashup', 'could not save the mashup', error: e);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  /// Saves the songs as a playlist, so they can be played on their own later.
  ///
  /// The slices and levels are not saved here: a playlist is a list of songs,
  /// and inventing a file format to smuggle the arrangement into it would be a
  /// promise the rest of the app cannot keep. That is what "Save" above is for.
  static Future<void> _saveAsPlaylist(
    BuildContext context,
    WidgetRef ref,
    MashupController controller,
  ) async {
    final repository = ref.read(appDependenciesProvider).libraryRepository;
    final messenger = ScaffoldMessenger.of(context);
    final name = await promptForName(
      context,
      title: 'Save these songs',
      action: 'Save',
      hint: 'Late night blend',
    );
    if (name == null) return;

    try {
      final playlist = await repository.createPlaylist(name);
      for (final part in controller.arrangement.parts) {
        await repository.addTrackToPlaylist(playlist.id, part.track.id);
      }
      ref.invalidate(playlistsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved “$name” as a playlist.'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => context.go('/playlists/${playlist.id}'),
          ),
        ),
      );
    } catch (e) {
      AppLogger.instance.warn('mashup', 'could not save the playlist', error: e);
      messenger.showSnackBar(SnackBar(content: Text('Could not save that: $e')));
    }
  }

  static Future<void> _clear(
    BuildContext context,
    MashupController controller,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Clear the mix?',
      message:
          'The songs and every slice, entry and level go back to nothing. A '
          'mix you have saved as a mashup file is not affected.',
      action: 'Clear',
    );
    if (!confirmed) return;
    await controller.clear();
  }
}

/// Asks a yes/no question in a dialog. Returns false when dismissed.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// The transport: what the mix is doing, where it is, and how to move it.
class _TransportCard extends StatelessWidget {
  const _TransportCard({
    required this.controller,
    required this.onPlay,
    required this.onStop,
  });

  final MashupController controller;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  /// How far the seek buttons move the mix. Long enough to cross a blend, short
  /// enough to land inside the part you were listening to.
  static const Duration step = Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final playing = controller.isPlaying;
    final busy = controller.isPreparing;

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : (playing ? onStop : onPlay),
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                label: Text(playing ? 'Stop the mix' : 'Play the mix'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: controller.position,
                  builder: (context, position, _) => Text(
                    '${formatDuration(position)} / '
                    '${formatDuration(controller.duration)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (busy)
                Text('Preparing…', style: theme.textTheme.bodySmall)
              else if (controller.isRunning)
                Text(
                  controller.mixState == MixerState.paused ? 'Paused' : 'Mixing',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.accentColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: 'Back to the start',
                onPressed: () => controller.seekTo(Duration.zero),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'Back 10 seconds',
                onPressed: () =>
                    controller.seekTo(controller.positionNow - step),
                icon: const Icon(Icons.replay_10),
              ),
              IconButton(
                tooltip: 'Pause',
                onPressed: controller.pause,
                icon: const Icon(Icons.pause),
              ),
              IconButton(
                tooltip: 'Forward 10 seconds',
                onPressed: () =>
                    controller.seekTo(controller.positionNow + step),
                icon: const Icon(Icons.forward_10),
              ),
              IconButton(
                tooltip: 'To the end',
                onPressed: () =>
                    controller.seekTo(controller.duration),
                icon: const Icon(Icons.last_page),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Move the mix with the timeline below, or these buttons.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < controller.layers.length; i++)
                _LayerChip(index: i, layer: controller.layers[i]),
            ],
          ),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              controller.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One part's state, so a silent layer is visibly silent rather than a mystery.
class _LayerChip extends StatelessWidget {
  const _LayerChip({required this.index, required this.layer});

  final int index;
  final MashupLayer layer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final (label, color) = switch (layer.state) {
      LayerState.playing => ('playing', tokens.accentColor),
      LayerState.waiting => ('waiting', tokens.textSecondaryColor),
      LayerState.done => ('done', tokens.textSecondaryColor),
      LayerState.failed => ('failed', theme.colorScheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderColor),
      ),
      child: Text(
        '${index + 1} · $label',
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// The blend, and what it did to the arrangement.
class _BlendCard extends ConsumerWidget {
  const _BlendCard({required this.controller});

  final MashupController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mix = controller.arrangement;
    final seams = <int>[
      for (var i = 1; i < mix.parts.length; i++)
        if (mix.overlapBefore(i) > Duration.zero) i,
    ].length;

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingSliderTile(
            title: 'Blend',
            description:
                'How far each song overlaps the one before it. This places '
                'every part; moving one by hand below is kept until you touch '
                'this again.',
            value: mix.blend.inMilliseconds / 1000,
            min: 0,
            max: Mashup.maxBlend.inSeconds.toDouble(),
            divisions: Mashup.maxBlend.inSeconds * 2,
            valueLabel: (v) => v <= 0 ? 'None' : '${v.toStringAsFixed(1)} s',
            onChanged: (v) => controller.setBlend(
              Duration(milliseconds: (v * 1000).round()),
            ),
          ),
          Text(
            seams > 0
                ? '$seams seam${seams == 1 ? '' : 's'} where two songs sound '
                      'together.'
                : 'Nothing overlaps, so this plays as a plain sequence. Raise '
                      'the blend to mash them.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The arrangement drawn to scale, and the surface you move the mix with.
///
/// The whole card is a scrub bar: a press anywhere moves the mix there, and
/// dragging keeps moving it. Parts are drawn but are not buttons — the list
/// below is where a part is opened for editing — so there is no gesture here
/// fighting with the one that moves the playhead.
class _TimelineCard extends StatefulWidget {
  const _TimelineCard({required this.controller, required this.mix});

  final MashupController controller;
  final Mashup mix;

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

/// Key on the surface that moves the mix, so tests can press it directly.
const Key timelineKey = ValueKey<String>('mashup-timeline');

class _TimelineCardState extends State<_TimelineCard> {
  /// Where the finger is while dragging, so the playhead follows it even
  /// though each seek is an asynchronous round trip to the players.
  Duration? _dragging;

  Duration _at(double dx, double width) {
    final total = widget.mix.duration.inMilliseconds;
    if (total <= 0 || width <= 0) return Duration.zero;
    final fraction = (dx / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (total * fraction).round());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mix = widget.mix;

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The mix', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          ValueListenableBuilder<Duration>(
            valueListenable: widget.controller.position,
            builder: (context, position, _) => LayoutBuilder(
              builder: (context, constraints) => Listener(
                // Named so a test can aim at the scrub surface itself rather
                // than at whichever `Listener` happens to be found first.
                key: timelineKey,
                // A raw pointer listener rather than a gesture detector: this
                // has to see every press and drag without taking part in the
                // gesture arena, so nothing inside the timeline can win the
                // press and leave the mix where it was.
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  final at = _at(event.localPosition.dx, constraints.maxWidth);
                  setState(() => _dragging = at);
                  widget.controller.seekTo(at);
                },
                onPointerMove: (event) {
                  final at = _at(event.localPosition.dx, constraints.maxWidth);
                  setState(() => _dragging = at);
                  widget.controller.seekTo(at);
                },
                onPointerUp: (_) => setState(() => _dragging = null),
                onPointerCancel: (_) => setState(() => _dragging = null),
                child: _Timeline(
                  mix: mix,
                  position: _dragging ?? position,
                  dragging: _dragging != null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Press or drag anywhere on the bars to move the mix. '
                  'Tap a song below to open its controls.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (widget.controller.isStale)
                Text(
                  'Changed since it was loaded — playing will reload it.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The bars, the playhead and the time ruler.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.mix,
    required this.position,
    required this.dragging,
  });

  final Mashup mix;
  final Duration position;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final total = mix.duration.inMilliseconds > 0
        ? mix.duration.inMilliseconds
        : 1;
    final progress = (position.inMilliseconds / total).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const rowHeight = 26.0;
        final rowsHeight = rowHeight * mix.parts.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: rowsHeight,
              child: Stack(
                children: [
                  for (var i = 0; i < mix.parts.length; i++)
                    Positioned(
                      top: i * rowHeight,
                      left: 0,
                      right: 0,
                      height: rowHeight,
                      child: _TimelineRow(
                        index: i,
                        part: mix.parts[i],
                        totalMs: total,
                        width: width,
                        secondsBefore: mix.overlapSecondsBefore(i),
                      ),
                    ),
                  // The playhead, over every row, so the eye can see which
                  // parts are sounding at this moment. It is wider and brighter
                  // while dragging, because then it is the thing being moved.
                  Positioned(
                    left: (progress * width).clamp(0.0, width - (dragging ? 3 : 2)),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: dragging ? 3 : 2,
                      color: dragging
                          ? tokens.accentColor
                          : tokens.textPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                for (final fraction in const <double>[0, 0.25, 0.5, 0.75, 1])
                  Expanded(
                    child: Text(
                      fraction == 0
                          ? '0:00'
                          : formatDuration(
                              Duration(
                                milliseconds: (total * fraction).round(),
                              ),
                            ),
                      textAlign: fraction == 0
                          ? TextAlign.left
                          : (fraction == 1
                                ? TextAlign.right
                                : TextAlign.center),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.index,
    required this.part,
    required this.totalMs,
    required this.width,
    required this.secondsBefore,
  });

  final int index;
  final MashupPart part;
  final int totalMs;
  final double width;
  final double secondsBefore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final left = (part.offset.inMilliseconds / totalMs * width).clamp(
      0.0,
      width,
    );
    final length = part.length.inMilliseconds <= 0
        // A part of unknown length has nothing to draw but its entry point; a
        // sliver at least shows where it comes in.
        ? 3.0
        : (part.length.inMilliseconds / totalMs * width).clamp(
            2.0,
            width - left,
          );
    final overlapWidth = (secondsBefore * 1000 / totalMs * width).clamp(
      0.0,
      length,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Stack(
        children: [
          Positioned(
            left: left,
            width: length,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.accentColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: tokens.borderColor),
              ),
            ),
          ),
          if (overlapWidth > 0)
            Positioned(
              left: left,
              width: overlapWidth,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.accentColor.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(6),
                  ),
                ),
              ),
            ),
          Positioned(
            left: left + 6,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${index + 1}. ${part.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The mashups saved as files: open one to carry on editing it.
class _SavedMashupsCard extends ConsumerWidget {
  const _SavedMashupsCard({required this.controller});

  final MashupController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final saved = ref.watch(savedMashupsProvider);

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saved mashups', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A mashup file keeps the slices, the entry points and the levels, '
            'so a mix can be reopened and worked on again.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          saved.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (error, _) => Text(
              'Could not read the saved mashups: $error',
              style: theme.textTheme.bodySmall,
            ),
            data: (list) {
              if (list.isEmpty) {
                return Text(
                  'None saved yet. "Save" above writes this arrangement to a '
                  'mashup file.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondaryColor,
                  ),
                );
              }
              return Column(
                children: [
                  for (final mashup in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.queue_music),
                      title: Text(mashup.name),
                      subtitle: Text(
                        '${mashup.summary} · saved ${_when(mashup.savedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () async {
                              await controller.open(mashup);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Opened “${mashup.name}”. Press play to '
                                    'load it.',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Open'),
                          ),
                          IconButton(
                            tooltip: 'Delete this mashup file',
                            onPressed: () async {
                              final confirmed = await _confirm(
                                context,
                                title: 'Delete “${mashup.name}”?',
                                message:
                                    'The mashup file is deleted. This cannot be '
                                    'undone.',
                                action: 'Delete',
                              );
                              if (!confirmed) return;
                              await controller.deleteSaved(mashup.name);
                              ref.invalidate(savedMashupsProvider);
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// A short, unambiguous date. Absolute rather than "3 minutes ago": a list of
  /// mixes is something you come back to days later.
  static String _when(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// One part: what it is, and everything you can do to it.
class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.index,
    required this.mix,
    required this.part,
    required this.open,
    required this.onToggle,
    required this.onChanged,
    required this.onJump,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final int index;
  final Mashup mix;
  final MashupPart part;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<MashupPart> onChanged;

  /// Moves the mix to where this part enters it.
  final VoidCallback onJump;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final overlapBeforeSeconds = mix.overlapSecondsBefore(index);

    return GandarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${index + 1}', style: theme.textTheme.bodySmall),
                ),
                AlbumArt(url: part.track.artworkUrl, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        _summary(overlapBeforeSeconds),
                        maxLines: 2,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Move up',
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'Move down',
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: 'Remove from the mix',
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  color: tokens.textSecondaryColor,
                ),
              ],
            ),
          ),
          if (open) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Part of “${part.title}”',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onJump,
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Jump here'),
                ),
              ],
            ),
            _SliceSliders(part: part, onChanged: onChanged),
            SettingSliderTile(
              title: 'Enters the mix at',
              description:
                  'When this part comes in, measured from the top of the mix. '
                  'Overlapping another part is what makes the blend.',
              value: part.offset.inMilliseconds / 1000,
              min: 0,
              // The ceiling is the arrangement as it stands, not the moment:
              // a bound that moved every time another part was trimmed would
              // drag this handle around while the user is looking at it.
              max: _seconds(
                Duration(
                  milliseconds: mix.duration.inMilliseconds + 10000,
                ),
              ),
              valueLabel: (v) => formatDuration(
                Duration(milliseconds: (v * 1000).round()),
              ),
              onChanged: (v) =>
                  onChanged(part.withOffset(Duration(milliseconds: (v * 1000).round()))),
            ),
            SettingSliderTile(
              title: 'Level',
              description:
                  'How loud this layer sits. Two layers at full level can '
                  'clip, so new parts start below it.',
              value: part.gain,
              min: 0,
              max: 1,
              divisions: 20,
              valueLabel: (v) => '${(v * 100).round()} %',
              onChanged: (v) => onChanged(part.withGain(v)),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  'Plays ${formatDuration(part.start)}–'
                  '${formatDuration(part.end)} of the song '
                  '(${formatDuration(part.length)})',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Sounds from ${formatDuration(part.offset)} to '
                  '${formatDuration(part.endInMix)} of the mix',
                  style: theme.textTheme.bodySmall,
                ),
                if (overlapBeforeSeconds > 0)
                  Text(
                    'Overlaps part $index for '
                    '${overlapBeforeSeconds.toStringAsFixed(1)} s',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.accentColor,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _summary(double overlapBefore) {
    final slice = part.hasKnownLength
        ? '${formatDuration(part.start)}–${formatDuration(part.end)}'
        : 'whole song';
    final enters = formatDuration(part.offset);
    final level = '${(part.gain * 100).round()} %';
    final overlap = overlapBefore > 0
        ? ' · ${overlapBefore.toStringAsFixed(1)} s overlap'
        : '';
    return '$slice · enters $enters · $level$overlap';
  }

  static double _seconds(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    // A slider whose min and max are equal is a Flutter assertion, and a
    // one-second ceiling would make the handles useless.
    return seconds < 1 ? 1 : seconds;
  }
}

/// The two ends of the slice, bounded by each other.
///
/// Each slider's range stops at the other end of the slice, so dragging one end
/// cannot move the other. That is the difference between trimming a part and
/// watching two handles shove each other around: the model still pushes the end
/// along rather than accepting a backwards slice (see [MashupPart.withStart]),
/// but the UI never asks it to, because the range it offers already excludes
/// the impossible values.
class _SliceSliders extends StatelessWidget {
  const _SliceSliders({required this.part, required this.onChanged});

  final MashupPart part;
  final ValueChanged<MashupPart> onChanged;

  /// The shortest slice the sliders will allow, in seconds.
  static final double _minimumSeconds =
      minimumMashupSlice.inMilliseconds / 1000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = part.sourceDuration.inMilliseconds / 1000;

    if (!part.hasKnownLength) {
      return Text(
        'This song arrived without a length, so it plays to its own end '
        'rather than to a guess.',
        style: theme.textTheme.bodySmall,
      );
    }

    final start = part.start.inMilliseconds / 1000;
    final end = part.end.inMilliseconds / 1000;
    final startMax = end - _minimumSeconds;
    final endMin = start + _minimumSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingSliderTile(
          title: 'Starts at',
          description: 'Where in the song this part begins.',
          value: start,
          min: 0,
          max: startMax > 0 ? startMax : total,
          // A slice already at its shortest has no room to move its start
          // earlier, so the handle is shown doing nothing rather than silently
          // pushing the end.
          onChanged: startMax <= 0
              ? null
              : (v) => onChanged(
                  part.withStart(Duration(milliseconds: (v * 1000).round())),
                ),
          valueLabel: (v) =>
              formatDuration(Duration(milliseconds: (v * 1000).round())),
        ),
        SettingSliderTile(
          title: 'Ends at',
          description: 'Where this part stops — the end of the slice.',
          value: end,
          min: endMin < total ? endMin : total,
          max: total,
          onChanged: endMin >= total
              ? null
              : (v) => onChanged(
                  part.withEnd(Duration(milliseconds: (v * 1000).round())),
                ),
          valueLabel: (v) =>
              formatDuration(Duration(milliseconds: (v * 1000).round())),
        ),
      ],
    );
  }
}
