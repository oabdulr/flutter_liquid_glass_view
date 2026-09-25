import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';

void main() {
  test('Android-compatible setters use the original clamp ranges', () {
    final LiquidGlassController controller = LiquidGlassController();

    controller.setCornerRadius(500);
    controller.setRefractionHeight(2);
    controller.setRefractionOffset(-500);
    controller.setDispersion(4);
    controller.setBlurRadius(0);

    expect(controller.config.cornerRadius, 99);
    expect(controller.config.refractionHeight, 12);
    expect(controller.config.refractionOffset, 120);
    expect(controller.config.dispersion, 1);
    expect(controller.config.blurSigma, 0.01);

    controller.setRefractionHeight(500);
    controller.setRefractionOffset(1);
    controller.setDispersion(-1);
    controller.setBlurRadius(100);

    expect(controller.config.refractionHeight, 50);
    expect(controller.config.refractionOffset, 20);
    expect(controller.config.dispersion, 0);
    expect(controller.config.blurSigma, 50);
  });

  test('tint channel setters preserve all other channels', () {
    final LiquidGlassController controller = LiquidGlassController(
      config: const LiquidGlassConfig(
        tintColor: Color.from(alpha: 0.8, red: 0.1, green: 0.2, blue: 0.3),
      ),
    );

    controller.setTintColorRed(0.4);
    controller.setTintColorGreen(0.5);
    controller.setTintColorBlue(0.6);
    controller.setTintAlpha(0.7);

    expect(controller.config.tintColor.a, closeTo(0.8, 1e-9));
    expect(controller.config.tintColor.r, closeTo(0.4, 1e-9));
    expect(controller.config.tintColor.g, closeTo(0.5, 1e-9));
    expect(controller.config.tintColor.b, closeTo(0.6, 1e-9));
    expect(controller.config.tintAlpha, 0.7);
  });

  test('translation and config updates notify once, no-ops do not', () {
    final LiquidGlassController controller = LiquidGlassController();
    int notifications = 0;
    controller.addListener(() => notifications++);

    controller.setTranslation(const Offset(4, 5));
    controller.setTranslation(const Offset(4, 5));
    controller.setDispersion(0.25);
    controller.setDispersion(0.25);

    expect(controller.translation, const Offset(4, 5));
    expect(controller.config.dispersion, 0.25);
    expect(notifications, 2);
  });

  test('advanced Config values and noFilter remain controllable', () {
    final LiquidGlassController controller = LiquidGlassController();

    controller.setDepthEffect(0.6);
    controller.setContrast(0.2);
    controller.setWhitePoint(-0.1);
    controller.setChromaMultiplier(1.3);
    controller.setEccentricFactor(0.8);
    controller.setTintColor(const Color(0xFF123456));

    expect(controller.config.depthEffect, 0.6);
    expect(controller.config.contrast, 0.2);
    expect(controller.config.whitePoint, -0.1);
    expect(controller.config.chromaMultiplier, 1.3);
    expect(controller.config.eccentricFactor, 0.8);
    expect(controller.config.tintColor, const Color(0xFF123456));

    controller.setNoFilter();
    expect(controller.config.refractionHeight, 0);
    expect(controller.config.refractionOffset, 0);
    expect(controller.config.blurSigma, 0);
    expect(controller.config.contrast, 0);
    expect(controller.config.whitePoint, 0);
    expect(controller.config.chromaMultiplier, 1);
    expect(controller.config.tintColor, const Color(0xFF123456));
  });
}
