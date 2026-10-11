import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/data/net/request_gate.dart';

/// A clock and a "sleep" that only move virtual time, so these tests exercise
/// the timing logic without actually waiting.
class _VirtualTime {
  _VirtualTime() : now = DateTime(2026, 1, 1);

  DateTime now;
  final List<Duration> sleeps = <Duration>[];

  Future<void> sleep(Duration duration) async {
    sleeps.add(duration);
    now = now.add(duration);
    // Yield to the event loop so concurrent tasks still make progress.
    await Future<void>.delayed(Duration.zero);
  }

  Duration get totalSlept => sleeps.fold(Duration.zero, (sum, d) => sum + d);
}

void main() {
  group('HostGovernor', () {
    test('never runs more than maxConcurrent requests at once', () async {
      final time = _VirtualTime();
      final governor = HostGovernor(
        host: 'example.test',
        maxConcurrent: 2,
        burst: 100,
        refillPerSecond: 1000,
        clock: () => time.now,
        sleep: time.sleep,
      );

      var active = 0;
      var peak = 0;
      await Future.wait(
        List.generate(10, (_) {
          return governor.schedule(() async {
            active++;
            peak = max(peak, active);
            // Yield so other tasks get a chance to start.
            await Future<void>.delayed(Duration.zero);
            active--;
          });
        }),
      );

      expect(peak, lessThanOrEqualTo(2));
      expect(governor.inFlight, 0);
    });

    test('caps the burst and meters the rest through the bucket', () async {
      final time = _VirtualTime();
      final governor = HostGovernor(
        host: 'example.test',
        maxConcurrent: 8,
        burst: 3,
        refillPerSecond: 10,
        clock: () => time.now,
        sleep: time.sleep,
      );

      for (var i = 0; i < 5; i++) {
        await governor.schedule(() async {});
      }

      // Three free requests, then two that wait about 100 ms each for a token.
      expect(time.sleeps, hasLength(2));
      expect(time.totalSlept.inMilliseconds, greaterThanOrEqualTo(100));
    });

    test('a throttled response pauses the host, then retries', () async {
      final time = _VirtualTime();
      final governor = HostGovernor(
        host: 'example.test',
        maxConcurrent: 2,
        burst: 5,
        refillPerSecond: 100,
        clock: () => time.now,
        sleep: time.sleep,
        random: Random(7),
      );
      governor.isRateLimited = (e) => e is RateLimitedException;
      governor.retryAfterOf = (e) =>
          e is RateLimitedException ? e.retryAfter : null;

      var attempts = 0;
      final result = await governor.schedule(() async {
        attempts++;
        if (attempts == 1) {
          throw RateLimitedException(
            'example.test',
            const Duration(seconds: 2),
          );
        }
        return 'ok';
      });

      expect(result, 'ok');
      expect(attempts, 2, reason: 'the throttled attempt should be retried');
      // The retry waited out the advertised window (+ jitter), which is the
      // behaviour that keeps us under a provider's limit.
      expect(time.totalSlept.inMilliseconds, greaterThanOrEqualTo(2000));
      // Cooldown has served its purpose by the time the retry succeeds.
      expect(governor.cooling, isFalse);
    });

    test('a non-throttle failure is not retried', () async {
      final time = _VirtualTime();
      final governor = HostGovernor(
        host: 'example.test',
        clock: () => time.now,
        sleep: time.sleep,
      );

      var attempts = 0;
      await expectLater(
        governor.schedule(() async {
          attempts++;
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
    });

    test('gives up after maxRetries on a persistent throttle', () async {
      final time = _VirtualTime();
      final governor = HostGovernor(
        host: 'example.test',
        maxRetries: 2,
        clock: () => time.now,
        sleep: time.sleep,
      );
      governor.isRateLimited = (e) => e is RateLimitedException;

      var attempts = 0;
      await expectLater(
        governor.schedule(() async {
          attempts++;
          throw RateLimitedException('example.test', Duration.zero);
        }),
        throwsA(isA<RateLimitedException>()),
      );
      expect(attempts, 3, reason: 'initial attempt plus two retries');
    });
  });

  group('InFlightCoalescer', () {
    test('two identical concurrent requests run once', () async {
      final coalescer = InFlightCoalescer();
      var calls = 0;

      Future<int> body() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 42;
      }

      final results = await Future.wait([
        coalescer.run<int>('GET /same', body),
        coalescer.run<int>('GET /same', body),
      ]);

      expect(results, [42, 42]);
      expect(calls, 1);
      expect(coalescer.size, 0, reason: 'entries are dropped once complete');
    });

    test('different keys are not coalesced', () async {
      final coalescer = InFlightCoalescer();
      var calls = 0;

      Future<int> body() async {
        calls++;
        return calls;
      }

      await Future.wait([
        coalescer.run<int>('a', body),
        coalescer.run<int>('b', body),
      ]);

      expect(calls, 2);
    });
  });

  group('RequestGate', () {
    test('shares one governor per host', () {
      final gate = RequestGate();
      expect(
        identical(gate.forHost('api.test'), gate.forHost('api.test')),
        isTrue,
      );
      expect(
        identical(gate.forHost('api.test'), gate.forHost('other.test')),
        isFalse,
      );
      expect(gate.hosts.keys, containsAll(['api.test', 'other.test']));
    });

    test('routes a URL to its own host governor', () async {
      final gate = RequestGate();
      await gate.scheduleForUrl('https://api.spotify.com/v1/me', () async {});
      await gate.scheduleForUrl('https://www.youtube.com/watch', () async {});
      expect(
        gate.hosts.keys,
        containsAll(['api.spotify.com', 'www.youtube.com']),
      );
    });
  });
}
