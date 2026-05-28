group_uniforms Terrain.Properties;
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec2 cell_size = vec2(2.0, 2.0);
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
group_uniforms;

group_uniforms Visuals.Palette;
// NOTE: Some GPUs/devices have a 64KB limit on uniform buffers. Large uniform arrays
// (like vec4[2048]) can exceed that and cause the shader to silently fail.
// We store palette data in small lookup textures instead:
// - palette_colors_tex:  8 x 256, RGBA (float).   x=color idx (0..7), y=slot (0..255)
// - palette_weights_tex: 8 x 256, R in [0..1].    x=color idx (0..7), y=slot (0..255)
// - palette_meta_tex:    1 x 256, RGBA8 encoded:  r=count(0..8), g=blend_mode(0..3),
//                          b=has_outline(0/1), a=outline_mode(0/1), each stored as 0..255
uniform sampler2D palette_colors_tex : filter_nearest;
uniform sampler2D palette_weights_tex : filter_nearest;
uniform sampler2D palette_meta_tex : filter_nearest;

// Controls outline thickness. Higher = thicker.
uniform float outline_width : hint_range(0.25, 32.0, 0.25) = 6.0;

group_uniforms;

group_uniforms Visuals.Vertex_Painting;
uniform sampler2DArray vc_tex_array : source_color, filter_nearest;
group_uniforms;

group_uniforms Visuals.Texture_Scales;
uniform float tex_scales[256];
group_uniforms;

group_uniforms Effects.Blending;
uniform bool use_hard_textures = false;
uniform int blend_mode = 0;
uniform float blend_sharpness : hint_range(0.0, 10.0, 0.1) = 5.0;
uniform float blend_noise_scale : hint_range(0.0, 50.0, 1.0) = 10.0;
uniform float blend_noise_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
group_uniforms;

group_uniforms Visuals.Normals;
uniform bool use_flat_normals = false;
group_uniforms;

group_uniforms Effects.Ridge_Ledge_Texture;
uniform bool use_ridge_texture = true;
uniform bool use_ledge_texture = true;
uniform float ridge_threshold : hint_range(0.0, 1.0) = 1.0;
uniform float ledge_threshold : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D rl_noise_texture : source_color, filter_nearest;
uniform float rl_noise_tile_size : hint_range(0.01, 1.0) = 0.075;
uniform float rl_noise_strength : hint_range(0.0, 10.0) = 10.0;
uniform float global_noise_scale = 0.08;
uniform float global_noise_strength = 0.3;
// 0..1 multiplier for scroll speed (0 = off)
uniform float global_noise_scroll = 0.0;
uniform sampler2D global_noise_texture : hint_default_white, repeat_enable, filter_linear;

// Used to keep terrain global-noise scroll aligned with grass wind.
uniform vec2 wind_direction = vec2(1.0, 1.0);
uniform float wind_speed = 0.14;
group_uniforms;

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
group_uniforms;

group_uniforms Visuals.Edge_Highlights;
uniform bool use_edge_highlights = false;
// Screen-space edge outlines (toon style).
uniform vec4 edge_highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float edge_highlight_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
// Higher = thicker / more sensitive.
uniform float edge_highlight_width : hint_range(0.0, 32.0, 0.25) = 10.0;
// Higher = harder edge (more ink-like).
uniform float edge_highlight_power : hint_range(0.1, 8.0, 0.1) = 2.0;
// Thresholding to avoid the "white wash" effect.
uniform float edge_highlight_threshold : hint_range(0.0, 5.0, 0.01) = 0.65;
uniform float edge_highlight_softness : hint_range(0.0, 1.0, 0.001) = 0.02;
// Allow separating silhouette (depth) vs crease (normal) edges.
uniform float edge_highlight_normal_weight : hint_range(0.0, 4.0, 0.05) = 1.0;

// Depth-based band-pass for "inner" outlines (step edges).
// We use view-space depth derivatives; scale/thresholds are tuned per project.
uniform float inner_outline_depth_scale : hint_range(0.0, 50000.0, 50.0) = 12000.0;
// Turns on at this depth-edge magnitude.
uniform float inner_outline_threshold : hint_range(0.0, 10.0, 0.01) = 0.55;
uniform float inner_outline_softness : hint_range(0.0, 2.0, 0.001) = 0.05;
// Reject very large depth discontinuities (outer silhouette).
uniform float inner_outline_silhouette_threshold : hint_range(0.0, 50.0, 0.01) = 2.0;
uniform float inner_outline_silhouette_softness : hint_range(0.0, 5.0, 0.001) = 0.10;

group_uniforms;

group_uniforms Visuals.Seam_Outline;
// Stable, mesh-driven outline at the floor/wall seam (no screen-space jitter).
uniform bool use_seam_outline = false;

// When seam_outline_from_albedo is false, this is the absolute outline color.
// When true, RGB acts as a multiplier and A is treated as opacity.
uniform vec4 seam_outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.9);

// If true, derive the outline color from the underlying surface ALBEDO (preserves hue)
// and optionally lift/darken it via seam_outline_lift.
uniform bool seam_outline_from_albedo = false;

// -1..1 value shift applied to the derived outline color.
//  >0 lifts toward white (pastel), <0 pushes toward black.
uniform float seam_outline_lift : hint_range(-1.0, 1.0, 0.01) = 0.35;

uniform float seam_outline_width : hint_range(0.0, 32.0, 0.25) = 2.0;
uniform float seam_outline_strength : hint_range(0.0, 1.0, 0.01) = 1.0;

group_uniforms;

varying vec3 vertex_normal;
varying vec3 custom1;
varying flat float nearest_wall_color_idx;
varying flat float seam_flag;
varying vec3 world_pos;
#ifdef BAKE_MODE
varying vec3 virtual_vertex;
#endif

varying vec4 ridge_blend_factor;
varying vec4 ledge_blend_factor;

varying flat int material_index;
varying vec4 vc_color_0;
varying vec4 vc_color_1;

varying flat vec3 mat_indices;
varying vec2 mat_weights;
varying float use_vertex_colors;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cheap_noise(vec2 p) {
	vec2 warp = vec2(
		noise(p + vec2(1.7, 9.2)),
		noise(p + vec2(8.3, 2.8)));
	return noise(p + warp * 0.4) * 0.6 + noise(p * 2.1 + vec2(5.2, 1.3)) * 0.4;
}

float fbm_octaves(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) break;
		value += amplitude * cheap_noise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// Cloud field based on layered value-noise fBm (ported from arlez80/cloud-shader, MIT).
// Returns gn in [0..1] where 1=no darkening, 0=fully dark cloud.
const float CLOUD_NOISE_SCALE = 0.00005;
const float CLOUD_SEED = -1000.0;
const vec2 CLOUD_SPEED = vec2(2.0, 0.0);
const vec2 CLOUD_TRANSFORM_SPEED = vec2(0.0, 0.0001);

highp float cloud_random(vec2 pos) {
	// Use continuous hash (avoid mod() discontinuities that can create line artifacts).
	return fract(sin(dot(pos, vec2(12.9898, 78.233))) * 43758.5453);
}

float cloud_value_noise(vec2 pos) {
	vec2 p = floor(pos);
	vec2 f = fract(pos);

	float v00 = cloud_random(p + vec2(0.0, 0.0));
	float v10 = cloud_random(p + vec2(1.0, 0.0));
	float v01 = cloud_random(p + vec2(0.0, 1.0));
	float v11 = cloud_random(p + vec2(1.0, 1.0));

	vec2 u = smoothstep(0.0, 1.0, f);
	return mix(mix(v00, v10, u.x), mix(v01, v11, u.x), u.y);
}

float _cloud_h(vec2 pos_a, vec2 pos_b) {
	float h = (
		cloud_value_noise(pos_a) * 8.0 +
		cloud_value_noise(pos_a * 4.2) * 8.0 +
		cloud_value_noise(pos_a * 8.4) * 8.0 +
		cloud_value_noise(pos_a * 17.6) * 8.0 +
		cloud_value_noise(pos_a * 61.8) * 4.0 +
		cloud_value_noise(pos_b * 90.1) * 4.0 +
		cloud_value_noise(pos_b * 110.1) * 0.0 +
		cloud_value_noise(pos_b * 220.0) * 0.0
	) / 46.0;
	return clamp(h, 0.0, 1.0);
}

float cloud_shadow_field(vec2 world_xz) {
	// Same CloudShadow.shader h computation, but keep it signed (h - bias) so we can anti-alias the threshold.
	float scale = global_noise_scale * 1250.0;
	vec2 p = world_xz * scale;
	vec2 pos_a = (vec2(p.x, p.y + CLOUD_SEED) + (TIME * CLOUD_SPEED)) * CLOUD_NOISE_SCALE;
	vec2 pos_b = pos_a + CLOUD_TRANSFORM_SPEED * TIME;

	// Blur/low-pass to reduce grid-aligned "digital camo" edges.
	vec2 o = vec2(0.37, 0.17);
	vec2 op = vec2(o.y, -o.x);
	float h = (
		_cloud_h(pos_a, pos_b) * 0.40 +
		_cloud_h(pos_a + o, pos_b + o) * 0.15 +
		_cloud_h(pos_a - o, pos_b - o) * 0.15 +
		_cloud_h(pos_a + op, pos_b + op) * 0.15 +
		_cloud_h(pos_a - op, pos_b - op) * 0.15
	);
	float bias = 0.4;
	return h - bias;
}

int get_material_index(vec4 vc_col_0, vec4 vc_col_1) {
	int index = 0;
	if (vc_col_0.r > 0.1) {
		if (vc_col_1.r > 0.1) index = 0;
		else if (vc_col_1.g > 0.1) index = 1;
		else if (vc_col_1.b > 0.1) index = 2;
		else if (vc_col_1.a > 0.1) index = 3;
	}
	else if (vc_col_0.g > 0.1) {
		if (vc_col_1.r > 0.1) index = 4;
		else if (vc_col_1.g > 0.1) index = 5;
		else if (vc_col_1.b > 0.1) index = 6;
		else if (vc_col_1.a > 0.1) index = 7;
	}
	else if (vc_col_0.b > 0.1) {
		if (vc_col_1.r > 0.1) index = 8;
		else if (vc_col_1.g > 0.1) index = 9;
		else if (vc_col_1.b > 0.1) index = 10;
		else if (vc_col_1.a > 0.1) index = 11;
	}
	else if (vc_col_0.a > 0.1) {
		if (vc_col_1.r > 0.1) index = 12;
		else if (vc_col_1.g > 0.1) index = 13;
		else if (vc_col_1.b > 0.1) index = 14;
		else if (vc_col_1.a > 0.1) index = 15;
	}
	return index;
}

float get_texture_scale(int index) {
	index = clamp(index, 0, 255);
	// Keep legacy VOID slot behavior (texture_15) scale = 1.0.
	if (index == 15) return 1.0;
	return max(tex_scales[index], 0.0001);
}

vec4 _palette_meta(int slot) {
	slot = clamp(slot, 0, 255);
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_meta_tex, vec2(0.5, v));
}

int _palette_count(int slot) {
	return int(round(_palette_meta(slot).r * 255.0));
}

int _palette_blend_mode(int slot) {
	return int(round(_palette_meta(slot).g * 255.0));
}

int _palette_has_outline(int slot) {
	return int(round(_palette_meta(slot).b * 255.0));
}

int _palette_outline_mode(int slot) {
	return int(round(_palette_meta(slot).a * 255.0));
}

vec4 sample_palette_entry(int slot, int color_idx) {
	slot = clamp(slot, 0, 255);
	int idx = clamp(color_idx, 0, 7);
	float u = (float(idx) + 0.5) / 8.0;
	float v = (float(slot) + 0.5) / 256.0;
	return texture(palette_colors_tex, vec2(u, v));
}

float sample_palette_weight(int slot, int color_idx) {
	slot = clamp(slot, 0, 255);
	int idx = clamp(color_idx, 0, 7);
	float u = (float(idx) + 0.5) / 8.0;
	float v = (float(slot) + 0.5) / 256.0;
	return max(texture(palette_weights_tex, vec2(u, v)).r, 0.0);
}

vec4 get_palette_color(int tex_idx, vec2 world_xz) {
	tex_idx = clamp(tex_idx, 0, 255);
	int color_count = _palette_count(tex_idx);

	if (color_count <= 0)
		return vec4(0.392, 0.471, 0.318, 1.0);
	if (color_count == 1)
		return sample_palette_entry(tex_idx, 0);

	int mode = _palette_blend_mode(tex_idx);

	// Single cheap noise sample — replaces 3x fbm calls
	vec2 p = vec2(
		world_xz.x * 0.06 + world_xz.y * 0.041 + world_pos.y * 0.06,
		world_xz.y * 0.06 - world_xz.x * 0.037 + world_pos.y * 0.038);
	float n = cheap_noise(p);
	n = smoothstep(0.0, 1.0, n);

	// Weighted distribution (values are normalized per slot).
	float ws[8];
	float total = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i < color_count) {
			float w = sample_palette_weight(tex_idx, i);
			ws[i] = w;
			total += w;
		} else {
			ws[i] = 0.0;
		}
	}
	if (total <= 0.0001) {
		total = float(color_count);
		for (int i = 0; i < 8; i++) {
			ws[i] = (i < color_count) ? 1.0 : 0.0;
		}
	}

	float x = clamp(n, 0.0, 1.0) * total;
	int i0 = 0;
	float start = 0.0;
	float w0 = ws[0];
	float cum = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= color_count) break;
		float wi = ws[i];
		if (x < cum + wi || i == color_count - 1) {
			i0 = i;
			start = cum;
			w0 = wi;
			break;
		}
		cum += wi;
	}
	int i1 = min(i0 + 1, color_count - 1);
	float t = 0.0;
	if (w0 > 0.00001) t = clamp((x - start) / w0, 0.0, 1.0);

	if (mode == 1) {
		// Retro: hard snap
		return sample_palette_entry(tex_idx, i0);

	} else if (mode == 2) {
		// Dithered (weight-aware)
		vec2 dither_coord = floor(vec2(
			world_xz.x + world_pos.y * 0.7,
			world_xz.y + world_pos.y * 1.3) * 8.0);
		float dither = hash(dither_coord);
		float sel = step(dither, t);
		return mix(sample_palette_entry(tex_idx, i0), sample_palette_entry(tex_idx, i1), sel);

	} else if (mode == 3) {
		// Stipple (weight-aware)
		float seam = 0.05;
		if (t < 0.5 - seam) {
			return sample_palette_entry(tex_idx, i0);
		} else if (t > 0.5 + seam) {
			return sample_palette_entry(tex_idx, i1);
		} else {
			vec3 checker_coord = floor(vec3(world_xz.x, world_pos.y, world_xz.y) * 4.0);
			float checker = mod(checker_coord.x + checker_coord.y + checker_coord.z, 2.0);
			return checker > 0.5 ? sample_palette_entry(tex_idx, i1) : sample_palette_entry(tex_idx, i0);
		}

	} else {
		// Gradient (weight-aware)
		return mix(sample_palette_entry(tex_idx, i0), sample_palette_entry(tex_idx, i1), smoothstep(0.0, 1.0, t));
	}
}

vec4 get_outline_palette_color(int slot) {
	slot = clamp(slot, 0, 255);
	int count = _palette_count(slot);
	if (count <= 0) return vec4(0.392, 0.471, 0.318, 1.0);

	int mode = _palette_outline_mode(slot);
	if (mode == 1) {
		// Use last palette color (Color N)
		return sample_palette_entry(slot, max(count - 1, 0));
	}

	// Darken first palette color (Color 1)
	vec4 c = sample_palette_entry(slot, 0);
	c.rgb *= 0.5;
	return c;
}

vec4 sample_texture_layer(int index, vec2 uv) {
	index = clamp(index, 0, 255);
	return texture(vc_tex_array, vec3(uv, float(index)));
}

vec4 sample_material_by_index_tint(int index, vec2 base_uv, vec4 tint) {
	float scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	return sample_texture_layer(index, uv) * tint;
}

vec4 sample_material_by_index(int index, vec2 base_uv) {
	float scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	vec4 tex = sample_texture_layer(index, uv);
	if (index == 15) return tex;
	return tex * get_palette_color(index, world_pos.xz);
}

void calculate_blend_weights(vec4 vc0, vec4 vc1, float sharpness, out float weights[16]) {
	float raw_weights[16];
	raw_weights[0]  = vc0.r * vc1.r;
	raw_weights[1]  = vc0.r * vc1.g;
	raw_weights[2]  = vc0.r * vc1.b;
	raw_weights[3]  = vc0.r * vc1.a;
	raw_weights[4]  = vc0.g * vc1.r;
	raw_weights[5]  = vc0.g * vc1.g;
	raw_weights[6]  = vc0.g * vc1.b;
	raw_weights[7]  = vc0.g * vc1.a;
	raw_weights[8]  = vc0.b * vc1.r;
	raw_weights[9]  = vc0.b * vc1.g;
	raw_weights[10] = vc0.b * vc1.b;
	raw_weights[11] = vc0.b * vc1.a;
	raw_weights[12] = vc0.a * vc1.r;
	raw_weights[13] = vc0.a * vc1.g;
	raw_weights[14] = vc0.a * vc1.b;
	raw_weights[15] = vc0.a * vc1.a;

	float power = 2.0 + sharpness * 2.0;
	float total = 0.0;
	for (int i = 0; i < 16; i++) {
		weights[i] = pow(max(raw_weights[i], 0.0), power);
		total += weights[i];
	}
	if (total > 0.001) {
		for (int i = 0; i < 16; i++) weights[i] /= total;
	} else {
		float max_raw = 0.0;
		int max_idx = 0;
		for (int i = 0; i < 16; i++) {
			if (raw_weights[i] > max_raw) { max_raw = raw_weights[i]; max_idx = i; }
		}
		for (int i = 0; i < 16; i++) weights[i] = (i == max_idx) ? 1.0 : 0.0;
	}
}

vec4 snap_to_dominant(vec4 c) {
	float max_val = max(max(c.r, c.g), max(c.b, c.a));
	if (max_val < 0.001) return vec4(1.0, 0.0, 0.0, 0.0);
	vec4 result = vec4(0.0);
	if (c.r >= max_val - 0.001) result.r = 1.0;
	else if (c.g >= max_val - 0.001) result.g = 1.0;
	else if (c.b >= max_val - 0.001) result.b = 1.0;
	else result.a = 1.0;
	return result;
}

vec4 blend_wall_materials(vec2 uv, vec4 vc0, vec4 vc1, float sharpness) {
	vec4 snapped_vc0 = snap_to_dominant(vc0);
	vec4 snapped_vc1 = snap_to_dominant(vc1);
	float weights[16];
	calculate_blend_weights(snapped_vc0, snapped_vc1, sharpness, weights);
	vec4 wall_color = vec4(0.0);
	float total_weight = 0.0;
	for (int i = 0; i < 16; i++) {
		if (weights[i] > 0.01) {
			wall_color += sample_material_by_index(i, uv) * weights[i];
			total_weight += weights[i];
		}
	}
	if (total_weight > 0.001) wall_color /= total_weight;
	return wall_color;
}

float get_world_noise(vec3 world_position, float tile_size) {
	vec2 noise_uv = world_position.xz * tile_size;
	return texture(rl_noise_texture, noise_uv).r;
}

void vertex() {
	vertex_normal = NORMAL;
	custom1 = CUSTOM1.rgb;
	float a = CUSTOM1.a;
	nearest_wall_color_idx = floor(a);
	seam_flag = step(0.25, fract(a));
#ifndef BAKE_MODE
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#else
	virtual_vertex = CUSTOM3.xyz;
	world_pos = (MODEL_MATRIX * vec4(virtual_vertex, 1.0)).xyz;
#endif
	vec2 rl_uv = UV;
	float rl_factor = max(rl_uv.x, rl_uv.y);
	ridge_blend_factor = vec4(step(ridge_threshold, rl_factor), 0.0, 0.0, 0.0);
	ledge_blend_factor = vec4(step(ledge_threshold, rl_factor), 0.0, 0.0, 0.0);

	vc_color_0 = COLOR;
	vc_color_1 = CUSTOM0;

	mat_indices = CUSTOM2.rgb;
	mat_weights = vec2(CUSTOM2.a, CUSTOM0.r);
	use_vertex_colors = 0.0;
	material_index = int(round(mat_indices.x));

	// Treat wall vertices explicitly via UV sentinel (walls use UV=(2,2)).
	bool is_floor = (UV.x < 1.5) && (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold);
	if (use_flat_normals && is_floor)
		NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#ifndef BAKE_MODE
	vec4 vertex_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
#else
	vec4 vertex_pos = INV_VIEW_MATRIX * vec4(virtual_vertex, 1.0);
#endif

	vec2 tiling_factor_floor = vec2(1.0 / float(chunk_size.x - 1), 1.0 / float(chunk_size.z - 1));
	vec2 tiling_factor_wall = vec2(1.0 / float(chunk_size.x - 1), 1.0 / float(chunk_size.y - 1));
	// Treat wall vertices explicitly via UV sentinel (walls use UV=(2,2)).
	bool is_floor = (UV.x < 1.5) && (dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold);

	vec3 abs_normal = abs(vertex_normal);
	vec3 tri_weights = vec3(abs_normal.x, 0.0, abs_normal.z);
	tri_weights /= (tri_weights.x + tri_weights.z);

	vec4 floor_color;
	vec3 wall_color;

	vec2 floor_uv = vec2(0.0);
	int edge_mat_a = -1;
	int edge_mat_b = -1;
	float edge_weight_a = 0.0;
	float edge_weight_b = 0.0;

	if (is_floor) {
		floor_uv = UV2 * tiling_factor_floor;

		if (use_hard_textures) {
			if (blend_mode == 2)
				floor_color = sample_material_by_index(material_index, floor_uv);
			else {
				int cell_dominant_mat = int(round(mat_indices.x));
				floor_color = sample_material_by_index(cell_dominant_mat, floor_uv);
			}
		}
		else {
			int mat_a = int(round(mat_indices.x));
			int mat_b = int(round(mat_indices.y));
			int mat_c = int(round(mat_indices.z));

			float weight_a = max(0.0, mat_weights.x);
			float weight_b = max(0.0, mat_weights.y);
			float weight_c = max(0.0, 1.0 - weight_a - weight_b);

			float weight_sum = weight_a + weight_b + weight_c;
			if (weight_sum > 0.001) {
				weight_a /= weight_sum;
				weight_b /= weight_sum;
				weight_c /= weight_sum;
			}

			if (blend_noise_strength > 0.0) {
				float n = noise(world_pos.xz * blend_noise_scale);
				float noise_offset = (n - 0.5) * blend_noise_strength;
				weight_a = clamp(weight_a + noise_offset, 0.0, 1.0);
				weight_b = clamp(weight_b - noise_offset * 0.5, 0.0, 1.0);
				weight_c = clamp(weight_c - noise_offset * 0.5, 0.0, 1.0);
				float total = weight_a + weight_b + weight_c;
				if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
			}

			if (blend_sharpness > 0.0) {
				float power = 1.0 + blend_sharpness;
				weight_a = pow(weight_a, power);
				weight_b = pow(weight_b, power);
				weight_c = pow(weight_c, power);
				float total = weight_a + weight_b + weight_c;
				if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
			}

			int top1_idx = mat_a;
			int top2_idx = mat_b;
			float top1_w = weight_a;
			float top2_w = weight_b;
			if (top2_w > top1_w) {
				int ti = top1_idx; top1_idx = top2_idx; top2_idx = ti;
				float tw = top1_w; top1_w = top2_w; top2_w = tw;
			}
			if (weight_c > top1_w) {
				top2_idx = top1_idx;
				top2_w = top1_w;
				top1_idx = mat_c;
				top1_w = weight_c;
			} else if (weight_c > top2_w) {
				top2_idx = mat_c;
				top2_w = weight_c;
			}

			edge_mat_a = top1_idx;
			edge_mat_b = top2_idx;
			edge_weight_a = top1_w;
			edge_weight_b = top2_w;

			floor_color = sample_material_by_index(mat_a, floor_uv) * weight_a
						+ sample_material_by_index(mat_b, floor_uv) * weight_b
						+ sample_material_by_index(mat_c, floor_uv) * weight_c;
		}

		ALBEDO = floor_color.rgb;
		ALPHA = floor_color.a;
	}
	else {
		vec2 uv_x = (vertex_pos.zy / cell_size.yx) * tiling_factor_wall;
		vec2 uv_z = (vertex_pos.xy / cell_size) * tiling_factor_wall;

		int mat_a = int(round(mat_indices.x));
		int mat_b = int(round(mat_indices.y));
		int mat_c = int(round(mat_indices.z));

		float weight_a = max(0.0, mat_weights.x);
		float weight_b = max(0.0, mat_weights.y);
		float weight_c = max(0.0, 1.0 - weight_a - weight_b);

		float weight_sum = weight_a + weight_b + weight_c;
		if (weight_sum > 0.001) {
			weight_a /= weight_sum;
			weight_b /= weight_sum;
			weight_c /= weight_sum;
		}

		if (blend_noise_strength > 0.0) {
			float n = noise(world_pos.xz * blend_noise_scale);
			float noise_offset = (n - 0.5) * blend_noise_strength;
			weight_a = clamp(weight_a + noise_offset, 0.0, 1.0);
			weight_b = clamp(weight_b - noise_offset * 0.5, 0.0, 1.0);
			weight_c = clamp(weight_c - noise_offset * 0.5, 0.0, 1.0);
			float total = weight_a + weight_b + weight_c;
			if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
		}

		if (blend_sharpness > 0.0) {
			float power = 1.0 + blend_sharpness;
			weight_a = pow(weight_a, power);
			weight_b = pow(weight_b, power);
			weight_c = pow(weight_c, power);
			float total = weight_a + weight_b + weight_c;
			if (total > 0.001) { weight_a /= total; weight_b /= total; weight_c /= total; }
		}

		vec4 wall_mat_x = sample_material_by_index(mat_a, uv_x) * weight_a
						+ sample_material_by_index(mat_b, uv_x) * weight_b
						+ sample_material_by_index(mat_c, uv_x) * weight_c;
		vec4 wall_mat_z = sample_material_by_index(mat_a, uv_z) * weight_a
						+ sample_material_by_index(mat_b, uv_z) * weight_b
						+ sample_material_by_index(mat_c, uv_z) * weight_c;

		ALBEDO = wall_mat_x.rgb * tri_weights.x + wall_mat_z.rgb * tri_weights.z;
		ALPHA = wall_mat_x.a;
	}

	float blend_noise = get_world_noise(vertex_pos.xyz, rl_noise_tile_size);
	float mixed_blend_factor = 0.0;
	vec3 mixed_triplanar_color;
	if (use_ledge_texture && custom1.b > 0.5 && is_floor) {
		mixed_blend_factor = ledge_blend_factor.x;
		if (rl_noise_strength > 0.0) {
			float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
			mixed_blend_factor = step(ledge_threshold + noise_variation, max(UV.x, UV.y));
		}
		vec3 rl_x = sample_material_by_index(int(nearest_wall_color_idx), UV2 * tiling_factor_wall).rgb * tri_weights.x;
		vec3 rl_z = sample_material_by_index(int(nearest_wall_color_idx), UV2 * tiling_factor_wall).rgb * tri_weights.z;
		ALBEDO = mix(floor_color.rgb, rl_x + rl_z, mixed_blend_factor);
	}
	else if (use_ridge_texture && custom1.g > 0.5 && is_floor) {
		mixed_blend_factor = ridge_blend_factor.x;
		if (rl_noise_strength > 0.0) {
			float noise_variation = (blend_noise - 0.5) * rl_noise_strength;
			mixed_blend_factor = step(ridge_threshold + noise_variation, max(UV.x, UV.y));
		}
		vec3 rl_x = sample_material_by_index(int(nearest_wall_color_idx), UV2 * tiling_factor_wall).rgb * tri_weights.x;
		vec3 rl_z = sample_material_by_index(int(nearest_wall_color_idx), UV2 * tiling_factor_wall).rgb * tri_weights.z;
		ALBEDO = mix(floor_color.rgb, rl_x + rl_z, mixed_blend_factor);
	}

	// Inner outlines (white): screen-space variant (can be jittery). Kept for optional use.
	if (use_edge_highlights && is_floor) {
		float dz = abs(dFdx(FRAGCOORD.z)) + abs(dFdy(FRAGCOORD.z));
		float dzm = dz * max(inner_outline_depth_scale, 0.0);

		float inner = smoothstep(inner_outline_threshold, inner_outline_threshold + max(inner_outline_softness, 0.00001), dzm);
		float sil = smoothstep(inner_outline_silhouette_threshold, inner_outline_silhouette_threshold + max(inner_outline_silhouette_softness, 0.00001), dzm);
		inner *= (1.0 - sil);

		vec3 n = normalize(vertex_normal);
		float dn = (length(dFdx(n)) + length(dFdy(n))) * edge_highlight_normal_weight;
		float crease = smoothstep(edge_highlight_threshold, edge_highlight_threshold + max(edge_highlight_softness, 0.00001), dn * (max(edge_highlight_width, 0.0) * 0.35));

		float mask = clamp(max(inner, crease), 0.0, 1.0);
		mask = pow(mask, edge_highlight_power);

		float amt = clamp(mask * edge_highlight_strength, 0.0, 1.0);
		ALBEDO = mix(ALBEDO, edge_highlight_color.rgb, amt);
	}

	// Stable outline at floor/wall junction + along wall face edges.
	// seam_flag ensures we only draw this where the cell actually contains a wall/cliff.
	if (use_seam_outline && seam_flag > 0.5) {
		float amt = 0.0;
		if (is_floor) {
			// Floor rim: thin band at the terrace edge.
			float t = max(UV.x, UV.y);
			float band = max(fwidth(t) * seam_outline_width, 0.0001);
			amt = smoothstep(1.0 - band, 1.0, t);
		} else {
			// Walls: outer-boundary outline is generated by a separate mesh (to avoid per-cell striping).
			amt = 0.0;
		}
		amt = clamp(amt * seam_outline_strength, 0.0, 1.0);

		vec3 target_rgb = seam_outline_color.rgb;
		if (seam_outline_from_albedo) {
			vec3 base = ALBEDO;
			vec3 lifted = base;
			if (seam_outline_lift > 0.0) {
				lifted = mix(base, vec3(1.0), seam_outline_lift);
			} else if (seam_outline_lift < 0.0) {
				lifted = mix(base, vec3(0.0), -seam_outline_lift);
			}
			// Allow a subtle tint bias while still preserving hue by default (rgb = 1,1,1).
			target_rgb = lifted * seam_outline_color.rgb;
		}

		ALBEDO = mix(ALBEDO, target_rgb, amt * seam_outline_color.a);
	}

	// Material outlines ("land foam" style). Uses weight equality band, so it doesn't widen with brush falloff.
	if (is_floor) {
		if (edge_mat_a >= 0 && edge_mat_b >= 0
				&& edge_mat_a != edge_mat_b
				&& edge_mat_a >= 0 && edge_mat_a < 256 && edge_mat_b >= 0 && edge_mat_b < 256
				&& edge_weight_b > 0.001) {

			int ha = _palette_has_outline(edge_mat_a);
			int hb = _palette_has_outline(edge_mat_b);
			int outline_slot = -1;
			if (ha == 1 && hb == 0) outline_slot = edge_mat_a;
			else if (hb == 1 && ha == 0) outline_slot = edge_mat_b;
			else if (ha == 1 && hb == 1) outline_slot = min(edge_mat_a, edge_mat_b);

			if (outline_slot >= 0) {
				float min_w = min(edge_weight_a, edge_weight_b);
				float diff = edge_weight_a - edge_weight_b;
				float d = abs(diff);
				float fw = fwidth(diff);
				float band = max(fw * outline_width, 0.0001);
				float mask = 1.0 - smoothstep(0.0, band, d);
				mask *= smoothstep(0.0, 0.15, min_w);


				vec4 tint = get_outline_palette_color(outline_slot);
				vec3 outline_rgb = sample_material_by_index_tint(outline_slot, floor_uv, tint).rgb;
				ALBEDO = mix(ALBEDO, outline_rgb, mask);
			}
		}
	}


	if (global_noise_strength > 0.0) {
		vec2 scroll = vec2(0.0);
		if (global_noise_scroll > 0.0) {
			vec2 dir = normalize(wind_direction);
			scroll = dir * TIME * wind_speed * 3.0 * global_noise_scroll;
		}

		vec2 uv = (vec2(world_pos.x, world_pos.z) + scroll) * global_noise_scale;
		uv = fract(uv);

		float gn = texture(global_noise_texture, uv).r;
		float mult = mix(1.0 - global_noise_strength, 1.0, clamp(gn, 0.0, 1.0));
		ALBEDO *= mult;
	}

}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float stepped = use_cell_shading ? (ceil(NdotL * float(bands)) / float(bands)) : NdotL;

	// Base toon weight (before attenuation).
	float toon_weight = use_cell_shading
		? mix(shadow_intensity, 0.3, stepped)
		: (NdotL * 0.3);

	// Edge Highlights are currently implemented in fragment() as a black outline.

	float toon_light = toon_weight * ATTENUATION;
	DIFFUSE_LIGHT += mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
}