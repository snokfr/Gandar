import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging/app_logger.dart';
import '../core/settings/playback_settings.dart';
import '../data/mashup/mashup_store.dart';
import '../domain/models/mashup.dart';
import '../domain/models/resolved_stream.dart';
import '../domain/models/track.dart';
import '../playback/audio_engine/audio_engine.dart';
import '../playback/mix/mashup_mixer.dart';

/// The mashup screen's state, owned by the app rather than by the screen.
///
/// ## Why this is not in the page
///
/// A mix is a thing that *plays*. It takes a minute to trim two songs and place
/// them, and the reason to leave the mashup tab is usually to go and look
/// something up — which song that was, what album this came from. If the
/// arrangement and the players died with the route, then looking something up
/// would stop the music and throw the work away, and the tab would be somewhere
/// you could not leave. So the state lives here, above the navigation, and the
/// screen is a view of it: leaving and coming back shows the same arrangement
/// in the same place, and a running mix keeps running.
class MashupController extends ChangeNotifier {
  MashupController({
    required AudioEngine Function() createEngine,
    required Future<ResolvedStream> Function(Track track) resolve,
    required PlaybackSettings Function() settings,
    required double Function() masterVolume,
    MashupStore? store,
    MashupMixer? mixer,
  }) : _readSettings = settings,
       _readVolume = masterVolume,
       store = store ?? MashupStore() {
    _mixer =
        mixer ??
        MashupMixer(createEngine: createEngine, resolve: resolve);
    _mixer.addListener(_onMixerChanged);
  }

  /// Where named mashups are written.
  final MashupStore store;

  /// Read when the players are loaded rather than held: the settings and the
  /// volume belong to the player, and both can change while a mix is open.
  final PlaybackSettings Function() _readSettings;
  final double Function() _readVolume;

  late final MashupMixer _mixer;

  Mashup _arrangement = Mashup.empty;

  int? _editing;
  bool _stale = false;
  bool _preparing = false;

  /// Set while a seek is in flight, and the newest position asked for during
  /// it, so a drag coalesces instead of queueing.
  bool _seeking = false;
  Duration? _queuedSeek;

  /// The name this arrangement was saved under, when it has one.
  String? _savedName;

  /// The arrangement being built.
  Mashup get arrangement => _arrangement;

  /// How long the arrangement runs, for the timeline.
  Duration get duration => _arrangement.duration;

  /// The mix clock, for the playhead.
  ValueListenable<Duration> get position => _mixer.positionNotifier;

  MixerState get mixState => _mixer.state;

  List<MashupLayer> get layers => _mixer.layers;

  String? get errorMessage => _mixer.errorMessage;

  bool get isPreparing => _preparing || _mixer.state == MixerState.preparing;

  bool get isPlaying => _mixer.state == MixerState.playing;

  bool get isRunning => _mixer.isRunning;

  /// Whether the arrangement has moved on since the players last heard about
  /// it, so playing has to re-prime first.
  bool get isStale => _stale;

  /// Which part's controls are open. Null when there is nothing to edit.
  int? get editing => _editing;

  /// The name this arrangement is saved under, or null when it is unsaved.
  String? get savedName => _savedName;

  bool get isEmpty => _arrangement.isEmpty;

  /// Where the mix currently is.
  Duration get positionNow => _mixer.position;

  // ---- Arranging ---------------------------------------------------------

  void openPart(int? index) {
    if (_editing == index) return;
    _editing = index;
    notifyListeners();
  }

  /// Adopts [next] as the arrangement.
  ///
  /// Every edit invalidates the mix that is loaded: the players hold the old
  /// arrangement, and playing on with it would sound like the old one.
  void arrange(Mashup next, {int? editing, String? name}) {
    _arrangement = next;
    _stale = _mixer.hasLayers;
    if (editing != null) _editing = editing;
    if (name != null) _savedName = name;
    final current = _editing;
    if (current != null && current >= next.parts.length) {
      _editing = next.parts.isEmpty ? null : next.parts.length - 1;
    }
    notifyListeners();
  }

  void add(Track track) {
    if (_arrangement.parts.any((part) => part.track.id == track.id)) return;
    final next = _arrangement.adding(track);
    arrange(next, editing: next.parts.length - 1);
  }

  void removeAt(int index) => arrange(_arrangement.removingAt(index));

  void move(int index, int delta) =>
      arrange(_arrangement.moving(index, delta), editing: index + delta);

  void replaceAt(int index, MashupPart part) =>
      arrange(_arrangement.replacingAt(index, part));

  void setBlend(Duration value) => arrange(_arrangement.withBlend(value));

  /// Empties the arrangement, keeping the players for the next one.
  Future<void> clear() async {
    await _mixer.unload();
    _arrangement = Mashup.empty;
    _savedName = null;
    _editing = null;
    _stale = false;
    notifyListeners();
  }

  // ---- Playing -----------------------------------------------------------

  /// Starts the mix, loading the players first when they do not match what is
  /// arranged.
  Future<void> play() async {
    if (_arrangement.isEmpty) return;
    if (_stale || !_mixer.hasLayers) await _prepare();
    if (_arrangement.isEmpty) return;
    await _mixer.play();
  }

  Future<void> pause() => _mixer.pause();

  Future<void> stop() => _mixer.stop();

  /// Moves the mix to [moment] of the arrangement.
  ///
  /// Coalesced, because this is what a drag on the timeline calls: a finger
  /// moving across the card can ask for forty positions a second, and each one
  /// is a seek on every player. Only the latest request matters, so a new one
  /// arriving mid-seek replaces the one waiting rather than queueing behind it.
  Future<void> seekTo(Duration moment) async {
    if (_arrangement.isEmpty) return;
    if (_seeking) {
      _queuedSeek = moment;
      return;
    }
    _seeking = true;
    try {
      var target = moment;
      while (true) {
        await _seekOnce(target);
        final queued = _queuedSeek;
        if (queued == null) break;
        _queuedSeek = null;
        target = queued;
      }
    } finally {
      _seeking = false;
    }
  }

  Future<void> _seekOnce(Duration moment) async {
    if (_stale || !_mixer.hasLayers) {
      // Seeking an arrangement the players have not been told about means
      // loading it where it should be, not loading it and then jumping.
      await _prepare();
    }
    if (_arrangement.isEmpty) return;
    await _mixer.seekTo(moment);
  }

  /// Moves the mix to where part [index] enters, and opens that part.
  Future<void> jumpToPart(int index) async {
    if (index < 0 || index >= _arrangement.parts.length) return;
    openPart(index);
    await seekTo(_arrangement.parts[index].offset);
  }

  /// Moves the mix to a moment *inside* one part's own song.
  ///
  /// This is what makes the words of a part usable: a line of its lyrics is a
  /// time in the song, and the equivalent moment of the mix is that time plus
  /// wherever the part was placed, clamped to the slice that actually plays.
  Future<void> jumpIntoPart(int index, Duration songTime) async {
    if (index < 0 || index >= _arrangement.parts.length) return;
    final part = _arrangement.parts[index];
    final intoSlice = songTime - part.start;
    final clamped = intoSlice < Duration.zero
        ? Duration.zero
        : (intoSlice > part.length ? part.length : intoSlice);
    openPart(index);
    await seekTo(part.offset + clamped);
  }

  Future<void> _prepare() async {
    if (_arrangement.isEmpty) return;
    _preparing = true;
    notifyListeners();
    await _mixer.prepare(
      _arrangement,
      settings: _readSettings(),
      masterVolume: _readVolume(),
    );
    _preparing = false;
    _stale = false;
    notifyListeners();
  }

  void _onMixerChanged() => notifyListeners();

  // ---- Named mashups -----------------------------------------------------

  /// Every mashup on disk, most recently saved first.
  Future<List<SavedMashup>> saved() => store.list();

  /// Writes the arrangement to a mashup file called [name].
  Future<SavedMashup> saveAs(String name) async {
    final saved = await store.save(name, _arrangement);
    _savedName = saved.name;
    AppLogger.instance.info(
      'mashup',
      'arrangement saved as "${saved.name}"',
    );
    notifyListeners();
    return saved;
  }

  /// Replaces the arrangement with a saved one, ready to edit again.
  ///
  /// The mix is stopped and the players dropped: what they held was the old
  /// arrangement, and the file's version of it may have different slices,
  /// different entries and a different number of parts. Playing picks the new
  /// one up.
  Future<void> open(SavedMashup saved) async {
    await _mixer.unload();
    _arrangement = saved.mashup;
    _savedName = saved.name;
    _editing = _arrangement.parts.isEmpty ? null : 0;
    _stale = false;
    notifyListeners();
  }

  Future<bool> deleteSaved(String name) async {
    final deleted = await store.delete(name);
    if (deleted && _savedName == name) {
      _savedName = null;
      notifyListeners();
    }
    return deleted;
  }

  @override
  void dispose() {
    _mixer.removeListener(_onMixerChanged);
    unawaited(_mixer.disposeLayers());
    _mixer.dispose();
    super.dispose();
  }
}
