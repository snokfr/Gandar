import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/domain/models/mashup.dart';
import 'package:gandar/domain/models/resolved_stream.dart';
import 'package:gandar/domain/models/track.dart';
import 'package:gandar/playback/audio_engine/audio_engine.dart';
import 'package:gandar/playback/mix/mashup_mixer.dart';

Track _track(String id, {int seconds = 60}) => Track(
  id: id,
  title: 'Song $id',
  artists: const <String>['Artist'],
  durationMs: seconds * 1000,
);

Duration _ms(int value) => Duration(milliseconds: value);

/// Collects the players the mixer asks for so the test can inspect each layer.
class _EngineFarm {
  final List<FakeAudioEngine> engines = <FakeAudioEngine>[];
  final List<String> resolvedFor = <String>[];

  FakeAudioEngine create() {
    final engine = FakeAudioEngine();
    engines.add(engine);
    return engine;
  }

  Future<ResolvedStream> resolve(Track track) async {
    resolvedFor.add(track.id);
    return ResolvedStream(
      url: 'https://cdn.test/${track.id}.m4a',
      videoId: 'v-${track.id}',
      container: 'm4a',
      headers: const <String, String>{},
    );
  }
}

/// Two ten-second slices that overlap by four seconds: the first plays 0-10 s
/// of the mix from 5-15 s of its own song, the second enters at 6 s playing
/// 30-40 s of its own song.
Mashup _twoPartMix() => Mashup(
  blend: const Duration(seconds: 4),
  parts: <MashupPart>[
    MashupPart.whole(_track('a', seconds: 60))
        .withStart(_ms(5000))
        .withEnd(_ms(15000)),
    MashupPart.whole(_track('b', seconds: 60))
        .withStart(_ms(30000))
        .withEnd(_ms(40000))
        .withOffset(_ms(6000)),
  ],
);

Future<void> _settle() => Future<void>.delayed(_ms(60));

void main() {
  test('preparing resolves, loads, seeks and trims every part', () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(_twoPartMix());

    expect(mixer.state, MixerState.idle);
    expect(mixer.layers, hasLength(2));
    expect(farm.resolvedFor, <String>['a', 'b']);

    final first = farm.engines[0];
    final second = farm.engines[1];
    expect(first.loadedUrls, <String>['https://cdn.test/a.m4a']);
    // The slice, not the song: start at 5 s, stop at 15 s.
    expect(first.seeks, <Duration>[_ms(5000)]);
    expect(first.trim, _ms(15000));
    expect(second.seeks, <Duration>[_ms(30000)]);
    expect(second.trim, _ms(40000));
    // Levels come from the arrangement, not from a shared default.
    expect(first.volumes.last, MashupPart.defaultGain);
  });

  test('a part whose length is unknown is not trimmed to a guess', () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(
      Mashup(
        parts: <MashupPart>[
          MashupPart.whole(
            Track(id: 'live', title: 'Live take', artists: const <String>['A']),
          ),
        ],
      ),
    );

    expect(mixer.layers.single.part.playsToTheEnd, isTrue);
    expect(farm.engines.single.trim, isNull);
  });

  test('a part at the same level as the mix is scaled by the master volume',
      () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(
      Mashup.fromTracks(<Track>[_track('a')]),
      masterVolume: 0.5,
    );

    expect(farm.engines.single.volumes.last, closeTo(0.4, 0.0001));
  });

  test('play starts the first part at once and the second at its offset',
      () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(_twoPartMix());
    expect(mixer.mashup.parts[1].offset, const Duration(seconds: 6));

    await mixer.play();
    await _settle();
    expect(mixer.state, MixerState.playing);
    expect(farm.engines[0].state, EngineState.playing);
    // Not yet: it enters at 6 s of the mix.
    expect(farm.engines[1].state, isNot(EngineState.playing));
    expect(mixer.layers[1].state, LayerState.waiting);

    await mixer.stop();
    // Both clocks agree about where the mix is, and both layers are at the top.
    expect(mixer.position, Duration.zero);
    expect(mixer.layers.every((l) => l.state == LayerState.waiting), isTrue);
  });

  test('a part that ends on its own is recorded as done, and the mix finishes',
      () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(
      Mashup.fromTracks(
        <Track>[_track('a', seconds: 10)],
        blend: Duration.zero,
      ),
    );
    await mixer.play();
    await _settle();
    expect(mixer.layers.single.state, LayerState.playing);

    // mpv reaching its own trim reports completion.
    farm.engines.single.emitTrimReached();
    await _settle();

    expect(mixer.layers.single.state, LayerState.done);
    expect(mixer.state, MixerState.finished);
    expect(mixer.position, mixer.duration);
  });

  test('pausing holds the mix clock and resuming carries on from there',
      () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(
      Mashup.fromTracks(<Track>[_track('a', seconds: 30)], blend: Duration.zero),
    );
    await mixer.play();
    await Future<void>.delayed(_ms(120));
    await mixer.pause();

    expect(mixer.state, MixerState.paused);
    expect(farm.engines.single.state, EngineState.paused);
    final held = mixer.position;
    await Future<void>.delayed(_ms(80));
    // A frozen clock is frozen: the playhead does not creep while paused.
    expect(mixer.position, held);

    await mixer.play();
    await _settle();
    expect(mixer.state, MixerState.playing);
    expect(farm.engines.single.state, EngineState.playing);
  });

  test('a resumed part is seeked to where the mix already is', () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    final mix = Mashup(
      parts: <MashupPart>[
        MashupPart.whole(_track('a', seconds: 60))
            .withStart(_ms(10000))
            .withEnd(_ms(40000)),
      ],
    );
    await mixer.prepare(mix);
    await mixer.play();
    await Future<void>.delayed(_ms(150));
    await mixer.pause();

    final held = mixer.position;
    final seeksBefore = farm.engines.single.seeks.length;
    await mixer.play();
    await _settle();

    // Resuming seeks into the slice rather than restarting it: 10 s in plus
    // wherever the mix had reached.
    final resumed = farm.engines.single.seeks.sublist(seeksBefore);
    expect(resumed, hasLength(1));
    expect(resumed.single.inMilliseconds,
        closeTo(10000 + held.inMilliseconds, 40));
  });

  test('a part that cannot be resolved leaves the others in the mix',
      () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: (track) async {
        if (track.id == 'b') throw StateError('refused by the server');
        return farm.resolve(track);
      },
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(_twoPartMix());

    expect(mixer.layers, hasLength(1));
    expect(mixer.layers.single.part.track.id, 'a');
    expect(mixer.errorMessage, contains('1 of 2'));
    // The player for the part that failed is released, not left open.
    expect(farm.engines, hasLength(2));
    expect(farm.resolvedFor, <String>['a']);
  });

  test('a mix with nothing playable says so instead of pretending', () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: (track) async => throw StateError('no stream'),
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(_twoPartMix());

    expect(mixer.state, MixerState.failed);
    expect(mixer.layers, isEmpty);
    expect(mixer.errorMessage, isNotNull);
  });

  test('an engine failure is reported against the part that failed', () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    await mixer.prepare(_twoPartMix());
    await mixer.play();
    await _settle();

    farm.engines.first.emitError('audio output failed');
    await _settle();

    expect(mixer.layers.first.state, LayerState.failed);
    expect(mixer.layers.first.error, contains('audio output failed'));
    expect(mixer.errorMessage, contains('Song a'));
    // The other part is untouched: two players, two fates.
    expect(mixer.layers[1].state, LayerState.waiting);
  });

  test('a part that is past its slice when the mix resumes is skipped',
      () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    // One long part and one that only sounds for the first half second.
    final mix = Mashup(
      parts: <MashupPart>[
        MashupPart.whole(_track('lead', seconds: 30)),
        MashupPart.whole(_track('blip', seconds: 30))
            .withStart(_ms(1000))
            .withEnd(_ms(1500))
            .withOffset(_ms(0)),
      ],
    );
    await mixer.prepare(mix);
    await mixer.play();
    // Past the blip's half second, so it is over before the pause.
    await Future<void>.delayed(_ms(750));
    await mixer.pause();

    // Resuming after the blip's slice has passed does not start it again.
    await mixer.play();
    await _settle();

    final blip = mixer.layers[1];
    expect(blip.state, LayerState.done);
    expect(farm.engines[0].state, EngineState.playing);
  });

  test('the soundings at a moment are the parts overlapping there', () async {
    final farm = _EngineFarm();
    final mixer = MashupMixer(
      createEngine: farm.create,
      resolve: farm.resolve,
    );
    addTearDown(mixer.dispose);

    final mix = _twoPartMix();
    await mixer.prepare(mix);

    // Part 1 sounds across 0-10 s of the mix, part 2 across 6-16 s, so 6-10 s
    // is where both records are playing at once.
    expect(mixer.soundingAt(const Duration(seconds: 8)).map((l) => l.part.track.id),
        <String>['a', 'b']);
    expect(mixer.soundingAt(const Duration(seconds: 2)).map((l) => l.part.track.id),
        <String>['a']);
    expect(
      mixer
          .soundingAt(const Duration(seconds: 12))
          .map((l) => l.part.track.id),
      <String>['b'],
    );
  });
}
