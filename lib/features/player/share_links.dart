import '../../data/youtube/youtube_search.dart';
import '../../domain/models/track.dart';

/// One place a track can be shared to.
class ShareLink {
  const ShareLink({
    required this.source,
    required this.label,
    required this.url,
    this.exact = false,
  });

  /// `youtube` or `spotify`.
  final String source;

  /// What the link points at, for the row label.
  final String label;

  final String url;

  /// True when the link opens this exact track rather than a search for it.
  final bool exact;
}

/// Builds the links a track can be shared by.
///
/// Pure and network-free, so the two questions that decide the answer — *is
/// this a Spotify id?* and *do we know the YouTube video?* — are unit-tested
/// rather than buried in a button's callback.
///
/// Both services are always offered. A track imported from Spotify can have no
/// known YouTube video yet, and a track found on YouTube has no Spotify id;
/// neither case should leave the user with a button that does nothing, so the
/// fallback is a search link on the service that does not know the track.
class ShareLinks {
  const ShareLinks._();

  /// Spotify ids are 22 base-62 characters. Track ids from an import are
  /// Spotify ids; ids from YouTube search carry the `youtube:` prefix and are
  /// deliberately excluded by [youTubeVideoIdOf] first.
  static final RegExp _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');

  static bool isSpotifyId(String id) => _spotifyId.hasMatch(id);

  /// Links for [track]. [youtubeVideoId] is the permanently cached mapping when
  /// one exists, which is what turns the YouTube row into an exact link.
  static List<ShareLink> forTrack(Track track, {String? youtubeVideoId}) {
    final videoId = youTubeVideoIdOf(track.id) ?? youtubeVideoId;
    final query = track.searchQuery;
    final hasQuery = query.isNotEmpty;

    return <ShareLink>[
      ShareLink(
        source: 'youtube',
        label: videoId != null ? 'YouTube' : 'YouTube search',
        exact: videoId != null,
        url: videoId != null
            ? 'https://www.youtube.com/watch?v=$videoId'
            : 'https://www.youtube.com/results?search_query='
                  '${Uri.encodeQueryComponent(query)}',
      ),
      if (hasQuery || isSpotifyId(track.id))
        ShareLink(
          source: 'spotify',
          label: isSpotifyId(track.id) ? 'Spotify' : 'Spotify search',
          exact: isSpotifyId(track.id),
          url: isSpotifyId(track.id)
              ? 'https://open.spotify.com/track/${track.id}'
              : 'https://open.spotify.com/search/'
                    '${Uri.encodeQueryComponent(query)}',
        ),
    ];
  }

  /// One line of text with every link, for pasting into a chat.
  static String asText(Track track, List<ShareLink> links) {
    final who = track.artists.isEmpty
        ? track.title
        : '${track.artists.join(', ')} — ${track.title}';
    return <String>[
      who,
      for (final link in links) '${link.label}: ${link.url}',
    ].join('\n');
  }
}
