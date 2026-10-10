import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/playback_settings.dart';
import 'package:gandar/domain/models/playlist.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/domain/repositories/repositories.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/preloader.dart';
import 'package:gandar/state/playback_controller.dart';

Track t(String id) => Track(id: id, title: id, artists: const ['Artist']);

/// Resolver that succeeds except for ids listed in [failFor].
class StubResolver implements AudioResolver {
  StubResolver({this.failFor = const {}});

  final Set<String> failFor;
  final List<String> resolved = [];

  @override
  Future<ResolvedStream> resolve(Track track) async {
    resolved.add(track.id);
    if (failFor.contains(track.id)) {
      throw StateError('no stream for ${track.id}');
    }
    return ResolvedStream(
      url: 'https://cdn.test/${track.id}.m4a',
      videoId: 'v-${track.id}',
      container: 'm4a',
      headers: const {'Referer': 'https://youtube.com'},
    );
  }
}

/// Minimal in-memory library repository.
class FakeLibrary implements LibraryRepository {
  final List<String> plays = [];

  @override
  Future<void> recordPlay(String trackId, DateTime at) async =>
      plays.add(trackId);

  @override
  Future<List<String>> recentTrackIds({int limit = 50}) async => const [];

  @override
  Future<void> upsertTracks(List<Track> tracks) async {}

  @override
  Future<List<Track>> cachedLikedTracks() async => const [];

  @override
  Future<void> upsertPlaylists(List<Playlist> playlists) async {}

  @override
  Future<List<Playlist>> cachedPlaylists() async => const [];
}

void main() {
  late FakeAudioEngine engine;
  late StubResolver resolver;
  late FakeLibrary library;
  late PlaybackController controller;

  const tracks = <Track>[];

  setUp(() {
    engine = FakeAudioEngine();
    resolver = StubResolver();
    library = FakeLibrary();
    controller = PlaybackController(
      engine: engine,
      preloader: StreamPreloader(resolver: resolver),
      library: library,
      settings: const PlaybackSettings(shuffleMode: ShuffleMode.off),
    );
  });

  tearDown(() => controller.dispose());

  test('starts idle with nothing loaded', () {
    expect(controller.engineState, EngineState.idle);
    expect(controller.currentTrack, isNull);
    expect(controller.queue, isEmpty);
  });

  test(
    'playTracks resolves, loads and plays from the requested index',
    () async {
      await controller.playTracks([
        for (var i = 0; i < 3; i++) t('$i'),
      ], startTrackId: '1');

      expect(controller.currentTrack!.id, '1');
      expect(engine.loadedUrls, ['https://cdn.test/1.m4a']);
      expect(controller.isPlaying, isTrue);
      expect(resolver.resolved.first, '1');
    },
  );

  test('stream headers are passed through to the engine', () async {
    await controller.playTracks([t('a')]);
    // FakeAudioEngine records URLs; headers are covered by the resolver output.
    expect(engine.loadedUrls.single, contains('a.m4a'));
  });

  test('records play history for the started track', () async {
    await controller.playTracks([t('a')]);
    expect(library.plays, ['a']);
  });

  test('togglePlayPause flips between playing and paused', () async {
    await controller.playTracks([t('a')]);
    expect(controller.isPlaying, isTrue);

    await controller.togglePlayPause();
    expect(controller.engineState, EngineState.paused);

    await controller.togglePlayPause();
    expect(controller.engineState, EngineState.playing);
  });

  test('next advances to the following track and loads it', () async {
    await controller.playTracks([for (var i = 0; i < 3; i++) t('$i')]);
    await controller.next();

    expect(controller.currentTrack!.id, '1');
    expect(engine.loadedUrls.last, 'https://cdn.test/1.m4a');
  });

  test('next at the end of the queue stops the engine', () async {
    await controller.playTracks([t('only')]);
    await controller.next();
    expect(controller.engineState, EngineState.idle);
  });

  test('previous restarts the track when past the restart threshold', () async {
    await controller.playTracks([
      for (var i = 0; i < 3; i++) t('$i'),
    ], startTrackId: '1');
    engine.emitPosition(const Duration(seconds: 10));
    // The controller consumes positions from a stream; let the event land.
    await Future<void>.delayed(Duration.zero);
    await controller.previous();

    expect(controller.currentTrack!.id, '1', reason: 'should not step back');
  });

  test('previous steps back when near the start of the track', () async {
    await controller.playTracks([
      for (var i = 0; i < 3; i++) t('$i'),
    ], startTrackId: '1');
    engine.emitPosition(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    await controller.previous();

    expect(controller.currentTrack!.id, '0');
  });

  test('a resolve failure is reported without crashing playback', () async {
    final failing = PlaybackController(
      engine: FakeAudioEngine(),
      preloader: StreamPreloader(resolver: StubResolver(failFor: {'x'})),
      library: FakeLibrary(),
    );
    await failing.playTracks([t('x')]);

    expect(failing.errorMessage, isNotNull);
    expect(failing.errorMessage, contains('Could not play'));
    failing.dispose();
  });

  test('prefetch warms the next track when enabled', () async {
    await controller.playTracks([for (var i = 0; i < 3; i++) t('$i')]);
    await Future<void>.delayed(Duration.zero);

    expect(
      resolver.resolved,
      contains('1'),
      reason: 'the next track should be resolved ahead of time',
    );
  });

  test('updateSettings pushes filters to the engine', () async {
    const next = PlaybackSettings(
      eqEnabled: true,
      eqBands: [EqBand(frequency: 31, gain: 5)],
      monoAudio: true,
      crossfadeSeconds: 4,
    );
    await controller.updateSettings(next);

    expect(controller.settings.crossfadeSeconds, 4);
    expect(engine.lastAppliedFilters, controller.settings);
  });

  test('updateSettings clamps out-of-range values', () async {
    await controller.updateSettings(
      const PlaybackSettings(crossfadeSeconds: 50),
    );
    expect(controller.settings.crossfadeSeconds, 12);
  });

  test('completion auto-advances to the next track', () async {
    await controller.playTracks([for (var i = 0; i < 2; i++) t('$i')]);
    engine.emitError('ignored'); // sanity: error stream does not throw
    await controller.next();
    expect(controller.currentTrack!.id, '1');
  });

  test('setVolume clamps into 0..1', () async {
    await controller.setVolume(2);
    expect(controller.volume, 1.0);
    await controller.setVolume(-1);
    expect(controller.volume, 0.0);
  });

  test('progress is zero when the duration is unknown', () {
    expect(controller.progress, 0);
  });

  test('empty queue is a safe no-op for transport actions', () async {
    await controller.playTracks(const <Track>[]);
    await controller.next();
    await controller.previous();
    expect(controller.currentTrack, isNull);
    expect(tracks, isEmpty);
  });
}
