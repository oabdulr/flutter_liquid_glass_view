# Migrating from AndroidLiquidGlassView

This guide maps the Android library
([QmDeve/AndroidLiquidGlassView](https://github.com/QmDeve/AndroidLiquidGlassView))
onto this package, for apps moving from native Android views to Flutter.

## 1. Replace the source binding

Android places the source `ViewGroup` and `LiquidGlassView` as siblings, then
calls `liquidGlassView.bind(content)`. Flutter does the same composition with a
`Stack`: paint the source first and the glass later. No bind call is needed
because `BackdropFilter` samples everything already painted below it.

```dart
Stack(
  children: [
    Positioned.fill(child: YourContent()),
    Positioned(
      left: 80,
      top: 160,
      child: LiquidGlassView(width: 200, height: 200),
    ),
  ],
)
```

Do not put the source inside the glass child. The optional child is foreground
content painted over the refracted backdrop, equivalent to Android child views
inside `LiquidGlassView`.

## 2. Map configuration

| Android                                     | Flutter                                                           |
| ------------------------------------------- | ----------------------------------------------------------------- |
| `setCornerRadius(px)`                       | `controller.setCornerRadius(v)` / `config.copyWith(cornerRadius:)` |
| `setRefractionHeight(px)`                   | `setRefractionHeight` / `refractionHeight`                        |
| `setRefractionOffset(px)`                   | `setRefractionOffset` / `refractionOffset` (positive magnitude)   |
| `setBlurRadius(radius)`                     | `setBlurRadius` / `blurSigma`                                     |
| `setDispersion(value)`                      | `setDispersion` / `dispersion`                                    |
| `setTintColorRed/Green/Blue`                | same names, plus `setTintColor(Color)`                            |
| `setTintAlpha(value)`                       | `setTintAlpha` / `tintAlpha`                                      |
| `setDraggableEnabled(bool)`                 | `draggable:`                                                      |
| `setElasticEnabled(bool)`                   | `elastic:`                                                        |
| `setTouchEffectEnabled(bool)`               | `touchEffect:`                                                    |
| `Config.Overrides.noFilter()`               | `LiquidGlassConfig.noFilter` / `controller.setNoFilter()`         |
| Layout `WIDTH` / `HEIGHT`                   | required `width:` / `height:`                                     |
| `getTranslationX/Y()` after a drag          | `controller.translation` / `onTranslationChanged`                 |

Android `dp` values map directly to Flutter logical pixels. Do not multiply them
by the device pixel ratio; the library converts for the shader internally.

The controller setters keep the Android clamp ranges (for example refraction
height 12–50 and blur 0.01–50). Values passed directly in `LiquidGlassConfig`
are not clamped, apart from the corner radius, which is always limited to half
of the view's shorter side.

## 3. Enable the full renderer

Use Flutter 3.41 or newer and leave Impeller enabled; it is the default on
Android and iOS. Where Impeller is unavailable (web, Windows, Linux) the view
renders a blur/tint fallback rather than nothing. Android's original shows no
effect at all below Android 13. Observe the active renderer with
`onRenderModeChanged` or `LiquidGlassView.isHighFidelitySupported`.

## 4. Lifecycle

Create and dispose `LiquidGlassController` with the owning `State`. Shader
programs are cached process-wide; per-view fragment shader instances are
disposed automatically. Calling `LiquidGlassView.warmUp()` once during startup
removes first-use compilation from the interaction path.

## 5. Multiple glass views

Each view samples independently. A `BackdropKey` can be supplied through
`backdropGroupKey` for Flutter backdrop grouping, but overlapping filters must
not share a key because Flutter may treat the overlap as one backdrop
operation. Start without grouping and profile before opting in.
