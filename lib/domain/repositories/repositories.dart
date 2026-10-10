import '../models/cache_entry.dart';
import '../models/playlist.dart';
import '../models/resolved_stream.dart';
import '../models/track.dart';

/// Metadata layer backed by the Spotify Web API.
abstract class SpotifyRepository {
  Future<bool> isAuthenticated();

  /// Signs in via Authorization Code + PKCE and stores tokens.
  Future<void> signIn();

  Future<void> signOut();

  /// Paged: [offset]/[limit] follow Spotify's pagination.
  Future<List<Track>> getLikedTracks({int offset = 0, int limit = 50});

  Future<List<Playlist>> getPlaylists({int offset = 0, int limit = 50});

  Future<List<Track>> getPlaylistTracks(
    String playlistId, {
    int offset = 0,
    int limit = 100,
  });

  Future<void> saveTrack(String trackId);

  Future<void> removeTrack(String trackId);
}

/// Audio extraction layer. Implementations resolve a [Track] to a playable
/// direct stream. Deliberately swappable because YouTube extraction is fragile.
abstract class AudioResolver {
  /// Resolves a stream, preferring a previously cached mapping.
  Future<ResolvedStream> resolve(Track track);
}

/// Persists Spotify -> YouTube mappings permanently so repeat plays are instant.
abstract class MappingRepository {
  Future<String?> findVideoId(String spotifyTrackId);
  Future<void> saveMapping(String spotifyTrackId, String videoId);
  Future<void> clearMapping(String spotifyTrackId);
}

/// Tracks cached audio files for LRU eviction.
abstract class CacheRepository {
  Future<List<CacheEntry>> all();
  Future<CacheEntry?> find(String videoId);
  Future<void> put(CacheEntry entry);
  Future<void> touch(String videoId, DateTime at);
  Future<void> remove(String videoId);
}

/// Local library cache (tracks + playlists) for offline-first listing.
abstract class LibraryRepository {
  Future<void> upsertTracks(List<Track> tracks);
  Future<List<Track>> cachedLikedTracks();
  Future<void> upsertPlaylists(List<Playlist> playlists);
  Future<List<Playlist>> cachedPlaylists();
  Future<void> recordPlay(String trackId, DateTime at);
  Future<List<String>> recentTrackIds({int limit = 50});
}
