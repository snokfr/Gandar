import 'dart:io';

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
import 'package:gandar/data/mashup/mashup_store.dart';
import 'package:gandar/data/repositories/local_repositories.dart';
import 'package:gandar/data/storage/app_database.dart';
import 'package:gandar/data/usage/app_usage.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/features/mashup/mashup_page.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/preloader.dart';
import 'package:gandar/state/app_dependencies.dart';
import 'package:gandar/state/playback_controller.dart';
import 'package:gandar/state/providers.dart';
import 'package:gandar/state/retry_policy.dart';
import 'package:gandar/widgets/common.dart';

import 'helpers.dart';

const List<Track> _library = <Track>[
  Track(
    id: 'a',
    title: 'Song A',
    artists: <String>['Artist'],
    durationMs: 180000,
  ),
  Track(
    id: 'b',
    title: 'Song B',
    artists: <String>['Artist'],
    durationMs: 240000,
  ),
];

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

/// The players the page asks for, so the test can check what each part got.
class _Players {
  final List<FakeAudioEngine> engines = <FakeAudioEngine>[];

  FakeAudioEngine create() {
    final engine = FakeAudioEngine();
    engines.add(engine);
    return engine;
  }
}

/// Lyrics that are simply absent, so no test reaches the network.
class _NoLyrics implements LyricsSource {
  const _NoLyrics();

  @override
  Future<Lyrics?> lookup(Track track) async => null;
}

/// Timed words for Song A only, so the words card can be checked without a
/// network, and so a part with nothing to show is visible in the same test.
class _TimedLyrics implements LyricsSource {
  const _TimedLyrics();

  @override
  Future<Lyrics?> lookup(Track track) async => track.id == 'a'
      ? const Lyrics(
          plain: 'first line\nsecond line',
          synced: '[00:10.00] first line\n[00:14.00] second line\n',
          attribution: 'test',
        )
      : null;
}

Future<(AppDependencies, _Players)> _harness() async {
  final database = AppDatabase.withExecutor(NativeDatabase.memory());
  const resolver = _StubResolver();
  final library = DriftLibraryRepository(database);
  await library.upsertTracks(_library);
  final players = _Players();
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
    createMixEngine: players.create,
    playbackController: PlaybackController(
      engine: FakeAudioEngine(),
      preloader: StreamPreloader(resolver: resolver),
      library: library,
      settings: const PlaybackSettings(),
    ),
    appUsage: AppUsageTracker(store: InMemoryStore()),
  );
  return (dependencies, players);
}

/// A store pointed at a throwaway directory, so a test never writes a mashup
/// into the real Gandar data folder.
MashupStore _temporaryStore() {
  final directory = Directory.systemTemp.createTempSync('gandar-mashups-test');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return MashupStore(directory: directory);
}

Widget _page(
  AppDependencies dependencies,
  MashupStore store, {
  LyricsSource lyrics = const _NoLyrics(),
}) => ProviderScope(
  retry: gandarProviderRetry,
  overrides: [
    appDependenciesProvider.overrideWithValue(dependencies),
    mashupStoreProvider.overrideWithValue(store),
    lyricsSourceProvider.overrideWithValue(lyrics),
  ],
  child: MaterialApp(
    theme: ThemeEngine.build(ThemePresets.spotifyClassic),
    home: const MashupPage(),
  ),
);

/// Pumps a few short frames.
///
/// Not `pumpAndSettle`: a running mix has a 50 ms clock behind it, so frames
/// keep being scheduled and settling would run the whole arrangement out.
Future<void> _frames(WidgetTester tester, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

/// Picks the library's songs into the mix through the real picker, then closes
/// it — the way the screen is actually used.
Future<void> _addBothSongs(WidgetTester tester) async {
  await tester.tap(find.text('Add songs').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Song A'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Song B'));
  await tester.pumpAndSettle();
  // Dismiss the sheet by tapping the barrier above it.
  await tester.tapAt(const Offset(400, 12));
  await tester.pumpAndSettle();
}

final bool _skipWithoutSqlite = !sqliteAvailable;

/// Stands in for the app shell: one `ProviderScope`, and the mashup screen
/// swapped out of it and back, which is exactly what changing tabs does. The
/// scope stays; the route's widgets do not.
class _Shell extends StatefulWidget {
  const _Shell({super.key});

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool _onMashup = true;

  void goToOtherTab() => setState(() => _onMashup = false);

  void comeBack() => setState(() => _onMashup = true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _onMashup
          ? const MashupPage()
          : Center(
              child: TextButton(
                onPressed: comeBack,
                child: const Text('Back to the mashup'),
              ),
            ),
      floatingActionButton: _onMashup
          ? FloatingActionButton.extended(
              onPressed: goToOtherTab,
              label: const Text('Other tab'),
              icon: const Icon(Icons.tab),
            )
          : null,
    );
  }
}

void main() {
  testWidgets('two songs become two layered parts with their own controls', (
    tester,
  ) async {
    final (dependencies, _) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(dependencies, _temporaryStore()));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to mix yet'), findsOneWidget);
    // The header offers the picker, and the empty state offers it too.
    expect(find.text('Add songs'), findsNWidgets(2));

    await _addBothSongs(tester);

    // Each song is a part of the arrangement, drawn on the timeline.
    expect(find.text('2 songs · 6:56 mix · 1 overlap'), findsOneWidget);
    expect(find.text('1. Song A'), findsOneWidget);
    expect(find.text('2. Song B'), findsOneWidget);
    // The second one is pulled back onto the first by the default blend, which
    // is what makes this a mix rather than a playlist: 3:00 minus 4 s.
    expect(find.textContaining('enters 2:56'), findsOneWidget);

    // The controls the mix is made with, for the part being edited.
    expect(find.text('Starts at'), findsOneWidget);
    expect(find.text('Ends at'), findsOneWidget);
    expect(find.text('Enters the mix at'), findsWidgets);
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('Blend'), findsOneWidget);
    // Both the part's own slice and where it lands in the mix are stated.
    expect(find.textContaining('of the mix'), findsWidgets);
  }, skip: _skipWithoutSqlite);

  testWidgets('the blend slider decides the overlap, and zero removes it', (
    tester,
  ) async {
    final (dependencies, _) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(dependencies, _temporaryStore()));
    await _addBothSongs(tester);

    expect(find.text('2 songs · 6:56 mix · 1 overlap'), findsOneWidget);
    expect(find.textContaining('1 seam where two songs'), findsOneWidget);

    final blendSlider = find.descendant(
      of: find.ancestor(
        of: find.text('Blend'),
        matching: find.byType(SettingSliderTile),
      ),
      matching: find.byType(Slider),
    );
    // Drag the blend to zero: the parts stop overlapping and are simply in
    // order, which the screen says in as many words.
    await tester.drag(blendSlider, const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Nothing overlaps, so this plays as a plain sequence. '
        'Raise the blend to mash them.'), findsOneWidget);
    // End to end: 3:00 + 4:00 with nothing shared.
    expect(find.text('2 songs · 7:00 mix'), findsOneWidget);
  }, skip: _skipWithoutSqlite);

  testWidgets('playing the mix primes one player per part and reports state', (
    tester,
  ) async {
    final (dependencies, players) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(dependencies, _temporaryStore()));
    await _addBothSongs(tester);

    expect(players.engines, isEmpty);
    await tester.tap(find.text('Play the mix'));
    await _frames(tester, count: 10);

    // One player per part, each with its own source, trim and level.
    expect(players.engines, hasLength(2));
    expect(players.engines[0].loadedUrls, <String>['https://cdn.test/a.m4a']);
    expect(players.engines[1].loadedUrls, <String>['https://cdn.test/b.m4a']);
    expect(players.engines[0].trim, const Duration(seconds: 180));
    expect(players.engines[1].trim, const Duration(seconds: 240));
    expect(players.engines.first.volumes.last, lessThan(1.0));

    // The transport says what is happening, layer by layer.
    expect(find.text('Mixing'), findsOneWidget);
    expect(find.text('Stop the mix'), findsOneWidget);
    expect(find.text('1 · playing'), findsOneWidget);
    expect(find.text('2 · waiting'), findsOneWidget);

    // Stopping gives the transport back and puts every part back to waiting,
    // without waiting on the players to say they have let go.
    await tester.tap(find.text('Stop the mix'));
    await _frames(tester, count: 8);
    expect(find.text('Play the mix'), findsOneWidget);
    expect(find.text('1 · waiting'), findsOneWidget);
  }, skip: _skipWithoutSqlite);

  testWidgets('the timeline takes the mix to the moment it is pressed', (
    tester,
  ) async {
    final (dependencies, players) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(dependencies, _temporaryStore()));
    await _addBothSongs(tester);
    await tester.tap(find.text('Play the mix'));
    await _frames(tester, count: 10);

    await tester.ensureVisible(find.byKey(timelineKey));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(timelineKey));

    // Half way through a 6:56 mix is 3:28 — inside Song B's part, which starts
    // at 2:56, so that is 32 s into the song itself.
    await tester.tapAt(Offset(rect.left + rect.width / 2, rect.center.dy));
    await _frames(tester, count: 8);

    expect(find.text('3:28 / 6:56'), findsOneWidget);
    expect(players.engines[1].seeks.last, const Duration(seconds: 32));

    // And dragging keeps moving it, which is how a mix is listened through.
    await tester.dragFrom(
      Offset(rect.left + rect.width / 2, rect.center.dy),
      Offset(rect.width / 4, 0),
    );
    await _frames(tester, count: 8);

    // Three quarters of the way is 5:12, which is 2:16 into Song B.
    expect(find.text('5:12 / 6:56'), findsOneWidget);
    expect(players.engines[1].seeks.last, const Duration(minutes: 2, seconds: 16));

    // The part under the playhead is named in the words card, which is the
    // same arithmetic from the other direction.
    expect(find.text('Song B'), findsWidgets);
  }, skip: _skipWithoutSqlite);

  testWidgets('a part can be jumped to, wherever the mix happens to be', (
    tester,
  ) async {
    final (dependencies, _) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(dependencies, _temporaryStore()));
    await _addBothSongs(tester);

    // The part that was just added is the one whose controls are open, and it
    // enters the mix at 2:56.
    await tester.tap(find.text('Jump here'));
    await _frames(tester, count: 6);

    expect(find.text('2:56 / 6:56'), findsOneWidget);
  }, skip: _skipWithoutSqlite);

  testWidgets('a mix is saved under a name and opened again for editing', (
    tester,
  ) async {
    final (dependencies, _) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = _temporaryStore();
    await tester.pumpWidget(_page(dependencies, store));
    await _addBothSongs(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test blend');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();

    // The arrangement really is on disk, under the name it was given.
    final saved = await store.list();
    expect(saved.single.name, 'Test blend');
    expect(saved.single.mashup.parts, hasLength(2));
    expect(
      find.textContaining('Saved “Test blend”'),
      findsOneWidget,
    );

    // Clearing the mix leaves the saved mashup listed and openable — which is
    // the whole point of saving one.
    await tester.tap(find.byTooltip('Clear the mix'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Clear'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing to mix yet'), findsOneWidget);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('2 songs · 6:56 mix · 1 overlap'), findsOneWidget);
    expect(
      find.text('Mashup · Test blend'),
      findsOneWidget,
      reason: 'the reopened mix is named, so it is clear what is being edited',
    );
  }, skip: _skipWithoutSqlite);

  testWidgets('the words of each part are listed, and a line moves the mix', (
    tester,
  ) async {
    final (dependencies, _) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _page(dependencies, _temporaryStore(), lyrics: const _TimedLyrics()),
    );
    await _addBothSongs(tester);

    await tester.ensureVisible(find.text('The words'));
    await tester.pumpAndSettle();

    // Both lines are inside Song A's slice, so both are listed — with the time
    // they fall at — and the part with no words says so instead of showing an
    // empty box.
    expect(find.text('first line'), findsOneWidget);
    expect(find.text('second line'), findsOneWidget);
    expect(find.text('0:10'), findsOneWidget);
    expect(find.text('No words found for this song.'), findsOneWidget);

    // Tapping a line moves the mix to that line: part one enters at 0:00, so
    // its 0:14 line is 0:14 of the mix.
    await tester.tap(find.text('second line'));
    await _frames(tester, count: 6);

    expect(find.text('0:14 / 6:56'), findsOneWidget);
  }, skip: _skipWithoutSqlite);

  testWidgets('the mix and its arrangement survive leaving the tab', (
    tester,
  ) async {
    final (dependencies, players) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final shell = GlobalKey<_ShellState>();
    await tester.pumpWidget(
      ProviderScope(
        retry: gandarProviderRetry,
        overrides: [
          appDependenciesProvider.overrideWithValue(dependencies),
          mashupStoreProvider.overrideWithValue(_temporaryStore()),
          lyricsSourceProvider.overrideWithValue(const _NoLyrics()),
        ],
        child: MaterialApp(
          theme: ThemeEngine.build(ThemePresets.spotifyClassic),
          home: _Shell(key: shell),
        ),
      ),
    );
    await _addBothSongs(tester);
    await tester.tap(find.text('Play the mix'));
    await _frames(tester, count: 10);
    expect(players.engines, hasLength(2));
    expect(find.text('2 songs · 6:56 mix · 1 overlap'), findsOneWidget);

    // Look something up in another tab: the screen goes, the mix does not.
    await tester.tap(find.text('Other tab'));
    await _frames(tester, count: 6);
    expect(find.text('2 songs · 6:56 mix · 1 overlap'), findsNothing);
    expect(
      players.engines.first.state,
      EngineState.playing,
      reason: 'the players belong to the app, not to the screen',
    );

    // Coming back shows the same arrangement, still playing.
    await tester.tap(find.text('Back to the mashup'));
    await _frames(tester, count: 6);
    expect(find.text('2 songs · 6:56 mix · 1 overlap'), findsOneWidget);
    expect(find.text('1 · playing'), findsOneWidget);
    expect(players.engines, hasLength(2));
  }, skip: _skipWithoutSqlite);

  testWidgets('an empty mix offers no transport at all', (tester) async {
    final (dependencies, _) = await _harness();
    addTearDown(dependencies.database.close);
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(dependencies, _temporaryStore()));
    await tester.pumpAndSettle();

    expect(find.text('Play the mix'), findsNothing);
    expect(find.text('Blend'), findsNothing);
  }, skip: _skipWithoutSqlite);
}
