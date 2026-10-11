import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/failure_text.dart';
import '../../domain/models/album.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// The library, filed by album.
///
/// Albums are read from the same rows the Library page shows, so a track that is
/// imported shows up here without anything having to keep a second index.
class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);

    return Scaffold(
      body: albums.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final failure = describeFailure(error);
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not read your albums',
            message: failure.message,
            action: FailureAction(
              failure: failure,
              onRetry: () => ref.invalidate(likedTracksProvider),
            ),
          );
        },
        data: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.album_outlined,
              title: 'No albums yet',
              message:
                  'Albums come from the albums printed on your imported '
                  'tracks. Import a library or a playlist and they appear here.',
            );
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: SectionHeader(
                    title: 'Albums',
                    subtitle: '${all.length} from your library',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 210,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final album = all[index];
                    return _AlbumCard(
                      album: album,
                      onTap: () => context.go(
                        '/albums/${Uri.encodeComponent(album.id)}',
                      ),
                    );
                  }, childCount: all.length),
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

/// One album: cover, title, artist, and how much of it is here.
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AlbumArt(
                    url: album.artworkUrl,
                    radius: 10,
                    size: double.infinity,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (album.artist.isNotEmpty)
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              album.trackCount == 1 ? '1 track' : '${album.trackCount} tracks',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One album's tracks, in library order, with a single button that plays them.
class AlbumDetailPage extends ConsumerWidget {
  const AlbumDetailPage({super.key, required this.albumId});

  /// The album id as it appears in the route: `Album.id`.
  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final controller = ref.watch(playbackControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Album')),
      body: albums.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off,
          title: 'Could not read your albums',
          message: describeFailure(error).message,
        ),
        data: (all) {
          final album = all.where((a) => a.id == albumId).firstOrNull;
          if (album == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'That album is not in your library',
              message:
                  'It may have been removed, or its tracks were imported '
                  'without an album name.',
            );
          }

          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final currentId = controller.currentTrack?.id;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AlbumArt(
                            url: album.artworkUrl,
                            size: 132,
                            radius: 12,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  album.name,
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                if (album.artist.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    album.artist,
                                    style: Theme.of(context).textTheme.titleMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  '${album.trackCount} tracks · '
                                  '${_duration(album.duration)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () =>
                                      controller.playTracks(album.tracks),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Play album'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverList.builder(
                      itemCount: album.tracks.length,
                      itemBuilder: (context, index) {
                        final track = album.tracks[index];
                        return TrackTile(
                          track: track,
                          isCurrent: track.id == currentId,
                          onTap: () => controller.playTracks(
                            album.tracks,
                            startTrackId: track.id,
                          ),
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

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }
}
