# Performance design and verification

## Rendering design

- One runtime shader image filter performs the liquid effect.
- The edge path uses seven texture samples; the deep interior uses one.
- Blur is composed as a GPU filter before refraction.
- No `RenderRepaintBoundary.toImage`, CPU bitmap, platform view, or method
  channel is used per frame.
- The shader program is cached globally and can be warmed during startup.
- Each view owns one fragment shader instance so uniforms can update without
  cross-view contention.
- Filter parameters are bound at paint time, avoiding layout callbacks and
  one-frame coordinate lag during drag.
- The sampled surface is padded only far enough for worst-case refraction,
  dispersion, and the two-pixel anti-aliased edge. Flutter expands the inner
  Gaussian filter's source bounds by three sigmas itself; duplicating that
  margin around the runtime shader would not change pixels.
- The backdrop filter is clipped to that padded surface. Without a clip,
  Flutter applies a backdrop filter to the whole screen, so every glass view
  would blur and shade the full frame. Emulator captures of the clipped and
  unclipped filter matched to within one 8-bit step, apart from a single
  anti-aliased pixel.
- Static shader uniforms and the fallback blur filter are cached per view;
  only the paint-time placement is rebound while the glass moves.
- Translation is isolated in a `ValueListenableBuilder`, and elastic scale and
  touch glow repaint their own layers without rebuilding the glass child.
- Widget configuration updates repaint the filter; the background tree is not
  rebuilt by the package.
- The post-frame placement check only repaints a filter whose layer moved
  without repainting; it never schedules frames on its own.

## Color-grade identity fast path

`grade_color` retains the all-default pass-through. When tint, white point, or
contrast makes later grading active, it runs `saturate_color` only when
`u_chroma_multiplier != 1.0`. At the default chroma value, this skips the
identity linear-sRGB conversion and inverse conversion while preserving white
point, contrast, tint, alpha, and all non-default chroma behavior. That avoids
two power operations per RGB channel (six scalar power operations total) for
each graded fragment in this case.

This is a shader-source operation reduction, not a measured FPS or raster
result. The focused regression checks the shipped shader's branch shape and
compares old/new CPU reference formulas across representative cases; it is not
GPU screenshot parity or a golden-image test.

## Measured Android profile result

The included integration test drags a 220 × 180 logical-pixel surface for 120
input frames with elastic motion, touch glow, blur sigma 10, and dispersion
0.5, in profile mode on Impeller OpenGLES. It gates on p90 build and p90 raster
time staying below 16.67 ms, the 60 Hz frame budget.

An earlier run on a Pixel 10 Pro x86_64 emulator image (1280 × 2856, Flutter
3.41.5) recorded:

- Frame count captured: 238
- Average / p90 / worst build time: 0.494 / 0.814 / 1.239 ms
- Average / p90 / p99 / worst raster time: 2.766 / 3.322 / 4.793 / 6.100 ms
- Missed raster budgets: 0

Re-running on a newer API 37 emulator image for this release produced raster
averages between 6 and 14 ms from run to run, with the same spread for the
pre-release code. Emulator GPU timings are dominated by host emulation, vary
widely between runs, and neither predict nor substitute for physical-device
measurements. Production apps should profile their actual glass size, blur,
overlap, and background workload on real hardware.

Run the benchmark with:

```console
cd example
flutter drive --profile --no-dds -d <android-device> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/liquid_glass_performance_test.dart
```

Capture a reference frame (written to `example/build/liquid_glass_visual.png`)
with:

```console
cd example
flutter drive --profile --no-dds -d <android-device> \
  --driver=test_driver/liquid_glass_visual_test.dart \
  --target=integration_test/liquid_glass_visual_test.dart
```
