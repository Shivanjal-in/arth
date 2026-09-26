// Reader scrolling: a slow drag or a gentle flick moves exactly as the
// platform's own scrolling does (steady, good for reading); a hard flick is
// carried further, so crossing a long book isn't a slog.

import 'package:flutter/widgets.dart';

class FlickBoostPhysics extends ScrollPhysics {
  const FlickBoostPhysics({super.parent});

  /// Flicks slower than this (logical px/s) are left alone.
  static const threshold = 1500.0;

  /// The boost grows over this much extra speed…
  static const ramp = 3000.0;

  /// …up to this many times the flick's own speed.
  static const maxFactor = 2.5;

  /// The velocity a flick is given: unchanged below [threshold], then
  /// scaled up smoothly to [maxFactor].
  static double boost(double velocity) {
    final speed = velocity.abs();
    if (speed <= threshold) return velocity;
    final t = ((speed - threshold) / ramp).clamp(0.0, 1.0);
    return velocity * (1 + (maxFactor - 1) * t);
  }

  @override
  FlickBoostPhysics applyTo(ScrollPhysics? ancestor) => FlickBoostPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      super.createBallisticSimulation(position, boost(velocity));
}
