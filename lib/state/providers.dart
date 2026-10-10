import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/playback_settings.dart';
import '../core/theme/theme_presets.dart';
import '../core/theme/theme_tokens.dart';
import '../domain/models/playlist.dart';
import '../domain/models/track.dart';
import 'app_dependencies.dart';
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
// Spotify library
// ---------------------------------------------------------------------------

/// Whether a Spotify session is currently available.
final isSignedInProvider = FutureProvider<bool>(
  (ref) => ref.watch(appDependenciesProvider).spotifyApi.isAuthenticated(),
);

/// The user's liked songs, paged until exhausted (capped for safety).
final likedTracksProvider = FutureProvider<List<Track>>((ref) async {
  final api = ref.watch(appDependenciesProvider).spotifyApi;
  if (!await api.isAuthenticated()) return const <Track>[];

  const pageSize = 50;
  const maxPages = 40; // 2000 tracks; the UI is virtualized regardless.
  final all = <Track>[];
  for (var page = 0; page < maxPages; page++) {
    final batch = await api.getLikedTracks(
      offset: page * pageSize,
      limit: pageSize,
    );
    all.addAll(batch);
    if (batch.length < pageSize) break;
  }
  final library = ref.watch(appDependenciesProvider).libraryRepository;
  await library.upsertTracks(all);
  return all;
});

/// The user's playlists.
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final api = ref.watch(appDependenciesProvider).spotifyApi;
  if (!await api.isAuthenticated()) return const <Playlist>[];
  final playlists = await api.getPlaylists(limit: 50);
  await ref
      .watch(appDependenciesProvider)
      .libraryRepository
      .upsertPlaylists(playlists);
  return playlists;
});

/// Tracks inside a specific playlist.
final playlistTracksProvider = FutureProvider.family<List<Track>, String>((
  ref,
  playlistId,
) async {
  final api = ref.watch(appDependenciesProvider).spotifyApi;
  return api.getPlaylistTracks(playlistId, limit: 100);
});

/// Locally cached liked tracks, used when offline or signed out.
final cachedLikedTracksProvider = FutureProvider<List<Track>>(
  (ref) =>
      ref.watch(appDependenciesProvider).libraryRepository.cachedLikedTracks(),
);
