import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fluid-interface motion helpers.
///
/// These encode the physical-motion approach: springs rather than fixed
/// durations, momentum projection so a flick lands where the gesture was
/// heading, rubber-banding at boundaries, and reduced-motion fallbacks.
class Motion {
  const Motion._();

  /// Critically damped, no overshoot — the default for non-gestural UI.
  static const SpringDescription standard = SpringDescription(
    mass: 1,
    stiffness: 220,
    damping: 26,
  );

  /// Slightly under-damped, for momentum-driven interactions (a flicked
  /// sheet, a thrown card). A little bounce reads as physical because the
  /// gesture itself carried velocity.
  static const SpringDescription momentum = SpringDescription(
    mass: 1,
    stiffness: 220,
    damping: 20,
  );

  /// Deceleration rate for scroll-like projection. 0.998 ≈ normal feel.
  static const double decelerationRate = 0.998;

  /// Projects where a flick will come to rest, given its release velocity
  /// (px/s). Uses the exponential-decay form, not v²/2a.
  static double projectMomentum(double velocity, {double? decelerationRate}) {
    final d = decelerationRate ?? Motion.decelerationRate;
    return (velocity / 1000) * d / (1 - d);
  }

  /// Chooses the snap target nearest the *projected* resting point, so a small
  /// input produces a decisive, intended output.
  static int snapIndex({
    required double currentIndex,
    required double releaseVelocity,
    required int itemCount,
  }) {
    final projected = currentIndex + projectMomentum(releaseVelocity);
    return projected.round().clamp(0, itemCount - 1).toInt();
  }

  /// Progressive resistance past a boundary — soft, not a hard stop.
  static double rubberBand(
    double overshoot,
    double dimension, {
    double constant = 0.55,
  }) {
    return (overshoot * dimension * constant) /
        (dimension + constant * overshoot.abs());
  }

  /// Equal-power crossfade curve. Returns the gain for [t] in 0..1 such that
  /// a² + b² stays constant, avoiding the volume dip a linear fade produces.
  static double equalPowerGain(double t) =>
      math.sin(t.clamp(0.0, 1.0) * math.pi / 2);

  /// Whether the platform asks for reduced motion.
  static bool prefersReducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Animation duration respecting reduced-motion: short cross-fade when
  /// reduced motion is on, otherwise a comfortable spring-timed duration.
  static Duration adaptiveDuration(
    BuildContext context, {
    Duration full = const Duration(milliseconds: 320),
    Duration reduced = const Duration(milliseconds: 120),
  }) => prefersReducedMotion(context) ? reduced : full;
}
