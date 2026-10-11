import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/failure_text.dart';
import '../../domain/models/playlist.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/track_picker.dart';

/// Lists the playlists in Gandar: the ones made here, and the ones imported
/// from a Spotify link or an exported file. Both are editable and deletable.
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createPlaylist(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New playlist'),
      ),
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
                  'Make one here and add songs from your library, or paste a '
                  'Spotify playlist or album link to bring one in.',
              // Two ways out of an empty library, because they are different
              // intentions: start something new, or bring in something you
              // already have somewhere else.
              action: Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => createPlaylist(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('New playlist'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/import'),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Import a playlist'),
                  ),
                ],
              ),
            );
          }
          final mine = playlists.where((p) => p.isLocal).length;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: SectionHeader(
                    title: 'Your Playlists',
                    subtitle:
                        '${playlists.length} total · $mine made here · '
                        '${playlists.length - mine} imported',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
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
            ],
          );
        },
      ),
    );
  }
}

/// Asks for a name and creates an empty playlist, then opens it.
Future<void> createPlaylist(BuildContext context, WidgetRef ref) async {
  final name = await promptForName(
    context,
    title: 'New playlist',
    action: 'Create',
    hint: 'Late night drive',
  );
  if (name == null || !context.mounted) return;

  final repository = ref.read(appDependenciesProvider).libraryRepository;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final playlist = await repository.createPlaylist(name);
    ref.invalidate(playlistsProvider);
    if (context.mounted) context.go('/playlists/${playlist.id}');
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not create that playlist: $e')),
    );
  }
}

/// Confirms and then deletes [playlist].
///
/// The wording differs by where the playlist came from, because the two cases
/// really are different: one destroys something only this app holds, the other
/// forgets a local copy of something Spotify still has.
Future<void> deletePlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  // Captured before the dialog: after an await, looking the messenger up again
  // would be reaching through a context that may no longer be mounted.
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete "${playlist.name}"?'),
      content: Text(
        playlist.isLocal
            ? 'This playlist was made in Gandar, so deleting it removes it for '
                  'good. The ${playlist.trackCount} songs in it stay in your '
                  'library.'
            : 'This is a local copy of a Spotify playlist. Deleting it removes '
                  'the copy from Gandar — nothing changes on Spotify. The '
                  'songs stay in your library, and you can paste the link again '
                  'to bring it back.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final repository = ref.read(appDependenciesProvider).libraryRepository;
  try {
    await repository.deletePlaylist(playlist.id);
    ref.invalidate(playlistsProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted "${playlist.name}".')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not delete it: $e')));
  }
}

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${playlist.trackCount} tracks'
                    '${playlist.isLocal ? ' · made here' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Playlist actions',
              onSelected: (value) async {
                if (value == 'rename') {
                  final name = await promptForName(
                    context,
                    title: 'Rename playlist',
                    action: 'Rename',
                    initial: playlist.name,
                  );
                  if (name == null) return;
                  await ref
                      .read(appDependenciesProvider)
                      .libraryRepository
                      .renamePlaylist(playlist.id, name);
                  ref.invalidate(playlistsProvider);
                } else if (value == 'delete') {
                  await deletePlaylist(context, ref, playlist);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the tracks of one playlist, and lets them be edited.
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistTracksProvider(playlistId));
    final controller = ref.watch(playbackControllerProvider);
    final playlist = ref
        .watch(playlistsProvider)
        .asData
        ?.value
        .where((p) => p.id == playlistId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/playlists'),
        ),
        actions: [
          if (playlist != null)
            PopupMenuButton<String>(
              tooltip: 'Playlist actions',
              onSelected: (value) async {
                if (value == 'rename') {
                  final name = await promptForName(
                    context,
                    title: 'Rename playlist',
                    action: 'Rename',
                    initial: playlist.name,
                  );
                  if (name == null) return;
                  await ref
                      .read(appDependenciesProvider)
                      .libraryRepository
                      .renamePlaylist(playlistId, name);
                  ref.invalidate(playlistsProvider);
                } else if (value == 'delete') {
                  final navigator = context;
                  await deletePlaylist(context, ref, playlist);
                  if (navigator.mounted) navigator.go('/playlists');
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
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
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final currentId = controller.currentTrack?.id;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: SectionHeader(
                      title: '${tracks.length} tracks',
                      subtitle: playlist == null
                          ? null
                          : playlist.isLocal
                          ? 'Made here — add and remove songs freely.'
                          : 'Imported from a Spotify link. Edits are local; '
                                're-importing the link replaces them.',
                      action: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => showTrackPicker(
                              context,
                              title: 'Add to "${playlist?.name ?? 'playlist'}"',
                              alreadyPicked: <String>{
                                for (final track in tracks) track.id,
                              },
                              onPick: (track) async {
                                await ref
                                    .read(appDependenciesProvider)
                                    .libraryRepository
                                    .addTrackToPlaylist(playlistId, track.id);
                                ref.invalidate(
                                  playlistTracksProvider(playlistId),
                                );
                                ref.invalidate(playlistsProvider);
                              },
                            ),
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Add songs'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: tracks.isEmpty
                                ? null
                                : () => controller.playTracks(tracks),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: tracks.isEmpty
                        ? const EmptyState(
                            icon: Icons.music_off,
                            title: 'This playlist is empty',
                            message:
                                'Tap "Add songs" to pick tracks out of your '
                                'library.',
                          )
                        : ListView.builder(
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
                                trailing: IconButton(
                                  tooltip: 'Remove from this playlist',
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () async {
                                    await ref
                                        .read(appDependenciesProvider)
                                        .libraryRepository
                                        .removeTrackFromPlaylist(
                                          playlistId,
                                          track.id,
                                        );
                                    ref.invalidate(
                                      playlistTracksProvider(playlistId),
                                    );
                                    ref.invalidate(playlistsProvider);
                                  },
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
