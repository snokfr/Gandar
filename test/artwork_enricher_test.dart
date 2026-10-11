import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/artwork/artwork_enricher.dart';
import 'package:gandar/data/artwork/artwork_lookup.dart';
import 'package:gandar/domain/models/play_record.dart';
import 'package:gandar/domain/models/playlist.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';

/// A source that answers from a fixed map, and counts what it was asked.
class _FakeSource implements ArtworkSource {
  _FakeSource(this.covers, {this.albumCovers = const <String, String?>{}});

  final Map<String, String?> covers;

  /// Album covers, keyed by `artist album`.
  final Map<String, String?> albumCovers;

  final List<String> asked = <String>[];
  final List<String> askedAlbums = <String>[];

  @override
  Future<String?> artworkFor(Track track) async {
    asked.add(track.searchQuery);
    if (covers.containsKey(track.searchQuery)) {
      return covers[track.searchQuery];
    }
    return null;
  }

  @override
  Future<String?> albumArtworkFor({
    required String album,
    required String artist,
  }) async {
    final key = '$artist $album';
    askedAlbums.add(key);
    return albumCovers[key];
  }
}

class _FakeLibrary implements LibraryRepository {
  _FakeLibrary(this.tracks, {this.siblingArtwork = true});

  List<Track> tracks;

  /// Whether an album mate's cover is visible to the pass. Off models a
  /// library where nothing on the album has a cover yet.
  final bool siblingArtwork;

  @override
  Future<String?> cachedArtworkForAlbum(String album) async {
    if (!siblingArtwork) return null;
    for (final track in tracks) {
      if (track.album == album &&
          track.artworkUrl != null &&
          track.artworkUrl!.isNotEmpty) {
        return track.artworkUrl;
      }
    }
    return null;
  }

  @override
  Future<List<Track>> tracksMissingArtwork({int limit = 500}) async => tracks
      .where((t) => t.artworkUrl == null || t.artworkUrl!.isEmpty)
      .take(limit)
      .toList(growable: false);

  @override
  Future<void> upsertTracks(List<Track> incoming) async {
    for (final track in incoming) {
      tracks = tracks
          .map((t) => t.id == track.id ? track : t)
          .toList(growable: false);
    }
  }

  @override
  Future<void> removeTrack(String trackId) async {
    tracks = tracks.where((t) => t.id != trackId).toList(growable: false);
  }

  @override
  Future<List<Track>> cachedLikedTracks() async => tracks;

  @override
  Future<void> upsertPlaylists(List<Playlist> playlists) async {}

  @override
  Future<List<Playlist>> cachedPlaylists() async => const [];

  @override
  Future<void> replacePlaylistTracks(String playlistId, List<Track> t) async {}

  @override
  Future<List<Track>> cachedPlaylistTracks(String playlistId) async => const [];

  @override
  Future<Playlist> createPlaylist(String name) async => Playlist(
    id: '${Playlist.localPrefix}0',
    name: name,
    isLocal: true,
  );

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {}

  @override
  Future<void> deletePlaylist(String playlistId) async {}

  @override
  Future<bool> addTrackToPlaylist(String playlistId, String trackId) async =>
      true;

  @override
  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {}

  @override
  Future<void> recordPlay(String trackId, DateTime at) async {}

  @override
  Future<List<String>> recentTrackIds({int limit = 50}) async => const [];

  @override
  Future<List<PlayRecord>> playHistory() async => const [];
}

Track _track(String title, {String? artwork}) => Track(
  id: title.hashCode.toRadixString(16),
  title: title,
  artists: const <String>['An Artist'],
  artworkUrl: artwork,
);

void main() {
  group('iTunes responses', () {
    test('reads the first result and asks for a bigger render', () {
      const body = '''
{"resultCount":1,"results":[{"trackName":"Stop The Wedding!",
"artworkUrl100":"https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/b7/55/7a/x/075679571403.jpg/100x100bb.jpg"}]}''';
      expect(
        ITunesArtwork.artworkFromSearchJson(body),
        'https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/b7/55/7a/x/075679571403.jpg/600x600bb.jpg',
      );
    });

    test('returns null when there is no match, or no JSON', () {
      expect(
        ITunesArtwork.artworkFromSearchJson('{"resultCount":0,"results":[]}'),
        isNull,
      );
      expect(ITunesArtwork.artworkFromSearchJson('<html>nope'), isNull);
    });

    test('a differently sized URL is rewritten, not duplicated', () {
      expect(
        ITunesArtwork.upscale('https://x/y/50x50bb.png', size: 300),
        'https://x/y/300x300bb.png',
      );
    });
  });

  group('the enrichment pass', () {
    test('fills in the covers it finds and reports progress', () async {
      final library = _FakeLibrary(<Track>[
        _track('Stop The Wedding!'),
        _track('Nicole Kidman'),
      ]);
      final source = _FakeSource(<String, String?>{
        'An Artist Stop The Wedding!': 'https://art/1.jpg',
        'An Artist Nicole Kidman': 'https://art/2.jpg',
      });
      final progress = <ArtworkProgress>[];

      final result = await ArtworkEnricher(
        library: library,
        source: source,
      ).run(onProgress: progress.add);

      expect(result.updated, 2);
      expect(result.missing, 0);
      expect(result.running, isFalse);
      expect(library.tracks.every((t) => t.artworkUrl != null), isTrue);
      // Progress is reported per track, and starts from the whole batch.
      expect(progress.first.total, 2);
      expect(progress.last.done, 2);
      expect(progress.any((p) => p.running), isTrue);
    });

    test('counts tracks the source has never heard of', () async {
      final library = _FakeLibrary(<Track>[
        _track('Known Song'),
        _track('Obscure Song'),
      ]);
      final source = _FakeSource(<String, String?>{
        'An Artist Known Song': 'https://art/1.jpg',
      });

      final result = await ArtworkEnricher(
        library: library,
        source: source,
      ).run();

      expect(result.updated, 1);
      expect(result.missing, 1);
      expect(source.asked, hasLength(2));
    });

    test('a second pass only looks at what is still missing', () async {
      final library = _FakeLibrary(<Track>[
        _track('Known Song'),
        _track('Obscure Song'),
      ]);
      final source = _FakeSource(<String, String?>{
        'An Artist Known Song': 'https://art/1.jpg',
      });
      final enricher = ArtworkEnricher(library: library, source: source);

      await enricher.run();
      source.asked.clear();
      final second = await enricher.run();

      // This is what makes the pass resumable after a restart.
      expect(source.asked, <String>['An Artist Obscure Song']);
      expect(second.updated, 0);
      expect(second.missing, 1);
    });

    test('is cancellable, keeping the work already done', () async {
      final library = _FakeLibrary(<Track>[
        _track('One'),
        _track('Two'),
        _track('Three'),
      ]);
      final source = _FakeSource(<String, String?>{
        'An Artist One': 'https://art/1.jpg',
        'An Artist Two': 'https://art/2.jpg',
        'An Artist Three': 'https://art/3.jpg',
      });
      late ArtworkEnricher enricher;
      enricher = ArtworkEnricher(library: library, source: source);

      final result = await enricher.run(
        onProgress: (progress) {
          if (progress.done == 1) enricher.stop();
        },
      );

      expect(result.running, isFalse);
      expect(result.note, contains('Stopped'));
      expect(result.updated, 1);
      expect(library.tracks.where((t) => t.artworkUrl != null), hasLength(1));
    });

    test('a track with no cover inherits its album mate\'s', () async {
      final library = _FakeLibrary(<Track>[
        Track(
          id: 'a',
          title: 'Cold Water',
          artists: const <String>['Major Lazer'],
          album: 'Cold Water',
        ),
        Track(
          id: 'b',
          title: 'Cold Water (Remix)',
          artists: const <String>['Major Lazer'],
          album: 'Cold Water',
        ),
      ]);
      // The catalogue knows the track but not the remix. The remix should not
      // even be asked about it: the album mate's cover already answers it.
      final source = _FakeSource(<String, String?>{
        'Major Lazer Cold Water': 'https://art/track.jpg',
      });

      final result = await ArtworkEnricher(
        library: library,
        source: source,
      ).run();

      expect(result.updated, 2);
      expect(result.missing, 0);
      expect(library.tracks[0].artworkUrl, 'https://art/track.jpg');
      expect(library.tracks[1].artworkUrl, 'https://art/track.jpg');
      expect(source.askedAlbums, isEmpty);
    });

    test('falls back to the album cover when nothing else has one', () async {
      final library = _FakeLibrary(
        <Track>[
          Track(
            id: 'a',
            title: 'B-Side No One Indexed',
            artists: const <String>['An Artist'],
            album: 'An Album',
          ),
        ],
        siblingArtwork: false,
      );
      final source = _FakeSource(
        const <String, String?>{},
        albumCovers: <String, String?>{
          'An Artist An Album': 'https://art/album.jpg',
        },
      );

      final result = await ArtworkEnricher(
        library: library,
        source: source,
      ).run();

      // The point of the fallback: a track the catalogue has never heard of
      // still gets the picture it is filed under, instead of a blank square.
      expect(result.updated, 1);
      expect(result.missing, 0);
      expect(library.tracks.single.artworkUrl, 'https://art/album.jpg');
    });

    test('asks for an album cover once, not once per track', () async {
      final library = _FakeLibrary(
        <Track>[
          Track(
            id: 'a',
            title: 'One',
            artists: const <String>['An Artist'],
            album: 'An Album',
          ),
          Track(
            id: 'b',
            title: 'Two',
            artists: const <String>['An Artist'],
            album: 'An Album',
          ),
        ],
        siblingArtwork: false,
      );
      final source = _FakeSource(
        const <String, String?>{},
        albumCovers: <String, String?>{
          'An Artist An Album': 'https://art/album.jpg',
        },
      );

      await ArtworkEnricher(library: library, source: source).run();

      expect(source.askedAlbums, hasLength(1));
      expect(library.tracks.every((t) => t.artworkUrl == 'https://art/album.jpg'), isTrue);
    });

    test('a source that throws is a missing cover, not a crash', () async {
      final library = _FakeLibrary(<Track>[_track('Boom')]);
      final result = await ArtworkEnricher(
        library: library,
        source: _ExplodingSource(),
      ).run();

      expect(result.missing, 1);
      expect(result.updated, 0);
    });
  });
}

class _ExplodingSource implements ArtworkSource {
  @override
  Future<String?> artworkFor(Track track) async => throw StateError('nope');

  @override
  Future<String?> albumArtworkFor({
    required String album,
    required String artist,
  }) async => throw StateError('nope');
}
