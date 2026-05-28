shader_type spatial;
render_mode diffuse_toon, depth_draw_opaque, cull_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms Visuals.Normals;
uniform bool use_flat_normals = false;
group_uniforms;

group_uniforms Effects.Experimental;
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0; // Experimental feature (used for rounding merge thresholds)
group_uniforms;

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.0;
group_uniforms;

group_uniforms Visuals.Edge_Highlights;
uniform bool use_edge_highlights = false;
uniform float edge_highlight_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float edge_highlight_width : hint_range(0.0, 32.0, 0.25) = 10.0;
uniform float edge_highlight_power : hint_range(0.1, 8.0, 0.1) = 1.6;
group_uniforms;


void vertex() {
	bool is_floor = dot(NORMAL, vec3(0.0, 1.0, 0.0)) > wall_threshold;
	if (use_flat_normals && is_floor)
		NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo_tex.rgb;

}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = use_cell_shading ? (ceil(NdotL * float(bands)) / float(bands)) : NdotL;

	float toon_weight = use_cell_shading
		? mix(shadow_intensity, 0.3, stepped)
		: (NdotL * 0.3);

	// Edge Highlights are currently implemented in fragment() as a black outline.

	float toon_light = toon_weight * ATTENUATION;
	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
	DIFFUSE_LIGHT += light_color;
}