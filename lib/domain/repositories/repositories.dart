import '../../core/settings/playback_settings.dart';
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

  /// Tells the resolver how much bandwidth it may spend per track.
  ///
  /// Only a resolver that chooses between several published streams has
  /// anything to do here; one that produces a single stream ignores it. It
  /// exists so the quality setting is not quietly dropped by the one resolver
  /// that can honour it.
  void setAudioQuality(AudioQuality quality);
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

  /// Creates an empty playlist owned by this app.
  Future<Playlist> createPlaylist(String name);

  /// Renames a playlist. A blank name is ignored rather than stored.
  Future<void> renamePlaylist(String playlistId, String name);

  /// Removes a playlist and its membership rows. The tracks themselves stay in
  /// the library — deleting a playlist must never delete music.
  Future<void> deletePlaylist(String playlistId);

  /// Appends [trackId] to [playlistId] and returns true, or returns false when
  /// the track was already in it.
  Future<bool> addTrackToPlaylist(String playlistId, String trackId);

  /// Drops [trackId] from [playlistId], keeping the order of the rest.
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId);

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

  /// Artwork already stored for any track on [album], if one has it.
  ///
  /// The first rung of the artwork fallback ladder: an imported album's tracks
  /// share a cover, so one track having it means the rest can have it too —
  /// instantly, offline, and without asking a stranger's API. Defaults to null
  /// so an in-memory fake with no data needs no extra work.
  Future<String?> cachedArtworkForAlbum(String album) async => null;
  Future<void> recordPlay(String trackId, DateTime at);
  Future<List<String>> recentTrackIds({int limit = 50});

  /// Play history, oldest first, with durations where a track is cached.
  Future<List<PlayRecord>> playHistory();
}
