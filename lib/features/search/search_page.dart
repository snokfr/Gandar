import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Searches the user's library and playlists.
///
/// Track metadata comes from Spotify; the YouTube lookup happens later, at
/// play time, and is invisible to this screen.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final liked = ref.watch(likedTracksProvider).asData?.value ?? const [];
    final playlists = ref.watch(playlistsProvider).asData?.value ?? const [];
    final player = ref.watch(playbackControllerProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search songs, artists and playlists',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? const EmptyState(
                    icon: Icons.search,
                    title: 'Search your library',
                    message:
                        'Find liked songs and playlists by title or artist.',
                  )
                : ListView(
                    children: [
                      for (final p in playlists.where(
                        (p) => p.name.toLowerCase().contains(query),
                      ))
                        ListTile(
                          leading: AlbumArt(url: p.artworkUrl, size: 44),
                          title: Text(p.name),
                          subtitle: Text('${p.trackCount} tracks'),
                        ),
                      for (final t in liked.where(
                        (t) =>
                            t.title.toLowerCase().contains(query) ||
                            t.artists.any(
                              (a) => a.toLowerCase().contains(query),
                            ),
                      ))
                        TrackTile(
                          track: t,
                          onTap: () =>
                              player.playTracks(liked, startTrackId: t.id),
                        ),
                      if (playlists.isEmpty && liked.isEmpty)
                        const EmptyState(
                          icon: Icons.search_off,
                          title: 'No matches',
                          message: 'Nothing in your library matches that.',
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
