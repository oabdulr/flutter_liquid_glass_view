import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';

void main() {
  testWidgets('fallback renders child, blur, tint, and rounded clip', (
    WidgetTester tester,
  ) async {
    final LiquidGlassController controller = LiquidGlassController();
    addTearDown(controller.dispose);
    const Key childKey = Key('glass-child');

    await tester.pumpWidget(
      _TestScene(
        child: LiquidGlassView(
          width: 120,
          height: 80,
          controller: controller,
          forceFallback: true,
          child: const SizedBox(key: childKey),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(ColoredBox), findsWidgets);

    controller.setCornerRadius(25);
    await tester.pump();
    final ClipRRect clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(25));
  });

  testWidgets('corner radius is limited by the shorter side', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const _TestScene(
        child: LiquidGlassView(
          width: 40,
          height: 200,
          config: LiquidGlassConfig(cornerRadius: 90),
          forceFallback: true,
        ),
      ),
    );

    final ClipRRect clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(20));
  });

  testWidgets('dragging is bounded to the direct parent like Android', (
    WidgetTester tester,
  ) async {
    final LiquidGlassController controller = LiquidGlassController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_BoundedScene(controller: controller));

    final Offset center = tester.getCenter(find.byType(LiquidGlassView));
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(500, 500));
    await tester.pump();
    expect(controller.translation, const Offset(150, 160));

    await gesture.moveBy(const Offset(-1000, -1000));
    await tester.pump();
    expect(controller.translation, const Offset(-50, -60));
    await gesture.up();
  });

  testWidgets('drag stays anchored to the pointer after hitting an edge', (
    WidgetTester tester,
  ) async {
    final LiquidGlassController controller = LiquidGlassController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_BoundedScene(controller: controller));

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    await gesture.moveBy(const Offset(500, 0));
    await tester.pump();
    expect(controller.translation.dx, 150);

    // The pointer is now 500 px right of where it went down. Android keeps the
    // glass pinned at the edge until the pointer comes back past that point,
    // rather than moving immediately and slipping out from under the finger.
    await gesture.moveBy(const Offset(-400, 0));
    await tester.pump();
    expect(controller.translation.dx, 100);
    await gesture.up();
  });

  testWidgets('drag bounds see through proxy wrappers', (
    WidgetTester tester,
  ) async {
    final LiquidGlassController controller = LiquidGlassController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _BoundedScene(controller: controller, wrapInRepaintBoundary: true),
    );

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    await gesture.moveBy(const Offset(500, 500));
    await tester.pump();
    expect(controller.translation, const Offset(150, 160));
    await gesture.up();
  });

  testWidgets('interactive glass consumes taps; passive glass does not', (
    WidgetTester tester,
  ) async {
    int backgroundTaps = 0;
    Widget scene({required bool interactive}) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => backgroundTaps++,
            ),
            Center(
              child: LiquidGlassView(
                width: 120,
                height: 80,
                touchEffect: interactive,
                forceFallback: true,
              ),
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(scene(interactive: true));
    await tester.tap(find.byType(LiquidGlassView));
    await tester.pumpAndSettle();
    expect(backgroundTaps, 0);

    await tester.pumpWidget(scene(interactive: false));
    await tester.tap(find.byType(LiquidGlassView));
    await tester.pumpAndSettle();
    expect(backgroundTaps, 1);
  });

  testWidgets('secondary mouse button does not drag', (
    WidgetTester tester,
  ) async {
    final LiquidGlassController controller = LiquidGlassController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_BoundedScene(controller: controller));

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();
    expect(controller.translation, Offset.zero);
    await gesture.up();
  });

  testWidgets('touch glow follows the pointer and clears on release', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const _TestScene(
        child: LiquidGlassView(
          width: 120,
          height: 80,
          touchEffect: true,
          forceFallback: true,
        ),
      ),
    );

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    await tester.pump();
    expect(find.byType(CustomPaint), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('pointer motion does not rebuild the glass content', (
    WidgetTester tester,
  ) async {
    int childBuilds = 0;
    final Widget countedChild = Builder(
      builder: (BuildContext context) {
        childBuilds++;
        return const SizedBox.expand();
      },
    );

    await tester.pumpWidget(
      _TestScene(
        child: LiquidGlassView(
          width: 120,
          height: 80,
          draggable: true,
          elastic: true,
          touchEffect: true,
          forceFallback: true,
          child: countedChild,
        ),
      ),
    );
    final int buildsBeforeGesture = childBuilds;

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    for (int index = 0; index < 10; index++) {
      await gesture.moveBy(
        const Offset(2, 1),
        timeStamp: Duration(milliseconds: 16 * (index + 1)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();

    expect(childBuilds, buildsBeforeGesture);
  });

  testWidgets('elastic movement deforms and springs back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const _TestScene(
        child: LiquidGlassView(
          width: 120,
          height: 80,
          draggable: true,
          elastic: true,
          forceFallback: true,
        ),
      ),
    );

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    await _fling(tester, gesture, step: const Offset(6, 0.5));
    await tester.pump(const Duration(milliseconds: 80));

    final ({double x, double y}) deformed = _elasticScale(tester);
    expect(deformed.x, greaterThan(1.01));
    expect(deformed.y, lessThan(0.99));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    final ({double x, double y}) settled = _elasticScale(tester);
    expect(settled.x, closeTo(1, 0.01));
    expect(settled.y, closeTo(1, 0.01));
  });

  testWidgets('coincident pointer timestamps do not spike the deformation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const _TestScene(
        child: LiquidGlassView(
          width: 120,
          height: 80,
          draggable: true,
          elastic: true,
          forceFallback: true,
        ),
      ),
    );

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    for (int index = 0; index < 4; index++) {
      await gesture.moveBy(const Offset(2, 0));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(_elasticScale(tester).x, lessThan(1.1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('disabling elastic mid-gesture still springs back', (
    WidgetTester tester,
  ) async {
    Widget scene({required bool elastic}) {
      return _TestScene(
        child: LiquidGlassView(
          width: 120,
          height: 80,
          draggable: true,
          elastic: elastic,
          forceFallback: true,
        ),
      );
    }

    await tester.pumpWidget(scene(elastic: true));
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(LiquidGlassView)),
    );
    await _fling(tester, gesture, step: const Offset(6, 0.5));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_elasticScale(tester).x, greaterThan(1.01));

    await tester.pumpWidget(scene(elastic: false));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(_elasticScale(tester).x, closeTo(1, 0.01));
    expect(_elasticScale(tester).y, closeTo(1, 0.01));
  });
}

/// Moves quickly enough, over enough samples, for a velocity estimate.
Future<void> _fling(
  WidgetTester tester,
  TestGesture gesture, {
  required Offset step,
}) async {
  for (int index = 1; index <= 5; index++) {
    await gesture.moveBy(step, timeStamp: Duration(milliseconds: 8 * index));
  }
  await tester.pump();
}

/// Reads the elastic scale, which sits inside the drag translation.
({double x, double y}) _elasticScale(WidgetTester tester) {
  final Transform scale = tester
      .widgetList<Transform>(
        find.descendant(
          of: find.byType(LiquidGlassView),
          matching: find.byType(Transform),
        ),
      )
      .last;
  return (x: scale.transform.storage[0], y: scale.transform.storage[5]);
}

class _TestScene extends StatelessWidget {
  const _TestScene({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 300,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: Color(0xFF336699)),
            Center(child: child),
          ],
        ),
      ),
    );
  }
}

/// A 300 x 300 parent with a 100 x 80 glass laid out at (50, 60).
class _BoundedScene extends StatelessWidget {
  const _BoundedScene({
    required this.controller,
    this.wrapInRepaintBoundary = false,
  });

  final LiquidGlassController controller;
  final bool wrapInRepaintBoundary;

  @override
  Widget build(BuildContext context) {
    final Widget glass = LiquidGlassView(
      width: 100,
      height: 80,
      controller: controller,
      draggable: true,
      forceFallback: true,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 50,
                top: 60,
                child: wrapInRepaintBoundary
                    ? RepaintBoundary(child: glass)
                    : glass,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
