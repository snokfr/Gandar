import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../core/settings/playback_settings.dart';
import 'audio_engine.dart';
import 'audio_filters.dart';

/// [AudioEngine] backed by `media_kit` (libmpv).
///
/// mpv is used (rather than a higher-level player) because EQ, loudness
/// normalization and mono downmix are native mpv audio filters, giving us the
/// advanced playback settings on every desktop and mobile platform.
class MediaKitAudioEngine implements AudioEngine {
  MediaKitAudioEngine({Player? player}) : _player = player ?? Player() {
    _subs = <StreamSubscription<dynamic>>[
      _player.stream.playing.listen((playing) {
        if (_state == EngineState.loading || _state == EngineState.idle) {
          _emit(playing ? EngineState.playing : _state);
        }
      }),
      _player.stream.completed.listen((completed) {
        if (completed) _emit(EngineState.completed);
      }),
      _player.stream.error.listen((error) {
        if (error.isNotEmpty) _emit(EngineState.error, error: error);
      }),
    ];
  }

  final Player _player;
  late final List<StreamSubscription<dynamic>> _subs;

  final _stateController = StreamController<EngineState>.broadcast();
  EngineState _state = EngineState.idle;

  @override
  Stream<EngineState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration?> get durationStream => _player.stream.duration;

  @override
  Stream<Object> get errorStream =>
      _player.stream.error.where((e) => e.isNotEmpty);

  @override
  EngineState get state => _state;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  void _emit(EngineState s, {Object? error}) {
    _state = s;
    _stateController.add(s);
  }

  @override
  Future<void> load(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    _emit(EngineState.loading);
    await _player.open(
      Media(url, httpHeaders: headers.isEmpty ? null : headers),
      play: false,
    );
  }

  @override
  Future<void> play() async {
    await _player.play();
    _emit(EngineState.playing);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _emit(EngineState.paused);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _emit(EngineState.idle);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume0to1) =>
      _player.setVolume(volume0to1.clamp(0.0, 1.0).toDouble() * 100);

  @override
  Future<void> applyFilters(PlaybackSettings settings) async {
    final af = AudioFilters.buildAf(settings);
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('af', af ?? '');
    // Gapless playback is an mpv property, not a filter.
    await platform.setProperty(
      'gapless-audio',
      settings.gaplessPlayback ? 'yes' : 'no',
    );
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
    await _stateController.close();
  }
}
