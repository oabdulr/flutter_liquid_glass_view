// Ported from AndroidLiquidGlassView's `Config` by Donny Yale (QmDeve).
// https://github.com/QmDeve/AndroidLiquidGlassView - MIT License.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Rendering parameters for a liquid-glass surface.
///
/// Distances are Flutter logical pixels. Defaults mirror the Android library's
/// dp defaults one-for-one: 40 corner radius, 20 refraction height, 70
/// refraction offset, 0.01 blur sigma, and 0.5 dispersion.
@immutable
class LiquidGlassConfig {
  /// Creates a configuration. Every parameter defaults to the Android value.
  const LiquidGlassConfig({
    this.cornerRadius = 40,
    this.refractionHeight = 20,
    this.refractionOffset = 70,
    this.depthEffect = 0.3,
    this.dispersion = 0.5,
    this.contrast = 0,
    this.whitePoint = 0,
    this.chromaMultiplier = 1,
    this.blurSigma = 0.01,
    this.tintColor = const Color(0xFFFFFFFF),
    this.tintAlpha = 0,
    this.eccentricFactor = 1,
  });

  /// The Android widget defaults, exposed as a named constant for migration.
  static const LiquidGlassConfig androidDefaults = LiquidGlassConfig();

  /// A pass-through configuration matching `Config.Overrides.noFilter()`.
  static const LiquidGlassConfig noFilter = LiquidGlassConfig(
    refractionHeight: 0,
    refractionOffset: 0,
    dispersion: 0,
    blurSigma: 0,
  );

  /// Radius of the rounded outline.
  ///
  /// Clamped at render time to half of the view's shorter side.
  final double cornerRadius;

  /// Width of the band along the edge in which the backdrop is refracted.
  ///
  /// Zero or less disables refraction; the backdrop then only passes through
  /// blur and the color grade.
  final double refractionHeight;

  /// Positive displacement magnitude. The shader applies it inward, matching
  /// Android's `setRefractionOffset`, which stores the supplied value negated.
  final double refractionOffset;

  /// Blends a radial, center-facing normal into the rounded-rectangle normal,
  /// which makes the edge read as a thicker lens.
  final double depthEffect;

  /// Chromatic aberration strength of the seven spectrum samples, usually
  /// between 0 and 1.
  final double dispersion;

  /// Contrast adjustment. Zero is the identity; positive values increase
  /// contrast and negative values flatten it.
  final double contrast;

  /// Mix toward white (positive) or black (negative). Zero is the identity.
  final double whitePoint;

  /// Saturation multiplier in linear sRGB. One is the identity.
  final double chromaMultiplier;

  /// Standard deviation of the Gaussian blur applied before refraction.
  final double blurSigma;

  /// Tint mixed over the refracted backdrop.
  ///
  /// Only the RGB channels are used; the strength comes from [tintAlpha].
  final Color tintColor;

  /// Strength of [tintColor], from 0 (no tint) to 1 (solid tint).
  final double tintAlpha;

  /// Retained for source-level parity with Android's `Config`.
  ///
  /// Android 1.0.5 also stores but does not consume this value in its AGSL
  /// shader, so this port intentionally has the same behavior.
  final double eccentricFactor;

  /// Returns a copy with the given fields replaced.
  LiquidGlassConfig copyWith({
    double? cornerRadius,
    double? refractionHeight,
    double? refractionOffset,
    double? depthEffect,
    double? dispersion,
    double? contrast,
    double? whitePoint,
    double? chromaMultiplier,
    double? blurSigma,
    Color? tintColor,
    double? tintAlpha,
    double? eccentricFactor,
  }) {
    return LiquidGlassConfig(
      cornerRadius: cornerRadius ?? this.cornerRadius,
      refractionHeight: refractionHeight ?? this.refractionHeight,
      refractionOffset: refractionOffset ?? this.refractionOffset,
      depthEffect: depthEffect ?? this.depthEffect,
      dispersion: dispersion ?? this.dispersion,
      contrast: contrast ?? this.contrast,
      whitePoint: whitePoint ?? this.whitePoint,
      chromaMultiplier: chromaMultiplier ?? this.chromaMultiplier,
      blurSigma: blurSigma ?? this.blurSigma,
      tintColor: tintColor ?? this.tintColor,
      tintAlpha: tintAlpha ?? this.tintAlpha,
      eccentricFactor: eccentricFactor ?? this.eccentricFactor,
    );
  }

  /// Clamps [cornerRadius] to what a view of [size] can display.
  ///
  /// Android clamps to half the height only. A radius larger than half the
  /// width breaks the shader's signed-distance field while the child clip
  /// silently shrinks it, so the two outlines would disagree. Clamping to the
  /// shorter side keeps them identical; results for wide views are unchanged.
  LiquidGlassConfig resolvedFor(Size size) {
    final double shortestSide = math.min(size.width, size.height);
    final double maxRadius = shortestSide > 0 ? shortestSide / 2 : 99;
    return copyWith(cornerRadius: cornerRadius.clamp(0, maxRadius).toDouble());
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LiquidGlassConfig &&
            other.cornerRadius == cornerRadius &&
            other.refractionHeight == refractionHeight &&
            other.refractionOffset == refractionOffset &&
            other.depthEffect == depthEffect &&
            other.dispersion == dispersion &&
            other.contrast == contrast &&
            other.whitePoint == whitePoint &&
            other.chromaMultiplier == chromaMultiplier &&
            other.blurSigma == blurSigma &&
            other.tintColor == tintColor &&
            other.tintAlpha == tintAlpha &&
            other.eccentricFactor == eccentricFactor;
  }

  @override
  int get hashCode => Object.hash(
    cornerRadius,
    refractionHeight,
    refractionOffset,
    depthEffect,
    dispersion,
    contrast,
    whitePoint,
    chromaMultiplier,
    blurSigma,
    tintColor,
    tintAlpha,
    eccentricFactor,
  );

  @override
  String toString() {
    return 'LiquidGlassConfig('
        'cornerRadius: $cornerRadius, '
        'refractionHeight: $refractionHeight, '
        'refractionOffset: $refractionOffset, '
        'depthEffect: $depthEffect, '
        'dispersion: $dispersion, '
        'contrast: $contrast, '
        'whitePoint: $whitePoint, '
        'chromaMultiplier: $chromaMultiplier, '
        'blurSigma: $blurSigma, '
        'tintColor: $tintColor, '
        'tintAlpha: $tintAlpha, '
        'eccentricFactor: $eccentricFactor)';
  }
}
