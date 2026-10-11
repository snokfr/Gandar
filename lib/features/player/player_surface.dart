import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/settings/playback_settings.dart';
import '../../core/theme/theme_engine.dart';
import '../../domain/models/track.dart';
import '../../state/playback_controller.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'lyrics_view.dart';
import 'share_links.dart';

/// Formats a duration as `m:ss` (or `h:mm:ss` for long media).
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// Subscribes to a playback controller and rebuilds on state changes.
class PlaybackScope extends ConsumerWidget {
  const PlaybackScope({super.key, required this.builder});

  final Widget Function(BuildContext context, PlaybackController controller)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(playbackControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => builder(context, controller),
    );
  }
}

/// The seek bar, with the elapsed time, the track's length and the time left.
///
/// All three, because they answer different questions: how far into the song
/// you are, how long it is, and how much is left — and the last one is what
/// decides whether to start something else.
class _SeekBar extends StatelessWidget {
  const _SeekBar({super.key, required this.controller, this.dense = false});

  final PlaybackController controller;

  /// Sized for the 84 px playback bar. A default [Slider] is 48 px tall on its
  /// own, which with the transport buttons above it left no room for the times
  /// and got them clipped instead — a bar with no time on it at all.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.positionNotifier,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: controller.durationNotifier,
          builder: (context, duration, _) {
            final total = duration.inMilliseconds;
            final known = total > 0;
            final elapsed = known ? position : Duration.zero;
            final left = known ? duration - position : Duration.zero;
            final value = known
                ? position.inMilliseconds.clamp(0, total).toDouble()
                : 0.0;

            final slider = SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: dense ? 12 : 18,
                ),
              ),
              child: Slider(
                value: value,
                max: known ? total.toDouble() : 1,
                onChanged: known
                    ? (v) => controller.seek(Duration(milliseconds: v.round()))
                    : null,
              ),
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dense) SizedBox(height: 22, child: slider) else slider,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _TimeLabel(
                        text: formatDuration(elapsed),
                        semantics: 'Elapsed',
                      ),
                      _TimeLabel(
                        text: formatDuration(duration),
                        semantics: 'Total length',
                      ),
                      _TimeLabel(
                        text:
                            '-${formatDuration(left.isNegative ? Duration.zero : left)}',
                        semantics: 'Time remaining',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One of the playback bar's trailing controls.
///
/// Fixed at 36 px rather than the default 48: five of these plus the volume
/// slider have to fit 300 px, and the default size is what made them overflow
/// their box and take the last one off the bar with them.
class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Icon(icon, color: color),
    );
  }
}

/// A time read-out. Three bare `1:04`s in a row read as noise to a screen
/// reader, so each one says which of the three it is.
class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.text, required this.semantics});

  final String text;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      value: text,
      child: ExcludeSemantics(
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.controller,
    this.iconSize = 26,
    this.dense = false,
  });

  final PlaybackController controller;
  final double iconSize;

  /// Tightens the tap targets to fit the playback bar's fixed height. Still
  /// above the 36 px minimum a desktop pointer needs; there is no room for the
  /// full 48.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gandarTokens;
    final hasTrack = controller.currentTrack != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous',
          iconSize: iconSize,
          padding: dense ? EdgeInsets.zero : null,
          constraints: dense
              ? const BoxConstraints.tightFor(width: 38, height: 36)
              : null,
          onPressed: hasTrack ? controller.previous : null,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: controller.isPlaying ? 'Pause' : 'Play',
          child: Material(
            color: tokens.textPrimaryColor,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: hasTrack ? controller.togglePlayPause : null,
              child: Padding(
                padding: EdgeInsets.all(dense ? 6 : 8),
                child: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: iconSize + 2,
                  color: tokens.backgroundPrimaryColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Next',
          iconSize: iconSize,
          padding: dense ? EdgeInsets.zero : null,
          constraints: dense
              ? const BoxConstraints.tightFor(width: 38, height: 36)
              : null,
          onPressed: hasTrack ? controller.next : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}

/// Desktop playback bar pinned to the bottom of the shell.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.gandarTokens;
    return PlaybackScope(
      builder: (context, controller) {
        final track = controller.currentTrack;
        return Container(
          height: 88,
          decoration: BoxDecoration(
            color: tokens.surfaceElevatedColor.withValues(alpha: 0.96),
            border: Border(top: BorderSide(color: tokens.borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Without this, every IconButton keeps a 48x48 minimum tap target
          // whatever constraints it is given, which is what made this bar
          // overflow: the buttons above the seek bar and the five controls on
          // its right both want more room than the bar has.
          child: Theme(
            data: Theme.of(
              context,
            ).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: track == null
                      ? Text(
                          'Nothing playing',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : Row(
                          children: [
                            AlbumArt(url: track.artworkUrl, size: 52),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Text(
                                    track.artists.join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _TransportControls(
                        controller: controller,
                        iconSize: 24,
                        dense: true,
                      ),
                      // A ceiling, not a fixed width: the bar is laid out at
                      // whatever the window gives it, and a hard 460 px inside
                      // an Expanded overflows as soon as the window is narrower
                      // than the three groups want it to be.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _SeekBar(controller: controller, dense: true),
                      ),
                    ],
                  ),
                ),
                // 300 px for five buttons, a volume glyph and a slider. The
                // default 48 px IconButton tap target does not fit five of them
                // here, and the group overflowed its box — which is where the
                // Share button went missing from the bar.
                SizedBox(
                  width: 300,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _BarIconButton(
                        tooltip: 'Shuffle',
                        onPressed: () => ref
                            .read(playbackSettingsProvider.notifier)
                            .update(
                              controller.settings.copyWith(
                                shuffleMode:
                                    controller.settings.shuffleMode ==
                                        ShuffleMode.off
                                    ? ShuffleMode.standard
                                    : ShuffleMode.off,
                              ),
                            ),
                        icon: Icons.shuffle,
                        color:
                            controller.settings.shuffleMode == ShuffleMode.off
                            ? tokens.textSecondaryColor
                            : tokens.accentColor,
                      ),
                      Icon(
                        Icons.volume_up,
                        color: tokens.textSecondaryColor,
                        size: 18,
                      ),
                      SizedBox(
                        width: 84,
                        child: Slider(
                          value: controller.volume,
                          max: 1,
                          onChanged: controller.setVolume,
                        ),
                      ),
                      _BarIconButton(
                        tooltip: 'Lyrics',
                        onPressed: track == null
                            ? null
                            : () => showLyricsSheet(context, track),
                        icon: Icons.lyrics_outlined,
                      ),
                      _BarIconButton(
                        tooltip: 'Share',
                        onPressed: track == null
                            ? null
                            : () => showShareSheet(context, ref, track),
                        icon: Icons.ios_share,
                      ),
                      _BarIconButton(
                        tooltip: 'Now playing',
                        onPressed: () => openNowPlaying(context),
                        icon: Icons.keyboard_arrow_up,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mobile mini player sitting above the bottom navigation bar.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.gandarTokens;
    return PlaybackScope(
      builder: (context, controller) {
        final track = controller.currentTrack;
        if (track == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => openNowPlaying(context),
          onVerticalDragEnd: (details) {
            // A flick upward opens the full player (velocity-driven, like a
            // sheet you throw open).
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -200) openNowPlaying(context);
          },
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                AlbumArt(url: track.artworkUrl, size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ValueListenableBuilder<Duration>(
                        valueListenable: controller.positionNotifier,
                        builder: (context, position, _) {
                          final total =
                              controller.durationNotifier.value.inMilliseconds;
                          final value = total <= 0
                              ? 0.0
                              : (position.inMilliseconds / total).clamp(
                                  0.0,
                                  1.0,
                                );
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 2,
                              backgroundColor: tokens.borderColor,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: controller.togglePlayPause,
                  icon: Icon(
                    controller.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                ),
                IconButton(
                  onPressed: controller.next,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Opens the full-screen now-playing surface.
Future<void> openNowPlaying(BuildContext context) {
  final duration = Motion.adaptiveDuration(
    context,
    full: const Duration(milliseconds: 360),
    reduced: const Duration(milliseconds: 120),
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    transitionAnimationController: AnimationController(
      vsync: Navigator.of(context),
      duration: duration,
    ),
    builder: (_) => const NowPlayingSheet(),
  );
}

/// Offers every place [track] can be shared to, and copies the chosen link.
///
/// Both services are always offered. A track imported from Spotify usually has
/// no YouTube video resolved yet, and a track found on YouTube has no Spotify
/// id at all; in either case the row becomes a search link rather than a
/// disabled button. The cached Spotify -> YouTube mapping is consulted first,
/// which is a local read, so an exact YouTube link is available for virtually
/// everything that has ever been played.
Future<void> showShareSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  String? mapped;
  try {
    mapped = await ref
        .read(appDependenciesProvider)
        .mappingRepository
        .findVideoId(track.id);
  } catch (_) {
    // A mapping lookup is an optimisation here, never a reason to fail.
    mapped = null;
  }
  if (!context.mounted) return;

  final links = ShareLinks.forTrack(track, youtubeVideoId: mapped);
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: AlbumArt(url: track.artworkUrl, size: 44),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              track.artists.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          for (final link in links)
            ListTile(
              leading: Icon(
                link.source == 'youtube'
                    ? Icons.smart_display_outlined
                    : Icons.graphic_eq,
              ),
              title: Text('Copy ${link.label} link'),
              subtitle: Text(
                link.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: link.url));
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                messenger.showSnackBar(
                  SnackBar(content: Text('Copied the ${link.label} link.')),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Copy as text'),
            subtitle: Text(
              'The artist, title and every link in one paste',
              style: theme.textTheme.bodySmall,
            ),
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: ShareLinks.asText(track, links)),
              );
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Copied the track and its links.'),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Full-screen player: artwork, transport, lyrics and the whole queue.
class NowPlayingSheet extends ConsumerWidget {
  const NowPlayingSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.gandarTokens;
    final reduceMotion = Motion.prefersReducedMotion(context);
    return PlaybackScope(
      builder: (context, controller) {
        final track = controller.currentTrack;
        final queue = controller.queue;
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: tokens.backgroundSecondaryColor,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(tokens.radiusLg),
                ),
              ),
              // Slivers rather than a ListView of children: the queue can hold
              // thousands of tracks, and building every row to show eight of
              // them is exactly the kind of waste that shows up as a stutter.
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(<Widget>[
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: tokens.borderColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (track == null)
                          const EmptyState(
                            icon: Icons.music_note,
                            title: 'Nothing playing',
                          )
                        else ...[
                          Center(
                            child: AlbumArt(
                              url: track.artworkUrl,
                              size: 280,
                              radius: tokens.radiusLg,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            track.title,
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.artists.join(', '),
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  showShareSheet(context, ref, track),
                              icon: const Icon(Icons.ios_share, size: 18),
                              label: const Text('Share'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: reduceMotion
                                ? const Duration(milliseconds: 120)
                                : const Duration(milliseconds: 220),
                            child: _SeekBar(
                              key: ValueKey(track.id),
                              controller: controller,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _TransportControls(
                            controller: controller,
                            iconSize: 34,
                          ),
                          const SizedBox(height: 20),
                          if (controller.errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                controller.errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          _LyricsSection(track: track),
                          const SizedBox(height: 12),
                        ],
                      ]),
                    ),
                  ),
                  if (track != null && queue.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                      sliver: SliverToBoxAdapter(
                        child: SectionHeader(
                          title: 'Up next',
                          subtitle: queue.length == 1
                              ? 'just this track — it was played on its own'
                              : '${queue.length} tracks · tap any to jump',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverList.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final queued = queue[index];
                          return TrackTile(
                            track: queued,
                            dense: true,
                            isCurrent: queued.id == track.id,
                            onTap: () => controller.jumpTo(queued.id),
                          );
                        },
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The words to the current track, from LRCLIB (no account, no key).
///
/// A missing lyric is not an error: most of a large library will not have one,
/// and the section says so in a sentence instead of an empty box.
class _LyricsSection extends ConsumerWidget {
  const _LyricsSection({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(lyricsProvider(track))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (error, _) => Text(
            'Could not load lyrics: $error',
            style: theme.textTheme.bodySmall,
          ),
          data: (lyrics) {
            if (lyrics == null || lyrics.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Lyrics'),
                  const SizedBox(height: 6),
                  Text(
                    lyrics?.instrumental ?? false
                        ? 'This track is instrumental.'
                        : 'No lyrics found for this track.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Lyrics',
                  subtitle: lyrics.hasSynced
                      ? '${lyrics.attribution} · following the song'
                      : lyrics.attribution,
                  action: OutlinedButton.icon(
                    onPressed: () => showLyricsSheet(context, track),
                    icon: const Icon(Icons.open_in_full, size: 18),
                    label: const Text('Full lyrics'),
                  ),
                ),
                const SizedBox(height: 8),
                SyncedLyricsView(
                  lyrics: lyrics,
                  position: ref
                      .watch(playbackControllerProvider)
                      .positionNotifier,
                  // This sheet is already a scrollable; a second scroll view
                  // inside it would fight it for the drag.
                  scrollable: false,
                ),
              ],
            );
          },
        );
  }
}
