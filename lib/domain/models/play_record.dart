/// One recorded play, with the track's duration where it is known.
///
/// The duration is 0 when the track was never cached locally, so callers must
/// treat listening totals as a floor rather than an exact figure.
class PlayRecord {
  const PlayRecord({
    required this.trackId,
    required this.playedAt,
    this.durationMs = 0,
  });

  final String trackId;
  final DateTime playedAt;
  final int durationMs;

  Duration get duration => Duration(milliseconds: durationMs);

  @override
  String toString() => 'PlayRecord($trackId, $playedAt, ${durationMs}ms)';
}
