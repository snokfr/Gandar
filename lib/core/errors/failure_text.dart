import '../../data/import/library_file_import.dart';

/// Turns a thrown error into copy that belongs on screen, plus whether
/// offering a **Retry** button would be honest.
class FailureText {
  const FailureText({required this.message, required this.retryable});

  /// One or two sentences a person can act on.
  final String message;

  /// False when repeating the work cannot change the answer — a file that will
  /// never parse, a row that is not in the library. A Retry button in that case
  /// just teaches the user that the button does nothing.
  final bool retryable;
}

/// Describes [error] for the UI.
///
/// Since Gandar has no account, every failure it can show comes from either a
/// file the user picked or a request it made itself. The file case is the only
/// one where the answer is already final.
FailureText describeFailure(Object error) {
  if (error is LibraryFileException) {
    return FailureText(message: error.message, retryable: false);
  }

  final text = error.toString();
  return FailureText(
    message: text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text,
    retryable: true,
  );
}
