import 'dart:async';

import 'package:flutter/foundation.dart';

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
    _stateSub = engine.stateStream.listen(_onEngineState);
    _positionSub = engine.positionStream.listen((p) {
      positionNotifier.value = p;
    });
    _durationSub = engine.durationStream.listen((d) {
      if (d != null) durationNotifier.value = d;
    });
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

  Future<void> seek(Duration position) async {
    await engine.seek(position);
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    await engine.setVolume(_volume);
    notifyListeners();
  }

  Future<void> _playCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    _errorMessage = null;

    try {
      final stream = await preloader.resolve(track);
      await engine.load(stream.url, headers: stream.headers);
      await engine.applyFilters(_settings);
      await engine.setVolume(_volume);
      await engine.play();

      _recent.record(track.id);
      await library.recordPlay(track.id, DateTime.now());

      // Warm the next track so it starts without a gap.
      if (_settings.prefetchNextTrack) {
        preloader.prefetch(_queue.next);
      }
    } catch (e) {
      _errorMessage = 'Could not play "${track.title}": $e';
      _engineState = EngineState.error;
    }
    notifyListeners();
  }

  void _onEngineState(EngineState state) {
    _engineState = state;
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
    positionNotifier.dispose();
    durationNotifier.dispose();
    engine.dispose();
    super.dispose();
  }
}
