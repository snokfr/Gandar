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
import 'package:gandar/data/youtube/youtube_search.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/features/artists/artist_page.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/preloader.dart';
import 'package:gandar/state/app_dependencies.dart';
import 'package:gandar/state/playback_controller.dart';
import 'package:gandar/state/providers.dart';
import 'package:gandar/state/retry_policy.dart';

import 'helpers.dart';

/// Shuffle off, so "play all" queues the artist's songs in the order the
/// library has them and the test can say what that order is.
const PlaybackSettings _settings = PlaybackSettings(
  shuffleMode: ShuffleMode.off,
);

const List<Track> _library = <Track>[
  Track(
    id: 'a',
    title: 'One',
    artists: <String>['Ariana Grande'],
    album: 'Sweetener',
    durationMs: 180000,
  ),
  Track(
    id: 'b',
    title: 'Two',
    artists: <String>['Ariana Grande', 'The Weeknd'],
    album: 'Sweetener',
    durationMs: 200000,
  ),
  Track(
    id: 'c',
    title: 'Three',
    artists: <String>['The Weeknd'],
    album: 'After Hours',
    durationMs: 240000,
  ),
  // A name that merely starts like the artist's, to prove the page is a
  // filter over the library and not a search box.
  Track(id: 'd', title: 'Four', artists: <String>['Ari'], durationMs: 100000),
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

Future<AppDependencies> _harness() async {
  final database = AppDatabase.withExecutor(NativeDatabase.memory());
  const resolver = _StubResolver();
  final library = DriftLibraryRepository(database);
  await library.upsertTracks(_library);
  return AppDependencies(
    database: database,
    settingsRepository: SettingsRepository(InMemoryStore()),
    playbackSettings: _settings,
    activeTheme: ThemePresets.spotifyClassic,
    customThemes: const <ThemeTokens>[],
    mappingRepository: DriftMappingRepository(database),
    cacheRepository: DriftCacheRepository(database),
    libraryRepository: library,
    cacheManager: CacheManager(repository: DriftCacheRepository(database)),
    audioResolver: resolver,
    audioEngine: FakeAudioEngine(),
    createMixEngine: FakeAudioEngine.new,
    playbackController: PlaybackController(
      engine: FakeAudioEngine(),
      preloader: StreamPreloader(resolver: resolver),
      library: library,
      settings: _settings,
    ),
    appUsage: AppUsageTracker(store: InMemoryStore()),
  );
}

late AppDependencies _dependencies;

/// What YouTube "has" for an artist, without a network: enough to prove the
/// catalogue half of the page is wired to a search and can be played from.
const List<YouTubeVideo> _catalogue = <YouTubeVideo>[
  YouTubeVideo(
    videoId: 'v1',
    title: 'One (Official Video)',
    author: 'Ariana Grande',
    duration: Duration(minutes: 3, seconds: 20),
  ),
  YouTubeVideo(
    videoId: 'v2',
    title: 'Two (Live)',
    author: 'Ariana Grande',
    duration: Duration(minutes: 4),
  ),
];

Widget _page(String artistName) => ProviderScope(
  retry: gandarProviderRetry,
  overrides: [
    appDependenciesProvider.overrideWithValue(_dependencies),
    youTubeSearcherProvider.overrideWithValue(
      YouTubeSearcher(
        fetch: (query, limit) async => query.contains('Nobody') ? const [] : _catalogue,
      ),
    ),
  ],
  child: MaterialApp(
    theme: ThemeEngine.build(ThemePresets.spotifyClassic),
    home: ArtistPage(artistName: artistName),
  ),
);

final bool _skipWithoutSqlite = !sqliteAvailable;

void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 1500);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() async {
    _dependencies = await _harness();
  });
  tearDown(() => _dependencies.database.close());

  testWidgets('an artist page lists that artist and nobody else', (
    tester,
  ) async {
    _tallWindow(tester);
    await tester.pumpWidget(_page('Ariana Grande'));
    await tester.pumpAndSettle();

    // The songs the artist is credited on, including the one where they share
    // the credit with someone else.
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    // Songs by a *similar* name, and by the collaborator alone, are somebody
    // else's.
    expect(find.text('Four'), findsNothing);
    expect(find.text('Three'), findsNothing);
    expect(find.textContaining('2 tracks in your library'), findsOneWidget);
  }, skip: _skipWithoutSqlite);

  testWidgets('the name comes from the library, not from the route', (
    tester,
  ) async {
    _tallWindow(tester);
    await tester.pumpWidget(_page('ariana grande'));
    await tester.pumpAndSettle();

    // Once in the header, and again on each song that credits them.
    expect(find.text('Ariana Grande'), findsWidgets);
    expect(find.text('ariana grande'), findsNothing);
  }, skip: _skipWithoutSqlite);

  testWidgets('play all queues everything the artist has here', (tester) async {
    _tallWindow(tester);
    await tester.pumpWidget(_page('Ariana Grande'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play all'));
    await tester.pumpAndSettle();

    // The queue is the artist's tracks, and the first one is playing.
    final controller = _dependencies.playbackController;
    expect(controller.queue.map((t) => t.id), <String>['a', 'b']);
    expect(controller.currentTrack?.id, 'a');
  }, skip: _skipWithoutSqlite);

  testWidgets('the catalogue is separate from the library, and playable', (
    tester,
  ) async {
    _tallWindow(tester);
    await tester.pumpWidget(_page('Ariana Grande'));
    await tester.pumpAndSettle();

    // The two halves are named for what they are: one is a fact about this
    // machine, the other is a search result.
    expect(find.text('In your library'), findsOneWidget);
    expect(find.text('More from Ariana Grande'), findsOneWidget);
    expect(find.textContaining('From YouTube — playable, not imported'), findsOneWidget);

    expect(find.text('One (Official Video)'), findsOneWidget);
    expect(find.text('Two (Live)'), findsOneWidget);

    // Playing a result queues the results, entered at the row that was tapped,
    // so a stream carries on down the list like anything else.
    await tester.tap(find.text('Two (Live)'));
    await tester.pumpAndSettle();

    final controller = _dependencies.playbackController;
    expect(controller.queue.map((t) => t.id), <String>[
      'youtube:v1',
      'youtube:v2',
    ]);
    expect(controller.currentTrack?.id, 'youtube:v2');
  }, skip: _skipWithoutSqlite);

  testWidgets('an artist nothing here is by says so, and still lists them', (
    tester,
  ) async {
    _tallWindow(tester);
    await tester.pumpWidget(_page('Nobody At All'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing imported yet'), findsOneWidget);
    expect(
      find.textContaining('none of it is by this artist yet'),
      findsOneWidget,
    );
    expect(find.text('Play all'), findsNothing);
    // No YouTube results for this one either, and that is said out loud rather
    // than shown as an empty box.
    expect(find.text('More from Nobody At All'), findsOneWidget);
    expect(find.textContaining('YouTube returned nothing'), findsOneWidget);
  }, skip: _skipWithoutSqlite);
}
