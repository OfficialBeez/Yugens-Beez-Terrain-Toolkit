shader_type spatial;
// NOTE: Godot 4 render_mode does NOT support `depth_test_enabled`.
// Depth testing is enabled by default; only `depth_test_disabled` exists.
// This material is used as the *base pass* when Black Silhouette is enabled,
// with the regular terrain shader set as its next_pass.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// World-space thickness.
uniform float outline_thickness : hint_range(0.0, 0.5, 0.001) = 0.02;
// 0 = outline everything, 1 = outline mostly-vertical surfaces only.
uniform float wall_only : hint_range(0.0, 1.0, 0.01) = 0.0;

void vertex() {
	// Fade out on near-horizontal faces so we don't draw outlines across the top surface.
	float verticalness = 1.0 - abs(NORMAL.y); // 1 for vertical, 0 for horizontal
	float wall_factor = mix(1.0, smoothstep(0.1, 0.35, verticalness), wall_only);
	VERTEX += NORMAL * outline_thickness * wall_factor;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
