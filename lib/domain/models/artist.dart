import 'track.dart';

/// Everything this library holds by one artist.
///
/// Derived, like [Album] and for the same reason: every track already names its
/// artists, so "what has this artist done" is a filter over the library rather
/// than a second copy of it that could disagree with what every other screen
/// shows.
class Artist {
  const Artist({required this.name, required this.tracks, this.artworkUrl});

  /// The name as the music writes it, not as it was typed into a route.
  final String name;

  /// The library's tracks that credit this artist, in library order.
  final List<Track> tracks;

  /// Artwork of the first track that has any.
  final String? artworkUrl;

  int get trackCount => tracks.length;

  /// Total playing time of what is here, which is everything this artist has
  /// *in this library* — not their catalogue.
  Duration get duration =>
      tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  /// The albums of theirs that are in the library, each named once, in the
  /// order the tracks were liked.
  List<String> get albums {
    final seen = <String>{};
    final out = <String>[];
    for (final track in tracks) {
      final album = track.album?.trim() ?? '';
      if (album.isEmpty) continue;
      if (!seen.add(album.toLowerCase())) continue;
      out.add(album);
    }
    return List<String>.unmodifiable(out);
  }

  /// The key a route carries. Names are what every track agrees on; there is no
  /// artist id in the library to use instead.
  String get id => name;

  /// The library's tracks by [name], as an [Artist].
  ///
  /// Matching is case-insensitive and against the *split* artist list, because
  /// the stored field is one string holding all of them:
  ///
  ///   * a substring test would put Ariana Grande's songs on a page for "Ari";
  ///   * an equality test on the whole field would miss every track that names
  ///     a guest before the headliner.
  ///
  /// The spelling that comes back is the library's own, so a route typed in
  /// lower case still displays the name the way the music does.
  static Artist of(List<Track> library, String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) {
      return const Artist(name: '', tracks: <Track>[]);
    }

    final tracks = <Track>[];
    var spelling = name.trim();
    for (final track in library) {
      String? match;
      for (final credited in track.artists) {
        final trimmed = credited.trim();
        if (trimmed.toLowerCase() != wanted) continue;
        match = trimmed;
        break;
      }
      if (match == null) continue;
      if (tracks.isEmpty) spelling = match;
      tracks.add(track);
    }

    return Artist(
      name: spelling,
      tracks: List<Track>.unmodifiable(tracks),
      artworkUrl: tracks
          .map((t) => t.artworkUrl)
          .firstWhere(
            (url) => url != null && url.isNotEmpty,
            orElse: () => null,
          ),
    );
  }
}
