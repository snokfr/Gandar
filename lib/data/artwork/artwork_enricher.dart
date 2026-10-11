import '../../core/logging/app_logger.dart';
import '../../domain/models/track.dart';
import '../../domain/repositories/repositories.dart';
import 'artwork_lookup.dart';

/// How a bulk artwork pass is going.
class ArtworkProgress {
  const ArtworkProgress({
    required this.done,
    required this.total,
    required this.updated,
    required this.missing,
    this.running = true,
    this.note,
  });

  /// Tracks examined so far.
  final int done;

  /// Tracks that were missing artwork when the pass started.
  final int total;

  /// Tracks that gained artwork.
  final int updated;

  /// Tracks the source had nothing for.
  final int missing;

  final bool running;

  /// Set when the pass stopped for a reason worth showing.
  final String? note;

  double get fraction => total == 0 ? 1 : (done / total).clamp(0, 1).toDouble();

  ArtworkProgress copyWith({
    int? done,
    int? updated,
    int? missing,
    bool? running,
    String? note,
  }) => ArtworkProgress(
    done: done ?? this.done,
    total: total,
    updated: updated ?? this.updated,
    missing: missing ?? this.missing,
    running: running ?? this.running,
    note: note ?? this.note,
  );
}

/// Fills in missing album artwork for tracks already in the library.
///
/// This is the "port a lot of stuff over at a time" half of importing: a
/// playlist gives titles and artists in one request, and the covers arrive
/// afterwards, one polite request at a time. Each track gets the best cover
/// available to it — see [_coverFor], which borrows an album's cover rather
/// than giving up when a track has no artwork of its own.
///
/// Three properties matter more than speed here:
///
/// * **It paces itself.** Requests go through a [HostGovernor] with a token
///   bucket set to the source's documented rate, so a 46-track playlist cannot
///   look like an attack and cannot get the app throttled.
/// * **It is resumable.** Only tracks with no artwork are selected, and each
///   result is written as soon as it arrives, so stopping — or crashing —
///   loses nothing and the next run continues where this one stopped.
/// * **It is cancellable.** [stop] ends the pass without discarding progress.
class ArtworkEnricher {
  ArtworkEnricher({
    required this.library,
    required this.source,
    this.batchSize = 500,
  });

  final LibraryRepository library;
  final ArtworkSource source;

  /// How many tracks to consider in one pass. The library can be large; this
  /// only bounds the initial query, not what a later pass will pick up.
  final int batchSize;

  bool _stopRequested = false;

  /// Asks the running pass to finish the current request and stop.
  void stop() => _stopRequested = true;

  /// The best cover available for [track], trying the cheapest answer first.
  ///
  /// Three rungs, in order:
  ///
  /// 1. **A sibling on the same album** that already has a cover. A local
  ///    database read — instant, offline and almost always right, since an
  ///    imported album's tracks share one image.
  /// 2. **The track's own cover**, from the catalogue.
  /// 3. **The album's cover.** This is the case the per-track search has no
  ///    answer for: compilations, tracks whose title carries a feature suffix
  ///    the catalogue does not use, and anything never released under its own
  ///    name. Rather than leave a blank square, the row gets the picture it is
  ///    filed under.
  ///
  /// Steps 1 and 3 are what make a large import stop producing empty tiles:
  /// one cover is fetched and the rest of the album inherits it.
  Future<String?> _coverFor(
    Track track,
    Map<String, String?> albumCache,
  ) async {
    final album = track.album?.trim() ?? '';

    if (album.isNotEmpty) {
      try {
        final sibling = await library.cachedArtworkForAlbum(album);
        if (sibling != null && sibling.isNotEmpty) return sibling;
      } catch (e) {
        AppLogger.instance.debug(
          'artwork',
          'sibling lookup failed for "$album": $e',
        );
      }
    }

    try {
      final own = await source.artworkFor(track);
      if (own != null && own.isNotEmpty) return own;
    } catch (e) {
      AppLogger.instance.debug('artwork', 'lookup threw for ${track.id}: $e');
    }

    if (album.isEmpty) return null;
    if (albumCache.containsKey(album)) return albumCache[album];

    String? cover;
    try {
      cover = await source.albumArtworkFor(
        album: album,
        artist: track.primaryArtist,
      );
    } catch (e) {
      AppLogger.instance.debug(
        'artwork',
        'album lookup threw for "$album": $e',
      );
    }
    albumCache[album] = cover;
    return cover;
  }

  /// Runs one pass, reporting progress as it goes.
  ///
  /// Never throws: a failure to fetch one cover is a cosmetic problem, and
  /// reporting it as a crash would be worse than the missing image.
  Future<ArtworkProgress> run({
    void Function(ArtworkProgress)? onProgress,
    int? limit,
  }) async {
    _stopRequested = false;

    List<Track> pending;
    try {
      pending = await library.tracksMissingArtwork(limit: limit ?? batchSize);
    } catch (e) {
      AppLogger.instance.warn('artwork', 'could not list tracks', error: e);
      return ArtworkProgress(
        done: 0,
        total: 0,
        updated: 0,
        missing: 0,
        running: false,
        note: 'Could not read the library: $e',
      );
    }

    var progress = ArtworkProgress(
      done: 0,
      total: pending.length,
      updated: 0,
      missing: 0,
    );
    onProgress?.call(progress);
    AppLogger.instance.info(
      'artwork',
      'pass starting: ${pending.length} tracks need artwork',
    );

    // Album covers, resolved at most once per album per pass. A key present
    // with a null value means "asked, and the catalogue had nothing", which is
    // worth remembering so forty tracks of one album do not ask forty times.
    final albumCache = <String, String?>{};

    for (final track in pending) {
      if (_stopRequested) break;
      final url = await _coverFor(track, albumCache);

      if (url != null && url.isNotEmpty) {
        try {
          // Write immediately: that is what makes the pass resumable.
          await library.upsertTracks(<Track>[track.withArtwork(url)]);
          progress = progress.copyWith(updated: progress.updated + 1);
        } catch (e) {
          AppLogger.instance.warn(
            'artwork',
            'could not store artwork for ${track.id}',
            error: e,
          );
        }
      } else {
        progress = progress.copyWith(missing: progress.missing + 1);
      }

      progress = progress.copyWith(done: progress.done + 1);
      onProgress?.call(progress);
    }

    final finished = progress.copyWith(
      running: false,
      note: _stopRequested
          ? 'Stopped after ${progress.done} of ${progress.total}.'
          : null,
    );
    onProgress?.call(finished);
    AppLogger.instance.info(
      'artwork',
      'pass done: ${finished.updated} covers found, '
          '${finished.missing} not found, ${finished.done}/${finished.total} tried',
    );
    return finished;
  }
}
