import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/failure_text.dart';
import '../../domain/models/playlist.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Lists the playlists and albums that were imported into Gandar.
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistsProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          final failure = describeFailure(e);
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not read your playlists',
            message: failure.message,
            action: FailureAction(
              failure: failure,
              onRetry: () => ref.invalidate(playlistsProvider),
            ),
          );
        },
        data: (playlists) {
          if (playlists.isEmpty) {
            return EmptyState(
              icon: Icons.queue_music_outlined,
              title: 'No playlists yet',
              message:
                  'Paste a Spotify playlist or album link and it is stored '
                  'here, ready to play offline. For your own library, export it '
                  'with Exportify and import the file.',
              action: FilledButton.icon(
                onPressed: () => context.go('/import'),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Import a playlist'),
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: SectionHeader(title: 'Your Playlists'),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.4,
                  ),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) =>
                      _PlaylistCard(playlist: playlists[index]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return GandarCard(
      padding: const EdgeInsets.all(10),
      child: InkWell(
        onTap: () => context.go('/playlists/${playlist.id}'),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            AlbumArt(url: playlist.artworkUrl, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.trackCount} tracks',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the tracks of one playlist and lets the user play it.
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistTracksProvider(playlistId));
    final controller = ref.watch(playbackControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/playlists'),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          final failure = describeFailure(e);
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load this playlist',
            message: failure.message,
            action: FailureAction(
              failure: failure,
              onRetry: () => ref.invalidate(playlistTracksProvider(playlistId)),
            ),
          );
        },
        data: (tracks) {
          if (tracks.isEmpty) {
            return const EmptyState(
              icon: Icons.music_off,
              title: 'This playlist is empty',
            );
          }
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final currentId = controller.currentTrack?.id;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SectionHeader(
                      title: '${tracks.length} tracks',
                      action: FilledButton.icon(
                        onPressed: () => controller.playTracks(tracks),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
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
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
