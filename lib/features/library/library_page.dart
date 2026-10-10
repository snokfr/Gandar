import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import 'liked_songs_controller.dart';

/// Shows the user's liked songs with virtualized scrolling and tap-to-play.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(likedTracksProvider);
    final controller = ref.watch(playbackControllerProvider);
    final search = ref.watch(librarySearchProvider).toLowerCase();

    return Scaffold(
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off,
          title: 'Could not load your library',
          message: _friendlyError(error),
          action: FilledButton(
            onPressed: () => ref.invalidate(likedTracksProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.library_music_outlined,
              title: 'No liked songs yet',
              message: 'Sign in to Spotify and like some tracks, then they will appear here.',
            );
          }
          final tracks = search.isEmpty
              ? all
              : all
                    .where(
                      (t) =>
                          t.title.toLowerCase().contains(search) ||
                          t.artists.any(
                            (a) => a.toLowerCase().contains(search),
                          ),
                    )
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
                        title: 'Liked Songs',
                        subtitle: '${all.length} tracks',
                        action: FilledButton.icon(
                          onPressed: () => controller.playTracks(all),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play all'),
                        ),
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

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('403') || text.contains('401')) {
      return 'Spotify refused the request. New Spotify apps start in '
          'Development mode: add your account under User Management in the '
          'Spotify developer dashboard.';
    }
    return text;
  }
}

/// Unlikes a track via the Spotify API.
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Remove from Liked Songs',
      icon: const Icon(Icons.favorite),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref
              .read(appDependenciesProvider)
              .spotifyApi
              .removeTrack(track.id);
          ref.invalidate(likedTracksProvider);
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('Could not update Spotify: $e')),
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
