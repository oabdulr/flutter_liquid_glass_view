# liquid_glass_view example

An interactive playground for the liquid-glass view. Run it from this
directory:

```console
flutter run
```

The demo uses the background photo from the original
[AndroidLiquidGlassView](https://github.com/QmDeve/AndroidLiquidGlassView) demo
and exposes corner radius, refraction height, refraction offset, blur,
dispersion, tint, elastic motion, touch glow, bounded drag, position reset, and
the active renderer. The sliders drive a `LiquidGlassController`, so they
always show the clamped values the glass actually renders with.

Use an Impeller target (Android or iOS) to see refraction and dispersion; other
platforms show the blur/tint fallback.

For the Android profile benchmark:

```console
flutter drive --profile --no-dds -d <android-device> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/liquid_glass_performance_test.dart
```
