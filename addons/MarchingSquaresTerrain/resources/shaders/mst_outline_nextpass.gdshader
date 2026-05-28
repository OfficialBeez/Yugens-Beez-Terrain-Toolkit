shader_type spatial;
// NOTE: Godot 4 render_mode does NOT support `depth_test_enabled`.
// Depth testing is enabled by default; only `depth_test_disabled` exists.
// This material is used as the *base pass* when Black Silhouette is enabled,
// with the regular terrain shader set as its next_pass.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// World-space thickness (legacy fallback).
uniform float outline_thickness : hint_range(0.0, 0.5, 0.001) = 0.02;
// Screen-space thickness in pixels (preferred). Set to 0 to use outline_thickness.
uniform float outline_px : hint_range(0.0, 32.0, 0.25) = 0.0;
// 0 = outline everything, 1 = outline mostly-vertical surfaces only.
uniform float wall_only : hint_range(0.0, 1.0, 0.01) = 0.0;

void vertex() {
	// Fade out on near-horizontal faces so we don't draw outlines across the top surface.
	float verticalness = 1.0 - abs(NORMAL.y); // 1 for vertical, 0 for horizontal
	float wall_factor = mix(1.0, smoothstep(0.1, 0.35, verticalness), wall_only);

	float w = clamp(outline_px, 0.0, 64.0);

	// Legacy world-space expansion (used only when outline_px == 0).
	vec3 v = VERTEX;
	if (w <= 0.0) {
		v += NORMAL * outline_thickness * wall_factor;
	}

	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(v, 1.0);
	POSITION = clip;

	// Pixel-constant expansion.
	// Use the projected view-space normal direction so it works in both Perspective and Orthogonal.
	if (w > 0.0) {
		vec3 n_vs = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		float n2 = dot(n_vs, n_vs);
		if (n2 > 1e-12) n_vs *= inversesqrt(n2);

		vec2 dir = n_vs.xy;
		float d2 = dot(dir, dir);
		if (d2 < 1e-10) {
			// Fallback for faces whose normals point almost straight at the camera.
			vec2 p = clip.xy;
			d2 = dot(p, p);
			dir = (d2 > 1e-10) ? (p * inversesqrt(d2)) : vec2(1.0, 0.0);
		} else {
			dir *= inversesqrt(d2);
		}

		vec2 vp = max(vec2(1.0), vec2(VIEWPORT_SIZE));
		vec2 ndc_px = dir * (w * 2.0 / vp) * wall_factor;
		POSITION.xy += ndc_px * POSITION.w;
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
