shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_px : hint_range(0.0, 32.0, 0.25) = 2.0;
// Small clip-space depth bias to avoid z-fighting with the terrain.
uniform float depth_bias : hint_range(0.0, 0.01, 0.00001) = 0.00035;

void vertex() {
	// This mesh encodes the edge direction in NORMAL, and the side in COLOR.r (0 = -1, 1 = +1).
	float side = (COLOR.r < 0.5) ? -1.0 : 1.0;

	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;

	float w = clamp(outline_px, 0.0, 64.0);
	if (w > 0.0) {
		vec3 d_vs = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		vec2 d = d_vs.xy;
		float d2 = dot(d, d);
		if (d2 < 1e-10) {
			// If the edge direction projects to ~0, fall back to radial direction from origin.
			vec2 p = clip.xy;
			float p2 = dot(p, p);
			d = (p2 > 1e-10) ? (p * inversesqrt(p2)) : vec2(1.0, 0.0);
		} else {
			d *= inversesqrt(d2);
		}

		// Perpendicular in screen space.
		vec2 perp = vec2(-d.y, d.x);
		vec2 vp = max(vec2(1.0), vec2(VIEWPORT_SIZE));
		vec2 ndc_px = perp * (w * 2.0 / vp) * side;
		POSITION.xy += ndc_px * POSITION.w;
	}

	// Bias slightly toward the camera to sit on top.
	POSITION.z -= depth_bias * POSITION.w;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
