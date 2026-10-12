/// The export was asked to stop.
///
/// Its own type rather than a `StateError`, because "stopped because you asked"
/// and "stopped because it went wrong" have to be told apart: the first should
/// clean up quietly and say so, the second should be reported as a failure with
/// the reason.
///
/// It lives in a file of its own because both halves of an export throw it — the
/// decoder, when a part is abandoned mid-decode, and the job, between parts — and
/// neither should have to import the other to name it.
class ExportCancelled implements Exception {
  const ExportCancelled();

  @override
  String toString() => 'the export was cancelled';
}
