import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo renders the glass and its sliders drive the controller', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const LiquidGlassExampleApp());
    await tester.pump();

    expect(find.byType(LiquidGlassView), findsOneWidget);
    expect(find.text('Drag me'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(6));

    final LiquidGlassView glass = tester.widget(find.byType(LiquidGlassView));
    final LiquidGlassController controller = glass.controller!;
    expect(controller.config.dispersion, 0.5);

    // Drag the dispersion slider thumb to the far right.
    final Finder dispersion = find.byType(Slider).at(4);
    await tester.drag(dispersion, const Offset(400, 0));
    await tester.pump();
    expect(controller.config.dispersion, 1);
    expect(find.text('1.00'), findsOneWidget);
  });
}
