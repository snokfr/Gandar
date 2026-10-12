import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging/app_logger.dart';
import '../core/settings/playback_settings.dart';
import '../domain/models/track.dart';
import '../domain/repositories/repositories.dart';
import '../playback/audio_engine/audio_engine.dart';
import '../playback/audio_engine/crossfade.dart';
import '../playback/preloader.dart';
import '../playback/queue/playback_queue.dart';
import '../playback/queue/shuffle.dart';

/// Coordinates the audio engine, the queue, the stream preloader and the
/// persisted playback settings.
///
/// UI never touches the engine directly; every transport action goes through
/// here so shuffle order, pre-fetching and play history stay consistent.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.engine,
    required this.preloader,
    required this.library,
    PlaybackSettings settings = const PlaybackSettings(),
    PlaybackQueue? queue,
    ShuffleService? shuffleService,
  }) : _queue = queue ?? PlaybackQueue(shuffleService: shuffleService) {
    _settings = settings.sanitized();
    // The resolver picks the stream, so the quality in force has to reach it
    // before the first track is asked for.
    preloader.resolver.setAudioQuality(_settings.audioQuality);
    _stateSub = engine.stateStream.listen(_onEngineState);
    _positionSub = engine.positionStream.listen((p) {
      positionNotifier.value = p;
    });
    _durationSub = engine.durationStream.listen((d) {
      if (d != null) durationNotifier.value = d;
    });
    // The engine can fail on its own, after play() has already returned: a
    // stream the server refuses never reaches the catch blocks in
    // [_playCurrent]. Those failures have to reach the user too, or the only
    // sign of them is a playlist that never makes a sound.
    _errorSub = engine.errorStream.listen((error) {
      _errorMessage = _describeEngineError(error);
      AppLogger.instance.warn('playback', _errorMessage!);
      notifyListeners();
    });
  }

  /// A sentence for the player, from whatever libmpv said.
  static String _describeEngineError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    const limit = 300;
    return text.length <= limit ? text : '${text.substring(0, limit)}…';
  }

  /// The audio backend (media_kit in production, a fake in tests).
  final AudioEngine engine;

  /// Resolves and pre-fetches streams.
  final StreamPreloader preloader;

  /// Persists play history and holds the local library cache.
  final LibraryRepository library;

  final PlaybackQueue _queue;

  late final StreamSubscription<EngineState> _stateSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<Object> _errorSub;

  /// High-frequency playback position, separate from [notifyListeners] so the
  /// seek bar can rebuild without rebuilding the whole app chrome.
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  /// Duration of the loaded media.
  final ValueNotifier<Duration> durationNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  PlaybackSettings _settings = const PlaybackSettings();
  final RecentTracker<String> _recent = RecentTracker<String>(capacity: 30);

  EngineState _engineState = EngineState.idle;
  String? _errorMessage;
  double _volume = 1.0;
  bool _isCrossfading = false;

  // ---- Read-only state -------------------------------------------------

  PlaybackSettings get settings => _settings;
  EngineState get engineState => _engineState;
  bool get isPlaying => _engineState == EngineState.playing;
  bool get isCrossfading => _isCrossfading;
  String? get errorMessage => _errorMessage;
  double get volume => _volume;
  Track? get currentTrack => _queue.current;
  Track? get nextTrack => _queue.next;
  List<Track> get queue => _queue.order;
  Duration get position => positionNotifier.value;
  Duration get duration => durationNotifier.value;

  /// Currently playing track id, if any.
  String? get currentTrackId => _queue.current?.id;

  /// Progress in 0..1, or 0 when the duration is unknown.
  double get progress {
    final d = duration.inMilliseconds;
    if (d <= 0) return 0;
    return (position.inMilliseconds / d).clamp(0.0, 1.0).toDouble();
  }

  // ---- Settings --------------------------------------------------------

  /// Applies new settings, pushing audio filters to the engine immediately.
  Future<void> updateSettings(PlaybackSettings next) async {
    final previousMode = _settings.shuffleMode;
    _settings = next.sanitized();
    preloader.resolver.setAudioQuality(_settings.audioQuality);
    await engine.applyFilters(_settings);
    if (previousMode != _settings.shuffleMode) {
      _queue.applyShuffle(_settings.shuffleMode, recentTrackIds: _recent.items);
    }
    notifyListeners();
  }

  // ---- Transport -------------------------------------------------------

  /// Loads and starts playing [tracks], beginning at [startTrackId].
  Future<void> playTracks(List<Track> tracks, {String? startTrackId}) async {
    _queue.setTracks(
      tracks,
      startTrackId: startTrackId,
      mode: _settings.shuffleMode,
      recentTrackIds: _recent.items,
    );
    await _playCurrent();
  }

  Future<void> togglePlayPause() async {
    if (currentTrack == null) return;
    if (_engineState == EngineState.playing) {
      await engine.pause();
    } else {
      await engine.play();
    }
  }

  Future<void> next() async {
    final nextTrack = _queue.advance();
    if (nextTrack == null) {
      await engine.stop();
      notifyListeners();
      return;
    }
    await _playCurrent();
  }

  Future<void> previous() async {
    // Common convention: restart the track unless we're near its start.
    if (position > const Duration(seconds: 3)) {
      await engine.seek(Duration.zero);
      notifyListeners();
      return;
    }
    final prev = _queue.rewind();
    if (prev == null) return;
    await _playCurrent();
  }

  /// Jumps straight to [trackId] in the current queue and plays it.
  ///
  /// Returns false when the track is not in the queue, so the caller can say
  /// so instead of appearing to do nothing.
  Future<bool> jumpTo(String trackId) async {
    if (!_queue.jumpTo(trackId)) return false;
    await _playCurrent();
    return true;
  }

  Future<void> seek(Duration position) async {
    await engine.seek(position);
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    await engine.setVolume(_volume);
    notifyListeners();
  }

  /// How long the engine gets to accept a stream before playback is declared
  /// broken.
  ///
  /// Without a bound, a wedged native player is indistinguishable from a slow
  /// one: the user presses play, nothing happens, and nothing is reported. It
  /// is how a real bug in `media_kit`'s debug-mode handle file presented itself
  /// — `_playCurrent` never returned, so the error path never ran.
  static const Duration engineLoadTimeout = Duration(seconds: 20);

  /// Records the play, reporting a failure rather than throwing one.
  ///
  /// By the time this runs the engine has the stream and the music is already
  /// on its way out of the speakers, so a history row that cannot be written is
  /// a missing statistic — not a track that failed to play. Letting it throw
  /// would report the opposite of what happened.
  Future<void> _recordPlay(Track track) async {
    try {
      await library.recordPlay(track.id, DateTime.now());
    } catch (e) {
      AppLogger.instance.warn(
        'playback',
        'could not record the play of "${track.title}"',
        error: e,
      );
    }
  }

  Future<void> _playCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    _errorMessage = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      final stream = await preloader.resolve(track);
      AppLogger.instance.info(
        'playback',
        'resolved "${track.title}" in ${stopwatch.elapsedMilliseconds} ms '
            '(prefetch hit: ${preloader.peek(track.id) != null})',
      );

      await engine
          .load(stream.url, headers: stream.headers)
          .timeout(engineLoadTimeout);
      await engine.applyFilters(_settings);
      await engine.setVolume(_volume);
      await engine.play();

      _recent.record(track.id);
      await _recordPlay(track);
      // "started", not "playing": this line records that the engine accepted
      // the stream, which is not the same as sound coming out. The engine logs
      // `first audio at N ms` when the position really moves, and a refusal is
      // reported as an error rather than a completed track.
      AppLogger.instance.info(
        'playback',
        'started "${track.title}" (${stopwatch.elapsedMilliseconds} ms to '
            'hand-off)',
      );

      // Warm the next track so it starts without a gap.
      if (_settings.prefetchNextTrack) {
        preloader.prefetch(_queue.next);
      }
    } on TimeoutException {
      _errorMessage =
          'The audio engine stopped responding while loading '
          '"${track.title}". Restart Gandar; if it keeps happening, send the '
          'log from Settings.';
      _engineState = EngineState.error;
      AppLogger.instance.error(
        'playback',
        'engine did not accept "${track.title}" within '
            '${engineLoadTimeout.inSeconds}s (${progressSummary()})',
      );
    } catch (e, stack) {
      _errorMessage = 'Could not play "${track.title}": $e';
      _engineState = EngineState.error;
      AppLogger.instance.error(
        'playback',
        'could not play "${track.title}"',
        error: e,
        stackTrace: stack,
      );
    }
    notifyListeners();
  }

  /// A few facts about the engine, for a failure log that can be acted on.
  String progressSummary() {
    final track = currentTrack;
    return 'state=${_engineState.name}, track=${track?.id ?? '-'}, '
        'queue=${_queue.order.length}';
  }

  void _onEngineState(EngineState state) {
    _engineState = state;
    AppLogger.instance.debug(
      'playback',
      'engine -> ${state.name} (${progressSummary()})',
    );
    if (state == EngineState.completed) {
      // Auto-advance; automix uses a crossfade, otherwise a plain handoff.
      _isCrossfading =
          _settings.automixEnabled && _settings.crossfadeSeconds > 0;
      unawaited(next());
      _isCrossfading = false;
    }
    notifyListeners();
  }

  /// The crossfade plan for the current handoff, if one is in progress.
  CrossfadePlan? currentCrossfade() {
    if (!_isCrossfading) return null;
    return CrossfadePlan(
      durationSeconds: _settings.crossfadeSeconds,
      positionSeconds: 0,
    );
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _errorSub.cancel();
    positionNotifier.dispose();
    durationNotifier.dispose();
    engine.dispose();
    super.dispose();
  }
}
