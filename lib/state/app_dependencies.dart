import 'dart:async';

import '../core/logging/app_logger.dart';
import '../core/settings/playback_settings.dart';
import '../core/settings/settings_repository.dart';
import '../core/theme/theme_presets.dart';
import '../core/theme/theme_tokens.dart';
import '../data/cache/audio_cache.dart';
import '../data/cache/cache_manager.dart';
import '../data/repositories/local_repositories.dart';
import '../data/storage/app_database.dart';
import '../data/usage/app_usage.dart';
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
///
/// Note what is *not* here: any Spotify account, token or client id. Gandar
/// reads public pages and imported files instead, so there is no session to
/// keep alive and nothing to sign into.
class AppDependencies {
  AppDependencies({
    required this.database,
    required this.settingsRepository,
    required this.playbackSettings,
    required this.activeTheme,
    required this.customThemes,
    required this.mappingRepository,
    required this.cacheRepository,
    required this.libraryRepository,
    required this.cacheManager,
    required this.audioResolver,
    required this.audioEngine,
    required this.playbackController,
    required this.appUsage,
    this.logLevel = LogLevel.info,
  });

  final AppDatabase database;
  final SettingsRepository settingsRepository;
  final PlaybackSettings playbackSettings;
  final ThemeTokens activeTheme;
  final List<ThemeTokens> customThemes;

  final MappingRepository mappingRepository;
  final CacheRepository cacheRepository;
  final LibraryRepository libraryRepository;
  final CacheManager cacheManager;
  final AudioResolver audioResolver;
  final AudioEngine audioEngine;
  final PlaybackController playbackController;

  /// How long the app has been open, this run and ever.
  final AppUsageTracker appUsage;

  /// Log verbosity in force at startup.
  final LogLevel logLevel;

  /// Builds the production dependency graph.
  static Future<AppDependencies> bootstrap({
    required AppDatabase database,
    required SettingsRepository settingsRepository,
    required AudioEngine audioEngine,
  }) async {
    // Apply the saved log level before anything noisy happens.
    final savedLevel = LogLevel.byName(
      await settingsRepository.loadLogLevelName() ?? '',
    );
    if (savedLevel != null) AppLogger.instance.minLevel = savedLevel;

    final playbackSettings = await settingsRepository.loadPlayback();
    final customThemes = await settingsRepository.loadCustomThemes();
    final activeId = await settingsRepository.loadActiveThemeId();
    final activeTheme = _resolveTheme(activeId, customThemes);

    final mappingRepository = DriftMappingRepository(database);
    final cacheRepository = DriftCacheRepository(database);
    final libraryRepository = DriftLibraryRepository(database);
    final cacheManager = CacheManager(repository: cacheRepository);

    final appUsage = AppUsageTracker(store: settingsRepository.store);
    // The stored total is read before anything can ask for it, so the first
    // frame of the Discord presence and the activity view agree.
    await appUsage.load();

    // Cached audio: the resolver writes every track it plays to disk, and the
    // next play reads it back without touching the network. The limit is
    // enforced as files arrive, not only at the next launch — a session long
    // enough to fill the cache should not be the one that discovers it had no
    // ceiling.
    final audioCache = AudioCache(
      repository: cacheRepository,
      downloader: DioAudioDownloader(),
      afterStore: () async {
        await cacheManager.enforceLimits(
          maxMegabytes: playbackSettings.cacheMaxMegabytes,
          maxIdleDays: playbackSettings.cacheMaxIdleDays,
        );
      },
    );
    final resolver = CachedAudioResolver(
      inner: YoutubeExplodeResolver(mappings: mappingRepository),
      cache: audioCache,
      mappings: mappingRepository,
    );
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
      mappingRepository: mappingRepository,
      cacheRepository: cacheRepository,
      libraryRepository: libraryRepository,
      cacheManager: cacheManager,
      audioResolver: resolver,
      audioEngine: audioEngine,
      playbackController: controller,
      appUsage: appUsage,
      logLevel: AppLogger.instance.minLevel,
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
