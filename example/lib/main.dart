import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Compile the shader while the first frame is being prepared. A failure is
  // also reported through LiquidGlassView.onShaderError, so ignore it here.
  unawaited(LiquidGlassView.warmUp().catchError((Object _) {}));
  runApp(const LiquidGlassExampleApp());
}

/// Demo application for `liquid_glass_view`.
class LiquidGlassExampleApp extends StatelessWidget {
  /// Creates the demo application.
  const LiquidGlassExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Liquid Glass View',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4C7DFF),
        sliderTheme: const SliderThemeData(
          trackHeight: 8,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        ),
      ),
      home: const LiquidGlassDemo(),
    );
  }
}

/// Interactive playground: a draggable glass over a photo plus live controls.
class LiquidGlassDemo extends StatefulWidget {
  /// Creates the playground.
  const LiquidGlassDemo({super.key});

  @override
  State<LiquidGlassDemo> createState() => _LiquidGlassDemoState();
}

class _LiquidGlassDemoState extends State<LiquidGlassDemo> {
  final LiquidGlassController _controller = LiquidGlassController();
  bool _elastic = false;
  bool _touch = false;
  LiquidGlassRenderMode _mode = LiquidGlassRenderMode.fallback;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset('assets/demo_background.jpg', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x22000000),
                  Color(0x00000000),
                  Color(0x99000000),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Flutter Liquid Glass',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text('AndroidLiquidGlassView shader port'),
                      ],
                    ),
                  ),
                  _ModeBadge(mode: _mode),
                ],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.18),
            child: LiquidGlassView(
              width: 220,
              height: 180,
              controller: _controller,
              draggable: true,
              elastic: _elastic,
              touchEffect: _touch,
              onRenderModeChanged: (LiquidGlassRenderMode mode) {
                if (mounted) setState(() => _mode = mode);
              },
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.open_with_rounded, size: 30),
                    SizedBox(height: 8),
                    Text(
                      'Drag me',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                // A Material (not a coloured DecoratedBox) so the switch
                // tiles' ink splashes paint on the panel itself.
                child: Material(
                  color: const Color(0xCC11131A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: Color(0x33FFFFFF)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: _buildControls(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    // The controller is the single source of truth, so the sliders always
    // show the clamped values the glass actually renders with.
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? toggles) {
        final LiquidGlassConfig config = _controller.config;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Parameter(
              label: 'Corner radius',
              value: config.cornerRadius,
              min: 0,
              max: 90,
              onChanged: _controller.setCornerRadius,
            ),
            _Parameter(
              label: 'Refraction height',
              value: config.refractionHeight,
              min: 12,
              max: 50,
              onChanged: _controller.setRefractionHeight,
            ),
            _Parameter(
              label: 'Refraction offset',
              value: config.refractionOffset,
              min: 20,
              max: 120,
              onChanged: _controller.setRefractionOffset,
            ),
            _Parameter(
              label: 'Blur sigma',
              value: config.blurSigma,
              min: 0.01,
              max: 30,
              onChanged: _controller.setBlurRadius,
            ),
            _Parameter(
              label: 'Dispersion',
              value: config.dispersion,
              min: 0,
              max: 1,
              onChanged: _controller.setDispersion,
            ),
            _Parameter(
              label: 'Tint',
              value: config.tintAlpha,
              min: 0,
              max: 0.5,
              onChanged: _controller.setTintAlpha,
            ),
            toggles!,
          ],
        );
      },
      child: Row(
        children: <Widget>[
          Expanded(
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Elastic'),
              value: _elastic,
              onChanged: (bool value) => setState(() => _elastic = value),
            ),
          ),
          Expanded(
            child: SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Touch glow'),
              value: _touch,
              onChanged: (bool value) => setState(() => _touch = value),
            ),
          ),
          IconButton(
            tooltip: 'Reset position',
            onPressed: _controller.resetTranslation,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }
}

class _Parameter extends StatelessWidget {
  const _Parameter({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: <Widget>[
          SizedBox(width: 128, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              value.toStringAsFixed(max <= 1 ? 2 : 0),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final LiquidGlassRenderMode mode;

  @override
  Widget build(BuildContext context) {
    final bool shader = mode == LiquidGlassRenderMode.shader;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: shader ? const Color(0xCC176A3A) : const Color(0xCC6A4B17),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(shader ? 'Impeller shader' : 'Blur fallback'),
      ),
    );
  }
}
