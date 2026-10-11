import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/errors/failure_text.dart';
import 'package:gandar/data/import/library_file_import.dart';
import 'package:gandar/state/retry_policy.dart';

/// A failure that cannot change on a second attempt.
LibraryFileException _badFile() =>
    LibraryFileException('notes.txt is not valid JSON.');

void main() {
  group('gandarProviderRetry', () {
    test('never retries a file that cannot be parsed', () {
      expect(gandarProviderRetry(0, _badFile()), isNull);
    });

    test('retries what a retry could fix', () {
      expect(gandarProviderRetry(0, Exception('connection reset')), isNotNull);
    });

    test('gives up after a bounded number of attempts', () {
      final error = Exception('connection reset');
      expect(gandarProviderRetry(0, error), isNotNull);
      expect(gandarProviderRetry(4, error), isNull);
    });
  });

  group('a container using the policy', () {
    final probe = FutureProvider<void>((ref) async {});

    /// How many times a failing provider is started in the next 350 ms.
    ///
    /// Everything runs inside a guarded zone because a container reports the
    /// errors of its providers to the zone it was created in; here they are
    /// expected, so they are swallowed rather than failing the test.
    Future<int> startsFor(Object error, {bool withPolicy = true}) async {
      var runs = 0;
      await runZonedGuarded(() async {
        final container = ProviderContainer(
          retry: withPolicy ? gandarProviderRetry : null,
          overrides: [
            probe.overrideWith((ref) async {
              runs++;
              throw error;
            }),
          ],
        );
        try {
          // Listening is enough to start the work. The provider's own
          // `.future` is not awaited: every retry replaces it, so it can
          // hang until the last attempt settles.
          container.listen(probe, (previous, next) {}, fireImmediately: true);
          await Future<void>.delayed(const Duration(milliseconds: 350));
        } finally {
          container.dispose();
        }
      }, (Object _, StackTrace _) {});
      return runs;
    }

    test('runs an unparseable file exactly once', () async {
      final runs = await startsFor(_badFile());
      expect(runs, 1, reason: 'a bad file never reaches the retry timer');
    });

    test('still retries a transport failure', () async {
      final runs = await startsFor(Exception('connection reset'));
      expect(runs, greaterThan(1));
    });

    test('the default policy would have retried the bad file', () async {
      // Guards the reason this policy exists: without it Riverpod re-reads a
      // file that can never parse, forever, and buries the real cause.
      final runs = await startsFor(_badFile(), withPolicy: false);
      expect(runs, greaterThan(1));
    });
  });

  group('describeFailure', () {
    test('reports a bad file as final, with the file text as the message', () {
      final described = describeFailure(_badFile());

      expect(described.retryable, isFalse);
      expect(described.message, contains('not valid JSON'));
    });

    test('a transport failure stays retryable', () {
      final described = describeFailure(Exception('connection reset'));

      expect(described.retryable, isTrue);
    });

    test('falls back to the error text without the Exception: prefix', () {
      final described = describeFailure(Exception('disk on fire'));
      expect(described.message, 'disk on fire');
      expect(described.retryable, isTrue);
    });
  });
}
