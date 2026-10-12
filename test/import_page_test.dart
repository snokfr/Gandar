import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/core/settings/settings_repository.dart';
import 'package:gandar/core/theme/theme_engine.dart';
import 'package:gandar/core/theme/theme_presets.dart';
import 'package:gandar/core/theme/theme_tokens.dart';
import 'package:gandar/data/cache/cache_manager.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/spotify/spotify_public_web.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/data/usage/app_usage.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/features/import/import_page.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/preloader.dart';
import 'package:gandar/state/app_dependencies.dart';
import 'package:gandar/state/playback_controller.dart';
import 'package:gandar/state/providers.dart';
import 'package:gandar/state/retry_policy.dart';

import 'helpers.dart';

/// Drives the import screen the way a person does: paste a link, press the
/// button, read the result. The Spotify page is the recorded one from the real
/// site, served through the production client.
class _NoopResolver implements AudioResolver {
  const _NoopResolver();

  @override
  void setAudioQuality(AudioQuality quality) {}

  @override
  Future<ResolvedStream> resolve(Track track) async =>
      throw StateError('no audio expected in import tests');
}

(FakeHttpAdapter, AppDependencies) _harness() {
  final embed = File('test/fixtures/spotify_embed_playlist.html')
      .readAsStringSync();
  final adapter = FakeHttpAdapter((options) {
    if (options.path.contains('oembed')) {
      return ResponseBody.fromString('{}', 404);
    }
    return ResponseBody.fromString(
      embed,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html'],
      },
    );
  });

  final database = AppDatabase.withExecutor(NativeDatabase.memory());
  const resolver = _NoopResolver();
  final library = DriftLibraryRepository(database);
  final dependencies = AppDependencies(
    database: database,
    settingsRepository: SettingsRepository(InMemoryStore()),
    playbackSettings: const PlaybackSettings(),
    activeTheme: ThemePresets.spotifyClassic,
    customThemes: const <ThemeTokens>[],
    mappingRepository: DriftMappingRepository(database),
    cacheRepository: DriftCacheRepository(database),
    libraryRepository: library,
    cacheManager: CacheManager(repository: DriftCacheRepository(database)),
    audioResolver: resolver,
    audioEngine: FakeAudioEngine(),
    createMixEngine: FakeAudioEngine.new,
    appUsage: AppUsageTracker(store: InMemoryStore()),
    playbackController: PlaybackController(
      engine: FakeAudioEngine(),
      preloader: StreamPreloader(resolver: resolver),
      library: library,
      settings: const PlaybackSettings(),
    ),
  );
  return (adapter, dependencies);
}

Widget _page(FakeHttpAdapter adapter, AppDependencies dependencies) =>
    ProviderScope(
      retry: gandarProviderRetry,
      overrides: [
        appDependenciesProvider.overrideWithValue(dependencies),
        spotifyPublicWebProvider.overrideWithValue(
          SpotifyPublicWeb(http: dioWith(adapter)),
        ),
      ],
      child: MaterialApp(
        theme: ThemeEngine.build(ThemePresets.spotifyClassic),
        home: const ImportPage(),
      ),
    );

final bool _skipWithoutSqlite = !sqliteAvailable;

/// The page is a scrolling list, so the window has to be tall enough for the
/// result banner to be built at all.
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a pasted link imports the playlist and offers to open it', (
    tester,
  ) async {
    final (adapter, dependencies) = _harness();
    _tallWindow(tester);
    addTearDown(dependencies.database.close);

    await tester.pumpWidget(_page(adapter, dependencies));
    await tester.enterText(
      find.byType(TextField),
      'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc',
    );
    await tester.tap(find.text('Import from link'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Imported "Today'), findsOneWidget);
    expect(find.text('Open playlist'), findsOneWidget);

    // The tracks really are in the local database, in playlist order.
    final stored = await dependencies.libraryRepository.cachedPlaylistTracks(
      '37i9dQZF1DXcBWIGoYBM5M',
    );
    expect(stored, hasLength(3));
    expect(stored.first.title, 'Stop The Wedding!');
    expect(stored.first.artists, <String>['Ashe']);

    final playlists = await dependencies.libraryRepository.cachedPlaylists();
    expect(playlists.single.trackCount, 3);
    expect(playlists.single.name, isNotEmpty);
  }, skip: _skipWithoutSqlite);

  testWidgets('text that is not a link is explained before any request', (
    tester,
  ) async {
    final (adapter, dependencies) = _harness();
    _tallWindow(tester);
    addTearDown(dependencies.database.close);

    await tester.pumpWidget(_page(adapter, dependencies));
    await tester.enterText(find.byType(TextField), 'my favourite songs');
    await tester.tap(find.text('Import from link'));
    await tester.pumpAndSettle();

    expect(find.text('Import failed'), findsOneWidget);
    expect(
      find.textContaining('does not look like a Spotify link'),
      findsOneWidget,
    );
    expect(adapter.requests, isEmpty);
  }, skip: _skipWithoutSqlite);

  testWidgets('an empty box is refused with a nudge', (tester) async {
    final (adapter, dependencies) = _harness();
    addTearDown(dependencies.database.close);

    await tester.pumpWidget(_page(adapter, dependencies));
    await tester.tap(find.text('Import from link'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Paste a Spotify link first'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  }, skip: _skipWithoutSqlite);
}
