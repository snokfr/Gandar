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

/// The seek bar. Rebuilds only for position/duration updates.
class _SeekBar extends StatelessWidget {
  const _SeekBar({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.positionNotifier,
      builder: (context, position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: controller.durationNotifier,
          builder: (context, duration, _) {
            final total = duration.inMilliseconds;
            final value = total <= 0
                ? 0.0
                : position.inMilliseconds.clamp(0, total).toDouble();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    max: total <= 0 ? 1 : total.toDouble(),
                    onChanged: total <= 0
                        ? null
                        : (v) => controller.seek(
                            Duration(milliseconds: v.round()),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatDuration(position),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        formatDuration(duration),
                        style: theme.textTheme.bodySmall,
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

class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.controller, this.iconSize = 26});

  final PlaybackController controller;
  final double iconSize;

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
                padding: const EdgeInsets.all(8),
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
          height: 84,
          decoration: BoxDecoration(
            color: tokens.surfaceElevatedColor.withValues(alpha: 0.96),
            border: Border(top: BorderSide(color: tokens.borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  style: Theme.of(context).textTheme.bodySmall,
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
                    _TransportControls(controller: controller),
                    SizedBox(
                      width: 460,
                      child: _SeekBar(controller: controller),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 260,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
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
                      icon: Icon(
                        Icons.shuffle,
                        color:
                            controller.settings.shuffleMode == ShuffleMode.off
                            ? tokens.textSecondaryColor
                            : tokens.accentColor,
                      ),
                    ),
                    Icon(
                      Icons.volume_up,
                      color: tokens.textSecondaryColor,
                      size: 20,
                    ),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: controller.volume,
                        max: 1,
                        onChanged: controller.setVolume,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Share',
                      onPressed: track == null
                          ? null
                          : () => showShareSheet(context, ref, track),
                      icon: const Icon(Icons.ios_share),
                    ),
                    IconButton(
                      tooltip: 'Now playing',
                      onPressed: () => openNowPlaying(context),
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                  ],
                ),
              ),
            ],
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
                const SnackBar(content: Text('Copied the track and its links.')),
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
                SectionHeader(title: 'Lyrics', subtitle: lyrics.attribution),
                const SizedBox(height: 8),
                SelectableText(
                  lyrics.plain,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            );
          },
        );
  }
}
