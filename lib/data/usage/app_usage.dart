import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../core/settings/settings_repository.dart';

/// Compact duration: `2 h 14 m`, `45 min`, `30 s`.
///
/// One formatter for every place a duration is shown as a rounded figure — the
/// Discord line and the "time in Gandar" stat — so the two can never disagree
/// about how "two hours and five minutes" is written.
String describeShortDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final hours = d.inHours;
  final minutes = d.inMinutes - hours * 60;
  return minutes == 0 ? '$hours h' : '$hours h $minutes m';
}

/// How long Gandar has been open: this run, and ever.
///
/// This is a *clock on the app*, not on the music: it counts from launch, and
/// keeps counting while a track is paused and while nothing is playing at all.
/// That is what the Discord line and the activity view mean by "time in
/// Gandar", and counting listening time instead would quietly answer a
/// different question.
@immutable
class AppUsage {
  const AppUsage({required this.session, required this.lifetime});

  /// Time since this launch.
  final Duration session;

  /// Every session this install has had, added up.
  final Duration lifetime;

  static const AppUsage none = AppUsage(
    session: Duration.zero,
    lifetime: Duration.zero,
  );

  /// Total including the part of the current session not yet folded in.
  Duration get lifetimeIncludingSession => lifetime + session;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUsage &&
          other.session == session &&
          other.lifetime == lifetime;

  @override
  int get hashCode => Object.hash(session, lifetime);
}

/// Counts how long the app stays open and remembers it across launches.
///
/// The current session is ticked in memory and the *lifetime* total is written
/// to storage periodically rather than only at exit: a process that is killed,
/// or a machine that loses power, would otherwise lose the whole session. The
/// cost is that a crash can lose at most [flushEvery] of elapsed time, which is
/// the right trade for a counter nobody is billing against.
class AppUsageTracker extends ChangeNotifier {
  AppUsageTracker({
    required this.store,
    this.flushEvery = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final KeyValueStore store;
  final Duration flushEvery;
  final DateTime Function() _clock;

  /// Preference key. Versioned like the other preference keys so a future
  /// change of shape can be told apart from this one.
  static const String storageKey = 'usage.app.v1';

  /// The longest a single tick may count. A laptop that was asleep has a
  /// wall-clock gap in it, and counting eight suspended hours as eight hours in
  /// Gandar would be a lie of exactly the kind this app avoids elsewhere.
  static const Duration maxTick = Duration(seconds: 90);

  Timer? _timer;
  DateTime? _lastTickAt;
  Duration _lifetime = Duration.zero;
  Duration _session = Duration.zero;
  Duration _unflushed = Duration.zero;
  bool _started = false;

  /// [AppUsage.lifetime] here is only what storage holds, so the two fields
  /// never overlap and `lifetimeIncludingSession` stays a real total rather
  /// than the session counted twice.
  AppUsage get usage => AppUsage(session: _session, lifetime: _lifetime);

  /// Loads the stored total. Safe to call once at startup.
  Future<void> load() async {
    final raw = await store.getString(storageKey);
    final seconds = int.tryParse(raw ?? '') ?? 0;
    _lifetime = Duration(seconds: seconds < 0 ? 0 : seconds);
    notifyListeners();
  }

  /// Begins counting. Does nothing if already started.
  void start({Duration tick = const Duration(seconds: 5)}) {
    if (_started) return;
    _started = true;
    _lastTickAt = _clock();
    _timer = Timer.periodic(tick, (_) => tickOnce());
  }

  /// Advances the clock by however long it has been since the last tick.
  ///
  /// Exposed so a test can drive it with a fake clock instead of waiting.
  void tickOnce() {
    final now = _clock();
    final last = _lastTickAt;
    _lastTickAt = now;
    if (last == null) return;

    final elapsed = now.difference(last);
    if (elapsed <= Duration.zero) return;
    final counted = elapsed > maxTick ? maxTick : elapsed;

    _session += counted;
    _unflushed += counted;
    notifyListeners();
    if (_unflushed >= flushEvery) {
      unawaited(flush());
    }
  }

  /// Folds the current session into the stored lifetime.
  Future<void> flush() async {
    final pending = _unflushed;
    if (pending <= Duration.zero) return;
    _unflushed = Duration.zero;
    final total = _lifetime + pending;
    try {
      await store.setString(storageKey, '${total.inSeconds}');
      _lifetime = total;
    } catch (e) {
      // Losing the write is not worth interrupting anything over; the seconds
      // go back on the pile and the next flush tries again.
      _unflushed += pending;
      AppLogger.instance.warn('usage', 'could not save usage total', error: e);
    }
  }

  /// Writes the total once more and stops counting.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    tickOnce();
    await flush();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
