import 'dart:async';
import 'dart:math';

import '../../core/logging/app_logger.dart';

/// Raised when a host is cooling down and the caller asked not to wait.
class RateLimitedException implements Exception {
  RateLimitedException(this.host, this.retryAfter);

  final String host;
  final Duration retryAfter;

  @override
  String toString() =>
      'RateLimitedException($host): retry after '
      '${retryAfter.inMilliseconds} ms';
}

/// Politeness controls for one host.
///
/// Three mechanisms, in the order the provider will notice them:
///
/// 1. **Bounded concurrency** — never more than [maxConcurrent] requests in
///    flight, so a burst of paging does not look like an attack.
/// 2. **Token bucket** — [refillPerSecond] sustained, [burst] allowed at once.
///    This is what keeps a 40-page library fetch inside the rate a provider
///    expects instead of hammering it as fast as the network allows.
/// 3. **Cooldown** — on a `429`/`Retry-After`, every request for that host
///    waits out the window (plus jitter) before trying again.
///
/// The clock and sleep function are injectable so tests run instantly.
class HostGovernor {
  HostGovernor({
    required this.host,
    this.maxConcurrent = 4,
    this.burst = 6,
    this.refillPerSecond = 4,
    this.maxRetries = 3,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    Random? random,
    this.isRateLimited,
    this.retryAfterOf,
  }) : _now = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random();

  final String host;

  /// Requests that may be in flight at once.
  final int maxConcurrent;

  /// Tokens available after an idle period.
  final int burst;

  /// Sustained request rate.
  final double refillPerSecond;

  /// Retries for a rate-limited request before giving up.
  final int maxRetries;

  /// Classifies an error as "the provider is throttling us".
  ///
  /// Mutable so a client can attach its own classifier to a shared governor.
  bool Function(Object error)? isRateLimited;

  /// Extracts a `Retry-After` window from an error, when the provider sent one.
  Duration? Function(Object error)? retryAfterOf;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  double _tokens = -1;
  DateTime? _lastRefill;
  DateTime? _coolingUntil;
  int _inFlight = 0;
  int _queued = 0;

  /// FIFO of callers waiting for a concurrency slot.
  final List<Completer<void>> _waiters = <Completer<void>>[];

  /// Requests currently in flight.
  int get inFlight => _inFlight;

  /// Requests waiting for a slot or a token.
  int get queued => _queued;

  /// True while the host is in a `429` cooldown.
  bool get cooling => _coolingUntil != null && _coolingUntil!.isAfter(_now());

  /// Runs [task] under this host's limits, retrying throttled attempts.
  Future<T> schedule<T>(Future<T> Function() task) async {
    _queued++;
    try {
      await _acquireSlot();
    } finally {
      _queued--;
    }
    try {
      var attempt = 0;
      while (true) {
        await _waitForPermission();
        try {
          return await task();
        } catch (error) {
          if (_classifyRateLimit(error) && attempt < maxRetries) {
            attempt++;
            notifyRateLimited(retryAfterOf?.call(error));
            AppLogger.instance.warn(
              'net',
              '$host throttled, retry $attempt/$maxRetries',
            );
            continue;
          }
          rethrow;
        }
      }
    } finally {
      _releaseSlot();
    }
  }

  /// Records a throttle response so later requests wait it out.
  void notifyRateLimited(Duration? retryAfter) {
    // Respect the provider's window; otherwise back off exponentially with
    // jitter so parallel workers do not all come back at the same instant.
    final base = retryAfter ?? Duration(seconds: 2);
    final jitterMs = _random.nextInt(500);
    final wait = Duration(
      milliseconds:
          base.inMilliseconds * (retryAfter == null ? 1 : 1) + jitterMs,
    );
    final until = _now().add(wait);
    if (_coolingUntil == null || until.isAfter(_coolingUntil!)) {
      _coolingUntil = until;
      AppLogger.instance.warn(
        'net',
        '$host cooling down for ${wait.inMilliseconds} ms',
      );
    }
  }

  bool _classifyRateLimit(Object error) {
    final custom = isRateLimited;
    if (custom != null) return custom(error);
    return error is RateLimitedException;
  }

  Future<void> _acquireSlot() async {
    if (_inFlight < maxConcurrent) {
      _inFlight++;
      return;
    }
    // Wait to be handed a slot rather than polling, so no caller can spin the
    // event loop and nothing depends on how fast the clock advances.
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void _releaseSlot() {
    if (_inFlight > 0) _inFlight--;
    while (_waiters.isNotEmpty && _inFlight < maxConcurrent) {
      _inFlight++;
      _waiters.removeAt(0).complete();
    }
  }

  Future<void> _waitForPermission() async {
    while (true) {
      final cooling = _coolingUntil;
      if (cooling != null && cooling.isAfter(_now())) {
        final remaining = cooling.difference(_now());
        await _sleep(remaining);
        continue;
      }
      if (cooling != null) _coolingUntil = null;

      _refill();
      if (_tokens >= 1) {
        _tokens -= 1;
        return;
      }
      // Wait for the bucket to refill; capped so a cancelled token cannot
      // stall everything for a long time.
      final waitMs = ((1 - _tokens) / refillPerSecond * 1000).ceil();
      await _sleep(Duration(milliseconds: waitMs.clamp(5, 250)));
    }
  }

  void _refill() {
    final now = _now();
    if (_tokens < 0 || _lastRefill == null) {
      _tokens = burst.toDouble();
      _lastRefill = now;
      return;
    }
    final elapsedMs = now.difference(_lastRefill!).inMilliseconds;
    if (elapsedMs <= 0) return;
    _tokens = min(
      burst.toDouble(),
      _tokens + elapsedMs / 1000 * refillPerSecond,
    );
    _lastRefill = now;
  }

  /// Test seam: forget all state between cases.
  void reset() {
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _waiters.clear();
    _tokens = -1;
    _lastRefill = null;
    _coolingUntil = null;
    _inFlight = 0;
    _queued = 0;
  }
}

/// A gate per host, shared by every client in the app.
///
/// Providers throttle per host rather than per API, so one bucket per host is
/// what actually keeps requests under the limit.
class RequestGate {
  RequestGate({
    this.defaultMaxConcurrent = 4,
    this.defaultBurst = 6,
    this.defaultRefillPerSecond = 4,
    this.governorBuilder,
    this.randomSource,
    this.clock,
    this.sleeper,
  });

  final int defaultMaxConcurrent;
  final int defaultBurst;
  final double defaultRefillPerSecond;

  /// Overrides governor construction, used by tests to control timing.
  final HostGovernor Function(String host)? governorBuilder;
  final Random? randomSource;
  final DateTime Function()? clock;
  final Future<void> Function(Duration)? sleeper;

  final Map<String, HostGovernor> _hosts = <String, HostGovernor>{};

  /// The governor for [host], created on first use.
  HostGovernor forHost(String host) => _hosts.putIfAbsent(host, () {
    final built = governorBuilder?.call(host);
    if (built != null) return built;
    return HostGovernor(
      host: host,
      maxConcurrent: defaultMaxConcurrent,
      burst: defaultBurst,
      refillPerSecond: defaultRefillPerSecond,
      random: randomSource,
      clock: clock,
      sleep: sleeper,
    );
  });

  /// Schedules [task] against the governor for [url]'s host.
  Future<T> scheduleForUrl<T>(String url, Future<T> Function() task) =>
      forHost(Uri.parse(url).host).schedule(task);

  /// Hosts that currently exist, for diagnostics.
  Map<String, HostGovernor> get hosts =>
      Map<String, HostGovernor>.unmodifiable(_hosts);

  void reset() {
    for (final governor in _hosts.values) {
      governor.reset();
    }
    _hosts.clear();
  }
}

/// Coalesces identical in-flight GETs so two screens asking for the same URL
/// cause one request, not two.
///
/// Deliberately short-lived: entries are dropped when the request completes so
/// stale data is never served.
class InFlightCoalescer {
  final Map<String, Future<Object?>> _inFlight = <String, Future<Object?>>{};

  int get size => _inFlight.length;

  Future<T> run<T>(String key, Future<T> Function() body) {
    final existing = _inFlight[key];
    if (existing != null) {
      AppLogger.instance.debug('net', 'coalesced duplicate request: $key');
      return existing.then((value) => value as T);
    }
    // Note the block body: returning the removed future here would make
    // whenComplete await the very future it is completing, deadlocking.
    final future = body().whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }
}
