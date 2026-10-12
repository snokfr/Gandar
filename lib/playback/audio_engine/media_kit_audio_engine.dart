import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/playback_settings.dart';
import 'audio_engine.dart';
import 'audio_filters.dart';
import 'playback_temp.dart';

/// [AudioEngine] backed by `media_kit` (libmpv).
///
/// mpv is used (rather than a higher-level player) because EQ, loudness
/// normalization and mono downmix are native mpv audio filters, giving us the
/// advanced playback settings on every desktop and mobile platform.
class MediaKitAudioEngine implements AudioEngine {
  /// [temp] is where media_kit may write its temporary playlist. Omitting it
  /// leaves media_kit on the system temp directory, which is where playback
  /// fails on machines that deny new files there — see [PlaybackTemp].
  MediaKitAudioEngine({Player? player, this.temp})
    : _player = player ?? Player() {
    _subs = <StreamSubscription<dynamic>>[
      _player.stream.playing.listen((playing) {
        if (_state == EngineState.loading || _state == EngineState.idle) {
          _emit(playing ? EngineState.playing : _state);
        }
      }),
      _player.stream.completed.listen((completed) {
        if (!completed) return;
        final position = _player.state.position;
        final duration = _player.state.duration;
        AppLogger.instance.info(
          'mpv',
          'playback ended at ${position.inMilliseconds} ms of '
              '${duration.inMilliseconds} ms (opened ${_openHost ?? 'nothing'})',
        );
        // mpv reports "finished" both for a track that ended and for a URL it
        // was never able to open, and the difference matters: a refused stream
        // reported as completed makes the queue march through the playlist
        // with no sound and nothing on screen to explain why. Nothing decoded
        // means nothing played.
        if (duration == Duration.zero) {
          const message =
              'The audio stream ended before any sound played. The server '
              'refused it — see the log for what mpv said.';
          AppLogger.instance.error(
            'mpv',
            'stream refused: no audio decoded ($_openHost); treating as an '
                'error rather than end of track',
          );
          _emit(EngineState.error, error: message);
          return;
        }
        _emit(EngineState.completed);
      }),
      _player.stream.error.listen((error) {
        if (error.isEmpty) return;
        // libmpv explains itself here and nowhere else. Without this line a
        // refused stream looks like a track that simply did not start.
        AppLogger.instance.error('mpv', error);
        _emit(EngineState.error, error: error);
      }),
      // libmpv's own messages ("Failed to open …", "audio output failed", …),
      // at debug level so they are there when something goes wrong and silent
      // otherwise.
      _player.stream.log.listen((entry) {
        final text = entry.text.trim();
        if (text.isEmpty) return;
        AppLogger.instance.debug('mpv', '[${entry.prefix}] $text');
      }),
      // Position advancing is the only proof that sound is being produced:
      // mpv reports `playing: true` for a URL it never managed to open.
      _player.stream.position.listen((position) {
        if (position <= Duration.zero || _firstAudioLogged) return;
        _firstAudioLogged = true;
        AppLogger.instance.info(
          'mpv',
          'first audio at ${position.inMilliseconds} ms '
              '($_openHost, ${_loadStartedAt == null ? '?' : '${DateTime.now().difference(_loadStartedAt!).inMilliseconds} ms after load'})',
        );
      }),
    ];
  }

  final Player _player;

  /// Where media_kit may write its temporary playlist; null means the system
  /// temp directory, i.e. the default media_kit behaviour.
  final PlaybackTemp? temp;

  /// Host of the URL the player was last asked to open, for failure logs.
  String? _openHost;

  /// When the current media was handed to the player, for first-audio timing.
  DateTime? _loadStartedAt;

  /// Guards the "first audio" line so it is written once per track.
  bool _firstAudioLogged = false;

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
    // A cached track is a local path, which has no host — and `Uri` reads the
    // drive letter of `C:\…` as a scheme and reports an empty host, so the
    // fallback has to catch the empty case and not just the null one.
    final parsed = Uri.tryParse(url);
    _openHost = (parsed != null && parsed.host.isNotEmpty) ? parsed.host : url;
    _loadStartedAt = DateTime.now();
    _firstAudioLogged = false;
    AppLogger.instance.debug(
      'mpv',
      'open $_openHost '
          '${headers.isEmpty ? '(no headers)' : 'with ${headers.length} headers'}',
    );
    Future<void> open() => _player.open(
      Media(url, httpHeaders: headers.isEmpty ? null : headers),
      play: false,
    );
    // media_kit writes its playlist file while this call is in flight, reading
    // Directory.systemTemp as it goes, so the override has to cover the call.
    final dir = temp;
    await (dir == null ? open() : dir.withTempDirectory(open));
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
  Future<void> stopAt(Duration? position) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // mpv's own `end`: the player stops there and reports completion, so a
    // trimmed part ends on its own rather than because a timer said so.
    await platform.setProperty(
      'end',
      position == null ? 'no' : (position.inMilliseconds / 1000).toString(),
    );
  }

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
