import 'dart:math' as math;

/// Equal-power crossfade gain computation for a two-player handoff.
///
/// Using sine/cosine (power-preserving) curves instead of a linear ramp avoids
/// the audible volume dip a linear crossfade produces at its midpoint.
class CrossfadeCurve {
  const CrossfadeCurve();

  /// Gain for the outgoing track at normalized progress [t] (0..1).
  double outgoingGain(double t) => math.cos(_clamp01(t) * math.pi / 2);

  /// Gain for the incoming track at normalized progress [t] (0..1).
  double incomingGain(double t) => math.sin(_clamp01(t) * math.pi / 2);

  static double _clamp01(double v) =>
      v.isNaN ? 0.0 : v.clamp(0.0, 1.0).toDouble();
}

/// Describes an in-progress crossfade between two players.
class CrossfadePlan {
  CrossfadePlan({
    required this.durationSeconds,
    required this.positionSeconds,
    CrossfadeCurve? curve,
  }) : curve = curve ?? const CrossfadeCurve();

  final double durationSeconds;
  final double positionSeconds;
  final CrossfadeCurve curve;

  /// Normalized progress, clamped to 0..1.
  double get progress => durationSeconds <= 0
      ? 1.0
      : (positionSeconds / durationSeconds).clamp(0.0, 1.0).toDouble();

  bool get isComplete => progress >= 1.0;

  double get outgoingGain => curve.outgoingGain(progress);
  double get incomingGain => curve.incomingGain(progress);

  /// Advances the plan, returning a new immutable plan.
  CrossfadePlan advance(double deltaSeconds) => CrossfadePlan(
    durationSeconds: durationSeconds,
    positionSeconds: positionSeconds + deltaSeconds,
    curve: curve,
  );

  /// When the *next* track should begin fading in, given the current track's
  /// remaining time and the configured crossfade length. A crossfade longer
  /// than the remaining audio is truncated to the remaining time.
  static double triggerOffsetSeconds({
    required double remainingSeconds,
    required double crossfadeSeconds,
  }) {
    if (crossfadeSeconds <= 0) return 0;
    return remainingSeconds < crossfadeSeconds
        ? math.max(0.0, remainingSeconds)
        : crossfadeSeconds;
  }
}
