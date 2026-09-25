// Mirrors the setters of AndroidLiquidGlassView's `LiquidGlassView` by
// Donny Yale (QmDeve). https://github.com/QmDeve/AndroidLiquidGlassView
// MIT License.

import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'liquid_glass_config.dart';

/// Imperative compatibility controller for a liquid-glass surface.
///
/// Flutter callers can also rebuild with a new immutable
/// [LiquidGlassConfig]. These setters intentionally mirror the Android API and
/// its clamping rules, which makes incremental migrations straightforward.
///
/// The controller also owns the drag translation of the view it is attached
/// to, so [translation] always reflects the latest drag and
/// [setTranslation] moves the glass programmatically.
///
/// Create it in [State.initState] and dispose it in [State.dispose].
class LiquidGlassController extends ChangeNotifier {
  /// Creates a controller with an initial [config] and [translation].
  LiquidGlassController({
    LiquidGlassConfig config = LiquidGlassConfig.androidDefaults,
    Offset translation = Offset.zero,
  }) : _config = config,
       _translation = translation;

  LiquidGlassConfig _config;
  Offset _translation;

  /// The configuration applied to the attached view.
  LiquidGlassConfig get config => _config;

  /// Replaces the whole configuration and notifies listeners if it changed.
  set config(LiquidGlassConfig value) => _replace(value);

  /// The current drag offset of the attached view, in logical pixels.
  Offset get translation => _translation;

  /// Sets the corner radius, clamped to 0 through 99 like Android.
  ///
  /// The view additionally clamps it to half its shorter side.
  void setCornerRadius(double logicalPixels) {
    _replace(
      _config.copyWith(cornerRadius: logicalPixels.clamp(0, 99).toDouble()),
    );
  }

  /// Sets the refraction band height, clamped to 12 through 50 like Android.
  void setRefractionHeight(double logicalPixels) {
    _replace(
      _config.copyWith(
        refractionHeight: logicalPixels.clamp(12, 50).toDouble(),
      ),
    );
  }

  /// Sets the refraction offset magnitude, clamped to 20 through 120 like
  /// Android. The sign is ignored; the shader always refracts inward.
  void setRefractionOffset(double logicalPixels) {
    _replace(
      _config.copyWith(
        refractionOffset: logicalPixels.abs().clamp(20, 120).toDouble(),
      ),
    );
  }

  /// Sets the red channel of the tint color, from 0 to 1.
  void setTintColorRed(double red) {
    final Color color = _config.tintColor;
    _replace(
      _config.copyWith(
        tintColor: Color.from(
          alpha: color.a,
          red: red,
          green: color.g,
          blue: color.b,
        ),
      ),
    );
  }

  /// Sets the green channel of the tint color, from 0 to 1.
  void setTintColorGreen(double green) {
    final Color color = _config.tintColor;
    _replace(
      _config.copyWith(
        tintColor: Color.from(
          alpha: color.a,
          red: color.r,
          green: green,
          blue: color.b,
        ),
      ),
    );
  }

  /// Sets the blue channel of the tint color, from 0 to 1.
  void setTintColorBlue(double blue) {
    final Color color = _config.tintColor;
    _replace(
      _config.copyWith(
        tintColor: Color.from(
          alpha: color.a,
          red: color.r,
          green: color.g,
          blue: blue,
        ),
      ),
    );
  }

  /// Sets the tint strength, from 0 (none) to 1 (solid).
  void setTintAlpha(double alpha) {
    _replace(_config.copyWith(tintAlpha: alpha));
  }

  /// Sets all tint channels at once. The color's own alpha is ignored; use
  /// [setTintAlpha] for strength.
  void setTintColor(Color color) {
    _replace(_config.copyWith(tintColor: color));
  }

  /// Sets the dispersion strength, clamped to 0 through 1 like Android.
  void setDispersion(double dispersion) {
    _replace(_config.copyWith(dispersion: dispersion.clamp(0, 1).toDouble()));
  }

  /// Sets the blur sigma, clamped to 0.01 through 50 like Android.
  void setBlurRadius(double radius) {
    _replace(_config.copyWith(blurSigma: radius.clamp(0.01, 50).toDouble()));
  }

  /// Sets [LiquidGlassConfig.depthEffect].
  void setDepthEffect(double value) {
    _replace(_config.copyWith(depthEffect: value));
  }

  /// Sets [LiquidGlassConfig.contrast].
  void setContrast(double value) {
    _replace(_config.copyWith(contrast: value));
  }

  /// Sets [LiquidGlassConfig.whitePoint].
  void setWhitePoint(double value) {
    _replace(_config.copyWith(whitePoint: value));
  }

  /// Sets [LiquidGlassConfig.chromaMultiplier].
  void setChromaMultiplier(double value) {
    _replace(_config.copyWith(chromaMultiplier: value));
  }

  /// Sets [LiquidGlassConfig.eccentricFactor], which is inert like Android.
  void setEccentricFactor(double value) {
    _replace(_config.copyWith(eccentricFactor: value));
  }

  /// Applies Android `Config.Overrides.noFilter()` without changing size or
  /// tint fields.
  void setNoFilter() {
    _replace(
      _config.copyWith(
        contrast: 0,
        whitePoint: 0,
        chromaMultiplier: 1,
        blurSigma: 0,
        refractionHeight: 0,
        refractionOffset: 0,
      ),
    );
  }

  /// Moves the attached view to [value], relative to its laid-out position.
  ///
  /// Programmatic translations are not clamped to the parent; drags are.
  void setTranslation(Offset value) {
    if (_translation == value) return;
    _translation = value;
    notifyListeners();
  }

  /// Returns the attached view to its laid-out position.
  void resetTranslation() => setTranslation(Offset.zero);

  void _replace(LiquidGlassConfig value) {
    if (_config == value) return;
    _config = value;
    notifyListeners();
  }
}
