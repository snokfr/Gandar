import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/failure_text.dart';
import '../../core/theme/theme_engine.dart';
import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../player/player_surface.dart' show formatDuration;

/// The route for one artist, with the name escaped so a slash in a name (AC/DC)
/// stays one path segment instead of two.
String artistRoute(String name) =>
    '/artists/${Uri.encodeComponent(name.trim())}';

/// Opens the artist's page. The one place the route is built, so every screen
/// that shows a name takes people to the same place.
void openArtist(BuildContext context, String artist) {
  final name = artist.trim();
  if (name.isEmpty) return;
  context.go(artistRoute(name));
}

/// Everything by one artist, in two clearly separated halves.
///
/// ## Why two halves
///
/// Because they are two different things and only one of them is a fact about
/// this machine. The top half is what is *here*: the tracks this library
/// actually holds, playable offline, in library order. The bottom half is what
/// is *out there*: YouTube's results for the artist, which is where the rest of
/// their songs are reachable from without an account, a key or a subscription.
///
/// Mixing the two would be the dishonest option. A screen that looked like one
/// list of an artist's songs would make a streamed video and an imported file
/// look the same, and one of them is a file you own and the other is a stream
/// that may not be there tomorrow. So each half says what it is, and the
/// library half is labelled as everything imported for this artist — no more.
class ArtistPage extends ConsumerWidget {
  const ArtistPage({super.key, required this.artistName});

  /// The name from the route. The model restores the library's spelling, so a
  /// hand-typed or lower-case name still displays the way the music writes it.
  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final artistAsync = ref.watch(artistProvider(artistName));
    final settings = ref.watch(playbackSettingsProvider);
    final controller = ref.watch(playbackControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Artist')),
      body: artistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off,
          title: 'Could not read your library',
          message: describeFailure(error).message,
        ),
        data: (artist) {
          final albums = artist.albums;

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
                            url: artist.artworkUrl,
                            size: 132,
                            radius: 12,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  artist.name,
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  artist.tracks.isEmpty
                                      ? 'Nothing imported yet'
                                      : '${artist.trackCount} '
                                            'track'
                                            '${artist.trackCount == 1 ? '' : 's'} '
                                            'in your library · '
                                            '${_total(artist.duration)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (artist.tracks.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  // One button, and it does one thing. The
                                  // queue it builds is in library order;
                                  // shuffle is a playback setting, not a
                                  // property of this artist, so it is not
                                  // quietly switched here.
                                  FilledButton.icon(
                                    onPressed: () =>
                                        controller.playTracks(artist.tracks),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Play all'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (albums.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albums.length == 1 ? 'Album' : 'Albums',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final album in albums)
                                  ActionChip(
                                    label: Text(album),
                                    backgroundColor:
                                        tokens.surfaceElevatedColor,
                                    onPressed: () => context.go(
                                      '/albums/${Uri.encodeComponent(album)}',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: SectionHeader(
                        title: 'In your library',
                        subtitle: artist.tracks.isEmpty
                            ? 'Nothing imported for this artist'
                            : 'Everything imported for this artist',
                      ),
                    ),
                  ),
                  if (artist.tracks.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Gandar can only play what is here, and none of it '
                          'is by this artist yet. Their songs are below, from '
                          'YouTube — or import a playlist that includes them.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      sliver: SliverList.builder(
                        itemCount: artist.tracks.length,
                        itemBuilder: (context, index) {
                          final track = artist.tracks[index];
                          return TrackTile(
                            track: track,
                            isCurrent: track.id == currentId,
                            onTap: () => controller.playTracks(
                              artist.tracks,
                              startTrackId: track.id,
                            ),
                          );
                        },
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                      child: SectionHeader(
                        title: 'More from ${artist.name}',
                        subtitle: settings.showYouTubeInSearch
                            ? 'From YouTube — playable, not imported'
                            : 'Turned off in Settings',
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: settings.showYouTubeInSearch
                          ? _Catalogue(
                              artist: artist.name,
                              currentId: currentId,
                              onPlay: (queue, start) => controller.playTracks(
                                queue,
                                startTrackId: start,
                              ),
                            )
                          : Text(
                              'YouTube results are switched off, so the rest '
                              'of this artist is not listed here. Settings → '
                              'Search turns them back on.',
                              style: theme.textTheme.bodySmall,
                            ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Playing time of what is here, in the same words the album pages use.
  static String _total(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }
}

/// What YouTube has for this artist, as a list you can play from.
///
/// This is the half of the page that is not a fact about this machine, and it
/// says so: nothing here is in the library, playing one streams it, and the
/// queue is the results themselves so that playing a row carries on down the
/// list instead of stopping after one song.
class _Catalogue extends ConsumerWidget {
  const _Catalogue({
    required this.artist,
    required this.currentId,
    required this.onPlay,
  });

  final String artist;
  final String? currentId;
  final void Function(List<Track> queue, String startTrackId) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.gandarTokens;
    final results = ref.watch(artistCatalogueProvider(artist));

    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => Text(
        'Could not search YouTube for this artist: $error',
        style: theme.textTheme.bodySmall,
      ),
      data: (videos) {
        if (videos.isEmpty) {
          return Text(
            'YouTube returned nothing for this artist. That is usually the '
            'network rather than the artist.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textSecondaryColor,
            ),
          );
        }
        final queue = <Track>[for (final video in videos) video.toTrack()];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final video in videos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => onPlay(queue, video.trackId),
                leading: AlbumArt(url: video.thumbnailUrl, size: 44),
                title: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  [
                    if (video.author != null) video.author!,
                    if (video.duration != null)
                      formatDuration(video.duration!),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Icon(
                  currentId == video.trackId
                      ? Icons.equalizer
                      : Icons.play_arrow,
                  color: currentId == video.trackId ? tokens.accentColor : null,
                ),
              ),
          ],
        );
      },
    );
  }
}
