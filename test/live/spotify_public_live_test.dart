import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/spotify/spotify_public.dart';
import 'package:gandar/data/spotify/spotify_public_web.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/domain/models/playlist.dart';

/// Live checks against Spotify's real public pages.
///
/// Skipped by default, because a test suite that needs Spotify to be up and to
/// keep its page format is a test suite that fails for reasons the developer
/// cannot fix. Run it deliberately:
///
/// ```bash
/// flutter test --dart-define=LIVE=true test/live/spotify_public_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('LIVE');

void main() {
  test(
    'imports a real public playlist into the local library',
    () async {
      final database = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(database.close);
      final library = DriftLibraryRepository(database);

      // Spotify's own "Today's Top Hits" — public, and long enough to prove
      // the page carries a real tracklist.
      final link = SpotifyLink.parse(
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=test',
      )!;
      final collection = await SpotifyPublicWeb().fetchCollection(link);

      // ignore: avoid_print
      print(
        'LIVE: "${collection.name}" — ${collection.tracks.length} tracks'
        '${collection.trackListTruncated ? ' (hit the public page limit)' : ''}'
        '\n      artwork: ${collection.artworkUrl}'
        '\n      first:   ${collection.tracks.take(3).map((t) => '${t.title} — ${t.artists.join(', ')}').join(' | ')}',
      );

      expect(collection.name, isNotEmpty);
      expect(collection.tracks, isNotEmpty);
      expect(collection.artworkUrl, startsWith('https://'));
      expect(
        collection.tracks.every((t) => t.id.length == 22 && t.title.isNotEmpty),
        isTrue,
        reason: 'every track needs an id and a title to be playable',
      );

      await library.upsertPlaylists(<Playlist>[collection.toPlaylist()]);
      await library.replacePlaylistTracks(link.id, collection.tracks);

      final stored = await library.cachedPlaylistTracks(link.id);
      final playlists = await library.cachedPlaylists();
      final summary = playlists.singleWhere((p) => p.id == link.id);

      expect(stored, hasLength(collection.tracks.length));
      expect(stored.first.title, collection.tracks.first.title);
      expect(stored.first.artists, collection.tracks.first.artists);
      expect(summary.name, collection.name);
      expect(summary.trackCount, collection.tracks.length);

      // Importing the same link twice must not duplicate anything.
      await library.replacePlaylistTracks(link.id, collection.tracks);
      expect(
        await library.cachedPlaylistTracks(link.id),
        hasLength(stored.length),
      );
      expect(await library.cachedPlaylists(), hasLength(1));
    },
    skip: _live ? false : 'live network test; run with --dart-define=LIVE=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
