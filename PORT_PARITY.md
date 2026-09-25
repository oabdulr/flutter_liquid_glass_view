# Port parity audit

The Android sources audited for this port are the Java classes under
`core/src/main/java/com/qmdeve/liquidglass` and
`core/src/main/res/raw/liquidglass_effect.agsl` of
[QmDeve/AndroidLiquidGlassView](https://github.com/QmDeve/AndroidLiquidGlassView)
1.0.5.

## Rendering pipeline

- Live source capture: Android records the bound target into a `RenderNode`;
  Flutter samples the already-painted scene with `BackdropFilter`.
- Hardware shader: AGSL `RuntimeShader` maps to Flutter
  `FragmentProgram` plus `ImageFilter.shader` on Impeller.
- Rounded geometry: the same rounded-rectangle signed-distance and analytic
  gradient functions are ported.
- Edge refraction: the same circle mapping, negative offset direction,
  smoothed gradient radius, and radial `depthEffect` are ported.
- Dispersion: red, orange, yellow, green, cyan, blue, and purple taps keep the
  original positions and channel divisors.
- Color: linear-sRGB luminance saturation, white point, contrast, RGB tint,
  and alpha handling are ported.
- Blur order: Gaussian blur is the inner filter and the liquid shader is the
  outer filter, matching Android `RenderEffect.createChainEffect`.
- Clip: shader coverage recreates the host rounded outline while a padded
  input surface preserves out-of-bounds refraction samples. The backdrop
  filter is clipped to that padded surface.
- Coordinates: paint-time `ImageFilterConfig.resolve` maps the glass through
  its full paint transform, and logical dimensions are converted with the
  device pixel ratio. The shape is evaluated in the view's own space, so
  scaled ancestors (including the elastic stretch) deform the glass like
  Android's scaled `RenderNode` instead of detaching it from its content.
- OpenGL ES: sampler Y is inverted under `IMPELLER_TARGET_OPENGLES`, as required
  by Flutter's image-filter runtime shader contract.

## Configuration

Every Android `Config` rendering value exists in `LiquidGlassConfig`:
dispersion, depth effect, size through widget bounds, corner radius, eccentric
factor, refraction height, refraction offset, contrast, white point, chroma
multiplier, blur, tint alpha, and tint RGB.

`eccentricFactor` is deliberately inert because the audited Android shader and
implementation also never pass it to a uniform. This preserves behavior rather
than inventing a new effect.

## Widget behavior

- Children fill and clip to the glass bounds.
- Drag translation is limited to the layout parent's bounds, and stays
  anchored to where the pointer went down (Android computes
  `startTranslation + (raw - downRaw)` and clamps).
- Elastic velocity comes from a least-squares velocity tracker, like
  Android's `VelocityTracker`, in logical pixels per millisecond.
- Elastic movement uses the original dominant-axis formula and clamps.
- Spring stiffness and damping ratios match `LiquidTracker`.
- The 200 ms movement-idle reset is present.
- Press begins a 1.02 spring scale, tracks the pointer glow, and returns to 1.
- The glow color, stops, radius, and rounded clipping match the Canvas code.
- An interactive view consumes the pointers it receives, like
  `onTouchEvent` returning `true`; a passive view lets them through.
- Size changes re-resolve the corner limit and shader bounds.
- Configuration updates repaint without reconstructing or capturing bitmaps.

## Intentional differences

These fix edge cases in the original rather than copying them:

- **Corner radius clamp.** Android clamps to half the height only. A radius
  larger than half the width breaks the signed-distance field while the child
  clip silently shrinks it, so the two outlines disagree. The port clamps to
  half the shorter side; wide views are unaffected.
- **Drag bounds through wrappers.** Proxy widgets such as `RepaintBoundary`
  between the glass and its parent are skipped when finding the drag bounds,
  since Flutter inserts them where Android has no equivalent view.
- **Pointer buttons.** Only the primary button (touch, stylus, or left mouse)
  starts an interaction.
- **Turning effects off mid-gesture** always springs the view back to rest.

## Platform behavior

Android's original AGSL path intentionally renders nothing below Android 13.
The Flutter port is broader: it uses the full shader wherever Flutter reports
Impeller image-filter support, including supported Android and iOS builds. A
blur/tint fallback keeps content usable on other renderers. That fallback is a
platform capability adaptation, not a substitute used on the verified Android
Impeller path.

## Evidence

- `flutter analyze` is clean with `public_member_api_docs` and strict
  language modes enabled.
- The unit, widget, and shader suite covers config, controller, physics,
  shader structure, rendering fallbacks, hit testing, drag bounds and
  anchoring, velocity robustness, and elastic reset. Each regression test for
  a fix above fails on the pre-fix code.
- Android emulator (API 37, Impeller OpenGLES): captures confirmed that the
  glass aligns with its content at rest, inside a scrolled list, and under a
  1.3 × 0.8 scale transform. The at-rest capture is pixel-identical to the
  output before the transform fix.
- Android profile drag benchmark: passes its 60 Hz p90 build and raster
  gates; see [PERFORMANCE.md](PERFORMANCE.md) for the numbers and caveats.
- iOS and macOS use the same Impeller path but have not been verified on a
  device for this release.
