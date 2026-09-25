import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';

void main() {
  group('LiquidGlassPhysics', () {
    test('matches horizontal Android deformation math', () {
      final ({double x, double y}) result = LiquidGlassPhysics.scaleForVelocity(
        const Offset(0.4, 0.1),
      );

      expect(result.x, closeTo(1.2, 1e-9));
      expect(result.y, closeTo(0.9, 1e-9));
    });

    test('matches vertical deformation and clamps extremes', () {
      final ({double x, double y}) moderate =
          LiquidGlassPhysics.scaleForVelocity(const Offset(0.1, -0.4));
      final ({double x, double y}) extreme =
          LiquidGlassPhysics.scaleForVelocity(const Offset(0, 20));

      expect(moderate.x, closeTo(0.9, 1e-9));
      expect(moderate.y, closeTo(1.2, 1e-9));
      expect(extreme.x, 0.6);
      expect(extreme.y, 1.4);
    });

    test(
      'padding contains refraction and dispersion without blur duplication',
      () {
        const LiquidGlassConfig config = LiquidGlassConfig(
          refractionOffset: 70,
          dispersion: 0.5,
          blurSigma: 10,
        );

        expect(LiquidGlassPhysics.samplingPaddingFor(config), 107);
        expect(
          LiquidGlassPhysics.samplingPaddingFor(config.copyWith(blurSigma: 48)),
          107,
        );
        expect(
          LiquidGlassPhysics.samplingPaddingFor(LiquidGlassConfig.noFilter),
          2,
        );
      },
    );
  });
}
