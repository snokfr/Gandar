import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/failure_text.dart';
import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'liked_songs_controller.dart';

/// The library, in the order a person looks for things: what they played last,
/// then everything they have liked, then a way to search it.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(likedTracksProvider);
    final recentAsync = ref.watch(recentTracksProvider);
    final controller = ref.watch(playbackControllerProvider);
    final search = ref.watch(librarySearchProvider).toLowerCase();

    return Scaffold(
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final failure = describeFailure(error);
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not read your library',
            message: failure.message,
            action: FailureAction(
              failure: failure,
              onRetry: () => ref.invalidate(likedTracksProvider),
            ),
          );
        },
        data: (all) {
          if (all.isEmpty) {
            // An empty library has one cause and one route out of it: import.
            return EmptyState(
              icon: Icons.library_music_outlined,
              title: 'Your library is empty',
              message:
                  'Bring your liked songs in from an Exportify CSV or '
                  "Spotify's YourLibrary.json, or paste a playlist link.",
              action: FilledButton.icon(
                onPressed: () => context.go('/import'),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Import music'),
              ),
            );
          }

          final searching = search.isNotEmpty;
          final tracks = searching ? _matching(all, search) : all;
          // Recent tracks follow the search too, so the row never offers a track
          // the rest of the page has just filtered away.
          final recent = (recentAsync.value ?? const <Track>[])
              .where((track) => !searching || _matches(track, search))
              .toList(growable: false);

          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final currentId = controller.currentTrack?.id;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: SectionHeader(
                        title: searching ? 'Results' : 'Liked Songs',
                        subtitle: searching
                            ? '${tracks.length} of ${all.length} tracks'
                            : '${all.length} tracks',
                        action: FilledButton.icon(
                          onPressed: () => controller.playTracks(tracks),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play all'),
                        ),
                      ),
                    ),
                  ),
                  if (recent.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _RecentRow(
                        tracks: recent,
                        currentId: currentId,
                        onPlay: (track) => controller.playTracks(
                          recent,
                          startTrackId: track.id,
                        ),
                      ),
                    ),
                  if (tracks.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 32,
                        ),
                        child: Text(
                          'Nothing in your library matches that.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverList.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return TrackTile(
                          track: track,
                          isCurrent: track.id == currentId,
                          onTap: () => controller.playTracks(
                            tracks,
                            startTrackId: track.id,
                          ),
                          trailing: _LikeButton(track: track),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static List<Track> _matching(List<Track> tracks, String search) =>
      tracks.where((track) => _matches(track, search)).toList(growable: false);

  static bool _matches(Track track, String search) =>
      track.title.toLowerCase().contains(search) ||
      track.artists.any((a) => a.toLowerCase().contains(search)) ||
      (track.album ?? '').toLowerCase().contains(search);
}

/// The last few things played, as a horizontal shelf.
///
/// This is the answer to "what was I listening to?", which is the first question
/// a library is asked — and it is the one thing the vertical list is worst at,
/// because it is ordered by when you liked a track, not by when you heard it.
class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.tracks,
    required this.onPlay,
    this.currentId,
  });

  final List<Track> tracks;
  final ValueChanged<Track> onPlay;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: SectionHeader(
            title: 'Recently played',
            subtitle: 'Pick up where you left off',
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isCurrent = track.id == currentId;
              return SizedBox(
                width: 132,
                child: InkWell(
                  onTap: () => onPlay(track),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AlbumArt(
                          url: track.artworkUrl,
                          size: 124,
                          radius: 10,
                          isCurrent: isCurrent,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        Text(
                          track.primaryArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Drops a track from the local library.
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Remove from library',
      icon: const Icon(Icons.delete_outline),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref
              .read(appDependenciesProvider)
              .libraryRepository
              .removeTrack(track.id);
          ref.invalidate(likedTracksProvider);
          ref.invalidate(playlistsProvider);
          messenger.showSnackBar(
            SnackBar(content: Text('Removed "${track.title}".')),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Could not remove that track: ${describeFailure(e).message}',
              ),
            ),
          );
        }
      },
    );
  }
}

/// Tracks the in-library search box text.
final librarySearchProvider = NotifierProvider<LibrarySearchController, String>(
  LibrarySearchController.new,
);
