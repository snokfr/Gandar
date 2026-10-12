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
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/data/usage/app_usage.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/features/player/player_surface.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/preloader.dart';
import 'package:gandar/state/app_dependencies.dart';
import 'package:gandar/state/playback_controller.dart';
import 'package:gandar/state/providers.dart';
import 'package:gandar/state/retry_policy.dart';

import 'helpers.dart';

const Track _track = Track(
  id: 't1',
  title: 'stranger',
  artists: <String>['Jhéné Aiko'],
  album: 'Sailor',
  durationMs: 152000,
);

class _StubResolver implements AudioResolver {
  const _StubResolver();

  @override
  void setAudioQuality(AudioQuality quality) {}

  @override
  Future<ResolvedStream> resolve(Track track) async => ResolvedStream(
    url: 'https://cdn.test/${track.id}.m4a',
    videoId: 'v-${track.id}',
    container: 'm4a',
    headers: const <String, String>{},
  );
}

(AppDependencies, PlaybackController) _harness() {
  final database = AppDatabase.withExecutor(NativeDatabase.memory());
  addTearDown(database.close);
  const resolver = _StubResolver();
  final library = DriftLibraryRepository(database);
  final controller = PlaybackController(
    engine: FakeAudioEngine(),
    preloader: StreamPreloader(resolver: resolver),
    library: library,
    settings: const PlaybackSettings(),
  );
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
    playbackController: controller,
    appUsage: AppUsageTracker(store: InMemoryStore()),
  );
  return (dependencies, controller);
}

Widget _bar(AppDependencies dependencies) => ProviderScope(
  retry: gandarProviderRetry,
  overrides: [appDependenciesProvider.overrideWithValue(dependencies)],
  child: MaterialApp(
    theme: ThemeEngine.build(ThemePresets.spotifyClassic),
    home: Scaffold(body: Column(children: [const Spacer(), const PlayerBar()])),
  ),
);

/// A desktop window, which is the only place this bar is drawn at all: below
/// the 900 px breakpoint the shell shows the mini player instead.
void _desktopWindow(WidgetTester tester, {double width = 1280}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // The bar records play history through the real library, so it needs a
  // working SQLite; skipped rather than failing obscurely without one.
  final skip = !sqliteAvailable;

  testWidgets('the bar shows elapsed, total length and time remaining', (
    tester,
  ) async {
    _desktopWindow(tester);
    final (dependencies, controller) = _harness();
    await controller.playTracks(<Track>[_track]);
    controller.positionNotifier.value = const Duration(seconds: 13);
    controller.durationNotifier.value = const Duration(minutes: 2, seconds: 32);

    await tester.pumpWidget(_bar(dependencies));
    await tester.pump();

    expect(find.text('0:13'), findsOneWidget, reason: 'elapsed');
    expect(find.text('2:32'), findsOneWidget, reason: 'total length');
    // 2:32 - 0:13 = 2:19, and it is shown as a countdown rather than a second
    // absolute time, which would be the same as the total.
    expect(find.text('-2:19'), findsOneWidget, reason: 'time remaining');

    // The regression this test exists for: the centre column used to be 48 px
    // of transport buttons plus a 48 px Slider plus the times, inside an 84 px
    // bar. It overflowed and the times were clipped away — a bar with no time
    // on it at all. A RenderFlex overflow raises in a widget test, so reaching
    // this line at all is the assertion.
    expect(tester.takeException(), isNull);
  }, skip: skip);

  testWidgets('the bar still fits at the narrowest desktop width', (
    tester,
  ) async {
    // 900 px is where the shell switches to the desktop layout, so it is the
    // tightest this bar is ever asked to be. Its three groups plus the seek bar
    // have to fit there, and a fixed-width seek bar in the middle is what stops
    // them.
    _desktopWindow(tester, width: 900);
    final (dependencies, controller) = _harness();
    await controller.playTracks(<Track>[_track]);
    controller.positionNotifier.value = const Duration(seconds: 13);
    controller.durationNotifier.value = const Duration(minutes: 2, seconds: 32);

    await tester.pumpWidget(_bar(dependencies));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Everything on the bar is still reachable, including the last control.
    expect(find.byTooltip('Now playing'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Lyrics'), findsOneWidget);
    expect(find.text('-2:19'), findsOneWidget);
  }, skip: skip);

  testWidgets('the bar offers a lyrics button for the current track', (
    tester,
  ) async {
    _desktopWindow(tester);
    final (dependencies, controller) = _harness();
    await controller.playTracks(<Track>[_track]);

    await tester.pumpWidget(_bar(dependencies));
    await tester.pump();

    expect(find.byTooltip('Lyrics'), findsOneWidget);
    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
  }, skip: skip);

  testWidgets('with nothing playing the times are zero, not blank', (
    tester,
  ) async {
    _desktopWindow(tester);
    final (dependencies, _) = _harness();

    await tester.pumpWidget(_bar(dependencies));
    await tester.pump();

    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.text('0:00'), findsNWidgets(2));
    expect(find.text('-0:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: skip);

  testWidgets('the lyrics button is disabled when nothing is playing', (
    tester,
  ) async {
    _desktopWindow(tester);
    final (dependencies, _) = _harness();

    await tester.pumpWidget(_bar(dependencies));
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.lyrics_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  }, skip: skip);
}
