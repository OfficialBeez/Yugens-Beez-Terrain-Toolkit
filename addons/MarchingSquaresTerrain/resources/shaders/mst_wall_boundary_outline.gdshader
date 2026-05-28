shader_type spatial;
// NOTE: Screen texture sampling is only reliable in the transparent pipeline.
// Keep render modes minimal/portable across Godot 4.x.
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Target thickness in SCREEN pixels for the wall boundary strip.
// (We keep the mesh-based approach, but make the thickness constant in screen-space to avoid popping.)
uniform float outline_px : hint_range(0.0, 32.0, 0.25) = 2.0;

// Tiny clip-space depth bias toward the camera to reduce z-fighting dropout.
// Keep small to avoid x-ray through other geometry.
uniform float depth_bias : hint_range(0.0, 0.01, 0.0001) = 0.0004;

// 0..1 strength for blending between the underlying color and the outline-modified color.
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.85;

// Contrast applied to the *already-lit* color underneath the outline.
// This keeps shadows dark while pushing lit areas lighter, without changing hue.
uniform float value_contrast : hint_range(0.0, 4.0, 0.01) = 1.35;

// Multiplier applied after contrast to ensure the outline is visibly darker than the base.
uniform float value_mul : hint_range(0.0, 1.0, 0.01) = 0.65;

// Optional tint multiplier (keep at 1,1,1 for "match underlying hue").
uniform vec3 tint = vec3(1.0);

// If > 0, sample the screen a little "inward" using a direction encoded in vertex COLOR.
// This is crucial for wall outlines: the strip can otherwise sample outside the wall (grass/sky) and look white.
uniform float sample_offset_world : hint_range(0.0, 0.2, 0.0005) = 0.0;

varying vec2 _sample_uv;

void vertex() {
	// Compute and write POSITION explicitly (so we can safely apply clip-space offsets).
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = clip;

	// Godot shader language doesn't allow early 'return' from vertex().
	_sample_uv = vec2(-1.0);

	// Only wall outlines set sample_offset_world > 0. Seam uses 0.
	if (sample_offset_world > 0.0) {
		// Decode interior direction from vertex color (encoded as 0..1).
		vec3 dir = COLOR.rgb * 2.0 - 1.0;
		float len2 = dot(dir, dir);
		if (len2 >= 1e-6) {
			dir *= inversesqrt(len2);

			// Constant pixel thickness: COLOR.a encodes 0 for edge verts, 1 for inner verts.
			float w = clamp(outline_px, 0.0, 64.0);
			if (w > 0.0 && COLOR.a > 0.001) {
				vec4 clip_dir = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + dir, 1.0);
				if (abs(clip.w) >= 1e-6 && abs(clip_dir.w) >= 1e-6) {
					vec2 ndc = clip.xy / clip.w;
					vec2 ndc_d = (clip_dir.xy / clip_dir.w) - ndc;
					float l2 = dot(ndc_d, ndc_d);
					if (l2 >= 1e-10) {
						ndc_d *= inversesqrt(l2);
						// NDC is -1..1, so 1 pixel = (2 / viewport_size) in NDC units.
						vec2 vp = max(vec2(1.0), vec2(VIEWPORT_SIZE));
						vec2 ndc_px = ndc_d * (w * 2.0 / vp);
						POSITION.xy += ndc_px * POSITION.w;
					}
				}
			}

			// Sampling UV (in world) so the outline color matches the wall hue/light.
			vec4 clip2 = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX + dir * sample_offset_world, 1.0);
			// Avoid NaNs/Infs if the vertex ends up on the projection plane.
			if (abs(clip2.w) >= 1e-6) {
				vec2 ndc2 = clip2.xy / clip2.w;
				_sample_uv = clamp(ndc2 * 0.5 + 0.5, vec2(0.0), vec2(1.0));
			}
		}
	}

	// Reduce z-fighting dropout.
	POSITION.z -= depth_bias * POSITION.w;

}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (_sample_uv.x >= 0.0) {
		uv = _sample_uv;
	}

	vec3 base = texture(screen_tex, uv).rgb;
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float lum2 = clamp((lum - 0.5) * value_contrast + 0.5, 0.0, 1.0);
	float scale = (lum > 0.0001) ? (lum2 / lum) : (lum2 / 0.0001);
	vec3 mod_col = clamp(base * scale, 0.0, 1.0) * tint;
	mod_col *= value_mul;
	// Stamp the outline color while staying opaque.
	ALBEDO = mix(base, mod_col, opacity);
	ALPHA = 1.0;
}
