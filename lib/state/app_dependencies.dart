import 'dart:async';

import '../core/settings/playback_settings.dart';
import '../core/settings/settings_repository.dart';
import '../core/theme/theme_presets.dart';
import '../core/theme/theme_tokens.dart';
import '../data/cache/cache_manager.dart';
import '../data/repositories/local_repositories.dart';
import '../data/spotify/spotify_api.dart';
import '../data/spotify/spotify_auth.dart';
import '../data/spotify/spotify_tokens.dart';
import '../data/storage/app_database.dart';
import '../data/youtube/youtube_explode_resolver.dart';
import '../domain/repositories/repositories.dart';
import '../playback/audio_engine/audio_engine.dart';
import '../playback/preloader.dart';
import '../playback/queue/shuffle.dart';
import 'playback_controller.dart';

/// Everything the app needs, constructed once at startup.
///
/// Holding these in one object keeps Riverpod providers trivial and makes the
/// whole graph swappable in tests.
class AppDependencies {
  AppDependencies({
    required this.database,
    required this.settingsRepository,
    required this.playbackSettings,
    required this.activeTheme,
    required this.customThemes,
    required this.spotifyApi,
    required this.mappingRepository,
    required this.cacheRepository,
    required this.libraryRepository,
    required this.cacheManager,
    required this.audioResolver,
    required this.audioEngine,
    required this.playbackController,
    this.clientId = '',
  });

  final AppDatabase database;
  final SettingsRepository settingsRepository;
  final PlaybackSettings playbackSettings;
  final ThemeTokens activeTheme;
  final List<ThemeTokens> customThemes;

  final SpotifyApi spotifyApi;
  final MappingRepository mappingRepository;
  final CacheRepository cacheRepository;
  final LibraryRepository libraryRepository;
  final CacheManager cacheManager;
  final AudioResolver audioResolver;
  final AudioEngine audioEngine;
  final PlaybackController playbackController;

  /// Spotify application client id (empty until the user configures it).
  final String clientId;

  /// Builds the production dependency graph.
  ///
  /// [clientId] must be supplied by configuration; without it the app still
  /// runs (themes, settings, local library) but sign-in is unavailable.
  static Future<AppDependencies> bootstrap({
    required AppDatabase database,
    required SettingsRepository settingsRepository,
    required AudioEngine audioEngine,
    required String clientId,
    OAuthBrowser? browser,
    TokenStore? tokenStore,
  }) async {
    final playbackSettings = await settingsRepository.loadPlayback();
    final customThemes = await settingsRepository.loadCustomThemes();
    final activeId = await settingsRepository.loadActiveThemeId();
    final activeTheme = _resolveTheme(activeId, customThemes);

    final mappingRepository = DriftMappingRepository(database);
    final cacheRepository = DriftCacheRepository(database);
    final libraryRepository = DriftLibraryRepository(database);
    final cacheManager = CacheManager(repository: cacheRepository);

    final auth = SpotifyAuthService(
      config: SpotifyAuthConfig(clientId: clientId),
      tokenStore: tokenStore ?? SecureTokenStore(),
      browser: browser ?? LoopbackOAuthBrowser(port: 8888),
    );
    final spotifyApi = SpotifyApi(auth: auth);

    final resolver = YoutubeExplodeResolver(mappings: mappingRepository);
    final preloader = StreamPreloader(resolver: resolver);

    final controller = PlaybackController(
      engine: audioEngine,
      preloader: preloader,
      library: libraryRepository,
      settings: playbackSettings,
      shuffleService: ShuffleService(),
    );

    // Enforce cache limits on startup (best effort; never blocks launch).
    unawaited(
      cacheManager
          .enforceLimits(
            maxMegabytes: playbackSettings.cacheMaxMegabytes,
            maxIdleDays: playbackSettings.cacheMaxIdleDays,
          )
          .then<void>((_) {}, onError: (Object _) {}),
    );

    return AppDependencies(
      database: database,
      settingsRepository: settingsRepository,
      playbackSettings: playbackSettings,
      activeTheme: activeTheme,
      customThemes: customThemes,
      spotifyApi: spotifyApi,
      mappingRepository: mappingRepository,
      cacheRepository: cacheRepository,
      libraryRepository: libraryRepository,
      cacheManager: cacheManager,
      audioResolver: resolver,
      audioEngine: audioEngine,
      playbackController: controller,
      clientId: clientId,
    );
  }

  static ThemeTokens _resolveTheme(String? activeId, List<ThemeTokens> custom) {
    if (activeId == null) return ThemePresets.defaultTheme;
    final preset = ThemePresets.byId(activeId);
    if (preset != null) return preset;
    for (final t in custom) {
      if (t.id == activeId) return t;
    }
    return ThemePresets.defaultTheme;
  }
}
