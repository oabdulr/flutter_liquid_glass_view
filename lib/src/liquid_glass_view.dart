// Ported from AndroidLiquidGlassView's `LiquidGlassView`, `LiquidGlass`, and
// `LiquidGlassimpl` by Donny Yale (QmDeve).
// https://github.com/QmDeve/AndroidLiquidGlassView - MIT License.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'liquid_glass_config.dart';
import 'liquid_glass_controller.dart';
import 'liquid_glass_physics.dart';

const String _shaderAsset =
    'packages/liquid_glass_view/shaders/liquid_glass.frag';

/// Where the glass sits on screen: the global (logical) position of its
/// top-left corner and the per-axis scale ancestors apply to it, including
/// the elastic stretch.
typedef _GlassPlacement = ({Offset origin, Offset scale});

/// The renderer currently used by [LiquidGlassView].
enum LiquidGlassRenderMode {
  /// Full refraction, seven-tap dispersion, grading, tint, and blur on Impeller.
  shader,

  /// Portable blur/tint fallback used while loading or without Impeller.
  fallback,
}

/// A live, GPU-sampled liquid-glass surface.
///
/// This is the Flutter counterpart of Android's `LiquidGlassView`. Put it above
/// the content it should sample (normally in a [Stack]); Flutter's
/// [BackdropFilter] then replaces Android's explicit `bind(ViewGroup)` call.
/// The width and height are explicit because the original Android view also has
/// concrete layout bounds and because the shader's signed-distance field must
/// know those bounds. Place the view where its parent lets it choose its own
/// size, such as a [Stack], [Positioned], [Align], or [Center].
///
/// When [draggable] or [touchEffect] is enabled the glass consumes pointers
/// that land on it, so content behind it does not also react. Otherwise it
/// is transparent to hit testing, apart from its [child].
class LiquidGlassView extends StatefulWidget {
  /// Creates a liquid-glass surface of exactly [width] by [height].
  const LiquidGlassView({
    super.key,
    required this.width,
    required this.height,
    this.config = LiquidGlassConfig.androidDefaults,
    this.controller,
    this.child,
    this.draggable = false,
    this.elastic = false,
    this.touchEffect = false,
    this.initialTranslation = Offset.zero,
    this.onTranslationChanged,
    this.onRenderModeChanged,
    this.onShaderError,
    this.backdropGroupKey,
    this.forceFallback = false,
  }) : assert(width > 0 && width < double.infinity),
       assert(height > 0 && height < double.infinity);

  /// Width of the glass in logical pixels. Must be positive and finite.
  final double width;

  /// Height of the glass in logical pixels. Must be positive and finite.
  final double height;

  /// Rendering parameters.
  ///
  /// Ignored when [controller] is supplied; the controller's config wins.
  final LiquidGlassConfig config;

  /// Optional imperative controller for config and translation.
  final LiquidGlassController? controller;

  /// Foreground content painted over the glass and clipped to its outline.
  ///
  /// This is the equivalent of Android child views inside `LiquidGlassView`.
  /// Do not put the content to be refracted here; place it behind the glass.
  final Widget? child;

  /// Whether the glass can be dragged within its layout parent.
  final bool draggable;

  /// Whether pointer velocity stretches the glass with a spring, like
  /// Android's `setElasticEnabled`. Takes effect while [draggable] or
  /// [touchEffect] is enabled.
  final bool elastic;

  /// Whether pressing shows a radial glow at the pointer and springs the
  /// glass to 1.02 scale.
  final bool touchEffect;

  /// Starting translation when no [controller] is supplied.
  final Offset initialTranslation;

  /// Called with the new translation whenever a drag moves the glass.
  final ValueChanged<Offset>? onTranslationChanged;

  /// Called after the first frame and whenever the renderer changes, for
  /// example from [LiquidGlassRenderMode.fallback] to
  /// [LiquidGlassRenderMode.shader] once the shader has loaded.
  final ValueChanged<LiquidGlassRenderMode>? onRenderModeChanged;

  /// Called if the fragment program fails to load. The view then stays on
  /// the fallback renderer.
  final ValueChanged<Object>? onShaderError;

  /// Optional [BackdropGroup] key, forwarded to [BackdropFilter].
  ///
  /// Overlapping glass views must not share a key.
  final BackdropKey? backdropGroupKey;

  /// Forces the cross-renderer blur/tint path. Primarily useful for tests and
  /// for apps that deliberately disable Impeller.
  final bool forceFallback;

  /// Whether the current engine can run the high-fidelity shader filter.
  static bool get isHighFidelitySupported =>
      ui.ImageFilter.isShaderFilterSupported;

  /// Compiles and caches the shader ahead of the first glass surface.
  static Future<void> warmUp() async {
    await _LiquidGlassShaderCache.load();
  }

  @override
  State<LiquidGlassView> createState() => _LiquidGlassViewState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('width', width))
      ..add(DoubleProperty('height', height))
      ..add(DiagnosticsProperty<LiquidGlassConfig>('config', config))
      ..add(
        DiagnosticsProperty<LiquidGlassController>(
          'controller',
          controller,
          defaultValue: null,
        ),
      )
      ..add(FlagProperty('draggable', value: draggable, ifTrue: 'draggable'))
      ..add(FlagProperty('elastic', value: elastic, ifTrue: 'elastic'))
      ..add(
        FlagProperty('touchEffect', value: touchEffect, ifTrue: 'touchEffect'),
      )
      ..add(
        FlagProperty(
          'forceFallback',
          value: forceFallback,
          ifTrue: 'forceFallback',
        ),
      );
  }
}

class _LiquidGlassViewState extends State<LiquidGlassView>
    with TickerProviderStateMixin {
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 180,
    ratio: 0.35,
  );
  static const Duration _elasticSettleDelay = Duration(milliseconds: 200);
  static const double _pressScale = 1.02;

  final GlobalKey _layoutKey = GlobalKey();
  final GlobalKey _backdropKey = GlobalKey();
  _GlassPlacement? _lastResolvedPlacement;
  late final AnimationController _scaleX;
  late final AnimationController _scaleY;
  late final Listenable _scaleAnimations;
  late final ValueNotifier<Offset> _translation;
  late final ValueNotifier<Offset> _touchGlowCenter;
  late final ValueNotifier<bool> _touchGlowVisible;

  ui.FragmentShader? _shader;
  Object? _shaderError;
  LiquidGlassRenderMode? _reportedMode;
  LiquidGlassConfig? _lastControllerConfig;
  LiquidGlassConfig? _resolvedConfigSource;
  LiquidGlassConfig? _resolvedConfig;
  Size? _resolvedConfigSize;
  _LiquidGlassFilterConfig? _cachedShaderFilterConfig;
  ui.ImageFilter? _cachedFallbackBlur;
  double? _cachedFallbackBlurSigma;
  Timer? _settleTimer;
  int? _activePointer;
  Offset _dragStartPointer = Offset.zero;
  Offset _dragStartTranslation = Offset.zero;
  VelocityTracker? _velocityTracker;

  LiquidGlassConfig get _config {
    final LiquidGlassConfig source = widget.controller?.config ?? widget.config;
    final Size size = Size(widget.width, widget.height);
    if (_resolvedConfigSource == source && _resolvedConfigSize == size) {
      return _resolvedConfig!;
    }
    _resolvedConfigSource = source;
    _resolvedConfigSize = size;
    return _resolvedConfig = source.resolvedFor(size);
  }

  bool get _isInteractive => widget.draggable || widget.touchEffect;

  @override
  void initState() {
    super.initState();
    _translation = ValueNotifier<Offset>(
      widget.controller?.translation ?? widget.initialTranslation,
    );
    _touchGlowCenter = ValueNotifier<Offset>(Offset.zero);
    _touchGlowVisible = ValueNotifier<bool>(false);
    _scaleX = AnimationController.unbounded(vsync: this, value: 1);
    _scaleY = AnimationController.unbounded(vsync: this, value: 1);
    _scaleAnimations = Listenable.merge(<Listenable>[_scaleX, _scaleY]);
    _lastControllerConfig = widget.controller?.config;
    widget.controller?.addListener(_controllerChanged);
    _loadShader();
    _schedulePlacementCheck();
  }

  RenderBox? get _backdropBox {
    final RenderObject? box = _backdropKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Layers can move without repainting their contents (a scrolled list
  /// item, a sliding sheet). After each frame that the app renders anyway,
  /// repaint the filter if it has moved since its placement was last
  /// resolved. This never schedules frames on its own while nothing moves.
  void _schedulePlacementCheck() {
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;
      final _GlassPlacement? resolved = _lastResolvedPlacement;
      final _GlassPlacement? current = _cachedShaderFilterConfig
          ?.currentPlacement();
      if (resolved != null &&
          current != null &&
          ((current.origin - resolved.origin).distanceSquared > 0.01 ||
              (current.scale - resolved.scale).distanceSquared > 1e-6)) {
        _backdropBox?.markNeedsPaint();
      }
      _schedulePlacementCheck();
    });
  }

  @override
  void didUpdateWidget(covariant LiquidGlassView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_controllerChanged);
      widget.controller?.addListener(_controllerChanged);
      _lastControllerConfig = widget.controller?.config;
      _translation.value =
          widget.controller?.translation ?? widget.initialTranslation;
    }
    if (!widget.touchEffect) {
      _touchGlowVisible.value = false;
    }
    if (!widget.elastic) {
      _settleTimer?.cancel();
      _velocityTracker = null;
    }
    if (!_isInteractive) {
      _activePointer = null;
    }
    // Turning an effect off mid-gesture must not strand a deformed view: the
    // pointer-up that would normally reset it may now be ignored.
    if (oldWidget.elastic != widget.elastic ||
        oldWidget.touchEffect != widget.touchEffect) {
      _animateScaleToRest();
    }
    if (oldWidget.forceFallback != widget.forceFallback) {
      _reportMode(
        _canUseShader
            ? LiquidGlassRenderMode.shader
            : LiquidGlassRenderMode.fallback,
      );
    }
  }

  Future<void> _loadShader() async {
    try {
      final ui.FragmentProgram program = await _LiquidGlassShaderCache.load();
      if (!mounted) return;
      setState(() {
        _shader = program.fragmentShader();
        _shaderError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _shaderError = error);
      widget.onShaderError?.call(error);
    }
  }

  void _controllerChanged() {
    final LiquidGlassController? controller = widget.controller;
    if (!mounted || controller == null) return;

    _translation.value = controller.translation;
    if (_lastControllerConfig == controller.config) return;
    _lastControllerConfig = controller.config;
    setState(() {});
  }

  bool get _canUseShader =>
      !widget.forceFallback &&
      _shader != null &&
      _shaderError == null &&
      ui.ImageFilter.isShaderFilterSupported;

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    _settleTimer?.cancel();
    _shader?.dispose();
    _translation.dispose();
    _touchGlowCenter.dispose();
    _touchGlowVisible.dispose();
    _scaleX.dispose();
    _scaleY.dispose();
    super.dispose();
  }

  void _pointerDown(PointerDownEvent event) {
    if (_activePointer != null || !_isInteractive) return;
    // Secondary and middle mouse buttons are left to context menus.
    if ((event.buttons & kPrimaryButton) == 0) return;

    _activePointer = event.pointer;
    _dragStartPointer = event.position;
    _dragStartTranslation = _translation.value;
    if (widget.elastic) {
      _velocityTracker = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.position);
    }
    if (widget.touchEffect) {
      _touchGlowCenter.value = event.localPosition;
      _touchGlowVisible.value = true;
      _animateScaleTo(_pressScale, _pressScale);
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer) return;

    if (widget.touchEffect) {
      _touchGlowCenter.value = event.localPosition;
    }

    if (widget.elastic) {
      final VelocityTracker tracker = _velocityTracker ??=
          VelocityTracker.withKind(event.kind);
      tracker.addPosition(event.timeStamp, event.position);
      // Android's computeCurrentVelocity(1) reports pixels per millisecond.
      final Offset velocity = tracker.getVelocity().pixelsPerSecond / 1000;
      final ({double x, double y}) scale = LiquidGlassPhysics.scaleForVelocity(
        velocity,
      );
      _animateScaleTo(scale.x, scale.y);
      _settleTimer?.cancel();
      _settleTimer = Timer(_elasticSettleDelay, () => _animateScaleTo(1, 1));
    }

    if (widget.draggable) {
      // Like Android, anchor to where the pointer went down rather than
      // accumulating clamped deltas, so the glass never slips off the finger
      // after being pushed against an edge.
      _dragTo(_dragStartTranslation + (event.position - _dragStartPointer));
    }
  }

  void _pointerUp(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _velocityTracker = null;
    _settleTimer?.cancel();
    _touchGlowVisible.value = false;
    _animateScaleToRest();
  }

  void _animateScaleTo(double x, double y) {
    if (!mounted) return;
    _scaleX.animateWith(SpringSimulation(_spring, _scaleX.value, x, 0));
    _scaleY.animateWith(SpringSimulation(_spring, _scaleY.value, y, 0));
  }

  void _animateScaleToRest() {
    if (_scaleX.value == 1 &&
        _scaleY.value == 1 &&
        !_scaleX.isAnimating &&
        !_scaleY.isAnimating) {
      return;
    }
    _animateScaleTo(1, 1);
  }

  void _dragTo(Offset target) {
    final Offset next = _clampToLayoutParent(target);
    if (next == _translation.value) return;
    if (widget.controller case final LiquidGlassController controller) {
      controller.setTranslation(next);
    } else {
      _translation.value = next;
    }
    widget.onTranslationChanged?.call(next);
  }

  /// Keeps [translation] inside the view's layout parent, as Android keeps
  /// it inside the direct parent `ViewGroup`.
  ///
  /// Proxy render objects (repaint boundaries, semantics, opacity, ...) share
  /// their child's bounds and are skipped. Inside slivers or at the root there
  /// is no box parent to clamp against, so the translation is left as is.
  Offset _clampToLayoutParent(Offset translation) {
    // The parent of the sized box is this widget's own translation transform.
    RenderObject? node = _layoutKey.currentContext?.findRenderObject()?.parent;
    while (node != null && node.parentData is! BoxParentData) {
      node = node.parent is RenderBox ? node.parent : null;
    }
    final RenderObject? parent = node?.parent;
    if (node == null || parent is! RenderBox || !parent.hasSize) {
      return translation;
    }

    final Offset origin = (node.parentData! as BoxParentData).offset;
    final double minX = -origin.dx;
    final double maxX = parent.size.width - origin.dx - widget.width;
    final double minY = -origin.dy;
    final double maxY = parent.size.height - origin.dy - widget.height;
    return Offset(
      translation.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)),
      translation.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LiquidGlassConfig config = _config;
    final LiquidGlassRenderMode mode = _canUseShader
        ? LiquidGlassRenderMode.shader
        : LiquidGlassRenderMode.fallback;
    _reportMode(mode);

    final Widget surface = mode == LiquidGlassRenderMode.shader
        ? _buildShaderSurface(context, config)
        : _buildFallbackSurface(config);

    final Widget interactiveSurface = Listener(
      behavior: _isInteractive
          ? HitTestBehavior.opaque
          : HitTestBehavior.deferToChild,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: surface,
    );

    return ValueListenableBuilder<Offset>(
      valueListenable: _translation,
      child: SizedBox(
        key: _layoutKey,
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _scaleAnimations,
          child: interactiveSurface,
          builder: (BuildContext context, Widget? child) {
            return Transform.scale(
              scaleX: _scaleX.value,
              scaleY: _scaleY.value,
              alignment: Alignment.center,
              child: child,
            );
          },
        ),
      ),
      builder: (BuildContext context, Offset translation, Widget? child) {
        return Transform.translate(offset: translation, child: child);
      },
    );
  }

  void _reportMode(LiquidGlassRenderMode mode) {
    if (_reportedMode == mode) return;
    _reportedMode = mode;
    if (widget.onRenderModeChanged case final callback?) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted && _reportedMode == mode) callback(mode);
      });
    }
  }

  Widget _buildShaderSurface(BuildContext context, LiquidGlassConfig config) {
    final double padding = LiquidGlassPhysics.samplingPaddingFor(config);
    final double surfaceWidth = widget.width + padding * 2;
    final double surfaceHeight = widget.height + padding * 2;
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    final ui.FragmentShader shader = _shader!;
    final Size viewSize = Size(widget.width, widget.height);
    final _LiquidGlassFilterConfig? cached = _cachedShaderFilterConfig;
    final _LiquidGlassFilterConfig filterConfig =
        cached != null &&
            cached.matches(
              shader: shader,
              config: config,
              viewSize: viewSize,
              padding: padding,
              devicePixelRatio: devicePixelRatio,
            )
        ? cached
        : _cachedShaderFilterConfig = _LiquidGlassFilterConfig(
            shader: shader,
            config: config,
            viewSize: viewSize,
            padding: padding,
            devicePixelRatio: devicePixelRatio,
            backdropBox: () => _backdropBox,
            onPlacementResolved: (_GlassPlacement? placement) =>
                _lastResolvedPlacement = placement,
          );

    return OverflowBox(
      alignment: Alignment.center,
      minWidth: surfaceWidth,
      maxWidth: surfaceWidth,
      minHeight: surfaceHeight,
      maxHeight: surfaceHeight,
      child: SizedBox(
        width: surfaceWidth,
        height: surfaceHeight,
        child: ClipRect(
          child: BackdropFilter(
            key: _backdropKey,
            filterConfig: filterConfig,
            blendMode: BlendMode.srcOver,
            backdropGroupKey: widget.backdropGroupKey,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: padding,
                  top: padding,
                  width: widget.width,
                  height: widget.height,
                  child: _buildForeground(config),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackSurface(LiquidGlassConfig config) {
    final double blurSigma = math.max(0, config.blurSigma);
    if (_cachedFallbackBlur == null || _cachedFallbackBlurSigma != blurSigma) {
      _cachedFallbackBlurSigma = blurSigma;
      _cachedFallbackBlur = ui.ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
        tileMode: ui.TileMode.clamp,
      );
    }
    final ui.ImageFilter blur = _cachedFallbackBlur!;
    final Color tint = config.tintColor.withValues(
      alpha: config.tintAlpha.clamp(0, 1).toDouble(),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(config.cornerRadius),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: blur,
        blendMode: BlendMode.srcOver,
        backdropGroupKey: widget.backdropGroupKey,
        child: _buildForeground(config, tint: tint, clip: false),
      ),
    );
  }

  Widget _buildForeground(
    LiquidGlassConfig config, {
    Color? tint,
    bool clip = true,
  }) {
    final Widget foreground = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // ColoredBox is opaque to hit testing; the tint must not make a
        // passive glass swallow taps meant for the content behind it.
        if (tint != null && tint.a > 0)
          IgnorePointer(child: ColoredBox(color: tint)),
        if (widget.child case final Widget child) RepaintBoundary(child: child),
        if (widget.touchEffect)
          ValueListenableBuilder<bool>(
            valueListenable: _touchGlowVisible,
            builder: (BuildContext context, bool visible, Widget? child) {
              if (!visible) return const SizedBox.shrink();
              return IgnorePointer(child: child);
            },
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _TouchGlowPainter(center: _touchGlowCenter),
              ),
            ),
          ),
      ],
    );
    if (!clip) return foreground;
    return ClipRRect(
      borderRadius: BorderRadius.circular(config.cornerRadius),
      clipBehavior: Clip.antiAlias,
      child: foreground,
    );
  }
}

/// Resolves shader geometry during paint, when the filter's final screen
/// placement is known.
///
/// Backdrop filters are evaluated in device space, whatever transforms sit
/// above them, so runtime image-filter fragment coordinates are device pixels
/// rather than being local to the widget.
class _LiquidGlassFilterConfig implements ImageFilterConfig {
  _LiquidGlassFilterConfig({
    required this.shader,
    required this.config,
    required this.viewSize,
    required this.padding,
    required this.devicePixelRatio,
    required this.backdropBox,
    required this.onPlacementResolved,
  }) : _blurFilter = config.blurSigma > 0.01
           ? ui.ImageFilter.blur(
               sigmaX: config.blurSigma,
               sigmaY: config.blurSigma,
               tileMode: ui.TileMode.clamp,
             )
           : null {
    // Slots 0 and 1 belong to u_texture_size and are filled by the engine.
    // Everything except the screen placement is immutable for this config.
    shader
      ..setFloat(2, viewSize.width * devicePixelRatio)
      ..setFloat(3, viewSize.height * devicePixelRatio)
      ..setFloat(6, config.cornerRadius * devicePixelRatio)
      ..setFloat(7, config.refractionHeight * devicePixelRatio)
      ..setFloat(8, -config.refractionOffset.abs() * devicePixelRatio)
      ..setFloat(9, config.depthEffect)
      ..setFloat(10, config.dispersion)
      ..setFloat(11, config.contrast)
      ..setFloat(12, config.whitePoint)
      ..setFloat(13, config.chromaMultiplier)
      ..setFloat(14, config.tintColor.r)
      ..setFloat(15, config.tintColor.g)
      ..setFloat(16, config.tintColor.b)
      ..setFloat(17, config.tintAlpha);
  }

  /// Guards the shader's division by scale for a view scaled to nothing.
  static const double _minScale = 1e-3;

  final ui.FragmentShader shader;
  final LiquidGlassConfig config;
  final Size viewSize;
  final double padding;
  final double devicePixelRatio;
  final ui.ImageFilter? _blurFilter;

  /// The laid-out filter box, whose child is the glass inset by [padding].
  final ValueGetter<RenderBox?> backdropBox;

  /// Reports the placement each [resolve] used.
  final ValueChanged<_GlassPlacement?> onPlacementResolved;

  bool matches({
    required ui.FragmentShader shader,
    required LiquidGlassConfig config,
    required Size viewSize,
    required double padding,
    required double devicePixelRatio,
  }) {
    return identical(this.shader, shader) &&
        this.config == config &&
        this.viewSize == viewSize &&
        this.padding == padding &&
        this.devicePixelRatio == devicePixelRatio;
  }

  /// Maps the glass's top-left and unit axes through the full paint
  /// transform. Layer-local bounds would only be correct when the enclosing
  /// layer starts at the screen origin, and would ignore ancestor scales.
  _GlassPlacement? currentPlacement() {
    final RenderBox? box = backdropBox();
    if (box == null) return null;
    final Matrix4 transform = box.getTransformTo(null);
    Offset map(double x, double y) =>
        MatrixUtils.transformPoint(transform, Offset(x, y));
    final Offset origin = map(padding, padding);
    return (
      origin: origin,
      scale: Offset(
        (map(padding + 1, padding) - origin).distance,
        (map(padding, padding + 1) - origin).distance,
      ),
    );
  }

  @override
  ui.ImageFilter? get filter => null;

  @override
  String get debugShortDescription => 'liquidGlass';

  @override
  ui.ImageFilter resolve(ImageFilterContext context) {
    final _GlassPlacement? placement = currentPlacement();
    onPlacementResolved(placement);
    final Offset origin =
        placement?.origin ?? context.bounds.topLeft + Offset(padding, padding);
    final Offset scale = placement?.scale ?? const Offset(1, 1);

    shader
      ..setFloat(4, origin.dx * devicePixelRatio)
      ..setFloat(5, origin.dy * devicePixelRatio)
      ..setFloat(18, math.max(scale.dx, _minScale))
      ..setFloat(19, math.max(scale.dy, _minScale));

    ui.ImageFilter result = ui.ImageFilter.shader(shader);
    if (_blurFilter case final ui.ImageFilter blurFilter) {
      result = ui.ImageFilter.compose(outer: result, inner: blurFilter);
    }
    return result;
  }

  @override
  String toString() => 'ImageFilterConfig.$debugShortDescription';
}

abstract final class _LiquidGlassShaderCache {
  static Future<ui.FragmentProgram>? _program;

  static Future<ui.FragmentProgram> load() {
    return _program ??= _loadWithPackageTestFallback().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      // Do not memoize a failure; a later view may retry.
      _program = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  static Future<ui.FragmentProgram> _loadWithPackageTestFallback() async {
    try {
      return await ui.FragmentProgram.fromAsset(_shaderAsset);
    } on Exception catch (error, stackTrace) {
      // `flutter test` executed at the package root exposes the package's own
      // shader without the `packages/<name>/` prefix. Consumer applications
      // use the qualified key above.
      try {
        return await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
      } on Exception {
        // Report the consumer-facing failure, not the test-only fallback.
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }
}

class _TouchGlowPainter extends CustomPainter {
  _TouchGlowPainter({required ValueListenable<Offset> center})
    : _center = center,
      super(repaint: center);

  final ValueListenable<Offset> _center;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = math.max(size.width, size.height) * 0.8;
    final Paint paint = Paint()
      ..shader = ui.Gradient.radial(
        _center.value,
        radius,
        const <Color>[Color.fromARGB(60, 255, 255, 255), Color(0x00FFFFFF)],
        const <double>[0, 1],
        ui.TileMode.clamp,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _TouchGlowPainter oldDelegate) {
    return oldDelegate._center != _center;
  }
}
