import 'package:flutter_test/flutter_test.dart';
import 'package:gandar/core/settings/settings_repository.dart';
import 'package:gandar/data/usage/app_usage.dart';

/// A clock a test can move by hand.
class FakeClock {
  FakeClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration d) => _now = _now.add(d);
}

/// Advances [total] in steps small enough that no single tick trips the
/// sleep guard, which is what a real app does at five seconds a tick.
void tickFor(
  AppUsageTracker tracker,
  FakeClock clock,
  Duration total, {
  Duration step = const Duration(seconds: 30),
}) {
  var remaining = total;
  while (remaining > Duration.zero) {
    final slice = remaining < step ? remaining : step;
    clock.advance(slice);
    tracker.tickOnce();
    remaining -= slice;
  }
}

void main() {
  group('AppUsageTracker', () {
    test('starts at zero and reads back what was stored', () async {
      final tracker = AppUsageTracker(store: InMemoryStore());
      expect(tracker.usage, AppUsage.none);

      await tracker.flush();
      expect(tracker.usage.lifetime, Duration.zero);
      expect(tracker.usage.lifetimeIncludingSession, Duration.zero);
    });

    test('restores the stored total', () async {
      final store = InMemoryStore(<String, String>{
        AppUsageTracker.storageKey: '3600',
      });
      final tracker = AppUsageTracker(store: store);
      await tracker.load();
      expect(tracker.usage.lifetime, const Duration(hours: 1));
      expect(tracker.usage.session, Duration.zero);
      // The loaded total is already part of the answer, not something that
      // still has to be added in.
      expect(tracker.usage.lifetimeIncludingSession, const Duration(hours: 1));
    });

    test('a nonsense stored value reads as zero rather than throwing', () async {
      final tracker = AppUsageTracker(
        store: InMemoryStore(<String, String>{
          AppUsageTracker.storageKey: 'not a number',
        }),
      );
      await tracker.load();
      expect(tracker.usage.lifetime, Duration.zero);
    });

    test('a negative stored value is clamped, not subtracted', () async {
      final tracker = AppUsageTracker(
        store: InMemoryStore(<String, String>{
          AppUsageTracker.storageKey: '-500',
        }),
      );
      await tracker.load();
      expect(tracker.usage.lifetime, Duration.zero);
    });

    test('ticks accumulate into the session', () {
      final clock = FakeClock(DateTime(2026, 10, 11, 9));
      final tracker = AppUsageTracker(
        store: InMemoryStore(),
        clock: clock.call,
      );
      tracker.start(tick: const Duration(hours: 1));

      tickFor(tracker, clock, const Duration(seconds: 60));

      expect(tracker.usage.session, const Duration(seconds: 60));
      // Nothing has been written yet, so the stored total is still zero and the
      // running total is exactly the session.
      expect(tracker.usage.lifetime, Duration.zero);
      expect(tracker.usage.lifetimeIncludingSession, const Duration(seconds: 60));
      tracker.dispose();
    });

    test('a suspended machine does not count as time in Gandar', () {
      // Sleep for eight hours, wake up, tick once: the wall clock moved but the
      // app was not open, so only one tick's worth may be counted.
      final clock = FakeClock(DateTime(2026, 10, 11, 22));
      final tracker = AppUsageTracker(store: InMemoryStore(), clock: clock.call);
      tracker.start(tick: const Duration(hours: 1));

      clock.advance(const Duration(hours: 8));
      tracker.tickOnce();

      expect(tracker.usage.session, AppUsageTracker.maxTick);
      tracker.dispose();
    });

    test('flush folds the session into the stored total exactly once', () async {
      final clock = FakeClock(DateTime(2026, 10, 11, 9));
      final store = InMemoryStore();
      final tracker = AppUsageTracker(
        store: store,
        clock: clock.call,
        // Long enough that no automatic flush happens mid-test.
        flushEvery: const Duration(hours: 1),
      );
      tracker.start(tick: const Duration(hours: 1));

      tickFor(tracker, clock, const Duration(minutes: 10));
      await tracker.flush();

      expect(await store.getString(AppUsageTracker.storageKey), '600');
      expect(tracker.usage.lifetime, const Duration(minutes: 10));
      expect(tracker.usage.session, const Duration(minutes: 10));
      // The session is not dropped after being folded in: the number on screen
      // is "this run", and it keeps growing.
      expect(tracker.usage.lifetimeIncludingSession, const Duration(minutes: 20));
      tracker.dispose();
    });

    test('a second flush with nothing new writes nothing', () async {
      final clock = FakeClock(DateTime(2026, 10, 11, 9));
      final store = InMemoryStore();
      final tracker = AppUsageTracker(
        store: store,
        clock: clock.call,
        flushEvery: const Duration(hours: 1),
      );
      tracker.start(tick: const Duration(hours: 1));

      tickFor(tracker, clock, const Duration(minutes: 5));
      await tracker.flush();
      expect(await store.getString(AppUsageTracker.storageKey), '300');

      await tracker.flush();
      expect(await store.getString(AppUsageTracker.storageKey), '300');
      tracker.dispose();
    });

    test('a total survives a restart through the same store', () async {
      final store = InMemoryStore();
      final clock = FakeClock(DateTime(2026, 10, 11, 9));

      final first = AppUsageTracker(
        store: store,
        clock: clock.call,
        flushEvery: const Duration(hours: 1),
      );
      first.start(tick: const Duration(hours: 1));
      tickFor(first, clock, const Duration(minutes: 20));
      await first.flush();
      first.dispose();

      final second = AppUsageTracker(store: store, clock: clock.call);
      await second.load();
      second.start(tick: const Duration(hours: 1));
      expect(second.usage.lifetime, const Duration(minutes: 20));
      second.dispose();
    });
  });

  group('describeShortDuration', () {
    test('covers the three shapes', () {
      expect(describeShortDuration(const Duration(seconds: 42)), '42 s');
      expect(describeShortDuration(const Duration(minutes: 42)), '42 min');
      expect(describeShortDuration(const Duration(hours: 4)), '4 h');
      expect(
        describeShortDuration(const Duration(hours: 4, minutes: 7)),
        '4 h 7 m',
      );
    });

    test('60 seconds reads as a minute, not 60 s', () {
      expect(describeShortDuration(const Duration(seconds: 60)), '1 min');
    });
  });
}
