import 'dart:convert';

import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';

/// What a pasted Spotify link points at.
enum SpotifyLinkKind { track, album, playlist, artist, episode, show, unknown }

/// A Spotify entity identified without the Web API.
///
/// Everything the app does with a link — a public playlist someone sent you,
/// your own profile URL, a track copied out of the desktop app — starts here,
/// so the parsing rules live in one place and are unit-tested rather than
/// re-derived inside a page.
class SpotifyLink {
  const SpotifyLink({required this.kind, required this.id});

  final SpotifyLinkKind kind;
  final String id;

  /// Spotify's own spelling of the entity, e.g. `spotify:playlist:abc`.
  String get uri => 'spotify:${kind.name}:$id';

  String get url => 'https://open.spotify.com/${kind.name}/$id';

  /// Whether Gandar can read this kind without an account.
  bool get isReadable => const <SpotifyLinkKind>{
    SpotifyLinkKind.playlist,
    SpotifyLinkKind.album,
    SpotifyLinkKind.track,
  }.contains(kind);

  /// A sentence naming the kind, for messages.
  String get label => switch (kind) {
    SpotifyLinkKind.track => 'track',
    SpotifyLinkKind.album => 'album',
    SpotifyLinkKind.playlist => 'playlist',
    SpotifyLinkKind.artist => 'artist',
    SpotifyLinkKind.episode => 'podcast episode',
    SpotifyLinkKind.show => 'podcast',
    SpotifyLinkKind.unknown => 'link',
  };

  /// Parses anything a person is likely to paste.
  ///
  /// Accepts `spotify:playlist:ID`, `spotify:user:someone:playlist:ID`,
  /// `https://open.spotify.com/playlist/ID?si=...`, an `/embed/` or `/intl-xx/`
  /// URL, and a bare 22-character id (assumed to be a playlist, which is what
  /// a bare id almost always is when copied from a playlist page).
  static SpotifyLink? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    if (text.startsWith('spotify:')) {
      final parts = text.split(':').where((p) => p.isNotEmpty).toList();
      if (parts.length < 3) return null;
      // Legacy form: spotify:user:<name>:playlist:<id>.
      final kind = _kindOf(parts[parts.length - 2]);
      final id = parts.last;
      if (kind == null || !_looksLikeId(id)) return null;
      return SpotifyLink(kind: kind, id: id);
    }

    // A URL, or a bare id. People paste `open.spotify.com/playlist/...`
    // without a scheme as often as with one, so add it rather than refusing.
    final hasScheme = Uri.tryParse(text)?.hasScheme ?? false;
    final uri = Uri.tryParse(
      !hasScheme && text.contains('/') ? 'https://$text' : text,
    );
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final segments = uri.pathSegments
          .where((s) => s.isNotEmpty && s != 'embed' && s != 'intl')
          .where((s) => !RegExp(r'^intl-[a-z]{2}$').hasMatch(s))
          .toList();
      for (var i = 0; i < segments.length - 1; i++) {
        final kind = _kindOf(segments[i]);
        if (kind != null && _looksLikeId(segments[i + 1])) {
          return SpotifyLink(kind: kind, id: segments[i + 1]);
        }
      }
      // open.spotify.com/track/ID is the only shape that matters for music;
      // anything else with no recognisable kind is not an entity link.
      return null;
    }

    if (_looksLikeId(text)) {
      return SpotifyLink(kind: SpotifyLinkKind.playlist, id: text);
    }
    return null;
  }

  static SpotifyLinkKind? _kindOf(String segment) => switch (segment) {
    'track' => SpotifyLinkKind.track,
    'album' => SpotifyLinkKind.album,
    'playlist' => SpotifyLinkKind.playlist,
    'artist' => SpotifyLinkKind.artist,
    'episode' => SpotifyLinkKind.episode,
    'show' => SpotifyLinkKind.show,
    _ => null,
  };

  /// Spotify ids are 22 characters of base-62.
  static bool _looksLikeId(String value) =>
      RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(value);

  @override
  String toString() => uri;
}

/// A collection read from a public Spotify page: no account, no API key.
class PublicCollection {
  const PublicCollection({
    required this.link,
    required this.name,
    this.description = '',
    this.artworkUrl,
    this.ownerName,
    this.tracks = const <Track>[],
    this.trackListTruncated = false,
  });

  final SpotifyLink link;
  final String name;
  final String description;
  final String? artworkUrl;
  final String? ownerName;
  final List<Track> tracks;

  /// True when Spotify's public page only carried the first page of tracks,
  /// which is 50. It is an honest signal that the list may be incomplete.
  final bool trackListTruncated;

  /// The playlist summary to store alongside the tracks.
  Playlist toPlaylist() => Playlist(
    id: link.id,
    name: name,
    description: description,
    trackCount: tracks.length,
    artworkUrl: artworkUrl,
    ownerName: ownerName,
  );

  /// How many tracks Spotify's public page returns at most.
  static const int publicTrackLimit = 50;
}

/// Raised when a public Spotify page cannot be read.
class SpotifyPublicException implements Exception {
  SpotifyPublicException(this.message, {this.link});

  final String message;
  final SpotifyLink? link;

  @override
  String toString() => 'SpotifyPublicException: $message';
}

/// Reads the data Spotify's own embed widget is served.
///
/// The embed page (`open.spotify.com/embed/<kind>/<id>`) is server-rendered and
/// carries a `__NEXT_DATA__` JSON payload with the collection's name, artwork
/// and — for playlists and albums — up to [PublicCollection.publicTrackLimit]
/// tracks, each with title, artists, duration and a 30-second preview URL.
///
/// This is not the supported API and Spotify can change or remove it at any
/// time; [parse] therefore reports what it found instead of assuming, and the
/// caller falls back to oEmbed metadata and a clear message.
class SpotifyEmbedPage {
  const SpotifyEmbedPage();

  /// The script tag Spotify uses to hand its page its own data.
  static final RegExp _nextData = RegExp(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    dotAll: true,
  );

  /// Where the entity lives inside that payload.
  static const List<String> _entityPath = <String>[
    'props',
    'pageProps',
    'state',
    'data',
    'entity',
  ];

  /// Parses an embed page, or throws [SpotifyPublicException] explaining why.
  PublicCollection parse(String html, {required SpotifyLink link}) {
    final match = _nextData.firstMatch(html);
    if (match == null) {
      throw SpotifyPublicException(
        'Spotify did not return the playlist data. The link may be private, '
        'or Spotify may be asking for a sign-in.',
        link: link,
      );
    }

    Object? node;
    try {
      node = jsonDecode(match.group(1)!);
    } on FormatException catch (e) {
      throw SpotifyPublicException(
        'Spotify returned a page Gandar could not read ($e).',
        link: link,
      );
    }

    for (final key in _entityPath) {
      if (node is! Map) break;
      node = node[key];
    }
    if (node is! Map) {
      throw SpotifyPublicException(
        'Spotify returned no data for this ${link.label}.',
        link: link,
      );
    }

    final entity = Map<String, dynamic>.from(node);
    final name = (entity['name'] ?? entity['title'])?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw SpotifyPublicException(
        'Spotify returned an unnamed ${link.label}. It may be unavailable in '
        'your region.',
        link: link,
      );
    }

    final artwork =
        _firstSourceUrl(entity['coverArt']) ??
        _firstSourceUrl(entity['visualIdentity']);
    final tracks = _tracksFrom(entity, link: link, artworkUrl: artwork);
    final rawList = entity['trackList'];
    final truncated =
        rawList is List && rawList.length >= PublicCollection.publicTrackLimit;

    return PublicCollection(
      link: link,
      name: name,
      description: entity['description']?.toString() ?? '',
      artworkUrl: artwork,
      ownerName: _ownerNameOf(entity) ?? entity['subtitle']?.toString(),
      tracks: tracks,
      trackListTruncated: truncated,
    );
  }

  /// A single track, for a `.../track/ID` link.
  static Track? singleTrack(
    Map<String, dynamic> entity, {
    required SpotifyLink link,
    String? artworkUrl,
  }) {
    final title = (entity['title'] ?? entity['name'])?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    final artists = <String>[
      for (final artist in (entity['artists'] as List? ?? const []))
        if (artist is Map && artist['name'] != null)
          artist['name'].toString()
        else if (artist is String)
          artist,
    ];
    return Track(
      id: link.id,
      title: title,
      artists: artists.isEmpty ? _splitArtists(entity['subtitle']) : artists,
      durationMs: (entity['duration'] as num?)?.toInt() ?? 0,
      artworkUrl: artworkUrl,
    );
  }

  List<Track> _tracksFrom(
    Map<String, dynamic> entity, {
    required SpotifyLink link,
    String? artworkUrl,
  }) {
    final raw = entity['trackList'];
    if (raw is! List) {
      // An album or track page whose list is absent still describes one track.
      final single = singleTrack(entity, link: link, artworkUrl: artworkUrl);
      return single == null ? const <Track>[] : <Track>[single];
    }

    final tracks = <Track>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final uri = item['uri']?.toString() ?? '';
      final id = uri.isEmpty ? '' : uri.split(':').last;
      final title = item['title']?.toString().trim() ?? '';
      // Episodes appear in playlists; they are not music and cannot be
      // resolved by the audio pipeline, so they are skipped.
      if (item['entityType']?.toString() == 'episode') continue;
      if (id.isEmpty || title.isEmpty) continue;
      tracks.add(
        Track(
          id: id,
          title: title,
          artists: _splitArtists(item['subtitle']),
          durationMs: (item['duration'] as num?)?.toInt() ?? 0,
          // An album's tracks really do share its cover, so that artwork is
          // correct for every row. A playlist's cover is the *playlist's*, and
          // stamping it on forty-six rows reads as a broken duplicate; those
          // covers are filled in per track by the artwork pass instead.
          artworkUrl: link.kind == SpotifyLinkKind.album ? artworkUrl : null,
        ),
      );
    }
    return tracks;
  }

  /// Spotify separates artists with a comma and a non-breaking space.
  static List<String> _splitArtists(Object? subtitle) {
    final text = subtitle?.toString().replaceAll('\u00a0', ' ') ?? '';
    return text
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList(growable: false);
  }

  static String? _ownerNameOf(Map<String, dynamic> entity) {
    final owner = entity['owner'];
    if (owner is Map) {
      return owner['name']?.toString() ?? owner['displayName']?.toString();
    }
    if (owner is String && owner.isNotEmpty) return owner;
    return null;
  }

  static String? _firstSourceUrl(Object? coverArt) {
    if (coverArt is! Map) return null;
    final sources = coverArt['sources'];
    if (sources is! List || sources.isEmpty) return null;
    final first = sources.first;
    if (first is Map) return first['url']?.toString();
    return first?.toString();
  }
}

/// Spotify's public oEmbed endpoint, which needs no credentials and returns a
/// title and a cover image for any public track, album, playlist or artist.
class SpotifyOEmbed {
  const SpotifyOEmbed();

  /// Builds the request URL for [link].
  static Uri urlFor(SpotifyLink link) =>
      Uri.https('open.spotify.com', '/oembed', {'url': link.url});

  /// Reads `title` and `thumbnail_url` out of an oEmbed response.
  static ({String title, String? thumbnailUrl})? parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final title = decoded['title']?.toString();
    if (title == null || title.trim().isEmpty) return null;
    return (title: title, thumbnailUrl: decoded['thumbnail_url']?.toString());
  }
}
