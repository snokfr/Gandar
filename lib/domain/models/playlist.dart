/// A Spotify playlist summary.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    this.trackCount = 0,
    this.artworkUrl,
    this.ownerName,
    this.isCollaborative = false,
  });

  final String id;
  final String name;
  final String description;
  final int trackCount;
  final String? artworkUrl;
  final String? ownerName;
  final bool isCollaborative;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'trackCount': trackCount,
    'artworkUrl': artworkUrl,
    'ownerName': ownerName,
    'isCollaborative': isCollaborative,
  };

  static Playlist fromJson(Map<String, dynamic> j) => Playlist(
    id: j['id'] as String,
    name: j['name'] as String? ?? 'Playlist',
    description: j['description'] as String? ?? '',
    trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
    artworkUrl: j['artworkUrl'] as String?,
    ownerName: j['ownerName'] as String?,
    isCollaborative: j['isCollaborative'] as bool? ?? false,
  );

  static Playlist fromSpotify(Map<String, dynamic> json) {
    final images = json['images'] as List? ?? const [];
    final tracks = json['tracks'] as Map?;
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Playlist',
      description: json['description']?.toString() ?? '',
      trackCount: (tracks?['total'] as num?)?.toInt() ?? 0,
      artworkUrl: images.isNotEmpty
          ? (images.first as Map)['url']?.toString()
          : null,
      ownerName: (json['owner'] as Map?)?['display_name']?.toString(),
      isCollaborative: json['collaborative'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Playlist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
