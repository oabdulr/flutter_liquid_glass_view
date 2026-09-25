import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_view/liquid_glass_view.dart';

void main() {
  testWidgets('packaged fragment program compiles', (
    WidgetTester tester,
  ) async {
    await expectLater(LiquidGlassView.warmUp(), completes);
  });

  test('shader maps geometry through the view scale', () {
    final String shader = File('shaders/liquid_glass.frag').readAsStringSync();

    // The shape is evaluated in the view's own space and every sample offset
    // is mapped back to device space, so ancestor scales (such as the elastic
    // stretch) deform the glass instead of detaching it from its content.
    expect(
      shader,
      contains('(coord - u_view_origin) / u_view_scale - half_size'),
    );
    expect(
      shader,
      contains('vec2 displacement = distance_amount * grad * u_view_scale;'),
    );
    // u_view_scale is declared last so the Dart side's fixed slots 0-17 hold.
    final int scaleIndex = shader.indexOf('uniform vec2 u_view_scale;');
    final int lastUniform = shader.lastIndexOf('uniform ');
    expect(scaleIndex, lastUniform);
  });

  test('shader retains every Android uniform and seven dispersion taps', () {
    final String shader = File('shaders/liquid_glass.frag').readAsStringSync();
    const List<String> uniforms = <String>[
      'u_corner_radius',
      'u_refraction_height',
      'u_refraction_amount',
      'u_depth_effect',
      'u_chromatic_aberration',
      'u_contrast',
      'u_white_point',
      'u_chroma_multiplier',
      'u_tint_color',
      'u_tint_alpha',
      'u_view_scale',
    ];

    for (final String uniform in uniforms) {
      expect(shader, contains(uniform), reason: 'Missing $uniform');
    }

    // One helper declaration, one deep-interior sample, and seven refracted
    // spectrum samples exactly mirror the AGSL source.
    expect(RegExp(r'sample_content\(').allMatches(shader).length, 9);
    expect(shader, contains('red.r / 3.5'));
    expect(shader, contains('orange.g / 7.0'));
    expect(shader, contains('yellow.g / 3.5'));
    expect(shader, contains('cyan.b / 3.0'));
    expect(shader, contains('purple.r / 7.0'));
  });

  test(
    'grade_color preserves identity-chroma output while skipping conversion',
    () {
      final String shader = File(
        'shaders/liquid_glass.frag',
      ).readAsStringSync();
      final String gradeBody = RegExp(
        r'vec4 grade_color\(vec4 color\) \{([\s\S]*?)\n\}\n\nvoid main',
      ).firstMatch(shader)!.group(1)!;
      final String normalizedBody = gradeBody.replaceAll(RegExp(r'\s+'), ' ');

      expect(
        normalizedBody,
        contains(
          'if (u_chroma_multiplier == 1.0 && u_white_point == 0.0 && '
          'u_contrast == 0.0 && u_tint_alpha == 0.0) { return color; }',
        ),
      );
      expect(
        normalizedBody,
        contains(
          'if (u_chroma_multiplier != 1.0) { '
          'color = saturate_color(color, u_chroma_multiplier); } '
          'vec3 target = u_white_point > 0.0 ? vec3(1.0) : vec3(0.0); '
          'color.rgb = mix(color.rgb, target, abs(u_white_point)); '
          'color.rgb = (color.rgb - 0.5) * (1.0 + u_contrast) + 0.5; '
          'color.rgb = mix(color.rgb, u_tint_color, u_tint_alpha);',
        ),
      );

      const List<_GradeCase> identityCases = <_GradeCase>[
        _GradeCase(
          rgba: <double>[0, 0.0001, 0.0031308, 0],
          whitePoint: 0,
          contrast: 0,
          tint: <double>[1, 0.25, 0],
          tintAlpha: 0.2,
        ),
        _GradeCase(
          rgba: <double>[0.04044, 0.04045, 0.04046, 0.37],
          whitePoint: 0.25,
          contrast: -0.15,
          tint: <double>[0.8, 0.2, 0.1],
          tintAlpha: 0.25,
        ),
        _GradeCase(
          rgba: <double>[1, 0.5, 0.75, 1],
          whitePoint: -0.2,
          contrast: 0.2,
          tint: <double>[0.1, 0.4, 1],
          tintAlpha: 0.1,
        ),
      ];
      const double parityTolerance = 1e-6;
      double maximumDifference = 0;
      for (int caseIndex = 0; caseIndex < identityCases.length; caseIndex++) {
        final _GradeCase testCase = identityCases[caseIndex];
        // false models the old unconditional round-trip; true models the
        // optimized identity skip. Both use the one reference helper below.
        final _GradeResult oldPipeline = _referenceGradeColor(
          testCase.rgba,
          skipIdentityChroma: false,
          whitePoint: testCase.whitePoint,
          contrast: testCase.contrast,
          chromaMultiplier: 1,
          tint: testCase.tint,
          tintAlpha: testCase.tintAlpha,
        );
        final _GradeResult optimizedPipeline = _referenceGradeColor(
          testCase.rgba,
          skipIdentityChroma: true,
          whitePoint: testCase.whitePoint,
          contrast: testCase.contrast,
          chromaMultiplier: 1,
          tint: testCase.tint,
          tintAlpha: testCase.tintAlpha,
        );

        expect(oldPipeline.saturationCalls, 1, reason: 'case $caseIndex');
        expect(optimizedPipeline.saturationCalls, 0, reason: 'case $caseIndex');
        expect(oldPipeline.rgba[3], testCase.rgba[3]);
        expect(optimizedPipeline.rgba[3], testCase.rgba[3]);
        expect(oldPipeline.rgba[3], optimizedPipeline.rgba[3]);
        for (int channel = 0; channel < 3; channel++) {
          maximumDifference = math
              .max(
                maximumDifference,
                (oldPipeline.rgba[channel] - optimizedPipeline.rgba[channel])
                    .abs(),
              )
              .toDouble();
        }
      }
      expect(
        maximumDifference,
        lessThanOrEqualTo(parityTolerance),
        reason: 'maximum RGB difference across identity cases',
      );

      const List<double> input = <double>[0.04045, 0.0031308, 0.5, 0.37];
      final _GradeResult tinted = _referenceGradeColor(
        input,
        skipIdentityChroma: true,
        whitePoint: 0,
        contrast: 0,
        chromaMultiplier: 1,
        tint: <double>[0.8, 0.2, 0.1],
        tintAlpha: 0.25,
      );
      expect(tinted.saturationCalls, 0);
      _expectRgbaClose(tinted.rgba, <double>[0.2303375, 0.0523481, 0.4, 0.37]);

      final _GradeResult otherGrading = _referenceGradeColor(
        input,
        skipIdentityChroma: true,
        whitePoint: 0.25,
        contrast: -0.1,
        chromaMultiplier: 1,
        tint: <double>[0.8, 0.2, 0.1],
        tintAlpha: 0.25,
      );
      expect(otherGrading.saturationCalls, 0);
      _expectRgbaClose(otherGrading.rgba, <double>[
        0.4267278125,
        0.2578349675,
        0.484375,
        0.37,
      ]);

      final _GradeResult nonDefaultChroma = _referenceGradeColor(
        input,
        skipIdentityChroma: true,
        whitePoint: 0,
        contrast: 0,
        chromaMultiplier: 0.75,
        tint: <double>[0.8, 0.2, 0.1],
        tintAlpha: 0,
      );
      expect(nonDefaultChroma.saturationCalls, 1);
      _expectRgbaClose(nonDefaultChroma.rgba, <double>[
        0.07375418175534112,
        0.05346516148832573,
        0.4424727732158841,
        0.37,
      ], tolerance: 1e-8);
    },
  );
}

class _GradeCase {
  const _GradeCase({
    required this.rgba,
    required this.whitePoint,
    required this.contrast,
    required this.tint,
    required this.tintAlpha,
  });

  final List<double> rgba;
  final double whitePoint;
  final double contrast;
  final List<double> tint;
  final double tintAlpha;
}

class _GradeResult {
  const _GradeResult(this.rgba, this.saturationCalls);

  final List<double> rgba;
  final int saturationCalls;
}

_GradeResult _referenceGradeColor(
  List<double> rgba, {
  required bool skipIdentityChroma,
  required double whitePoint,
  required double contrast,
  required double chromaMultiplier,
  required List<double> tint,
  required double tintAlpha,
}) {
  final List<double> result = List<double>.from(rgba);
  int saturationCalls = 0;
  if (!skipIdentityChroma || chromaMultiplier != 1.0) {
    saturationCalls++;
    final List<double> linear = result.take(3).map(_toLinearSrgb).toList();
    final double luminance =
        linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
    for (int index = 0; index < 3; index++) {
      result[index] = _fromLinearSrgb(
        luminance + (linear[index] - luminance) * chromaMultiplier,
      );
    }
  }

  final double target = whitePoint > 0 ? 1 : 0;
  for (int index = 0; index < 3; index++) {
    result[index] =
        result[index] * (1 - whitePoint.abs()) + target * whitePoint.abs();
    result[index] = (result[index] - 0.5) * (1 + contrast) + 0.5;
    result[index] = result[index] * (1 - tintAlpha) + tint[index] * tintAlpha;
  }
  return _GradeResult(result, saturationCalls);
}

double _toLinearSrgb(double color) {
  if (color <= 0.04045) return color / 12.92;
  return math.pow(math.max((color + 0.055) / 1.055, 0), 2.4).toDouble();
}

double _fromLinearSrgb(double color) {
  if (color <= 0.0031308) return color * 12.92;
  return 1.055 * math.pow(math.max(color, 0), 1 / 2.4).toDouble() - 0.055;
}

void _expectRgbaClose(
  List<double> actual,
  List<double> expected, {
  double tolerance = 1e-9,
}) {
  for (int index = 0; index < expected.length; index++) {
    expect(actual[index], closeTo(expected[index], tolerance));
  }
}
