#version 320 es
/*
 * Flutter port of AndroidLiquidGlassView/core/src/main/res/raw/
 * liquidglass_effect.agsl.
 *
 * Original shader copyright (c) 2025-2026 Donny Yale (QmDeve) and
 * contributors, including Ahmed Sbai.
 * https://github.com/QmDeve/AndroidLiquidGlassView
 * Distributed under the MIT License; see ../LICENSE.
 */

#include <flutter/runtime_effect.glsl>

precision highp float;

// ImageFilter.shader requires the first float uniform to be a vec2. Flutter
// supplies the input texture dimensions automatically.
uniform vec2 u_texture_size;
uniform sampler2D u_content;

// Geometry is expressed in the view's own (untransformed) physical pixels,
// except u_view_origin, which is the device-space position of its top-left.
uniform vec2 u_view_size;
uniform vec2 u_view_origin;
uniform float u_corner_radius;
uniform float u_refraction_height;
uniform float u_refraction_amount;
uniform float u_depth_effect;
uniform float u_chromatic_aberration;
uniform float u_contrast;
uniform float u_white_point;
uniform float u_chroma_multiplier;
uniform vec3 u_tint_color;
uniform float u_tint_alpha;
// Device pixels per view pixel along each axis, from ancestor transforms such
// as the elastic stretch. Declared last so earlier uniform slots stay stable.
uniform vec2 u_view_scale;

out vec4 frag_color;

const vec3 rgb_to_y = vec3(0.2126, 0.7152, 0.0722);

float sd_rounded_rect(vec2 coord, vec2 half_size, float radius) {
  vec2 corner_coord = abs(coord) - (half_size - vec2(radius));
  float outside = length(max(corner_coord, 0.0)) - radius;
  float inside = min(max(corner_coord.x, corner_coord.y), 0.0);
  return outside + inside;
}

float safe_sign(float value) {
  return value < 0.0 ? -1.0 : 1.0;
}

vec2 safe_normalize(vec2 value, vec2 fallback_value) {
  float value_length = length(value);
  if (value_length > 0.001) {
    return value / value_length;
  }
  return fallback_value;
}

vec2 grad_sd_rounded_rect(vec2 coord, vec2 half_size, float radius) {
  vec2 corner_coord = abs(coord) - (half_size - vec2(radius));
  if (corner_coord.x >= 0.0 || corner_coord.y >= 0.0) {
    vec2 outside = max(corner_coord, 0.0);
    float outside_length = length(outside);
    if (outside_length > 0.001) {
      return sign(coord) * (outside / outside_length);
    }
    float use_x = step(corner_coord.y, corner_coord.x);
    return vec2(
      use_x * safe_sign(coord.x),
      (1.0 - use_x) * safe_sign(coord.y)
    );
  }

  float grad_x = step(corner_coord.y, corner_coord.x);
  return sign(coord) * vec2(grad_x, 1.0 - grad_x);
}

float circle_map(float value) {
  float safe_value = clamp(value, -1.0, 1.0);
  return 1.0 - sqrt(max(0.0, 1.0 - safe_value * safe_value));
}

vec3 to_linear_srgb(vec3 color) {
  bvec3 cutoff = lessThanEqual(color, vec3(0.04045));
  vec3 low = color / 12.92;
  vec3 high = pow(max((color + 0.055) / 1.055, 0.0), vec3(2.4));
  return mix(high, low, cutoff);
}

vec3 from_linear_srgb(vec3 color) {
  bvec3 cutoff = lessThanEqual(color, vec3(0.0031308));
  vec3 low = color * 12.92;
  vec3 high = 1.055 * pow(max(color, 0.0), vec3(1.0 / 2.4)) - 0.055;
  return mix(high, low, cutoff);
}

vec4 saturate_color(vec4 color, float amount) {
  vec3 linear_color = to_linear_srgb(color.rgb);
  float luminance = dot(linear_color, rgb_to_y);
  vec3 saturated = from_linear_srgb(mix(vec3(luminance), linear_color, amount));
  return vec4(saturated, color.a);
}

vec4 sample_content(vec2 pixel_coord) {
  vec2 uv = pixel_coord / u_texture_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_content, clamp(uv, vec2(0.0), vec2(1.0)));
}

vec4 grade_color(vec4 color) {
  // The Android defaults make every grading operation an identity. Avoid two
  // power functions per channel in that overwhelmingly common case.
  if (u_chroma_multiplier == 1.0 &&
      u_white_point == 0.0 &&
      u_contrast == 0.0 &&
      u_tint_alpha == 0.0) {
    return color;
  }
  // Chroma 1.0 is an identity; skip its transfer conversions even when
  // later grading such as tint remains active.
  if (u_chroma_multiplier != 1.0) {
    color = saturate_color(color, u_chroma_multiplier);
  }
  vec3 target = u_white_point > 0.0 ? vec3(1.0) : vec3(0.0);
  color.rgb = mix(color.rgb, target, abs(u_white_point));
  color.rgb = (color.rgb - 0.5) * (1.0 + u_contrast) + 0.5;
  color.rgb = mix(color.rgb, u_tint_color, u_tint_alpha);
  return color;
}

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 half_size = u_view_size * 0.5;
  // Backdrop filters run in device space. Evaluate the shape in the view's own
  // space so a scaled ancestor stretches the glass like Android's scaled
  // RenderNode; sample offsets are mapped back to device space below.
  vec2 centered_coord = (coord - u_view_origin) / u_view_scale - half_size;
  float min_scale = min(u_view_scale.x, u_view_scale.y);

  // Most fragments belong to the sampling margin. Reject them before the
  // rounded-rectangle distance calculation, whose corner path uses a square
  // root. Anything beyond this box has exactly zero coverage below.
  if (any(greaterThan(abs(centered_coord), half_size + vec2(0.5 / min_scale)))) {
    frag_color = vec4(0.0);
    return;
  }

  float sd = sd_rounded_rect(centered_coord, half_size, u_corner_radius);

  // The Android host clips to an anti-aliased rounded outline. The shader is
  // rendered on a padded surface so it can sample beyond that outline; this
  // coverage recreates the host clip while leaving the padded area transparent.
  // The one-pixel ramp is measured in device pixels.
  float coverage = clamp(0.5 - sd * min_scale, 0.0, 1.0);
  if (coverage <= 0.0) {
    frag_color = vec4(0.0);
    return;
  }

  vec4 color;
  if (u_refraction_height <= 0.0 || -sd >= u_refraction_height) {
    color = grade_color(sample_content(coord));
  } else {
    float inside_sd = min(sd, 0.0);
    float distance_amount = circle_map(
      1.0 - (-inside_sd / u_refraction_height)
    ) * u_refraction_amount;
    float smooth_radius = max(u_corner_radius * 1.5, 30.0);
    float grad_radius = min(smooth_radius, min(half_size.x, half_size.y));

    vec2 shape_grad = grad_sd_rounded_rect(
      centered_coord,
      half_size,
      grad_radius
    );
    vec2 depth_grad = safe_normalize(centered_coord, shape_grad);
    vec2 grad = safe_normalize(
      shape_grad + u_depth_effect * depth_grad,
      shape_grad
    );

    vec2 displacement = distance_amount * grad * u_view_scale;
    vec2 refracted_coord = coord + displacement;
    float dispersion_intensity = u_chromatic_aberration *
      ((centered_coord.x * centered_coord.y) / (half_size.x * half_size.y));
    vec2 dispersed_coord = displacement * dispersion_intensity;

    color = vec4(0.0);

    vec4 red = sample_content(refracted_coord + dispersed_coord);
    color.r += red.r / 3.5;
    color.a += red.a / 7.0;

    vec4 orange = sample_content(
      refracted_coord + dispersed_coord * (2.0 / 3.0)
    );
    color.r += orange.r / 3.5;
    color.g += orange.g / 7.0;
    color.a += orange.a / 7.0;

    vec4 yellow = sample_content(
      refracted_coord + dispersed_coord * (1.0 / 3.0)
    );
    color.r += yellow.r / 3.5;
    color.g += yellow.g / 3.5;
    color.a += yellow.a / 7.0;

    vec4 green = sample_content(refracted_coord);
    color.g += green.g / 3.5;
    color.a += green.a / 7.0;

    vec4 cyan = sample_content(
      refracted_coord - dispersed_coord * (1.0 / 3.0)
    );
    color.g += cyan.g / 3.5;
    color.b += cyan.b / 3.0;
    color.a += cyan.a / 7.0;

    vec4 blue = sample_content(
      refracted_coord - dispersed_coord * (2.0 / 3.0)
    );
    color.b += blue.b / 3.0;
    color.a += blue.a / 7.0;

    vec4 purple = sample_content(refracted_coord - dispersed_coord);
    color.r += purple.r / 7.0;
    color.b += purple.b / 3.0;
    color.a += purple.a / 7.0;

    color = grade_color(color);
  }

  frag_color = color * coverage;
}
