// Ported from AndroidLiquidGlassView's `LiquidTracker` by Donny Yale (QmDeve).
// https://github.com/QmDeve/AndroidLiquidGlassView - MIT License.

import 'dart:math' as math;
import 'dart:ui';

import 'liquid_glass_config.dart';

/// Pure calculations shared by the liquid interaction and renderer.
///
/// These helpers are public so advanced integrations can predict elastic
/// deformation and sampling cost without constructing a widget.
abstract final class LiquidGlassPhysics {
  /// Reproduces Android `LiquidTracker.getLiquidScale()`.
  ///
  /// Velocity is in logical pixels per millisecond, matching Android's
  /// `VelocityTracker.computeCurrentVelocity(1)` output. The dominant axis
  /// stretches, the other compresses, and both are clamped to 0.6 through 1.4.
  static ({double x, double y}) scaleForVelocity(Offset velocity) {
    const double stretchFactor = 0.5;
    final double absX = velocity.dx.abs();
    final double absY = velocity.dy.abs();
    double scaleX;
    double scaleY;
    if (absX > absY) {
      scaleX = 1 + absX * stretchFactor;
      scaleY = 1 - absX * stretchFactor * 0.5;
    } else {
      scaleX = 1 - absY * stretchFactor * 0.5;
      scaleY = 1 + absY * stretchFactor;
    }
    return (
      x: scaleX.clamp(0.6, 1.4).toDouble(),
      y: scaleY.clamp(0.6, 1.4).toDouble(),
    );
  }

  /// Padding required to keep every refraction and dispersion sample inside
  /// the runtime-shader output.
  ///
  /// The shader's largest possible sample displacement is the refraction
  /// offset plus its dispersion contribution. The extra two logical pixels
  /// preserve the anti-aliased edge. Blur is an inner image filter, so Flutter
  /// expands its source bounds independently; duplicating three sigma here
  /// would only enlarge the runtime-shader surface.
  static double samplingPaddingFor(LiquidGlassConfig config) {
    final double refractionReach =
        config.refractionOffset.abs() * (1 + config.dispersion.abs());
    return math.max(2, refractionReach + 2);
  }
}
