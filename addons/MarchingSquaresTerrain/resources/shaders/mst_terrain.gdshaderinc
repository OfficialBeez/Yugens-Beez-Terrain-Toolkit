group_uniforms Terrain.Properties;
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec2 cell_size = vec2(2.0, 2.0);
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
group_uniforms;

group_uniforms Visuals.Palette;
uniform vec4 slot_colors[120]; // 15 slots * 8 colors max — indexed as slot * 8 + color_idx
uniform float slot_color_weights[120];
uniform int slot_color_counts[15];
uniform int slot_blend_modes[15];
// Outline settings (per slot)
// slot_has_outline[slot] = 1 enables outlines for that texture slot.
// slot_outline_modes[slot]: 0 = darken Color 1, 1 = use last palette color.
uniform int slot_has_outline[15];
uniform int slot_outline_modes[15];
// Controls outline thickness. Higher = thicker.
uniform float outline_width : hint_range(0.25, 32.0, 0.25) = 6.0;

group_uniforms;

group_uniforms Visuals.Vertex_Painting;
uniform sampler2D vc_tex_rr : source_color, filter_nearest;
uniform sampler2D vc_tex_rg : source_color, filter_nearest;
uniform sampler2D vc_tex_rb : source_color, filter_nearest;
uniform sampler2D vc_tex_ra : source_color, filter_nearest;
uniform sampler2D vc_tex_gr : source_color, filter_nearest;
uniform sampler2D vc_tex_gg : source_color, filter_nearest;
uniform sampler2D vc_tex_gb : source_color, filter_nearest;
uniform sampler2D vc_tex_ga : source_color, filter_nearest;
uniform sampler2D vc_tex_br : source_color, filter_nearest;
uniform sampler2D vc_tex_bg : source_color, filter_nearest;
uniform sampler2D vc_tex_bb : source_color, filter_nearest;
uniform sampler2D vc_tex_ba : source_color, filter_nearest;
uniform sampler2D vc_tex_ar : source_color, filter_nearest;
uniform sampler2D vc_tex_ag : source_color, filter_nearest;
uniform sampler2D vc_tex_ab : source_color, filter_nearest;
uniform sampler2D vc_tex_aa : source_color, filter_nearest;
group_uniforms;

group_uniforms Visuals.Texture_Scales;
uniform float tex_scale_1 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_2 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_3 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_4 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_5 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_6 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_7 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_8 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_9 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_10 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_11 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_12 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_13 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_14 : hint_range(0.1, 20.0, 0.1) = 1.0;
uniform float tex_scale_15 : hint_range(0.1, 20.0, 0.1) = 1.0;
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
group_uniforms;

group_uniforms CellShading;
uniform bool use_cell_shading = true;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
group_uniforms;

varying vec3 vertex_normal;
varying vec3 custom1;
varying flat float nearest_wall_color_idx;
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
	switch(index) {
		case 0: return tex_scale_1;
		case 1: return tex_scale_2;
		case 2: return tex_scale_3;
		case 3: return tex_scale_4;
		case 4: return tex_scale_5;
		case 5: return tex_scale_6;
		case 6: return tex_scale_7;
		case 7: return tex_scale_8;
		case 8: return tex_scale_9;
		case 9: return tex_scale_10;
		case 10: return tex_scale_11;
		case 11: return tex_scale_12;
		case 12: return tex_scale_13;
		case 13: return tex_scale_14;
		case 14: return tex_scale_15;
		default: return 1.0;
	}
}

vec4 sample_palette_entry(int slot, int color_idx) {
	return slot_colors[slot * 8 + clamp(color_idx, 0, 7)];
}

vec4 get_palette_color(int tex_idx, vec2 world_xz) {
	int color_count = slot_color_counts[tex_idx];

	if (color_count <= 0)
		return vec4(0.392, 0.471, 0.318, 1.0);
	if (color_count == 1)
		return slot_colors[tex_idx * 8];

	int mode = slot_blend_modes[tex_idx];

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
			float w = max(slot_color_weights[tex_idx * 8 + i], 0.0);
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
	int count = slot_color_counts[slot];
	if (count <= 0) return vec4(0.392, 0.471, 0.318, 1.0);

	int mode = slot_outline_modes[slot];
	if (mode == 1) {
		// Use last palette color (Color N)
		return sample_palette_entry(slot, max(count - 1, 0));
	}

	// Darken first palette color (Color 1)
	vec4 c = sample_palette_entry(slot, 0);
	c.rgb *= 0.5;
	return c;
}

vec4 sample_material_by_index_tint(int index, vec2 base_uv, vec4 tint) {
	float scale = 1.0;
	if (index != 15)
		scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	vec4 result = vec4(1.0);
	switch(index) {
		case 0:  result = texture(vc_tex_rr, uv) * tint; break;
		case 1:  result = texture(vc_tex_rg, uv) * tint; break;
		case 2:  result = texture(vc_tex_rb, uv) * tint; break;
		case 3:  result = texture(vc_tex_ra, uv) * tint; break;
		case 4:  result = texture(vc_tex_gr, uv) * tint; break;
		case 5:  result = texture(vc_tex_gg, uv) * tint; break;
		case 6:  result = texture(vc_tex_gb, uv) * tint; break;
		case 7:  result = texture(vc_tex_ga, uv) * tint; break;
		case 8:  result = texture(vc_tex_br, uv) * tint; break;
		case 9:  result = texture(vc_tex_bg, uv) * tint; break;
		case 10: result = texture(vc_tex_bb, uv) * tint; break;
		case 11: result = texture(vc_tex_ba, uv) * tint; break;
		case 12: result = texture(vc_tex_ar, uv) * tint; break;
		case 13: result = texture(vc_tex_ag, uv) * tint; break;
		case 14: result = texture(vc_tex_ab, uv) * tint; break;
		case 15: result = texture(vc_tex_aa, uv) * tint; break;
		default: result = texture(vc_tex_rr, uv) * tint; break;
	}
	return result;
}

vec4 sample_material_by_index(int index, vec2 base_uv) {
	float scale = 1.0;
	if (index != 15)
		scale = get_texture_scale(index);
	vec2 uv = base_uv * scale;
	vec4 result = vec4(1.0);
	switch(index) {
		case 0:  result = texture(vc_tex_rr, uv) * get_palette_color(0,  world_pos.xz); break;
		case 1:  result = texture(vc_tex_rg, uv) * get_palette_color(1,  world_pos.xz); break;
		case 2:  result = texture(vc_tex_rb, uv) * get_palette_color(2,  world_pos.xz); break;
		case 3:  result = texture(vc_tex_ra, uv) * get_palette_color(3,  world_pos.xz); break;
		case 4:  result = texture(vc_tex_gr, uv) * get_palette_color(4,  world_pos.xz); break;
		case 5:  result = texture(vc_tex_gg, uv) * get_palette_color(5,  world_pos.xz); break;
		case 6:  result = texture(vc_tex_gb, uv) * get_palette_color(6,  world_pos.xz); break;
		case 7:  result = texture(vc_tex_ga, uv) * get_palette_color(7,  world_pos.xz); break;
		case 8:  result = texture(vc_tex_br, uv) * get_palette_color(8,  world_pos.xz); break;
		case 9:  result = texture(vc_tex_bg, uv) * get_palette_color(9,  world_pos.xz); break;
		case 10: result = texture(vc_tex_bb, uv) * get_palette_color(10, world_pos.xz); break;
		case 11: result = texture(vc_tex_ba, uv) * get_palette_color(11, world_pos.xz); break;
		case 12: result = texture(vc_tex_ar, uv) * get_palette_color(12, world_pos.xz); break;
		case 13: result = texture(vc_tex_ag, uv) * get_palette_color(13, world_pos.xz); break;
		case 14: result = texture(vc_tex_ab, uv) * get_palette_color(14, world_pos.xz); break;
		case 15: result = texture(vc_tex_aa, uv); break;
		default: result = texture(vc_tex_rr, uv) * get_palette_color(0,  world_pos.xz); break;
	}
	return result;
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
	nearest_wall_color_idx = CUSTOM1.a;
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

	material_index = get_material_index(COLOR, CUSTOM0);
	vc_color_0 = COLOR;
	vc_color_1 = CUSTOM0;

	float packed_mats = CUSTOM2.r * 255.0;
	mat_indices.x = mod(packed_mats, 16.0) / 15.0;
	mat_indices.y = floor(packed_mats / 16.0) / 15.0;
	mat_indices.z = CUSTOM2.g;
	mat_weights = vec2(CUSTOM2.b, CUSTOM2.a);
	use_vertex_colors = CUSTOM2.a >= 1.5 ? 1.0 : 0.0;

	bool is_floor = dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold;
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
	bool is_floor = dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold;

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
				int cell_dominant_mat = int(round(mat_indices.x * 15.0));
				floor_color = sample_material_by_index(cell_dominant_mat, floor_uv);
			}
		}
		else if (use_vertex_colors > 0.5) {
			float weights[16];
			float effective_sharpness = blend_sharpness;
			if (blend_noise_strength > 0.0) {
				float n = noise(world_pos.xz * blend_noise_scale);
				effective_sharpness = mix(blend_sharpness, blend_sharpness * (0.5 + n), blend_noise_strength);
			}
			calculate_blend_weights(vc_color_0, vc_color_1, effective_sharpness, weights);

			float top1_w = 0.0;
			float top2_w = 0.0;
			int top1_idx = 0;
			int top2_idx = 0;

			floor_color = vec4(0.0);
			for (int i = 0; i < 16; i++) {
				float w = weights[i];
				if (w > 0.01)
					floor_color += sample_material_by_index(i, floor_uv) * w;

				if (w > top1_w) {
					top2_w = top1_w;
					top2_idx = top1_idx;
					top1_w = w;
					top1_idx = i;
				} else if (w > top2_w) {
					top2_w = w;
					top2_idx = i;
				}
			}

			edge_mat_a = top1_idx;
			edge_mat_b = top2_idx;
			edge_weight_a = top1_w;
			edge_weight_b = top2_w;
		}
		else {
			int mat_a = int(round(mat_indices.x * 15.0));
			int mat_b = int(round(mat_indices.y * 15.0));
			int mat_c = int(round(mat_indices.z * 15.0));

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

		float effective_sharpness = blend_sharpness;
		if (blend_noise_strength > 0.0) {
			float n = noise(world_pos.xz * blend_noise_scale);
			effective_sharpness = mix(blend_sharpness, blend_sharpness * (0.5 + n), blend_noise_strength);
		}

		vec4 wall_mat_x = blend_wall_materials(uv_x, vc_color_0, vc_color_1, effective_sharpness);
		vec4 wall_mat_z = blend_wall_materials(uv_z, vc_color_0, vc_color_1, effective_sharpness);

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

	// Material outlines ("land foam" style). Uses weight equality band, so it doesn't widen with brush falloff.
	if (is_floor) {
		if (edge_mat_a >= 0 && edge_mat_b >= 0
				&& edge_mat_a != edge_mat_b
				&& edge_mat_a < 15 && edge_mat_b < 15
				&& edge_weight_b > 0.001) {

			int ha = slot_has_outline[edge_mat_a];
			int hb = slot_has_outline[edge_mat_b];
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

	if (is_floor && global_noise_strength > 0.0) {
		float gn = cheap_noise(vec2(
			vertex_pos.x * global_noise_scale + vertex_pos.z * 0.031,
			vertex_pos.z * global_noise_scale - vertex_pos.x * 0.023));
		gn = smoothstep(0.0, 1.0, gn);
		ALBEDO *= mix(1.0 - global_noise_strength, 1.0 + (global_noise_strength * 0.5), gn);
	}
}

void light() {
	float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float toon_light;
	if (use_cell_shading) {
		float stepped = ceil(NdotL * float(bands)) / float(bands);
		toon_light = mix(shadow_intensity, 0.3, stepped);
	} else {
		toon_light = NdotL * 0.3;
	}
	toon_light *= ATTENUATION;
	DIFFUSE_LIGHT += mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);
}