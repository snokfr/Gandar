import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/import/library_file_import.dart';

/// How long to wait before re-running a failed provider, or null to stop.
///
/// Riverpod retries a failed provider on its own — exponential backoff from
/// 200 ms, ten attempts, capped at 6.4 s. That is the right instinct for a
/// flaky network and the wrong one for an answer: a library file that cannot be
/// parsed would be re-read every 6.4 s for the life of the app, which the user
/// never sees, spends the provider's patience, and buries the real cause under
/// an identical line in the log.
///
/// So retry only what a retry could actually fix, and give up immediately on
/// everything else so the error reaches the screen and stays put.
Duration? gandarProviderRetry(int retryCount, Object error) {
  if (error is LibraryFileException) return null;
  // Fewer attempts than Riverpod's default: the host governor already owns
  // transport-level retrying, so a provider retry should be a last resort.
  return ProviderContainer.defaultRetry(retryCount, error, maxRetries: 4);
}
