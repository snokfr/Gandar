import 'track.dart';

/// The shortest slice a part may be.
///
/// Not a stylistic choice: a zero-length slice is a part that can never make a
/// sound, and a part you cannot hear is indistinguishable from a bug. Half a
/// second is short enough to be a stab and long enough to hear.
const Duration minimumMashupSlice = Duration(milliseconds: 500);

/// One record's contribution to a mashup: which slice of the song plays, where
/// that slice enters the mix, and how loud it sits against the others.
///
/// The three time values are deliberately separate, because a mashup needs all
/// three and they are not the same measurement:
///
/// * [start] and [end] are *inside the song* — the part you chose to lift.
/// * [offset] is *inside the mix* — when that part begins relative to the start
///   of the mashup. Two parts with overlapping `[offset, endInMix)` ranges play
///   at the same time, and that overlap is the mashup.
///
/// Everything is millisecond-resolution and nothing here touches a player, so
/// the whole arrangement can be reasoned about and tested as arithmetic.
class MashupPart {
  const MashupPart({
    required this.track,
    required this.start,
    required this.end,
    required this.offset,
    this.gain = defaultGain,
  });

  /// The whole of [track], entering at the top of the mix at [defaultGain].
  factory MashupPart.whole(Track track) => MashupPart._fit(
    track: track,
    start: Duration.zero,
    end: track.duration,
    offset: Duration.zero,
    gain: defaultGain,
  );

  /// Level a new part starts at.
  ///
  /// Below full on purpose: two layers at 100 % sum to clipping, and the sum is
  /// done by the system mixer where there is no limiter to catch it.
  static const double defaultGain = 0.8;

  final Track track;

  /// First moment of the song that plays.
  final Duration start;

  /// Where this part stops inside the song — the other end of the slice.
  final Duration end;

  /// When this part begins, measured from the start of the mix.
  final Duration offset;

  /// Level for this layer, 0..1.
  final double gain;

  String get title => track.title;
  String get artist => track.primaryArtist;

  /// Total length of the source song. [Duration.zero] when it is unknown.
  Duration get sourceDuration => track.duration;

  /// Whether the source's length is known, and therefore whether [end] can be
  /// bounded. An imported track always has one; a stream that arrived without
  /// metadata does not, and the mixer then plays to its real end.
  bool get hasKnownLength => sourceDuration > Duration.zero;

  /// Whether this part runs to the end of its source — only ever true for a
  /// song whose length was unknown when it was arranged, because then there was
  /// no end to choose. The mixer leaves such a part untrimmed rather than
  /// cutting it off at a guess.
  bool get playsToTheEnd => !hasKnownLength && end <= start;

  /// Length of the slice that actually plays.
  Duration get length {
    final span = end - start;
    return span > Duration.zero ? span : Duration.zero;
  }

  /// When this part stops, measured from the start of the mix.
  Duration get endInMix => offset + length;

  /// Position inside the song that should be sounding [intoMix] after this part
  /// began. Used for the playhead and for resuming after a pause.
  Duration sourcePositionAt(Duration intoPart) {
    final at = start + intoPart;
    return at > end ? end : at;
  }

  /// This part's own clock for a given position of the mix, or null when the
  /// mix position is outside this part entirely.
  Duration? positionInSource(Duration mixPosition) {
    if (mixPosition < offset || mixPosition >= endInMix) return null;
    return sourcePositionAt(mixPosition - offset);
  }

  MashupPart copyWith({
    Track? track,
    Duration? start,
    Duration? end,
    Duration? offset,
    double? gain,
  }) => MashupPart(
    track: track ?? this.track,
    start: start ?? this.start,
    end: end ?? this.end,
    offset: offset ?? this.offset,
    gain: gain ?? this.gain,
  );

  /// Moves where the part begins in its own song, pushing [end] along rather
  /// than refusing the edit: a slider dragged past the end of its own slice
  /// should slide the slice, not stop dead under the finger.
  MashupPart withStart(Duration value) =>
      _fit(track: track, start: value, end: end, offset: offset, gain: gain);

  /// Moves where the part stops in its own song.
  MashupPart withEnd(Duration value) =>
      _fit(track: track, start: start, end: value, offset: offset, gain: gain);

  /// Moves when the part begins in the mix. Never negative.
  MashupPart withOffset(Duration value) => copyWith(
    offset: value < Duration.zero ? Duration.zero : value,
  );

  MashupPart withGain(double value) => copyWith(gain: value.clamp(0.0, 1.0));

  /// A part whose slice is legal.
  ///
  /// Legal means inside the song when its length is known, and at least
  /// [minimumMashupSlice] long. Songs shorter than the minimum are the one
  /// exception: there is nothing to trim, so the whole song plays.
  static MashupPart _fit({
    required Track track,
    required Duration start,
    required Duration end,
    required Duration offset,
    required double gain,
  }) {
    final total = track.duration;
    if (total <= Duration.zero) {
      // Length unknown: an end of zero is not an empty slice here, it is "to
      // the end of whatever this turns out to be" — see [playsToTheEnd].
      return MashupPart(
        track: track,
        start: start < Duration.zero ? Duration.zero : start,
        end: end > start ? end : start,
        offset: offset < Duration.zero ? Duration.zero : offset,
        gain: gain.clamp(0.0, 1.0),
      );
    }

    if (total <= minimumMashupSlice) {
      return MashupPart(
        track: track,
        start: Duration.zero,
        end: total,
        offset: offset < Duration.zero ? Duration.zero : offset,
        gain: gain.clamp(0.0, 1.0),
      );
    }

    var from = start < Duration.zero ? Duration.zero : start;
    final latestStart = total - minimumMashupSlice;
    if (from > latestStart) from = latestStart;

    var to = end > total ? total : end;
    if (to < from + minimumMashupSlice) to = from + minimumMashupSlice;
    if (to > total) to = total;

    return MashupPart(
      track: track,
      start: from,
      end: to,
      offset: offset < Duration.zero ? Duration.zero : offset,
      gain: gain.clamp(0.0, 1.0),
    );
  }

  /// This part as a plain map, for a mashup file.
  ///
  /// Every field is written, the offset included: reopening a mashup has to
  /// give back the arrangement that was saved, not a re-laid-out version of it
  /// that happens to use the same songs.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'track': track.toJson(),
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'offsetMs': offset.inMilliseconds,
    'gain': gain,
  };

  /// Reads one part back.
  ///
  /// The values go through [_fit], so a mashup file that was edited by hand —
  /// or written by an older version with different limits — cannot produce a
  /// slice that runs past the end of its own song.
  static MashupPart fromJson(Map<String, dynamic> json) {
    final trackJson = json['track'];
    final track = trackJson is Map
        ? Track.fromJson(Map<String, dynamic>.from(trackJson))
        : const Track(id: '', title: 'Unknown', artists: <String>[]);
    return _fit(
      track: track,
      start: Duration(milliseconds: (json['startMs'] as num?)?.toInt() ?? 0),
      end: Duration(
        milliseconds:
            (json['endMs'] as num?)?.toInt() ?? track.durationMs,
      ),
      offset: Duration(
        milliseconds: (json['offsetMs'] as num?)?.toInt() ?? 0,
      ),
      gain: (json['gain'] as num?)?.toDouble() ?? defaultGain,
    );
  }

  @override
  String toString() =>
      'MashupPart(${track.id} ${start.inMilliseconds}-${end.inMilliseconds} ms '
      '@ ${offset.inMilliseconds} ms x$gain)';
}

/// An arrangement of [MashupPart]s: the parts, in the order they were placed,
/// plus the blend that decides how far each one overlaps the one before it.
class Mashup {
  const Mashup({this.parts = const <MashupPart>[], this.blend = defaultBlend});

  /// How much of two records sounds at once when the arrangement is laid out.
  static const Duration defaultBlend = Duration(seconds: 4);

  /// Longest selectable blend: past this a "blend" is just two songs playing
  /// over each other for so long that the first is unrecognisable.
  static const Duration maxBlend = Duration(seconds: 30);

  static const Mashup empty = Mashup();

  /// One part per track, in the given order, laid out end to end.
  factory Mashup.fromTracks(
    List<Track> tracks, {
    Duration blend = defaultBlend,
  }) => Mashup(blend: blend).withParts(
    tracks.map(MashupPart.whole).toList(growable: false),
  );

  final List<MashupPart> parts;

  /// Length of the overlap between each part and the one before it.
  final Duration blend;

  bool get isEmpty => parts.isEmpty;
  bool get hasLayer => parts.length >= 2;

  /// How long the whole mix runs: the last moment any part is still sounding.
  Duration get duration => parts.isEmpty
      ? Duration.zero
      : parts
            .map((part) => part.endInMix)
            .reduce((a, b) => a > b ? a : b);

  /// Every part sounding at [moment], in arrangement order.
  List<MashupPart> soundingAt(Duration moment) =>
      parts.where((part) => part.positionInSource(moment) != null).toList();

  /// Parts that sound at the same time as another part somewhere in the mix.
  ///
  /// A mix of parts laid out end to end has no overlap and is a playlist; the
  /// screen says so rather than calling it a mashup.
  bool get overlaps {
    for (var i = 1; i < parts.length; i++) {
      if (parts[i].offset < parts[i - 1].endInMix) return true;
    }
    return false;
  }

  /// How long part [index] overlaps the part before it — the audible blend at
  /// that seam, which is not the same as [blend] when a part is short.
  Duration overlapBefore(int index) {
    if (index <= 0 || index >= parts.length) return Duration.zero;
    final overlap = parts[index - 1].endInMix - parts[index].offset;
    return overlap > Duration.zero ? overlap : Duration.zero;
  }

  /// The blend actually in force at the seam before [index], in seconds.
  double overlapSecondsBefore(int index) =>
      overlapBefore(index).inMilliseconds / 1000;

  /// Replaces the parts and re-lays them out, which is what every edit goes
  /// through: a mashup is arranged by its blend, and a part moved by hand is
  /// the exception rather than the rule.
  Mashup withParts(List<MashupPart> next, {Duration? blend}) =>
      Mashup(blend: blend ?? this.blend).relayout(parts: next);

  /// Places every part at its blend-derived offset, keeping each slice and
  /// level exactly as it is.
  Mashup relayout({List<MashupPart>? parts, Duration? blend}) {
    final next = layout(parts ?? this.parts, blend ?? this.blend);
    return Mashup(parts: next, blend: blend ?? this.blend);
  }

  /// Changes the blend and re-lays the parts out.
  Mashup withBlend(Duration value) {
    final clamped = value < Duration.zero
        ? Duration.zero
        : (value > maxBlend ? maxBlend : value);
    return Mashup(blend: clamped).relayout(parts: parts);
  }

  Mashup adding(Track track) {
    if (parts.any((part) => part.track.id == track.id)) return this;
    return relayout(parts: <MashupPart>[...parts, MashupPart.whole(track)]);
  }

  Mashup removingAt(int index) {
    if (index < 0 || index >= parts.length) return this;
    final next = <MashupPart>[...parts]..removeAt(index);
    return relayout(parts: next);
  }

  Mashup moving(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= parts.length) return this;
    if (target < 0 || target >= parts.length) return this;
    final next = <MashupPart>[...parts];
    final part = next.removeAt(index);
    next.insert(target, part);
    return relayout(parts: next);
  }

  /// Replaces one part in place, leaving its offset where the user put it.
  ///
  /// Editing a slice must not move the part: a user dragging "ends at" is
  /// listening to that seam, and re-laying the whole arrangement out from under
  /// the drag would change the thing being judged.
  Mashup replacingAt(int index, MashupPart part) {
    if (index < 0 || index >= parts.length) return this;
    final next = <MashupPart>[...parts];
    next[index] = part;
    return Mashup(parts: next, blend: blend);
  }

  /// The arrangement as a plain map, for writing a mashup file.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'blendMs': blend.inMilliseconds,
    'parts': <Map<String, dynamic>>[
      for (final part in parts) part.toJson(),
    ],
  };

  /// Reads an arrangement back from [toJson].
  ///
  /// A payload with no usable parts is [Mashup.empty] rather than an error: an
  /// unreadable file should look like a mashup that has nothing in it yet, not
  /// like a crash on the way into the screen.
  static Mashup fromJson(Map<String, dynamic> json) {
    final raw = json['parts'];
    if (raw is! List) return Mashup.empty;
    final parts = <MashupPart>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final part = MashupPart.fromJson(Map<String, dynamic>.from(entry));
      if (part.track.id.isEmpty) continue;
      parts.add(part);
    }
    if (parts.isEmpty) return Mashup.empty;
    return Mashup(
      parts: List<MashupPart>.unmodifiable(parts),
      blend: Duration(
        milliseconds:
            (json['blendMs'] as num?)?.toInt() ?? defaultBlend.inMilliseconds,
      ),
    );
  }

  /// Places [parts] one after another, each overlapping the previous one by
  /// [blend].
  ///
  /// The overlap is capped at the length of the part before it: a blend longer
  /// than a slice cannot overlap it more than completely, and clamping here
  /// instead of letting offsets run backwards is what keeps the mix in the
  /// order it is shown in.
  static List<MashupPart> layout(
    List<MashupPart> parts,
    Duration blend,
  ) {
    final overlap = blend < Duration.zero ? Duration.zero : blend;
    final placed = <MashupPart>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i == 0) {
        placed.add(part.withOffset(Duration.zero));
        continue;
      }
      final previous = placed.last;
      var entersAt = previous.endInMix - overlap;
      // A part cannot be overlapped by more than its own length, so the blend
      // stops moving things earlier as soon as it has swallowed a whole slice.
      // Without this a long blend would stagger the parts backwards.
      if (entersAt < previous.offset) entersAt = previous.offset;
      placed.add(part.withOffset(entersAt));
    }
    return List<MashupPart>.unmodifiable(placed);
  }
}
