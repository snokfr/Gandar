import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/settings/playback_settings.dart';
import '../core/theme/theme_presets.dart';
import '../core/theme/theme_tokens.dart';
import '../data/artwork/artwork_enricher.dart';
import '../data/artwork/artwork_lookup.dart';
import '../data/discord/discord_ipc.dart';
import '../data/discord/discord_presence.dart';
import '../data/feed/artist_feed.dart';
import '../data/import/library_file_import.dart';
import '../data/lyrics/lyrics_source.dart';
import '../data/mashup/mashup_store.dart';
import '../data/net/request_gate.dart';
import '../data/spotify/spotify_public.dart';
import '../data/spotify/spotify_public_web.dart';
import '../data/usage/app_usage.dart';
import '../data/youtube/youtube_search.dart';
import '../domain/models/album.dart';
import '../domain/models/artist.dart';
import '../domain/models/listening_stats.dart';
import '../domain/models/playlist.dart';
import '../domain/models/track.dart';
import '../playback/export/mashup_exporter.dart';
import 'app_dependencies.dart';
import 'mashup_controller.dart';
import 'playback_controller.dart';

/// Overridden in `main()` with the bootstrapped dependency graph.
final appDependenciesProvider = Provider<AppDependencies>(
  (ref) =>
      throw UnimplementedError('appDependenciesProvider must be overridden'),
);

/// The long-lived playback controller.
///
/// Widgets subscribe with `ListenableBuilder` because the controller is a
/// `ChangeNotifier` shared across the whole app.
final playbackControllerProvider = Provider<PlaybackController>(
  (ref) => ref.watch(appDependenciesProvider).playbackController,
);

// ---------------------------------------------------------------------------
// Playback settings
// ---------------------------------------------------------------------------

/// Owns the persisted playback settings and pushes changes to the engine.
class PlaybackSettingsController extends Notifier<PlaybackSettings> {
  @override
  PlaybackSettings build() =>
      ref.watch(appDependenciesProvider).playbackSettings;

  /// Applies a settings change: persist, then push to the audio engine.
  Future<void> update(PlaybackSettings next) async {
    final sanitized = next.sanitized();
    state = sanitized;
    final deps = ref.read(appDependenciesProvider);
    await deps.settingsRepository.savePlayback(sanitized);
    await deps.playbackController.updateSettings(sanitized);
  }
}

final playbackSettingsProvider =
    NotifierProvider<PlaybackSettingsController, PlaybackSettings>(
      PlaybackSettingsController.new,
    );

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// The active theme plus every imported custom theme.
class ThemeState {
  const ThemeState({required this.active, required this.custom});

  final ThemeTokens active;
  final List<ThemeTokens> custom;

  /// Every selectable theme: the built-ins first, then imported ones.
  List<ThemeTokens> get all => <ThemeTokens>[...ThemePresets.all, ...custom];
}

class ThemeController extends Notifier<ThemeState> {
  @override
  ThemeState build() {
    final deps = ref.watch(appDependenciesProvider);
    return ThemeState(active: deps.activeTheme, custom: deps.customThemes);
  }

  Future<void> select(ThemeTokens tokens) async {
    state = ThemeState(active: tokens, custom: state.custom);
    await ref
        .read(appDependenciesProvider)
        .settingsRepository
        .saveActiveThemeId(tokens.id);
  }

  /// Adds or replaces a custom theme and makes it active.
  Future<void> importTheme(ThemeTokens tokens) async {
    final next = <ThemeTokens>[
      ...state.custom.where((t) => t.id != tokens.id),
      tokens,
    ];
    state = ThemeState(active: tokens, custom: next);
    final repo = ref.read(appDependenciesProvider).settingsRepository;
    await repo.saveCustomThemes(next);
    await repo.saveActiveThemeId(tokens.id);
  }

  Future<void> removeCustom(String id) async {
    final next = state.custom.where((t) => t.id != id).toList();
    final active = state.active.id == id
        ? (next.isNotEmpty
              ? next.first
              : ref.read(appDependenciesProvider).activeTheme)
        : state.active;
    state = ThemeState(active: active, custom: next);
    final repo = ref.read(appDependenciesProvider).settingsRepository;
    await repo.saveCustomThemes(next);
    await repo.saveActiveThemeId(active.id);
  }
}

final themeProvider = NotifierProvider<ThemeController, ThemeState>(
  ThemeController.new,
);

// ---------------------------------------------------------------------------
// The local library
// ---------------------------------------------------------------------------

/// The user's liked songs, straight from the local database.
///
/// There is no network step and therefore no failure mode: what the import
/// stored is what the library shows, offline, on every launch.
final FutureProvider<List<Track>> likedTracksProvider =
    FutureProvider<List<Track>>(
      (ref) => ref
          .watch(appDependenciesProvider)
          .libraryRepository
          .cachedLikedTracks(),
    );

/// The library grouped into albums.
///
/// Derived from the same rows the library shows, so the two views can never
/// disagree about what is in the library.
final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final tracks = await ref.watch(likedTracksProvider.future);
  return Album.group(tracks);
});

/// Where named mashups are written and read from.
final mashupStoreProvider = Provider<MashupStore>((ref) => MashupStore());

/// The mashup screen's arrangement and players.
///
/// Deliberately a plain provider kept for the life of the app: the mix has to
/// survive leaving the tab and coming back, which is the whole reason this is
/// not state inside the page. See [MashupController].
final mashupControllerProvider = Provider<MashupController>((ref) {
  final deps = ref.watch(appDependenciesProvider);
  final controller = MashupController(
    createEngine: deps.createMixEngine,
    resolve: deps.audioResolver.resolve,
    settings: () => ref.read(playbackSettingsProvider),
    masterVolume: () => ref.read(playbackControllerProvider).volume,
    store: ref.watch(mashupStoreProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// The mashups saved on disk. Invalidated after a save or a delete.
final savedMashupsProvider = FutureProvider<List<SavedMashup>>(
  (ref) => ref.watch(mashupStoreProvider).list(),
);

/// Writes a mix to an audio file.
///
/// A function rather than a controller: an export is one long job with progress
/// and an outcome, it belongs to the screen that asked for it, and nothing else
/// in the app needs to know it happened. It resolves songs through the same
/// resolver playback uses, so a mix mostly of cached tracks exports without
/// touching the network.
final mashupExportProvider = Provider<MashupExport>((ref) {
  final deps = ref.watch(appDependenciesProvider);
  return buildMashupExporter(resolve: deps.audioResolver.resolve);
});

/// Everything the library holds by one artist.
///
/// Built from the same rows every other screen shows, so an artist page cannot
/// claim something the library does not have. The name comes from the route —
/// there is no artist id to carry — and the model fixes the spelling up from
/// the tracks themselves.
final artistProvider = FutureProvider.family<Artist, String>((ref, name) async {
  final tracks = await ref.watch(likedTracksProvider.future);
  return Artist.of(tracks, name);
});

/// How many recent tracks the library shows before "all of it".
const int recentTracksShown = 20;

/// Tracks played recently, most recent first.
///
/// Play history stores ids, so the ids are matched against the library: a track
/// that has since been removed simply does not appear, and the id list cannot
/// resurrect it.
final recentTracksProvider = FutureProvider<List<Track>>((ref) async {
  final repository = ref.watch(appDependenciesProvider).libraryRepository;
  final ids = await repository.recentTrackIds(limit: recentTracksShown);
  if (ids.isEmpty) return const <Track>[];
  final tracks = await ref.watch(likedTracksProvider.future);
  final byId = <String, Track>{for (final track in tracks) track.id: track};
  return <Track>[
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];
});

/// Everything imported, newest import first.
final playlistsProvider = FutureProvider<List<Playlist>>(
  (ref) =>
      ref.watch(appDependenciesProvider).libraryRepository.cachedPlaylists(),
);

/// The tracks of one imported playlist, in playlist order.
final playlistTracksProvider = FutureProvider.family<List<Track>, String>(
  (ref, playlistId) => ref
      .watch(appDependenciesProvider)
      .libraryRepository
      .cachedPlaylistTracks(playlistId),
);

// A note on what used to be here: this file used to own a Spotify session —
// a PKCE sign-in, a token store, a client id the user typed in, and providers
// that paged the Web API. All of it is gone. Since February 2026 Spotify
// refuses Development-mode apps whose owner has no Premium, which made the
// whole path unusable for most people, so the app now reads public pages and
// imported files instead. Nothing in Gandar needs a Spotify account, and
// nothing asks for one.

/// YouTube search, gated like every other outbound request.
final youTubeSearcherProvider = Provider<YouTubeSearcher>(
  (ref) => YouTubeSearcher(),
);

/// Minimum query length before anything is searched.
const int kMinSearchLength = 2;

final youTubeSearchProvider = FutureProvider.family<List<YouTubeVideo>, String>(
  (ref, query) async {
    if (query.trim().length < kMinSearchLength) return const <YouTubeVideo>[];
    return ref.watch(youTubeSearcherProvider).search(query, limit: 15);
  },
);

/// What YouTube has for one artist, shown as the catalogue on an artist page.
///
/// Its own provider rather than a reuse of [youTubeSearchProvider]: this query
/// is not one the user typed, and a page about an artist wants a longer list
/// than a search box does. Cached per artist for the session like any other
/// future provider, so going back to a page does not search again.
final artistCatalogueProvider = FutureProvider.family<List<YouTubeVideo>, String>(
  (ref, artist) async {
    final trimmed = artist.trim();
    if (trimmed.length < kMinSearchLength) return const <YouTubeVideo>[];
    return ref.watch(youTubeSearcherProvider).search('$trimmed songs', limit: 30);
  },
);

/// Tracks already in the library that match [query].
///
/// This is what makes the search screen useful without a catalogue: the
/// imported libraries are local, so searching them is instant and offline.
final localTrackSearchProvider = FutureProvider.family<List<Track>, String>((
  ref,
  query,
) async {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.length < kMinSearchLength) return const <Track>[];
  final tracks = await ref.watch(likedTracksProvider.future);
  // No result cap. There used to be a `take(50)` here, which quietly hid the
  // rest of a 2,000-song library from a search that had actually matched it,
  // and made "play all" mean "play the first fifty". The list is virtualised
  // where it is shown, so the count costs nothing.
  return tracks
      .where(
        (t) =>
            t.title.toLowerCase().contains(trimmed) ||
            t.artists.any((a) => a.toLowerCase().contains(trimmed)) ||
            (t.album?.toLowerCase().contains(trimmed) ?? false),
      )
      .toList(growable: false);
});

/// Imported playlists whose name matches [query].
final localPlaylistSearchProvider =
    FutureProvider.family<List<Playlist>, String>((ref, query) async {
      final trimmed = query.trim().toLowerCase();
      if (trimmed.length < kMinSearchLength) return const <Playlist>[];
      final playlists = await ref.watch(playlistsProvider.future);
      return playlists
          .where((p) => p.name.toLowerCase().contains(trimmed))
          .toList(growable: false);
    });

/// The artists this library actually listens to, most-played first.
///
/// Ranked by play history rather than by how many songs are filed under a name,
/// because the feed answers "what is new from the music I play" — an artist with
/// one song that gets played daily belongs at the top, and a 40-track album that
/// was imported and never opened does not.
///
/// A library with no history yet falls back to the artists it holds, in library
/// order, so the tab has something to show on day one.
final topArtistsProvider = FutureProvider<List<String>>((ref) async {
  final tracks = await ref.watch(likedTracksProvider.future);
  if (tracks.isEmpty) return const <String>[];

  final byId = <String, Track>{for (final track in tracks) track.id: track};
  final records = await ref
      .watch(appDependenciesProvider)
      .libraryRepository
      .playHistory();

  final counts = <String, int>{};
  for (final record in records) {
    final artist = byId[record.trackId]?.primaryArtist.trim() ?? '';
    if (artist.isEmpty) continue;
    counts[artist] = (counts[artist] ?? 0) + 1;
  }

  if (counts.isEmpty) {
    final seen = <String>[];
    final lowered = <String>{};
    for (final track in tracks) {
      final artist = track.primaryArtist.trim();
      if (artist.isEmpty || !lowered.add(artist.toLowerCase())) continue;
      seen.add(artist);
    }
    return List<String>.unmodifiable(seen);
  }

  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });
  return List<String>.unmodifiable(<String>[for (final e in ranked) e.key]);
});

/// One service for the session, so the artist -> channel lookups it discovers
/// are reused instead of being re-searched every time the tab is opened.
final artistFeedServiceProvider = Provider<ArtistFeed>((ref) => ArtistFeed());

/// The newest uploads from the artists this library listens to.
final artistFeedProvider = FutureProvider<List<FeedVideo>>((ref) async {
  final artists = await ref.watch(topArtistsProvider.future);
  if (artists.isEmpty) return const <FeedVideo>[];
  return ref.watch(artistFeedServiceProvider).latestFor(artists);
});

/// Looks lyrics up by track. Free and keyless, so there is nothing to configure.
final lyricsSourceProvider = Provider<LyricsSource>((ref) => LrcLibLyrics());

/// Lyrics for one track, cached per track for the life of the app session.
///
/// Keyed by the whole [Track] because the lookup needs the title, artist and
/// duration, not just the id. A null result means "the source has none", which
/// is a normal answer and is rendered as such.
final lyricsProvider = FutureProvider.family<Lyrics?, Track>(
  (ref, track) => ref.watch(lyricsSourceProvider).lookup(track),
);

/// Lifetime listening stats for the savings view.
///
/// Re-reads the play history whenever playback settings change, because the
/// two assumptions it uses (ad time per track, subscription price) live there.
final listeningStatsProvider = FutureProvider<ListeningStats>((ref) async {
  final deps = ref.watch(appDependenciesProvider);
  final settings = ref.watch(playbackSettingsProvider);
  final records = await deps.libraryRepository.playHistory();
  return ListeningStats.from(
    records: records,
    premiumMonthlyCost: settings.savingsPremiumMonthlyCost,
    adBreakMinutes: settings.savingsAdBreakMinutes,
    adSeconds: settings.savingsAdSeconds,
    adsPerBreak: settings.savingsAdsPerBreak,
    adsCpm: settings.savingsAdsCpm,
    artistPayoutPerStream: settings.savingsArtistPayoutPerStream,
  );
});

/// Persisted verbosity of the log file.
class LogLevelController extends Notifier<LogLevel> {
  @override
  LogLevel build() => ref.watch(appDependenciesProvider).logLevel;

  Future<void> set(LogLevel level) async {
    await ref
        .read(appDependenciesProvider)
        .settingsRepository
        .saveLogLevelName(level.name);
    AppLogger.instance.minLevel = level;
    AppLogger.instance.info('logger', 'level set to ${level.name}');
    state = level;
  }
}

final logLevelProvider = NotifierProvider<LogLevelController, LogLevel>(
  LogLevelController.new,
);

/// Locally cached liked tracks, used when offline or signed out.
final cachedLikedTracksProvider = FutureProvider<List<Track>>(
  (ref) =>
      ref.watch(appDependenciesProvider).libraryRepository.cachedLikedTracks(),
);

// ---------------------------------------------------------------------------
// Importing without the Web API
// ---------------------------------------------------------------------------

/// Reads public Spotify pages: no account, no client id, no Web API.
final spotifyPublicWebProvider = Provider<SpotifyPublicWeb>(
  (ref) => SpotifyPublicWeb(),
);

/// What the last import did.
class ImportOutcome {
  const ImportOutcome({
    required this.headline,
    required this.detail,
    this.playlistId,
  });

  final String headline;
  final String detail;

  /// Set when a playlist was stored, so the UI can offer to open it.
  final String? playlistId;
}

/// State of the import screen.
class ImportState {
  const ImportState({this.busy = false, this.error, this.outcome});

  final bool busy;

  /// A sentence to show when the import failed.
  final String? error;
  final ImportOutcome? outcome;

  bool get idle => !busy && error == null && outcome == null;
}

/// Imports a public Spotify link or an exported library file into the local
/// library.
class LibraryImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportState();

  /// Reads a pasted link and stores it.
  Future<void> importLink(String input) async {
    final link = SpotifyLink.parse(input);
    if (link == null) {
      state = const ImportState(
        error:
            'That does not look like a Spotify link. Paste a link like '
            'open.spotify.com/playlist/... or a share link from the Spotify app.',
      );
      return;
    }

    state = const ImportState(busy: true);
    final deps = ref.read(appDependenciesProvider);
    try {
      final collection = await ref
          .read(spotifyPublicWebProvider)
          .fetchCollection(link);
      if (collection.tracks.isEmpty) {
        state = ImportState(
          error:
              'Spotify returned "${collection.name}" but no tracks Gandar can '
              'read. If it is a private or made-for-you playlist, export it '
              'with Exportify and import the file instead.',
        );
        return;
      }

      await deps.libraryRepository.upsertPlaylists(<Playlist>[
        collection.toPlaylist(),
      ]);
      await deps.libraryRepository.replacePlaylistTracks(
        collection.link.id,
        collection.tracks,
      );
      ref.invalidate(playlistsProvider);

      final truncated = collection.trackListTruncated;
      state = ImportState(
        outcome: ImportOutcome(
          headline: 'Imported "${collection.name}"',
          detail: truncated
              ? '${collection.tracks.length} tracks — Spotify\'s public page '
                    'only carries the first ${PublicCollection.publicTrackLimit}, '
                    'so this list may be incomplete. For the whole playlist, '
                    'export it with Exportify and import the CSV.'
              : '${collection.tracks.length} tracks added to your playlists.',
          playlistId: collection.link.id,
        ),
      );
      AppLogger.instance.info(
        'import',
        'public ${collection.link.kind.name} ${collection.link.id}: '
            '${collection.tracks.length} tracks stored',
      );
    } on SpotifyPublicException catch (e) {
      AppLogger.instance.warn('import', 'link import failed: ${e.message}');
      state = ImportState(error: e.message);
    } catch (e) {
      AppLogger.instance.error('import', 'link import failed', error: e);
      state = ImportState(error: 'Import failed: $e');
    }
  }

  /// Parses an exported library file and merges its tracks into the library.
  Future<void> importFile(String fileName, String contents) async {
    state = const ImportState(busy: true);
    final deps = ref.read(appDependenciesProvider);
    try {
      final parsed = parseLibraryFile(fileName, contents);
      await deps.libraryRepository.upsertTracks(parsed.tracks);
      ref.invalidate(likedTracksProvider);

      final skipped = parsed.problems.length;
      state = ImportState(
        outcome: ImportOutcome(
          headline: 'Imported ${parsed.tracks.length} tracks',
          detail:
              'From ${parsed.source}${skipped == 0 ? '' : ', $skipped rows skipped'}.'
              ' They are in your library and play like any other track.',
        ),
      );
      AppLogger.instance.info(
        'import',
        '${parsed.source}: ${parsed.tracks.length} tracks, $skipped unusable rows',
      );
    } on LibraryFileException catch (e) {
      state = ImportState(error: e.message);
    } catch (e) {
      AppLogger.instance.error('import', 'file import failed', error: e);
      state = ImportState(error: 'Could not read $fileName: $e');
    }
  }

  void clear() => state = const ImportState();
}

final libraryImportProvider =
    NotifierProvider<LibraryImportController, ImportState>(
      LibraryImportController.new,
    );

/// Looks up per-track album artwork, politely.
///
/// The gate is separate from the other clients so its token bucket can be set
/// to Apple's documented rate without slowing anything else down.
final artworkSourceProvider = Provider<ArtworkSource>((ref) {
  // About twenty requests a minute: the rate the iTunes Search API documents,
  // spread with a small burst so a short list still feels responsive.
  final gate = RequestGate(defaultRefillPerSecond: 20 / 60, defaultBurst: 3);
  return ITunesArtwork(gate: gate);
});

/// Runs the bulk artwork pass and reports its progress.
class ArtworkEnrichmentController extends Notifier<ArtworkProgress?> {
  ArtworkEnricher? _running;

  @override
  ArtworkProgress? build() => null;

  bool get running => _running != null;

  /// Fetches artwork for tracks that have none. Safe to call twice: the second
  /// call returns immediately while a pass is already going.
  Future<void> start({int? limit}) async {
    if (_running != null) return;
    final enricher = ArtworkEnricher(
      library: ref.read(appDependenciesProvider).libraryRepository,
      source: ref.read(artworkSourceProvider),
    );
    _running = enricher;
    try {
      await enricher.run(
        limit: limit,
        onProgress: (progress) {
          if (!ref.mounted) return;
          state = progress;
        },
      );
      ref.invalidate(likedTracksProvider);
    } finally {
      _running = null;
      if (ref.mounted && state != null) {
        state = state!.copyWith(running: false);
      }
    }
  }

  /// Asks the pass to stop after the current request.
  void stop() {
    _running?.stop();
  }
}

final artworkEnrichmentProvider =
    NotifierProvider<ArtworkEnrichmentController, ArtworkProgress?>(
      ArtworkEnrichmentController.new,
    );

// ---------------------------------------------------------------------------
// Time in Gandar
// ---------------------------------------------------------------------------

/// Mirrors the app-usage tracker into the widget tree.
///
/// The tracker itself is a [ChangeNotifier] owned by [AppDependencies], so this
/// is a thin adapter rather than a second source of truth: one counter, one
/// place it is persisted, and the UI reads it like any other provider.
class AppUsageController extends Notifier<AppUsage> {
  @override
  AppUsage build() {
    final tracker = ref.watch(appDependenciesProvider).appUsage;
    void listener() => state = tracker.usage;
    tracker.addListener(listener);
    ref.onDispose(() => tracker.removeListener(listener));
    return tracker.usage;
  }
}

final appUsageProvider = NotifierProvider<AppUsageController, AppUsage>(
  AppUsageController.new,
);

/// The counter itself, for code that wants the raw number without subscribing
/// to a rebuild — the Discord presence reads it when it pushes.
final appUsageTrackerProvider = Provider<AppUsageTracker>(
  (ref) => ref.watch(appDependenciesProvider).appUsage,
);

// ---------------------------------------------------------------------------
// Discord Rich Presence
// ---------------------------------------------------------------------------

/// Opens a connection to Discord. Replaced in tests.
typedef DiscordConnector = Future<DiscordConnection> Function(String clientId);

final discordConnectorProvider = Provider<DiscordConnector>(
  (ref) =>
      (clientId) => DiscordIpc.connect(clientId: clientId),
);

/// What the Discord connection is doing, for the settings screen to report.
enum DiscordStatus {
  /// The feature is off.
  off,

  /// On, but with no Application ID to connect with.
  needsClientId,

  connecting,
  connected,

  /// Discord is not reachable, or refused. [DiscordState.detail] says which.
  failed,
}

class DiscordState {
  const DiscordState({required this.status, this.detail});

  final DiscordStatus status;

  /// A sentence for the settings card: why it is not connected.
  final String? detail;

  bool get connected => status == DiscordStatus.connected;
}

/// Keeps the Discord profile in step with what Gandar is playing.
///
/// Everything here fails soft. Discord is an optional side-channel: if it is
/// not installed, not running, not signed in, or simply slow, the app plays
/// music exactly as it did before, and the settings card says what happened.
///
/// The presence is *pushed on change*, not polled: playback notifies through
/// [PlaybackController], the settings through this provider, and a five-minute
/// timer exists only because the "time in Gandar" line drifts while nothing
/// else changes.
class DiscordPresenceController extends Notifier<DiscordState> {
  DiscordConnection? _connection;
  Timer? _debounce;
  Timer? _heartbeat;
  Timer? _reconnect;
  Duration _backoff = DiscordPolicy.initialBackoff;

  /// Long enough to coalesce the several notifications one track change
  /// produces, short enough that the profile feels immediate.
  static const Duration _debounceDelay = Duration(milliseconds: 150);

  @override
  DiscordState build() {
    final playback = ref.watch(playbackControllerProvider);

    void onPlayback() => _schedule();
    playback.addListener(onPlayback);

    ref.listen(playbackSettingsProvider, (previous, next) {
      if (previous?.discordEnabled == next.discordEnabled &&
          previous?.discordClientId == next.discordClientId &&
          previous?.discordShowTrack == next.discordShowTrack &&
          previous?.discordShowAppTime == next.discordShowAppTime) {
        return;
      }
      // Turning it off is the one change that must not wait for a debounce:
      // the user has just asked for the presence to disappear.
      if (next.discordEnabled == false) {
        unawaited(_forget());
      }
      _backoff = DiscordPolicy.initialBackoff;
      _schedule();
    });

    ref.onDispose(() {
      playback.removeListener(onPlayback);
      _debounce?.cancel();
      _heartbeat?.cancel();
      _reconnect?.cancel();
      _connection?.close();
      _connection = null;
    });

    // Deferred: `state` cannot be written during build.
    Future<void>.microtask(_schedule);
    return const DiscordState(status: DiscordStatus.off);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => unawaited(_sync()));
  }

  /// Tries to connect again now, instead of waiting out the backoff.
  ///
  /// The backoff exists so a machine with no Discord at all is not hammered;
  /// a person who has just started Discord should not have to sit through it.
  /// The wait is reset, so a failure after this retries quickly again rather
  /// than inheriting the grown backoff.
  void retry() {
    _reconnect?.cancel();
    _reconnect = null;
    _debounce?.cancel();
    _backoff = DiscordPolicy.initialBackoff;
    _set(const DiscordState(status: DiscordStatus.connecting));
    unawaited(_sync());
  }

  /// Clears the presence and drops the connection, without touching status.
  Future<void> _forget() async {
    _reconnect?.cancel();
    _reconnect = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final connection = _connection;
    _connection = null;
    if (connection == null) return;
    try {
      await connection.setActivity(null);
    } catch (_) {
      // Discord may already be gone; dropping the handle is what matters.
    }
    connection.close();
  }

  Future<void> _sync() async {
    if (!ref.mounted) return;
    final settings = ref.read(playbackSettingsProvider);

    switch (DiscordPolicy.intentFor(settings)) {
      case DiscordIntent.clear:
        await _forget();
        _set(const DiscordState(status: DiscordStatus.off));
        return;
      case DiscordIntent.needClientId:
        await _forget();
        _set(const DiscordState(status: DiscordStatus.needsClientId));
        return;
      case DiscordIntent.publish:
        break;
    }

    if (_connection == null || !_connection!.isOpen) {
      _set(const DiscordState(status: DiscordStatus.connecting));
      try {
        final connection = await ref.read(discordConnectorProvider)(
          settings.discordClientId,
        );
        if (!ref.mounted) {
          connection.close();
          return;
        }
        _connection = connection;
        _backoff = DiscordPolicy.initialBackoff;
        _heartbeat ??= Timer.periodic(
          const Duration(minutes: 5),
          (_) => unawaited(_sync()),
        );
      } on DiscordUnavailable catch (e) {
        _fail(e.message);
        return;
      } catch (e) {
        _fail('Could not reach Discord: $e');
        return;
      }
    }

    await _push(settings);
  }

  /// Builds the activity from live playback state and sends it.
  Future<void> _push(PlaybackSettings settings) async {
    final connection = _connection;
    if (connection == null) return;
    final playback = ref.read(playbackControllerProvider);

    final activity = DiscordPresence.build(
      enabled: true,
      showTrack: settings.discordShowTrack,
      showAppTime: settings.discordShowAppTime,
      track: playback.currentTrack,
      isPlaying: playback.isPlaying,
      position: playback.position,
      duration: playback.duration,
      lifetime: ref
          .read(appUsageTrackerProvider)
          .usage
          .lifetimeIncludingSession,
    );

    try {
      await connection.setActivity(activity);
    } on DiscordUnavailable catch (e) {
      // A connection that failed mid-send is not worth keeping: the pipe is
      // gone, and leaving the handle open would swallow every later update.
      _connection = null;
      connection.close();
      _fail(e.message);
      return;
    } catch (e) {
      _connection = null;
      connection.close();
      _fail('Could not update Discord: $e');
      return;
    }
    if (ref.mounted) _set(const DiscordState(status: DiscordStatus.connected));
  }

  void _fail(String detail) {
    // The first time a particular failure happens it goes into the log at warn
    // level. Without that, everything Discord does wrong is visible only inside
    // the settings card — which is how a connection that has never once worked
    // leaves no trace in the log at all. The retries that follow stay at debug,
    // so a machine with no Discord does not fill the file with the same line.
    if (detail != state.detail) {
      AppLogger.instance.warn('discord', detail);
    } else {
      AppLogger.instance.debug('discord', detail);
    }
    _set(DiscordState(status: DiscordStatus.failed, detail: detail));
    _scheduleReconnect();
  }

  /// Discord may simply not have been open yet when the app started, so a
  /// failure is retried — backing off, because a machine without Discord at all
  /// should not spin.
  void _scheduleReconnect() {
    _reconnect?.cancel();
    _reconnect = Timer(_backoff, () => unawaited(_sync()));
    _backoff = DiscordPolicy.nextBackoff(_backoff);
  }

  void _set(DiscordState next) {
    if (!ref.mounted) return;
    if (state.status == next.status && state.detail == next.detail) return;
    state = next;
  }
}

final discordPresenceProvider =
    NotifierProvider<DiscordPresenceController, DiscordState>(
      DiscordPresenceController.new,
    );
