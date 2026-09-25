import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures a deterministic Impeller reference frame', (
    WidgetTester tester,
  ) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await binding.convertFlutterSurfaceToImage();

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(painter: _VisualBackdropPainter()),
              Center(
                child: LiquidGlassView(
                  width: 220,
                  height: 180,
                  config: LiquidGlassConfig(blurSigma: 10, dispersion: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    final List<int> png = await binding.takeScreenshot('liquid_glass_visual');
    expect(png, isNotEmpty);
  });
}

class _VisualBackdropPainter extends CustomPainter {
  const _VisualBackdropPainter();

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
