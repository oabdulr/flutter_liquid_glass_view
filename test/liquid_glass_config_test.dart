import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';

void main() {
  group('LiquidGlassConfig', () {
    test('matches Android defaults', () {
      const LiquidGlassConfig config = LiquidGlassConfig.androidDefaults;

      expect(config.cornerRadius, 40);
      expect(config.refractionHeight, 20);
      expect(config.refractionOffset, 70);
      expect(config.depthEffect, 0.3);
      expect(config.dispersion, 0.5);
      expect(config.contrast, 0);
      expect(config.whitePoint, 0);
      expect(config.chromaMultiplier, 1);
      expect(config.blurSigma, 0.01);
      expect(config.tintColor, const Color(0xFFFFFFFF));
      expect(config.tintAlpha, 0);
      expect(config.eccentricFactor, 1);
    });

    test('noFilter is a true pass-through configuration', () {
      const LiquidGlassConfig config = LiquidGlassConfig.noFilter;

      expect(config.refractionHeight, 0);
      expect(config.refractionOffset, 0);
      expect(config.dispersion, 0);
      expect(config.blurSigma, 0);
      expect(config.contrast, 0);
      expect(config.whitePoint, 0);
      expect(config.chromaMultiplier, 1);
    });

    test('copyWith preserves unspecified fields and value equality', () {
      const LiquidGlassConfig original = LiquidGlassConfig();
      final LiquidGlassConfig changed = original.copyWith(
        blurSigma: 12,
        tintAlpha: 0.25,
      );

      expect(changed.blurSigma, 12);
      expect(changed.tintAlpha, 0.25);
      expect(changed.cornerRadius, original.cornerRadius);
      expect(changed, changed.copyWith());
      expect(changed.hashCode, changed.copyWith().hashCode);
      expect(changed, isNot(original));
    });

    test('corner radius is clamped to half the shorter side', () {
      const LiquidGlassConfig config = LiquidGlassConfig(cornerRadius: 80);

      // Wide views match Android's height-dependent clamp exactly.
      expect(config.resolvedFor(const Size(200, 100)).cornerRadius, 50);
      expect(config.resolvedFor(const Size(200, 300)).cornerRadius, 80);
      // Narrow views are also limited by width, keeping the shader outline
      // identical to the child clip.
      expect(config.resolvedFor(const Size(60, 300)).cornerRadius, 30);
      expect(
        const LiquidGlassConfig(
          cornerRadius: -1,
        ).resolvedFor(const Size(100, 100)).cornerRadius,
        0,
      );
    });
  });
}
