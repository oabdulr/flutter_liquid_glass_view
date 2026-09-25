import 'package:flutter/material.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Impeller liquid-glass drag stays inside a 60 Hz frame budget', (
    WidgetTester tester,
  ) async {
    LiquidGlassRenderMode mode = LiquidGlassRenderMode.fallback;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const CustomPaint(painter: _PerformanceBackdropPainter()),
              Center(
                child: LiquidGlassView(
                  width: 220,
                  height: 180,
                  draggable: true,
                  elastic: true,
                  touchEffect: true,
                  config: const LiquidGlassConfig(
                    blurSigma: 10,
                    dispersion: 0.5,
                  ),
                  onRenderModeChanged: (LiquidGlassRenderMode value) {
                    mode = value;
                  },
                  child: const Center(child: Text('Performance test')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mode, LiquidGlassRenderMode.shader);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    await binding.watchPerformance(() async {
      for (int frame = 0; frame < 120; frame++) {
        await gesture.moveBy(Offset(frame.isEven ? 1.5 : -1.5, 0.5));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }, reportKey: 'liquid_glass_drag');
    await gesture.up();

    final Map<String, dynamic> summary = Map<String, dynamic>.from(
      binding.reportData!['liquid_glass_drag'] as Map<Object?, Object?>,
    );
    expect(
      summary['90th_percentile_frame_build_time_millis'] as num,
      lessThan(16.67),
    );
    expect(
      summary['90th_percentile_frame_rasterizer_time_millis'] as num,
      lessThan(16.67),
    );
  });
}

class _PerformanceBackdropPainter extends CustomPainter {
  const _PerformanceBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFFF9A3C),
          Color(0xFFEF3E72),
          Color(0xFF3757D5),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final Paint line = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 3;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(size.width - x / 2, size.height),
        line,
      );
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawCircle(Offset(size.width * 0.7, y), 12, line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
