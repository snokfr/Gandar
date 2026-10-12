import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/playback_settings.dart';
import '../../domain/models/mashup.dart';
import '../../domain/models/resolved_stream.dart';
import '../../domain/models/track.dart';
import '../audio_engine/audio_engine.dart';

/// What the mixer as a whole is doing.
enum MixerState {
  /// Nothing loaded.
  idle,

  /// Resolving and priming the parts.
  preparing,

  /// The mix is running.
  playing,

  /// Held where it is; resuming continues from the same place in the mix.
  paused,

  /// Every part has played out.
  finished,

  /// Nothing could be loaded.
  failed,
}

/// What one part is doing.
enum LayerState { waiting, playing, done, failed }

/// One part of a mix together with the player carrying it.
class MashupLayer {
  MashupLayer({required this.part, required this.engine});

  final MashupPart part;

  /// The player for this part alone. Independent of every other part's player,
  /// which is the entire mechanism: each part is seeked, trimmed, levelled and
  /// started on its own, and the layers are summed by the system mixer.
  final AudioEngine engine;

  LayerState state = LayerState.waiting;

  /// Whether this layer's player is already being watched for its own ending.
  bool listened = false;

  /// Why this layer is not playing, when that is known.
  String? error;

  /// Position inside the source song as of the last tick.
  Duration position = Duration.zero;

  bool get isPlaying => state == LayerState.playing;
}

/// Plays a [Mashup]: every part at its own offset, each trimmed to its own
/// slice, each at its own level.
///
/// ## Why this is a mixer and not a filter chain
///
/// The obvious way to layer two songs is one player, two sources and an
/// `amix` in an mpv filter graph. It does not work here: the libavfilter
/// shipped inside this build of libmpv has no `amix`, no `atrim`, no `adelay`
/// and no `acrossfade` — only `volume`, `equalizer` and `concat`. (That is also
/// why loudness normalization is unavailable; see `AudioFilters`.) So the mix is
/// done the other way: one player per part, all running at once, summed by the
/// operating system's audio mixer. That is how a live mashup is performed, and
/// it is what makes per-part trims and levels possible at all.
///
/// ## What it does and does not promise
///
/// Each part is trimmed by the *player* — mpv's own `end` — so a part stops
/// where the user said even if this object is busy. Timing between parts comes
/// from one clock, so an entry point is accurate to about a tick plus the
/// player's own seek latency (tens of milliseconds). It is not sample-accurate
/// beat matching: two independent clocks will not stay locked to a beat grid,
/// and this deliberately does not pretend otherwise.
class MashupMixer extends ChangeNotifier {
  MashupMixer({
    required this.createEngine,
    required this.resolve,
    this.tick = const Duration(milliseconds: 50),
    this.trimGrace = const Duration(milliseconds: 400),
  });

  /// Builds one player per part.
  final AudioEngine Function() createEngine;

  /// Resolves a track to a playable stream.
  final Future<ResolvedStream> Function(Track track) resolve;

  /// How often the mix clock is read and the layers are swept.
  final Duration tick;

  /// How long after a part's end the mixer stops waiting for the player to
  /// report its own trim before stopping it.
  final Duration trimGrace;

  MixerState _state = MixerState.idle;
  Mashup _mashup = Mashup.empty;
  final List<MashupLayer> _layers = <MashupLayer>[];
  final List<StreamSubscription<Object>> _engineSubs = <StreamSubscription<Object>>[];
  final List<Timer> _pending = <Timer>[];
  final Stopwatch _clock = Stopwatch();
  Duration _frozen = Duration.zero;
  Timer? _ticker;
  String? _errorMessage;

  /// Mix position, for the playhead. Separate from [notifyListeners] so a
  /// moving playhead does not rebuild the whole screen twenty times a second.
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  MixerState get state => _state;
  Mashup get mashup => _mashup;
  List<MashupLayer> get layers => List<MashupLayer>.unmodifiable(_layers);
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _state == MixerState.playing;
  bool get hasLayers => _layers.isNotEmpty;

  /// Where the mix is, from the top of the arrangement.
  Duration get position =>
      _frozen + (_clock.isRunning ? _clock.elapsed : Duration.zero);

  /// Total playing time of the arrangement.
  Duration get duration => _mashup.duration;

  bool get isRunning =>
      _state == MixerState.playing || _state == MixerState.paused;

  /// Which parts are sounding at [moment] of the mix.
  List<MashupLayer> soundingAt(Duration moment) => _layers
      .where((layer) => layer.part.positionInSource(moment) != null)
      .toList(growable: false);

  /// Loads every part of [mashup] and primes it to play.
  ///
  /// The parts are primed together, not in turn: they are usually being read
  /// from the same disk or the same network, and doing them one after another
  /// would make the wait add up for no reason.
  Future<void> prepare(
    Mashup mashup, {
    PlaybackSettings settings = const PlaybackSettings(),
    double masterVolume = 1.0,
  }) async {
    await _teardown(reportIdle: false);
    _mashup = mashup;
    _errorMessage = null;
    if (mashup.isEmpty) {
      _setState(MixerState.idle);
      return;
    }

    _setState(MixerState.preparing);
    final prepared = await Future.wait<MashupLayer?>(
      mashup.parts.map((part) => _prime(part, settings, masterVolume)),
    );
    _layers
      ..clear()
      ..addAll(prepared.whereType<MashupLayer>());

    final failures = prepared.where((layer) => layer == null).length;
    if (_layers.isEmpty) {
      _errorMessage ??= 'None of the songs in this mix could be loaded.';
      _setState(MixerState.failed);
      return;
    }
    if (failures > 0) {
      _errorMessage =
          '$failures of ${mashup.parts.length} parts could not be loaded and '
          'will be silent.';
    }
    AppLogger.instance.info(
      'mashup',
      'primed ${_layers.length} layer(s) for a '
          '${mashup.duration.inMilliseconds} ms mix',
    );
    _setState(MixerState.idle);
  }

  /// Resolves, loads, seeks and trims one part. Returns null when it cannot be
  /// loaded, which is reported to the user rather than thrown: one unplayable
  /// song should not take the other layers with it.
  Future<MashupLayer?> _prime(
    MashupPart part,
    PlaybackSettings settings,
    double masterVolume,
  ) async {
    final engine = createEngine();
    try {
      final stream = await resolve(part.track);
      await engine.load(stream.url, headers: stream.headers);
      await engine.setVolume((part.gain * masterVolume).clamp(0.0, 1.0));
      await engine.applyFilters(settings);
      // The slice is set before playback so it is in force from the first
      // sample: seeking first and trimming after would let a sliver of the
      // unwanted part through.
      await engine.seek(part.start);
      await engine.stopAt(part.playsToTheEnd ? null : part.end);
      return MashupLayer(part: part, engine: engine);
    } catch (e, stack) {
      AppLogger.instance.error(
        'mashup',
        'could not prime "${part.title}"',
        error: e,
        stackTrace: stack,
      );
      await engine.dispose();
      return null;
    }
  }

  /// Starts (or resumes) the mix.
  Future<void> play() async {
    if (_layers.isEmpty || _state == MixerState.preparing) return;

    // Playing out the end and pressing play again means "from the top", not
    // "from a position past the end" — which would otherwise be silence.
    if (!isRunning && position >= duration) {
      await _rewindToTop();
    }

    _frozen = position;
    _clock
      ..reset()
      ..start();
    _setState(MixerState.playing);
    _ticker ??= Timer.periodic(tick, (_) => _sweep());
    for (final layer in _layers) {
      _schedule(layer);
    }
  }

  /// Holds the mix where it is. Each part is paused, and the mix clock is
  /// frozen rather than the parts being trusted to agree on where they are.
  Future<void> pause() async {
    if (_state != MixerState.playing) return;
    _frozen = position;
    _clock.stop();
    _cancelPending();
    _ticker?.cancel();
    _ticker = null;
    for (final layer in _layers) {
      if (!layer.isPlaying) continue;
      await layer.engine.pause();
      layer.state = LayerState.waiting;
    }
    _setState(MixerState.paused);
  }

  /// Stops the mix and puts it back at the top, keeping the parts loaded.
  Future<void> stop() => _teardown(reportIdle: true);

  /// Moves the mix to [moment], the way scrubbing a recording works.
  ///
  /// Every part is handled on its own terms, which is the whole difficulty of
  /// seeking a mix: one whose slice contains the new position is seeked inside
  /// its own song and carries on; one that has not entered yet is parked, and
  /// starts when the playhead reaches it; one that is already over is stopped
  /// and marked done. Nothing here restarts the arrangement from the top, so a
  /// mix is something you can move around inside rather than only watch.
  Future<void> seekTo(Duration moment) async {
    if (_layers.isEmpty) return;
    var target = moment < Duration.zero ? Duration.zero : moment;
    if (target > duration) target = duration;

    final wasPlaying = _state == MixerState.playing;
    _cancelPending();
    _frozen = target;
    if (wasPlaying) {
      _clock
        ..reset()
        ..start();
    } else {
      _clock
        ..stop()
        ..reset();
    }
    positionNotifier.value = target;

    for (final layer in _layers) {
      // A player that could not load is left alone: there is nothing there to
      // seek, and pretending otherwise would only produce another failure.
      if (layer.state == LayerState.failed) continue;

      final inSource = layer.part.positionInSource(target);
      if (inSource == null) {
        final past = target >= layer.part.endInMix;
        if (layer.state == LayerState.playing) await layer.engine.pause();
        await _stopQuietly(layer.engine);
        layer.state = past ? LayerState.done : LayerState.waiting;
        layer.position = Duration.zero;
        continue;
      }

      layer.position = inSource;
      await layer.engine.seek(inSource);
      if (wasPlaying) {
        if (layer.state == LayerState.playing) continue;
        layer.state = LayerState.playing;
        if (!layer.listened) _listenTo(layer);
        await layer.engine.play();
      } else if (layer.state == LayerState.playing) {
        layer.state = LayerState.waiting;
        await layer.engine.pause();
      }
    }
    notifyListeners();
    // A mix that was moved must not claim to be over: reaching the end is a
    // thing that happens by playing there, not by being seeked there.
    if (wasPlaying && _state == MixerState.finished) {
      _setState(MixerState.playing);
    }
  }

  /// Stops everything and releases every player.
  Future<void> unload() async {
    await _teardown(reportIdle: true);
    _mashup = Mashup.empty;
  }

  Future<void> _teardown({required bool reportIdle}) async {
    _cancelPending();
    _ticker?.cancel();
    _ticker = null;
    _clock
      ..stop()
      ..reset();
    _frozen = Duration.zero;
    positionNotifier.value = Duration.zero;

    // Cancelling is not awaited, and that is deliberate. A subscription to a
    // broadcast stream can hand back a future that never completes — the
    // engine's own streams are broadcast, a player that has already gone away
    // does the same — and waiting on it would leave the transport stuck on
    // "Mixing" after the user asked it to stop. The listeners are going with
    // the player anyway; nothing here depends on being told they are gone.
    for (final subscription in _engineSubs) {
      unawaited(subscription.cancel());
    }
    _engineSubs.clear();

    final engines = _layers.map((layer) => layer.engine).toList(growable: false);
    for (final layer in _layers) {
      layer.state = LayerState.waiting;
      layer.position = Duration.zero;
      // The subscriptions just went with them, so the next start has to
      // re-attach or a part ending on its own would go unnoticed.
      layer.listened = false;
    }
    // The transport is told the mix is stopped before the players are waited
    // on, so stopping is instant on screen even if a player is slow to let go.
    if (reportIdle && _layers.isNotEmpty) _setState(MixerState.idle);
    await Future.wait(engines.map(_stopQuietly));
  }

  /// Stops one player, treating a player that is already gone as stopped.
  static Future<void> _stopQuietly(AudioEngine engine) async {
    try {
      await engine.stop();
    } catch (_) {
      // Already gone; nothing left to stop.
    }
  }

  /// Disposes the players themselves. Called when leaving the screen.
  Future<void> disposeLayers() async {
    await _teardown(reportIdle: false);
    final engines = _layers.map((layer) => layer.engine).toList(growable: false);
    _layers.clear();
    for (final engine in engines) {
      try {
        await engine.dispose();
      } catch (_) {
        // Disposal is best effort; the process is going away anyway.
      }
    }
  }


  /// Starts [layer] at the point the mix clock says it should already be at.
  void _schedule(MashupLayer layer) {
    if (layer.state == LayerState.done || layer.state == LayerState.playing) {
      return;
    }
    final now = position;
    if (layer.part.endInMix <= now) {
      _markDone(layer);
      return;
    }
    if (layer.part.offset <= now) {
      _start(layer, intoPart: now - layer.part.offset);
      return;
    }
    _pending.add(
      Timer(layer.part.offset - now, () => _start(layer, intoPart: Duration.zero)),
    );
  }

  /// Plays [layer] from [intoPart] after its own start.
  void _start(MashupLayer layer, {required Duration intoPart}) {
    if (layer.state == LayerState.playing) return;
    layer.state = LayerState.playing;
    notifyListeners();
    unawaited(() async {
      try {
        if (intoPart > Duration.zero) {
          await layer.engine.seek(layer.part.sourcePositionAt(intoPart));
        }
        if (!layer.listened) _listenTo(layer);
        await layer.engine.play();
      } catch (e) {
        _failLayer(layer, e);
      }
    }());
  }

  /// Watches a layer's player so that a part which ends (or dies) on its own
  /// is recorded as such: mpv stops itself at its trim, and nothing here asked
  /// it to.
  void _listenTo(MashupLayer layer) {
    layer.listened = true;
    _engineSubs.add(
      layer.engine.stateStream.listen((state) {
        if (state == EngineState.completed) _markDone(layer);
      }),
    );
    _engineSubs.add(
      layer.engine.errorStream.listen((error) => _failLayer(layer, error)),
    );
  }

  /// Reads the mix clock: moves each playing layer's own clock forward and
  /// forces a part that should be over to stop.
  void _sweep() {
    final now = position;
    positionNotifier.value = now;
    for (final layer in _layers) {
      final inSource = layer.part.positionInSource(now);
      if (inSource != null) layer.position = inSource;

      // A waiting part whose moment has arrived is started from here as well as
      // from the timer that was armed for it. That makes this sweep the single
      // place that decides what should be sounding, which is exactly what a
      // seek needs: after one, no timers are armed, and the parts that belong
      // in the mix are the ones whose window contains the playhead.
      if (layer.state == LayerState.waiting && inSource != null) {
        _start(layer, intoPart: now - layer.part.offset);
        continue;
      }

      if (layer.state != LayerState.playing) continue;
      if (layer.part.playsToTheEnd) continue;
      // The player trims itself; this is the safety net for the case where it
      // did not, so a part can never play past the slice the user chose.
      if (now >= layer.part.endInMix + trimGrace) {
        unawaited(layer.engine.stop());
        _markDone(layer);
      }
    }
    // The mix is over when every part has settled — not when nothing happens to
    // be sounding, which is also true in the gap before a late part enters.
    if (_state == MixerState.playing && _layers.every(_settled)) _complete();
  }

  static bool _settled(MashupLayer layer) =>
      layer.state == LayerState.done || layer.state == LayerState.failed;

  Future<void> _rewindToTop() async {
    _frozen = Duration.zero;
    _clock
      ..stop()
      ..reset();
    positionNotifier.value = Duration.zero;
    for (final layer in _layers) {
      layer.state = LayerState.waiting;
      layer.position = Duration.zero;
      await layer.engine.seek(layer.part.start);
    }
    notifyListeners();
  }

  void _markDone(MashupLayer layer) {
    if (layer.state == LayerState.done) return;
    layer.state = LayerState.done;
    notifyListeners();
  }

  void _failLayer(MashupLayer layer, Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (layer.state == LayerState.failed && layer.error == text) return;
    layer.state = LayerState.failed;
    layer.error = text;
    _errorMessage = '"${layer.part.title}" could not be played: $text';
    AppLogger.instance.warn('mashup', _errorMessage!);
    notifyListeners();
  }

  void _complete() {
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;
    _cancelPending();
    _frozen = duration;
    positionNotifier.value = duration;
    _setState(MixerState.finished);
  }

  void _cancelPending() {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
  }

  void _setState(MixerState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelPending();
    _ticker?.cancel();
    _ticker = null;
    for (final subscription in _engineSubs) {
      subscription.cancel();
    }
    _engineSubs.clear();
    for (final layer in _layers) {
      layer.engine.dispose();
    }
    _layers.clear();
    positionNotifier.dispose();
    super.dispose();
  }
}
