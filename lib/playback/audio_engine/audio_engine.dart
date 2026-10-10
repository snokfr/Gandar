import 'dart:async';

import '../../core/settings/playback_settings.dart';

/// Transport state of the audio engine.
enum EngineState { idle, loading, playing, paused, completed, error }

/// The playback boundary the rest of the app depends on.
///
/// The concrete `media_kit` implementation lives in [MediaKitAudioEngine]; a
/// fake lives here so queue/prefetch logic can be tested without audio.
abstract class AudioEngine {
  Stream<EngineState> get stateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<Object> get errorStream;

  EngineState get state;
  Duration get position;
  Duration get duration;

  Future<void> load(String url, {Map<String, String> headers});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume0to1);

  /// Applies EQ / normalization / mono filters. No-op on engines that cannot
  /// support them (e.g. the fake).
  Future<void> applyFilters(PlaybackSettings settings);

  Future<void> dispose();
}

/// Deterministic in-memory engine used by tests and for non-audio platforms.
class FakeAudioEngine implements AudioEngine {
  final _state = <EngineState>[];
  final _stateController = StreamController<EngineState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  EngineState _current = EngineState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Records the last filter string applied, for assertions.
  PlaybackSettings? lastAppliedFilters;

  /// Records every URL passed to [load].
  final List<String> loadedUrls = <String>[];

  @override
  Stream<EngineState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  @override
  EngineState get state => _current;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  /// Number of emitted state changes (test helper).
  int get stateChangeCount => _state.length;

  void _emit(EngineState s) {
    _current = s;
    _state.add(s);
    _stateController.add(s);
  }

  @override
  Future<void> load(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    loadedUrls.add(url);
    _emit(EngineState.loading);
  }

  @override
  Future<void> play() async => _emit(EngineState.playing);

  @override
  Future<void> pause() async => _emit(EngineState.paused);

  @override
  Future<void> stop() async {
    _position = Duration.zero;
    _emit(EngineState.idle);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume0to1) async {}

  @override
  Future<void> applyFilters(PlaybackSettings settings) async {
    lastAppliedFilters = settings;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _errorController.close();
  }

  /// Test helper: pretend the currently loaded track progressed.
  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  /// Test helper: report the loaded media's duration.
  void emitDuration(Duration duration) {
    _duration = duration;
    _durationController.add(duration);
  }

  /// Test helper: simulate an engine error.
  void emitError(Object error) => _errorController.add(error);
}
