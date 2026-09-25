# Changelog

## 1.0.0

First public release: a Flutter port of
[AndroidLiquidGlassView](https://github.com/QmDeve/AndroidLiquidGlassView)
1.0.5 by Donny Yale (QmDeve).

### Rendering

- Port the Android AGSL refraction shader to Flutter runtime GLSL, preserving
  the rounded signed-distance geometry, seven-tap dispersion, color grade,
  tint, and blur order.
- Sample the live backdrop on the GPU, binding geometry at paint time.
- Keep the glass aligned inside `RepaintBoundary`s, list items, scroll views,
  and page views, and under scaled ancestors, including the elastic stretch,
  which now deforms the glass instead of detaching it from its content.
- Clip the backdrop filter to its sampling area so each view no longer
  filters the whole screen.
- Fall back to blur + tint where runtime image-filter shaders are
  unavailable.

### Widget and interactions

- `LiquidGlassView` with bounded dragging, elastic spring deformation, and
  touch glow, using Android's spring constants and deformation formula.
- Drags stay anchored to the pointer after being pushed against an edge.
- Elastic velocity uses a least-squares velocity tracker, so pointer events
  with identical timestamps can no longer spike the deformation.
- Drag bounds see through proxy wrappers such as `RepaintBoundary`.
- Interactive glass consumes the pointers it receives; passive glass,
  including the fallback renderer's tint, lets them reach content behind it.
- Only the primary pointer button starts an interaction.
- Turning `elastic` or `touchEffect` off mid-gesture springs the view back.

### API

- `LiquidGlassConfig` with Android defaults, `androidDefaults` and
  `noFilter` presets. The corner radius is clamped to half the view's shorter
  side.
- `LiquidGlassController` with Android-compatible setters and clamp ranges,
  plus translation control.
- `LiquidGlassPhysics` helpers for the deformation and sampling math.
- `LiquidGlassView.warmUp()`, `isHighFidelitySupported`, and
  `onRenderModeChanged`.
- A failed shader load is no longer cached forever and reports the
  consumer-facing error.

### Tooling

- Interactive example app, unit/widget/shader tests, and Android profile and
  visual integration tests.
