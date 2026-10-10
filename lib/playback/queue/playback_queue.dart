import '../../core/settings/playback_settings.dart';
import '../../domain/models/track.dart';
import 'shuffle.dart';

/// The ordered list of tracks being played, plus the cursor into it.
///
/// Deliberately free of audio/platform concerns so ordering, shuffle and
/// next/previous semantics can be unit tested.
class PlaybackQueue {
  PlaybackQueue({
    List<Track> tracks = const <Track>[],
    ShuffleService? shuffleService,
  }) : _original = List<Track>.of(tracks),
       _shuffleService = shuffleService ?? ShuffleService(),
       _index = -1 {
    if (_original.isNotEmpty) {
      _order = List<Track>.of(_original);
      _index = 0;
    }
  }

  /// Builds a queue ready to play [tracks], positioned at [startTrackId].
  factory PlaybackQueue.loaded(
    List<Track> tracks, {
    String? startTrackId,
    ShuffleMode mode = ShuffleMode.off,
    ShuffleService? shuffleService,
  }) {
    return PlaybackQueue(tracks: tracks, shuffleService: shuffleService)
      ..setTracks(tracks, startTrackId: startTrackId, mode: mode);
  }

  final List<Track> _original;
  final ShuffleService _shuffleService;

  List<Track> _order = const <Track>[];
  int _index;

  /// The current playback order (shuffled or original).
  List<Track> get order => List<Track>.unmodifiable(_order);
  int get length => _order.length;
  int get index => _index;
  bool get isEmpty => _order.isEmpty;

  Track? get current =>
      _index >= 0 && _index < _order.length ? _order[_index] : null;

  Track? get next => _index + 1 < _order.length ? _order[_index + 1] : null;

  Track? get previous => _index > 0 ? _order[_index - 1] : null;

  /// Replaces the queue contents, positioning the cursor on [startTrackId]
  /// when given. [recentTrackIds] drives smart-shuffle avoidance.
  void setTracks(
    List<Track> tracks, {
    String? startTrackId,
    ShuffleMode mode = ShuffleMode.off,
    List<String> recentTrackIds = const [],
  }) {
    _original
      ..clear()
      ..addAll(tracks);
    _order = _shuffleService.order(
      _original,
      mode: mode,
      recent: recentTrackIds,
      idOf: (t) => t.id,
    );
    if (startTrackId == null) {
      _index = _order.isEmpty ? -1 : 0;
    } else {
      final found = _order.indexWhere((t) => t.id == startTrackId);
      _index = found >= 0 ? found : (_order.isEmpty ? -1 : 0);
    }
  }

  /// Re-orders the existing tracks according to [mode], keeping the cursor on
  /// the currently playing track wherever it lands.
  void applyShuffle(
    ShuffleMode mode, {
    List<String> recentTrackIds = const [],
  }) {
    final currentId = current?.id;
    _order = _shuffleService.order(
      _original,
      mode: mode,
      recent: recentTrackIds,
      idOf: (t) => t.id,
    );
    if (currentId == null) {
      _index = _order.isEmpty ? -1 : 0;
      return;
    }
    final found = _order.indexWhere((t) => t.id == currentId);
    _index = found >= 0 ? found : 0;
  }

  /// Advances the cursor. Returns the new current track, or null at the end.
  Track? advance() {
    if (_index + 1 >= _order.length) return null;
    _index++;
    return current;
  }

  /// Moves the cursor back. Returns the new current track, or null at the top.
  Track? rewind() {
    if (_index <= 0) return null;
    _index--;
    return current;
  }

  /// Jumps to the track with [trackId] if present.
  bool jumpTo(String trackId) {
    final found = _order.indexWhere((t) => t.id == trackId);
    if (found < 0) return false;
    _index = found;
    return true;
  }

  void clear() {
    _original.clear();
    _order = const <Track>[];
    _index = -1;
  }
}
