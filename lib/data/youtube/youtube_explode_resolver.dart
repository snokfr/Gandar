import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/playback_settings.dart';
import '../../domain/models/resolved_stream.dart';
import '../../domain/models/track.dart';
import '../../domain/repositories/repositories.dart';
import 'audio_stream_selector.dart';
import 'stream_health.dart';
import 'youtube_search.dart';

/// Raised when no playable audio stream could be resolved for a track.
class AudioResolutionException implements Exception {
  AudioResolutionException(this.message, {this.track, this.cause});
  final String message;
  final Track? track;
  final Object? cause;

  @override
  String toString() {
    final where = track == null ? '' : ' (${track!.searchQuery})';
    final why = cause == null ? '' : ' — $cause';
    return 'AudioResolutionException: $message$why$where';
  }
}

/// True when YouTube refused the request itself — rate limiting, a bot wall, a
/// 5xx — rather than this particular video being unusable.
///
/// The difference decides what to do next. An unusable video is worth skipping
/// to the next candidate; a refusal will hit every candidate and every track
/// after it, so the only useful responses are to stop asking and to say so.
bool isYouTubeRefusal(Object error) => refusalMessage(error) != null;

/// What [error] means for the person waiting to hear music, or null when the
/// error is only about this particular video.
///
/// Kept public so the UI and the tests can ask the same question the resolver
/// asks, and so a refusal never has to be recognised by matching strings at
/// three different layers.
String? refusalMessage(Object error) {
  if (error is RequestLimitExceededException ||
      error is FatalFailureException ||
      error is TransientFailureException ||
      error is HttpClientClosedException) {
    return 'YouTube is refusing Gandar\'s requests right now (rate limited or '
        'blocked). Nothing can play until it lifts — this is YouTube\'s '
        'answer, not a problem with your library.';
  }
  // A request YouTube does not trust comes back as an unplayable video whose
  // reason is a sign-in demand. That is about the request, not the track, and
  // it would repeat for every track in the queue.
  if (error is VideoUnplayableException && _botWall.hasMatch(error.message)) {
    return 'YouTube is asking Gandar to prove it is not a bot, and it will '
        'ask the same for every track. Playback is blocked until that lifts — '
        'this is YouTube\'s answer, not a problem with your library.';
  }
  return null;
}

/// YouTube's wording for the two ways it says "I do not trust this client".
final _botWall = RegExp(r'sign in to confirm|not a bot', caseSensitive: false);

/// The player client whose stream URLs YouTube still serves in full.
///
/// This is the whole reason audio plays at all. Measured against a real track
/// (`tool/client_matrix.dart`), every other client fails in one of two ways:
///
///   * `IOS` and `ANDROID` do hand out stream URLs, but googlevideo serves
///     only about the first megabyte of them: a bare GET or HEAD is answered
///     403, and so is any range past that limit. No player can stream a
///     three-minute track from that, which is exactly how the queue used to
///     race through tracks in silence. Those URLs are missing the PO token
///     YouTube now demands for those clients.
///   * `TVHTML5`, `WEB`, `MWEB` and the embedded players answer the player
///     request with a bot wall ("Sign in to confirm you're not a bot") or
///     plain "unplayable".
///
/// `VISIONOS` answers normally and its URLs serve the whole file, so it is the
/// one client worth a request.
YoutubeApiClient visionOsClient() => YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice14,1',
        'osName': 'visionOS',
        'osVersion': '2.0.0.21O209',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 '
            '(KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)',
        'hl': 'en',
        'timeZone': 'UTC',
        'gl': 'US',
        'utcOffsetMinutes': 0,
      },
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  // `youtube_explode_dart` puts the client's *name* in X-Youtube-Client-Name;
  // YouTube wants its number. `client.headers` is spread last into the request
  // headers, so this is the one place the number can be set from outside.
  headers: <String, String>{
    'X-Youtube-Client-Name': '101',
    'X-Youtube-Client-Version': '1.02',
  },
);

/// The player clients worth trying, best first.
///
/// [visionOsClient] is the one measured to work today; the others are what is
/// left if YouTube stops serving it. Which of them works is *measured*, not
/// assumed: a client is only trusted after [StreamHealth] confirms its URL
/// really streams, so this order is a starting point rather than a belief that
/// has to be edited by hand the next time YouTube moves.
List<YoutubeApiClient> defaultYoutubeClients() => <YoutubeApiClient>[
  visionOsClient(),
  // Both of these answer the player request, and hand out URLs that stop after
  // the first megabyte. They are here because "stops after a megabyte" is a
  // PO-token rule that could change, and if it does, the health check below is
  // what notices.
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.ios,
  YoutubeApiClient.tv,
];

/// Resolves library tracks to YouTube audio using `youtube_explode_dart`.
///
/// YouTube extraction is inherently fragile (signature deciphering, PO tokens,
/// SABR-only responses, 403s), so this resolver:
///   * reuses a permanently cached track->YouTube mapping when available,
///   * asks its clients in order, starting with whichever one last produced a
///     stream that really played,
///   * checks the stream it gets back with [StreamHealth] before handing it to
///     the player, so a URL YouTube is not serving is caught here rather than
///     looking like a track that simply never starts,
///   * picks the best such stream via [AudioStreamSelector],
///   * tries the next candidate video if a video yields no usable audio,
///   * and stops asking altogether for [refusalCooldown] when YouTube refuses
///     the request itself, rather than making the block worse.
class YoutubeExplodeResolver implements AudioResolver {
  YoutubeExplodeResolver({
    required this.mappings,
    YoutubeExplode? client,
    this.selector = const AudioStreamSelector(),
    List<YoutubeApiClient>? clients,
    this.searchResultLimit = 5,
    this.refusalCooldown = const Duration(minutes: 5),
    this.health = const StreamHealth(),
    this.attemptsPerClient = 2,
    DateTime Function()? clock,
  }) : _yt = client ?? YoutubeExplode(),
       _now = clock ?? DateTime.now,
       _clients = clients ?? defaultYoutubeClients();

  /// How long to stop asking after YouTube refuses a request.
  final Duration refusalCooldown;

  final DateTime Function() _now;

  /// When a refusal was last seen, if we are still sitting it out.
  DateTime? _refusedUntil;

  /// Cache of permanent Spotify -> YouTube mappings.
  final MappingRepository mappings;

  /// Chooses among the available audio-only streams.
  final AudioStreamSelector selector;

  /// Decides whether a resolved URL is really being served.
  final StreamHealth health;

  /// How many times one client is asked for a video before the resolver moves on.
  ///
  /// YouTube's answer is not stable per client: measured over one afternoon, the
  /// same client produced a URL that served the whole file, and, a minute later,
  /// one that stopped after the first megabyte. Because every attempt resolves a
  /// fresh manifest and therefore a fresh URL, one more attempt is worth more
  /// than a different client — and the cost is only paid on the broken path.
  final int attemptsPerClient;

  /// The player clients this resolver will ask, in order of preference.
  ///
  /// Read-only, and public because "which client" is the question every
  /// extraction failure comes down to: [visionOsClient] explains the choice,
  /// and seeing the list is how a test (or a bug report) confirms it.
  List<YoutubeApiClient> get clients =>
      List<YoutubeApiClient>.unmodifiable(_clients);

  /// Name of the client that last produced a stream which really played, if any.
  ///
  /// This is the self-healing part: once a client is measured to work it goes to
  /// the front of the queue, so the cost of a YouTube change is paid once per
  /// session instead of once per track.
  String? get preferredClient => _preferred;
  String? _preferred;

  /// How much bandwidth to spend on each track's audio.
  ///
  /// Held here rather than read from settings at resolve time so the resolver
  /// stays free of the settings store, and pushed in by the playback controller
  /// whenever the user changes it.
  AudioQuality _audioQuality = AudioQuality.balanced;

  /// The quality in force, for the diagnostics panel and tests.
  AudioQuality get audioQuality => _audioQuality;

  @override
  void setAudioQuality(AudioQuality quality) {
    if (quality == _audioQuality) return;
    _audioQuality = quality;
    AppLogger.instance.info('youtube', 'audio quality set to ${quality.name}');
  }

  final YoutubeExplode _yt;
  final List<YoutubeApiClient> _clients;
  final int searchResultLimit;

  static String _nameOf(YoutubeApiClient client) =>
      '${client.payload['context']?['client']?['clientName']}';

  /// [_clients] with the last client measured to work moved to the front.
  List<YoutubeApiClient> _orderedClients() {
    final preferred = _preferred;
    if (preferred == null) return _clients;
    final winner = _clients.where((c) => _nameOf(c) == preferred).toList();
    if (winner.isEmpty) return _clients;
    return <YoutubeApiClient>[
      ...winner,
      ..._clients.where((c) => _nameOf(c) != preferred),
    ];
  }

  @override
  Future<ResolvedStream> resolve(Track track) async {
    final cooldown = _cooldownLeft();
    if (cooldown != null) {
      throw AudioResolutionException(
        'YouTube is refusing requests from this network right now. Gandar is '
        'waiting ${cooldown.inSeconds}s before asking again, instead of making '
        'the block worse.',
        track: track,
      );
    }

    final direct = youTubeVideoIdOf(track.id) != null;
    Object? lastError;
    var sawDeadStream = false;
    var sawCandidate = false;
    // `await for`, not a collected list: the search inside [candidatesFor] must
    // not run at all when the stored mapping works, which is most of the time.
    await for (final videoId in candidatesFor(track)) {
      sawCandidate = true;
      for (final client in _orderedClients()) {
        for (var attempt = 1; attempt <= attemptsPerClient; attempt++) {
          try {
            final stream = await _resolveVideo(videoId, client);
            final verdict = await health.check(stream.url);
            if (verdict == StreamVerdict.refused) {
              // The URL resolved but YouTube will not serve it in full, so the
              // player would give up part way in. Asking again resolves a fresh
              // manifest and a different URL, which is usually enough; a
              // different client is the next step after that.
              sawDeadStream = true;
              AppLogger.instance.warn(
                'youtube',
                '${_nameOf(client)} handed out a stream that stops after the '
                    'first megabyte ("${track.title}", attempt $attempt of '
                    '$attemptsPerClient)',
              );
              continue;
            }
            // Equally important: remember what worked, so the next track starts
            // with the client that is actually serving today.
            _noteWorkingClient(client);
            // Cache the mapping so this track resolves instantly next time.
            // A YouTube-origin track already *is* its mapping.
            if (!direct) await _rememberMapping(track, videoId);
            return stream;
          } catch (e) {
            lastError = e;
            final refusal = refusalMessage(e);
            if (refusal != null) {
              // The next candidate and the next track would be refused too.
              _refusedUntil = _now().add(refusalCooldown);
              AppLogger.instance.warn(
                'youtube',
                'refused a stream request ($e); pausing extraction for '
                    '${refusalCooldown.inSeconds}s',
              );
              throw AudioResolutionException(refusal, track: track, cause: e);
            }
          }
        }
      }
    }

    if (!sawCandidate) {
      throw AudioResolutionException('No YouTube match found', track: track);
    }

    if (sawDeadStream) {
      // Every client produced a URL that the CDN would not serve in full. That
      // is a property of YouTube's answer, not of this track, so it is worth
      // the same cool-down a refusal gets — otherwise the queue works through
      // the whole library to learn the same thing each time.
      _refusedUntil = _now().add(refusalCooldown);
      throw AudioResolutionException(
        'YouTube resolved this track but refused to serve the audio: every '
        'stream URL stopped after its first megabyte. Gandar has paused '
        'extraction for ${refusalCooldown.inSeconds}s, because every track '
        'would get the same answer. It is YouTube\'s answer, not a problem '
        'with your library.',
        track: track,
        cause: lastError,
      );
    }

    throw AudioResolutionException(
      'No video for this track yielded a playable audio stream',
      track: track,
      cause: lastError,
    );
  }

  /// Stores the Spotify -> YouTube match, reporting a failure rather than
  /// throwing one.
  ///
  /// This is on the playback path but is not part of playing, so it has to be
  /// survivable: the stream in hand is good and all that is lost is the
  /// shortcut next time. It used to throw, and the surrounding `catch` could
  /// only read that as "this client did not work" — so one database hiccup
  /// (a lock, a read-only file, a full disk) came out as "No video for this
  /// track yielded a playable audio stream", naming YouTube for something the
  /// database had done. Nothing played, and nothing was cached either, because
  /// this line runs before the cache is handed the stream.
  Future<void> _rememberMapping(Track track, String videoId) async {
    try {
      await mappings.saveMapping(track.id, videoId);
    } catch (e) {
      AppLogger.instance.warn(
        'youtube',
        'could not remember the YouTube match for "${track.title}"; the track '
            'still plays, it will just be searched for again next time',
        error: e,
      );
    }
  }

  /// Records that [client] produced a stream worth playing.
  void _noteWorkingClient(YoutubeApiClient client) {
    final name = _nameOf(client);
    if (_preferred == name) return;
    _preferred = name;
    AppLogger.instance.info('youtube', 'playing through the $name client');
  }

  /// How much of the refusal cool-down is left, or null when there is none.
  Duration? _cooldownLeft() {
    final until = _refusedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    if (left <= Duration.zero) {
      _refusedUntil = null;
      return null;
    }
    return left;
  }

  /// The video ids worth trying for [track], in the order they are tried.
  ///
  /// The stored mapping comes first, because trying it costs no request. It is
  /// a head start rather than a verdict, though: YouTube can stop serving a
  /// video that played yesterday — taken down, age-gated, or answered with
  /// "the page needs to be reloaded" — and while this returned *only* that id,
  /// there was nothing left to fall back to. The track then failed the same
  /// way on every retry, for good, with 'no video for this track yielded a
  /// playable audio stream' naming a video the store had picked itself.
  ///
  /// So the search follows the mapping rather than replacing it, and only runs
  /// when the mapping does not pan out. Whatever does end up playing is saved
  /// over the stale entry, so a mapping that stops working heals itself on the
  /// next attempt instead of needing to be deleted by hand.
  ///
  /// [search] is a seam for the tests: the order these are tried in decides
  /// whether a stale mapping is recoverable, and that is worth pinning down
  /// without YouTube having a say in it.
  Stream<String> candidatesFor(
    Track track, {
    Future<List<String>> Function(String query)? search,
  }) async* {
    // A track that came from YouTube search already names its video, so there
    // is nothing to search for and nothing to cache.
    final direct = youTubeVideoIdOf(track.id);
    if (direct != null) {
      yield direct;
      return;
    }

    final cached = await mappings.findVideoId(track.id);
    if (cached != null && cached.isNotEmpty) yield cached;

    final query = track.searchQuery;
    if (query.isEmpty) return;

    final found = search != null
        ? await search(query)
        : (await _yt.search.search(query))
              .take(searchResultLimit)
              .map((v) => v.id.value)
              .toList(growable: false);
    for (final id in found) {
      // The stored id was tried first; offering it twice would only spend the
      // same attempt again.
      if (id == cached) continue;
      yield id;
    }
  }

  Future<ResolvedStream> _resolveVideo(
    String videoId,
    YoutubeApiClient client,
  ) async {
    // The watch page is not optional here: the visitor data and cookies it
    // carries are what keep YouTube's bot wall away, and without them the
    // player answers every request with "Sign in to confirm you're not a bot".
    // It costs one extra request per track. One client per call, so the caller
    // knows exactly which one produced the stream it is judging.
    final manifest = await _yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: <YoutubeApiClient>[client],
      requireWatchPage: true,
    );

    final options = manifest.audioOnly
        .map(
          (s) => AudioOption(
            url: s.url.toString(),
            container: s.container.name,
            bitrateBitsPerSecond: s.bitrate.bitsPerSecond,
            sizeBytes: s.size.totalBytes,
            audioCodec: s.audioCodec,
          ),
        )
        .toList(growable: false);

    final best = selector.selectBest(options, quality: _audioQuality);
    if (best == null) {
      throw AudioResolutionException('Video has no audio-only streams');
    }

    return ResolvedStream(
      url: best.url,
      videoId: videoId,
      container: best.extension,
      bitrate: best.bitrateBitsPerSecond,
      sizeBytes: best.sizeBytes,
    );
  }

  /// Releases the underlying HTTP client.
  void dispose() => _yt.close();
}
