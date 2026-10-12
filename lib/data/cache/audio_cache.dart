import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/settings/playback_settings.dart';
import '../../core/storage/app_directory.dart';
import '../../domain/models/cache_entry.dart';
import '../../domain/models/resolved_stream.dart';
import '../../domain/models/track.dart';
import '../../domain/repositories/repositories.dart';
import '../youtube/youtube_search.dart';

/// Fetches a stream URL to a file, abstracted so the cache can be tested
/// without a network or a CDN.
abstract class AudioDownloader {
  /// Writes [url] to [destination], replacing anything already there.
  Future<void> download(
    String url,
    Map<String, String> headers,
    File destination,
  );
}

/// The real one: one GET per track, straight to disk.
///
/// Deliberately not routed through the YouTube request gate. That gate exists
/// to stop Gandar hammering YouTube's *API* while resolving and searching;
/// these are plain GETs to a CDN host that is built to serve media, and making
/// them queue behind search requests would only make caching slower.
class DioAudioDownloader implements AudioDownloader {
  DioAudioDownloader([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              // A CDN that has gone quiet should not hold a slot forever.
              receiveTimeout: const Duration(minutes: 2),
              connectTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  @override
  Future<void> download(
    String url,
    Map<String, String> headers,
    File destination,
  ) async {
    await _dio.download(
      url,
      destination.path,
      options: Options(headers: headers.isEmpty ? null : headers),
    );
  }
}

/// Keeps the audio of tracks that have already been played, so playing them
/// again costs no network at all.
///
/// The pieces for this were all here and unused: [CacheRepository] has had
/// `put`/`find`/`touch`/`remove` since the beginning, [CacheManager] enforces
/// the size and idle limits on startup, [CacheEntry.lastPlayedAt] is documented
/// as the LRU order, [ResolvedStream.fileExtension] exists to name the file, and
/// the Savings view has been reporting a cache of zero the entire time. Nothing
/// ever wrote one. This is the writing half.
///
/// Two decisions worth stating:
///
///   * **Downloading happens after playback, never before it.** The track starts
///     from the network URL the resolver already has, and the file is fetched
///     alongside. Waiting for a 3 MB download before the first note would trade
///     a problem nobody has (a slow second play) for one everybody notices.
///   * **The cache is keyed by video id, and only ever reached through a
///     mapping.** A cached file is only playable if the store still says which
///     video this track resolves to, so a re-resolution that lands on a
///     different video stops using the old file rather than playing the wrong
///     audio.
class AudioCache {
  AudioCache({
    required this.repository,
    required this.downloader,
    this.directory = AppDirectory.cacheDirectory,
    this.clock = DateTime.now,
    this.afterStore,
  });

  /// Where the rows that describe the files on disk are kept.
  final CacheRepository repository;

  /// How a stream URL becomes a file.
  final AudioDownloader downloader;

  /// Where the files go. A function, not a directory, so a test can hand over a
  /// temporary one without an app-support lookup.
  final Future<Directory> Function() directory;

  final DateTime Function() clock;

  /// Called after a file is successfully stored, so the size limit is enforced
  /// during a session rather than only at the next launch.
  final Future<void> Function()? afterStore;

  /// Downloads started and not yet finished, so no video is fetched twice and a
  /// test can wait for the quiet.
  final Set<Future<void>> _inFlight = <Future<void>>{};

  final Set<String> _storing = <String>{};

  /// Completes when nothing is being downloaded at the moment of asking.
  Future<void> get idle => Future.wait(_inFlight.toList(growable: false));

  /// Whether [videoId] is being downloaded right now.
  bool isStoring(String videoId) => _storing.contains(videoId);

  /// A playable stream backed by the file for [videoId], or null when there is
  /// none — including when the table remembers a file that is no longer there,
  /// which is removed rather than trusted.
  Future<ResolvedStream?> find(String videoId, {String? title}) async {
    if (videoId.isEmpty) return null;
    final entry = await repository.find(videoId);
    if (entry == null) return null;

    final file = File(entry.filePath);
    final size = await file.exists() ? await file.length() : 0;
    if (size == 0) {
      // The row outlived the file — a manual delete, a cleanup tool, a failed
      // download. Forgetting it now keeps the Savings figures honest and frees
      // the vault.
      AppLogger.instance.info(
        'cache',
        'forgetting $videoId: ${entry.filePath} is gone',
      );
      await repository.remove(videoId);
      return null;
    }

    // Playing a cached file is a real play, so it moves up the LRU order and
    // protects the file from the idle rule.
    unawaited(repository.touch(videoId, clock()));

    return ResolvedStream(
      url: file.path,
      videoId: videoId,
      container: p.extension(entry.filePath).replaceFirst('.', ''),
      sizeBytes: size,
      title: title,
    );
  }

  /// Starts caching [stream] in the background. Returns immediately: this is an
  /// optimization for next time, never something to wait for.
  void store(String videoId, ResolvedStream stream) {
    if (videoId.isEmpty || stream.url.isEmpty) return;
    if (_storing.contains(videoId)) return;
    _storing.add(videoId);
    final started = _store(videoId, stream);
    _inFlight.add(started);
    unawaited(
      started.whenComplete(() {
        _storing.remove(videoId);
        _inFlight.remove(started);
      }),
    );
  }

  Future<void> _store(String videoId, ResolvedStream stream) async {
    File? partial;
    try {
      if (await repository.find(videoId) != null) return;

      final target = File(
        p.join((await directory()).path, '$videoId.${stream.fileExtension}'),
      );
      partial = File('${target.path}.part');
      if (await partial.exists()) await partial.delete();

      await downloader.download(stream.url, stream.headers, partial);

      final size = await partial.length();
      if (size <= 0) {
        AppLogger.instance.warn('cache', '$videoId downloaded to nothing');
        return;
      }

      // Renamed last. A file that is only half here must never be findable, or
      // the next play would use a truncated track.
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      partial = null;

      await repository.put(
        CacheEntry(
          videoId: videoId,
          filePath: target.path,
          sizeBytes: size,
          lastPlayedAt: clock(),
        ),
      );
      AppLogger.instance.info(
        'cache',
        'stored $videoId (${(size / 1024 / 1024).toStringAsFixed(1)} MB)',
      );

      final after = afterStore;
      if (after != null) await after();
    } catch (e) {
      // Caching is best effort in every direction: a track that will not
      // download still plays from the network, and a full disk is not an error
      // the person listening can do anything about.
      AppLogger.instance.warn('cache', 'could not cache $videoId', error: e);
    } finally {
      if (partial != null) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {
          // A leftover .part file is harmless and gets overwritten next time.
        }
      }
    }
  }
}

/// An [AudioResolver] that answers from the disk when it can.
///
/// Wraps the YouTube resolver rather than living inside it, because "where does
/// this audio come from" and "how do we get audio out of YouTube" are different
/// questions, and the extraction half is fragile enough already.
class CachedAudioResolver implements AudioResolver {
  CachedAudioResolver({
    required this.inner,
    required this.cache,
    required this.mappings,
  });

  final AudioResolver inner;
  final AudioCache cache;
  final MappingRepository mappings;

  int _hits = 0;

  /// How many tracks were answered from disk, for the diagnostics and tests.
  int get hits => _hits;

  @override
  Future<ResolvedStream> resolve(Track track) async {
    final videoId = await _knownVideoId(track);
    if (videoId != null) {
      final cached = await cache.find(videoId, title: track.title);
      if (cached != null) {
        _hits++;
        AppLogger.instance.debug(
          'cache',
          'playing ${track.title} from disk (${cached.sizeBytes} bytes)',
        );
        return cached;
      }
    }

    final stream = await inner.resolve(track);
    // Cached under the video the resolver actually chose, which is also what
    // gets saved to the mapping — so the two always agree about which file
    // belongs to this track.
    cache.store(stream.videoId, stream);
    return stream;
  }

  @override
  void setAudioQuality(AudioQuality quality) => inner.setAudioQuality(quality);

  /// The video id this track already has on record: named outright when the
  /// track came from YouTube, otherwise whatever the store mapped it to.
  ///
  /// Both sources only ever describe a *previous* resolution. A track that has
  /// never been played has no id here, which is exactly when there is nothing
  /// cached to find.
  Future<String?> _knownVideoId(Track track) async {
    final direct = youTubeVideoIdOf(track.id);
    if (direct != null) return direct;
    final mapped = await mappings.findVideoId(track.id);
    return (mapped == null || mapped.isEmpty) ? null : mapped;
  }
}
