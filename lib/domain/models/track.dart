/// A Spotify track, normalized into the small shape Gandar actually uses.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artists,
    this.album,
    this.durationMs = 0,
    this.artworkUrl,
    this.isrc,
    this.addedAt,
  });

  /// Spotify track id.
  final String id;
  final String title;
  final List<String> artists;
  final String? album;
  final int durationMs;
  final String? artworkUrl;

  /// International Standard Recording Code, when Spotify exposes it. Useful as
  /// a higher-confidence YouTube match key than free-text search.
  final String? isrc;

  final DateTime? addedAt;

  String get primaryArtist => artists.isEmpty ? '' : artists.first;

  /// The query used to search YouTube when no cached mapping exists.
  String get searchQuery =>
      [primaryArtist, title].where((s) => s.trim().isNotEmpty).join(' ').trim();

  Duration get duration => Duration(milliseconds: durationMs);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artists': artists,
    'album': album,
    'durationMs': durationMs,
    'artworkUrl': artworkUrl,
    'isrc': isrc,
    'addedAt': addedAt?.toIso8601String(),
  };

  static Track fromJson(Map<String, dynamic> j) {
    final artistsRaw = j['artists'];
    return Track(
      id: j['id'] as String,
      title: j['title'] as String? ?? 'Unknown',
      artists: artistsRaw is List
          ? artistsRaw.map((a) => a.toString()).toList(growable: false)
          : const <String>[],
      album: j['album'] as String?,
      durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      artworkUrl: j['artworkUrl'] as String?,
      isrc: j['isrc'] as String?,
      addedAt: j['addedAt'] != null
          ? DateTime.tryParse(j['addedAt'] as String)
          : null,
    );
  }

  /// Maps Spotify's `/me/tracks` (and playlist item) track object.
  static Track fromSpotify(Map<String, dynamic> json) {
    final artists = (json['artists'] as List? ?? const [])
        .map((a) => (a as Map)['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final albumMap = json['album'] as Map?;
    final images = (albumMap?['images'] as List? ?? const []);

    return Track(
      id: json['id']?.toString() ?? '',
      title: json['name']?.toString() ?? 'Unknown',
      artists: artists,
      album: albumMap?['name']?.toString(),
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      artworkUrl: images.isNotEmpty
          ? (images.last as Map)['url']?.toString()
          : null,
      isrc: (json['external_ids'] as Map?)?['isrc']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
