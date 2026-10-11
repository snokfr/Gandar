import '../models/cache_entry.dart';
import '../models/play_record.dart';
import '../models/playlist.dart';
import '../models/resolved_stream.dart';
import '../models/track.dart';

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

  /// Stores [tracks] as the complete contents of [playlist], in this order.
  ///
  /// Replaces whatever was stored before, and adds the playlist summary, so an
  /// import is idempotent: importing the same link twice does not duplicate
  /// rows. Tracks already in the library keep their metadata.
  Future<void> replacePlaylistTracks(String playlistId, List<Track> tracks);

  /// The locally stored contents of [playlist], in playlist order. Empty when
  /// the playlist was never imported.
  Future<List<Track>> cachedPlaylistTracks(String playlistId);

  /// Drops [trackId] from the library, and from every playlist holding it.
  ///
  /// There is no server to tell: removing a track here removes it locally and
  /// nothing else, which is the only promise this app can keep.
  Future<void> removeTrack(String trackId);

  /// Cached tracks that still have no artwork, newest first.
  ///
  /// The artwork pass reads this, which is what makes it resumable: a track
  /// stops being returned the moment its cover is stored.
  Future<List<Track>> tracksMissingArtwork({int limit = 500});
  Future<void> recordPlay(String trackId, DateTime at);
  Future<List<String>> recentTrackIds({int limit = 50});

  /// Play history, oldest first, with durations where a track is cached.
  Future<List<PlayRecord>> playHistory();
}
