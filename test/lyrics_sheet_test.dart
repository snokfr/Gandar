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
import 'package:gandar/data/lyrics/lyrics_source.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/data/usage/app_usage.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/features/player/lyrics_view.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/preloader.dart';
import 'package:gandar/state/app_dependencies.dart';
import 'package:gandar/state/playback_controller.dart';
import 'package:gandar/state/providers.dart';
import 'package:gandar/state/retry_policy.dart';

import 'helpers.dart';

const Track _track = Track(
  id: 'a',
  title: 'One',
  artists: <String>['Artist'],
  durationMs: 180000,
);

const Track _other = Track(
  id: 'b',
  title: 'Two',
  artists: <String>['Artist'],
  durationMs: 200000,
);

const String _lrc = '''
[00:10.00] first line
[00:14.00] second line
[00:18.00] third line
''';

/// Lyrics with timestamps, without a network call.
class _FakeLyrics implements LyricsSource {
  const _FakeLyrics();

  @override
  Future<Lyrics?> lookup(Track track) async => const Lyrics(
    plain: 'first line\nsecond line\nthird line',
    synced: _lrc,
    attribution: 'test',
  );
}

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

/// The app's dependencies over an in-memory library, with the engine in hand so
/// the test can see what the song was actually told to do.
class _Harness {
  _Harness(this.dependencies, this.engine, this.controller);

  final AppDependencies dependencies;
  final FakeAudioEngine engine;
  final PlaybackController controller;
}

Future<_Harness> _harness() async {
  final database = AppDatabase.withExecutor(NativeDatabase.memory());
  const resolver = _StubResolver();
  final library = DriftLibraryRepository(database);
  await library.upsertTracks(<Track>[_track, _other]);
  final engine = FakeAudioEngine();
  final controller = PlaybackController(
    engine: engine,
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
    audioEngine: engine,
    createMixEngine: FakeAudioEngine.new,
    playbackController: controller,
    appUsage: AppUsageTracker(store: InMemoryStore()),
  );
  return _Harness(dependencies, engine, controller);
}

Widget _sheet(_Harness harness, Track track) => ProviderScope(
  retry: gandarProviderRetry,
  overrides: [
    appDependenciesProvider.overrideWithValue(harness.dependencies),
    lyricsSourceProvider.overrideWithValue(const _FakeLyrics()),
  ],
  child: MaterialApp(
    theme: ThemeEngine.build(ThemePresets.spotifyClassic),
    home: Scaffold(body: LyricsSheet(track: track)),
  ),
);

final bool _skipWithoutSqlite = !sqliteAvailable;

/// The style a line is rendered with, read off the widget rather than off the
/// cross-fade that is mid-flight.
TextStyle _styleOf(WidgetTester tester, String line) {
  AnimatedDefaultTextStyle? found;
  tester.element(find.text(line)).visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is AnimatedDefaultTextStyle) {
      found = widget;
      return false;
    }
    return true;
  });
  return found!.style;
}

void main() {
  late _Harness harness;

  setUp(() async {
    harness = await _harness();
  });
  tearDown(() {
    harness.controller.dispose();
    return harness.dependencies.database.close();
  });

  testWidgets('tapping a line moves the playing song to that line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A queue of one, so the song under the sheet is the song playing no
    // matter which way shuffle happens to order the library.
    await harness.controller.playTracks(<Track>[_track]);
    await tester.pumpWidget(_sheet(harness, _track));
    await tester.pumpAndSettle();

    // The words are tappable, and the sheet says so.
    expect(find.textContaining('tap any line'), findsOneWidget);
    expect(find.byType(InkWell), findsWidgets);

    // The song is at the first line; tapping the third line jumps to it.
    await tester.tap(find.text('third line'));
    await tester.pumpAndSettle();

    expect(harness.engine.seeks.last, const Duration(seconds: 18));
    expect(
      _styleOf(tester, 'third line').fontWeight,
      FontWeight.w700,
      reason: 'the highlight follows the seek, because it follows the player',
    );

    // And back again, which is the case where the line has already gone by.
    await tester.tap(find.text('first line'));
    await tester.pumpAndSettle();

    expect(harness.engine.seeks.last, const Duration(seconds: 10));
    expect(_styleOf(tester, 'first line').fontWeight, FontWeight.w700);
    expect(_styleOf(tester, 'third line').fontWeight, isNot(FontWeight.w700));
  }, skip: _skipWithoutSqlite);

  testWidgets("another track's lyrics are words, not places to jump to", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Two is playing; the sheet is opened for One, the way the queue lets you
    // read ahead at what is coming.
    await harness.controller.playTracks(<Track>[_other]);
    await tester.pumpWidget(_sheet(harness, _track));
    await tester.pumpAndSettle();

    expect(find.textContaining('another song'), findsOneWidget);
    await tester.tap(find.text('third line'));
    await tester.pumpAndSettle();

    expect(
      harness.engine.seeks,
      isEmpty,
      reason: 'the wrong song must not be moved by a tap on these words',
    );
    expect(find.text('third line'), findsOneWidget);
  }, skip: _skipWithoutSqlite);
}
