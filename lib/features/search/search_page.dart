import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/youtube/youtube_search.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../artists/artist_page.dart';
import '../player/player_surface.dart' show formatDuration;

/// Searches every source at once:
///
/// * **your library** — already on disk, so it answers instantly and works
///   offline,
/// * **your playlists** — matched by name, so a playlist is reachable from the
///   search box as well as from the sidebar,
/// * **YouTube** — playable even when a track has nothing to do with it.
///
/// A track that comes from YouTube carries its video id, so tapping it plays
/// that exact video through the normal queue.
///
/// The two music lists are *queued*, not played one at a time: tapping a
/// YouTube result hands the whole result list to the player and starts at the
/// result you tapped. Playing a single track used to leave "Up next" holding
/// exactly the one song you had just started, which made the queue look
/// broken — a search result set is a playlist, and it is treated as one.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Waits for a pause in typing before querying the network.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _query;
    final searching = query.length >= kMinSearchLength;

    final liked = ref.watch(likedTracksProvider).asData?.value ?? const [];
    final playlists = ref.watch(playlistsProvider).asData?.value ?? const [];
    final player = ref.watch(playbackControllerProvider);
    final settings = ref.watch(playbackSettingsProvider);

    // Library matches need no network: filter what is already loaded.
    final libraryTracks = searching
        ? liked.where((t) => _matchesTrack(t, query)).toList(growable: false)
        : const <Track>[];
    final libraryPlaylists = searching
        ? playlists
              .where((p) => _matches(query, p.name))
              .toList(growable: false)
        : const <Playlist>[];

    // The YouTube section is what the playback setting switches off, and it is
    // the only part of the search that needs a connection.
    final youTube = searching && settings.showYouTubeInSearch
        ? ref.watch(youTubeSearchProvider(query))
        : const AsyncValue<List<YouTubeVideo>>.data(<YouTubeVideo>[]);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search your library and YouTube',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: !searching
                ? const EmptyState(
                    icon: Icons.search,
                    title: 'Search everything',
                    message:
                        'Finds anything you have imported and any video on '
                        'YouTube. Library results are instant and work offline; '
                        'the YouTube search needs a connection.',
                  )
                : ListView(
                    children: [
                      _Section(
                        title: 'In your library',
                        subtitle:
                            '${libraryTracks.length} songs · '
                            '${libraryPlaylists.length} playlists',
                        action: libraryTracks.isEmpty
                            ? null
                            : FilledButton.icon(
                                onPressed: () =>
                                    player.playTracks(libraryTracks),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play all'),
                              ),
                        child: _trackList(
                          context,
                          libraryTracks,
                          onPlay: (track) => player.playTracks(
                            libraryTracks,
                            startTrackId: track.id,
                          ),
                          empty: 'Nothing in your saved songs matches.',
                        ),
                      ),
                      _Section(
                        title: 'Playlists you have',
                        subtitle: '${libraryPlaylists.length}',
                        show: libraryPlaylists.isNotEmpty,
                        child: _playlistList(libraryPlaylists),
                      ),
                      _Section(
                        title: 'On YouTube',
                        subtitle: !settings.showYouTubeInSearch
                            ? 'turned off in Settings'
                            : youTube.asData == null
                            ? 'searching…'
                            : '${youTube.asData!.value.length} videos',
                        show: settings.showYouTubeInSearch,
                        child: _asyncList(youTube, (videos) {
                          // One queue for the whole result set, entered at the
                          // row that was tapped.
                          final queued = <Track>[
                            for (final video in videos) video.toTrack(),
                          ];
                          return Column(
                            children: [
                              for (final video in videos)
                                _VideoRow(
                                  video: video,
                                  onPlay: () => player.playTracks(
                                    queued,
                                    startTrackId: video.trackId,
                                  ),
                                ),
                              if (videos.isEmpty)
                                const _Hint('No YouTube matches.'),
                            ],
                          );
                        }),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static bool _matches(String query, String value) =>
      value.toLowerCase().contains(query.toLowerCase());

  static bool _matchesTrack(Track track, String query) =>
      _matches(query, track.title) ||
      track.artists.any((a) => _matches(query, a)) ||
      _matches(query, track.album ?? '');

  Widget _trackList(
    BuildContext context,
    List<Track> tracks, {
    required void Function(Track) onPlay,
    required String empty,
    String? subtitleLabel,
  }) {
    if (tracks.isEmpty) return _Hint(empty);
    return Column(
      children: [
        for (final track in tracks)
          TrackTile(
            track: track,
            subtitle: subtitleLabel == null
                ? null
                : '$subtitleLabel · ${track.artists.join(', ')}',
            onTap: () => onPlay(track),
            // Only when the second line really is the artist. With a playlist
            // label in front of it the line means two things, and a tap would
            // have to guess which one was meant.
            onArtistTap: subtitleLabel == null
                ? (artist) => openArtist(context, artist)
                : null,
          ),
      ],
    );
  }

  Widget _playlistList(List<Playlist> playlists) {
    if (playlists.isEmpty) return const _Hint('No playlists match.');
    return Column(
      children: [
        for (final playlist in playlists)
          ListTile(
            leading: AlbumArt(url: playlist.artworkUrl, size: 44),
            title: Text(playlist.name),
            subtitle: Text(
              '${playlist.trackCount} tracks'
              '${playlist.ownerName == null ? '' : ' · ${playlist.ownerName}'}',
            ),
            onTap: () => context.go('/playlists/${playlist.id}'),
          ),
      ],
    );
  }

  /// Renders an async section: spinner while loading, message on error, and
  /// the builder's content once loaded.
  Widget _asyncList<T>(AsyncValue<T> value, Widget Function(T data) builder) {
    return value.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => _Hint('Could not search: $error'),
      data: builder,
    );
  }
}

/// One labelled block of results.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.show = true,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool show;

  /// Optional trailing control, e.g. "Play all" for the section's results.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, subtitle: subtitle, action: action),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
    child: Text(message, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// A YouTube result, with a play action instead of a queue position.
class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.video, required this.onPlay});

  final YouTubeVideo video;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onPlay,
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
          if (video.duration != null) formatDuration(video.duration!),
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.play_arrow),
    );
  }
}

