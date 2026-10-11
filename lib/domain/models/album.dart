import 'track.dart';

/// A group of library tracks that came from the same album.
///
/// Albums are derived rather than stored: every imported track already carries
/// its album name, so grouping *is* the feature, and a group recomputed from the
/// library can never disagree with the library.
class Album {
  const Album({
    required this.name,
    required this.artist,
    required this.tracks,
    this.artworkUrl,
  });

  /// The album title, as the import gave it.
  final String name;

  /// The artist the album is filed under: the one most of its tracks name, so a
  /// record with guests on half its tracks is not renamed by whichever track
  /// happens to come first.
  final String artist;

  /// The album's tracks, in library order.
  final List<Track> tracks;

  /// Artwork of the first track that has any.
  final String? artworkUrl;

  int get trackCount => tracks.length;

  /// Total playing time of what is here, which is a floor rather than the
  /// album's real length: a library only ever holds the tracks that were
  /// imported.
  Duration get duration => tracks.fold(
    Duration.zero,
    (sum, track) => sum + track.duration,
  );

  /// A key that survives a route: titles are not unique on their own. Two
  /// different records called "Greatest Hits" are still one shelf here, which is
  /// the same grouping the album name implies everywhere else.
  String get id => name;

  /// Groups [tracks] by album name.
  ///
  /// Tracks with no album name are left out — an import that never carried the
  /// field should not produce an album called "Unknown" — and the result is
  /// ordered like a shelf: by artist, then by album.
  static List<Album> group(List<Track> tracks) {
    final byName = <String, List<Track>>{};
    for (final track in tracks) {
      final name = track.album?.trim() ?? '';
      if (name.isEmpty) continue;
      byName.putIfAbsent(name, () => <Track>[]).add(track);
    }

    final albums = byName.entries.map((entry) {
      final grouped = entry.value;
      return Album(
        name: entry.key,
        artist: _dominantArtist(grouped),
        tracks: List<Track>.unmodifiable(grouped),
        artworkUrl: grouped
            .map((t) => t.artworkUrl)
            .firstWhere((url) => url != null && url.isNotEmpty, orElse: () => null),
      );
    }).toList();

    albums.sort((a, b) {
      final byArtist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (byArtist != 0) return byArtist;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List<Album>.unmodifiable(albums);
  }

  /// The primary artist credited on most of [tracks].
  ///
  /// Ties break alphabetically so the answer does not depend on track order.
  static String _dominantArtist(List<Track> tracks) {
    final counts = <String, int>{};
    for (final track in tracks) {
      final artist = track.primaryArtist.trim();
      if (artist.isEmpty) continue;
      counts[artist] = (counts[artist] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    return ranked.first.key;
  }
}
