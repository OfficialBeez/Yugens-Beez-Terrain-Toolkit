extends RefCounted
class_name MarchingSquaresTerrainVertexColorHelper


# < 1.0 = more aggressive wall detection 
# > 1.0 = less aggressive / more slope blend
const BLEND_EDGE_SENSITIVITY : float = 1.25

# Cell height range for boundary detection (height-based color sampling)
var cell_min_height : float
var cell_max_height : float
# Height-based material colors for FLOOR boundary cells (prevents color bleeding between heights)
var cell_floor_lower_color_0 : Color
var cell_floor_upper_color_0 : Color
var cell_floor_lower_color_1 : Color
var cell_floor_upper_color_1 : Color
# Height-based material colors for WALL/RIDGE boundary cells
var cell_wall_lower_color_0 : Color
var cell_wall_upper_color_0 : Color
var cell_wall_lower_color_1 : Color
var cell_wall_upper_color_1 : Color
var cell_is_boundary : bool = false
# Per-cell materials for to supports up to 3 textures
var cell_mat_a : int = 0
var cell_mat_b : int = 0
var cell_mat_c : int = 0
var cell_weight_b : float = 0.0

# NOTE: Untyped to avoid @tool cyclic load issues (chunk <-> helper <-> cell).
var chunk
var cell


func blend_colors(vertex: Vector3, uv: Vector2, diag_midpoint: bool = false) -> Dictionary[String, Color]:
	var colors : Dictionary[String, Color] = {}
	var blend_threshold : float = cell.merge_threshold * BLEND_EDGE_SENSITIVITY # COMMENT: We can tweak the BLEND_EDGE_SENSITIVITY to allow more "agressive" Cliff vs Slope detection
	var blend_ab : bool = abs(cell.ay-cell.by) < blend_threshold
	var blend_ac : bool = abs(cell.ay-cell.cy) < blend_threshold
	var blend_bd : bool = abs(cell.by-cell.dy) < blend_threshold
	var blend_cd : bool = abs(cell.cy-cell.dy) < blend_threshold
	var cell_has_walls_for_blend : bool = not (blend_ab and blend_ac and blend_bd and blend_cd)
	
	# Detect ridge BEFORE selecting color maps (ridge needs wall colors, not ground colors)
	var is_ridge = cell.floor_mode and (uv.y > 0.0)
	var is_ledge = cell.floor_mode and (uv.x > 0.0)
	
	# Get color source maps based on floor/wall/ridge state
	var sources = _get_color_sources(cell.floor_mode)
	var source_map_0 : PackedColorArray = sources[0]
	var source_map_1 : PackedColorArray = sources[1]
	var rl_source_map_0 : PackedColorArray = sources[2]
	var rl_source_map_1 : PackedColorArray = sources[3]
	var use_wall_colors = (source_map_0 == chunk.wall_color_map_0)
	
	# Terrain texturing is driven by CUSTOM2 (and weight_b in CUSTOM0.r).
	# COLOR/CUSTOM0 are no longer used to encode the material index directly.
	colors["color_0"] = Color(0, 0, 0, 0)
	colors["color_1"] = Color(0, 0, 0, 0) # CUSTOM0.r is set after blend data is calculated.
	
	# is_ridge & is_ledge are already calculated above
	var c_1_val: Color = Color(chunk.grass_mask_map[cell.cell_coords.y*chunk.dimensions.x + cell.cell_coords.x]) # Grass mask
	c_1_val.g = 1.0 if is_ridge else 0.0
	c_1_val.b = 1.0 if is_ledge else 0.0
	
	# Calculate and store the closest wall color index to the ridge/ledge.
	# With 256 slots, we can no longer rely on the legacy one-hot interpolation.
	# Instead, pick the highest-weight corner's wall index.
	var x = cell.cell_coords.x
	var z = cell.cell_coords.y
	var base = z * chunk.dimensions.x + x
	var w_a = (1.0 - vertex.x) * (1.0 - vertex.z)
	var w_b = vertex.x * (1.0 - vertex.z)
	var w_c = (1.0 - vertex.x) * vertex.z
	var w_d = vertex.x * vertex.z
	
	var wall_a = get_texture_index_from_colors(chunk.wall_color_map_0[base], chunk.wall_color_map_1[base])
	var wall_b = get_texture_index_from_colors(chunk.wall_color_map_0[base + 1], chunk.wall_color_map_1[base + 1])
	var wall_c = get_texture_index_from_colors(chunk.wall_color_map_0[base + chunk.dimensions.x], chunk.wall_color_map_1[base + chunk.dimensions.x])
	var wall_d = get_texture_index_from_colors(chunk.wall_color_map_0[base + chunk.dimensions.x + 1], chunk.wall_color_map_1[base + chunk.dimensions.x + 1])
	
	var rl_idx = wall_a
	var best_w = w_a
	if w_b > best_w: best_w = w_b; rl_idx = wall_b
	if w_c > best_w: best_w = w_c; rl_idx = wall_c
	if w_d > best_w: rl_idx = wall_d
	
	c_1_val.a = rl_idx
	colors["custom_1_value"] = c_1_val
	
	# Material blend data is always driven by the CUSTOM2 encoding.
	colors["mat_blend"] = calculate_material_blend_data(vertex.x, vertex.z, source_map_0, source_map_1)
	colors["color_1"].r = cell_weight_b
	return colors


func calculate_corner_colors():
	# Calculate cell height range for boundary detection (height-based color sampling)
	cell_min_height = min(cell.ay, cell.by, cell.cy, cell.dy)
	cell_max_height = max(cell.ay, cell.by, cell.cy, cell.dy)
	
	var x = cell.cell_coords.x
	var z = cell.cell_coords.y
	
	# Determine if this is a boundary cell (significant height variation)
	cell_is_boundary = (cell_max_height - cell_min_height) > cell.merge_threshold
	
	# Calculate the 2 dominant textures for this cell
	calculate_cell_material_pair(chunk.color_map_0, chunk.color_map_1)
	
	if cell_is_boundary:
		# Identify corners at each height level for height-based color sampling
		# FLOOR colors - from color_map (used for regular floor vertices)
		var floor_corner_color_0s = [
			chunk.color_map_0[z * chunk.dimensions.x + x],           # A (top-left)
			chunk.color_map_0[z * chunk.dimensions.x + x + 1],       # B (top-right)
			chunk.color_map_0[(z + 1) * chunk.dimensions.x + x],     # C (bottom-left)
			chunk.color_map_0[(z + 1) * chunk.dimensions.x + x + 1]  # D (bottom-right)
		]
		var floor_corner_color_1s = [
			chunk.color_map_1[z * chunk.dimensions.x + x],
			chunk.color_map_1[z * chunk.dimensions.x + x + 1],
			chunk.color_map_1[(z + 1) * chunk.dimensions.x + x],
			chunk.color_map_1[(z + 1) * chunk.dimensions.x + x + 1]
		]
		# WALL colors - from wall_color_map (used for wall/ridge vertices)
		var wall_corner_color_0s = [
			chunk.wall_color_map_0[z * chunk.dimensions.x + x],           # A (top-left)
			chunk.wall_color_map_0[z * chunk.dimensions.x + x + 1],       # B (top-right)
			chunk.wall_color_map_0[(z + 1) * chunk.dimensions.x + x],     # C (bottom-left)
			chunk.wall_color_map_0[(z + 1) * chunk.dimensions.x + x + 1]  # D (bottom-right)
		]
		var wall_corner_color_1s = [
			chunk.wall_color_map_1[z * chunk.dimensions.x + x],
			chunk.wall_color_map_1[z * chunk.dimensions.x + x + 1],
			chunk.wall_color_map_1[(z + 1) * chunk.dimensions.x + x],
			chunk.wall_color_map_1[(z + 1) * chunk.dimensions.x + x + 1]
		]
		var corner_heights = [cell.ay, cell.by, cell.cy, cell.dy]
		
		# Find corners at min and max height
		var min_idx = 0
		var max_idx = 0
		for i in range(4):
			if corner_heights[i] < corner_heights[min_idx]:
				min_idx = i
			if corner_heights[i] > corner_heights[max_idx]:
				max_idx = i
		
		# Floor boundary colors (from ground color_map)
		cell_floor_lower_color_0 = floor_corner_color_0s[min_idx]
		cell_floor_upper_color_0 = floor_corner_color_0s[max_idx]
		cell_floor_lower_color_1 = floor_corner_color_1s[min_idx]
		cell_floor_upper_color_1 = floor_corner_color_1s[max_idx]
		# Wall boundary colors (from wall_color_map)
		cell_wall_lower_color_0 = wall_corner_color_0s[min_idx]
		cell_wall_upper_color_0 = wall_corner_color_0s[max_idx]
		cell_wall_lower_color_1 = wall_corner_color_1s[min_idx]
		cell_wall_upper_color_1 = wall_corner_color_1s[max_idx]

#region cell_geometry helpers & calculation functions and color interpolation helpers

## Returns 4 source_maps based on floor/wall[0][1] state, and for setting ridge/ledge[2][3] textures.
func _get_color_sources(is_floor: bool) -> Array[PackedColorArray]:
	var use_wall_colors = not is_floor
	
	var src_0 : PackedColorArray = chunk.wall_color_map_0 if use_wall_colors else chunk.color_map_0
	var src_1 : PackedColorArray = chunk.wall_color_map_1 if use_wall_colors else chunk.color_map_1
	var rl_src_0 : PackedColorArray = chunk.wall_color_map_0
	var rl_src_1 : PackedColorArray = chunk.wall_color_map_1
	return [src_0, src_1, rl_src_0, rl_src_1]


## Calculates color for diagonal midpoint vertices.
func _calc_diagonal_color(source_map: PackedColorArray) -> Color:
	if chunk.terrain_system.blend_mode == 1:
		# Hard edge mode uses same color as cell's top-left corner
		return source_map[cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x]
	
	# Smooth blend mode - lerp diagonal corners for smoother effect
	var idx = cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x
	var ad_color : Color = lerp(source_map[idx], source_map[idx + chunk.dimensions.x + 1], 0.5)
	var bc_color : Color = lerp(source_map[idx + 1], source_map[idx + chunk.dimensions.x], 0.5)
	var result = Color(min(ad_color.r, bc_color.r), min(ad_color.g, bc_color.g), min(ad_color.b, bc_color.b), min(ad_color.a, bc_color.a))
	if ad_color.r > 0.99 or bc_color.r > 0.99: result.r = 1.0
	if ad_color.g > 0.99 or bc_color.g > 0.99: result.g = 1.0
	if ad_color.b > 0.99 or bc_color.b > 0.99: result.b = 1.0
	if ad_color.a > 0.99 or bc_color.a > 0.99: result.a = 1.0
	return result


## Calculates height-based color for boundary cells (prevents color bleeding between heights).
func _calc_boundary_color(y: float, source_map: PackedColorArray, lower_color: Color, upper_color: Color) -> Color:
	if chunk.terrain_system.blend_mode == 1:
		# Hard edge mode uses cell's corner color
		return source_map[cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x]
	
	# HEIGHT-BASED SAMPLING for smooth blend mode
	var height_range = cell_max_height - cell_min_height
	var height_factor : float = clamp((y - cell_min_height) / height_range, 0.0, 1.0)
	
	# Sharp bands: < lower_thresh = lower color, > upper_thresh = upper color, middle = blend
	var color : Color
	if height_factor < chunk.lower_thresh:
		color = lower_color
	elif height_factor > chunk.upper_thresh:
		color = upper_color
	else:
		var blend_factor : float = (height_factor - chunk.lower_thresh) / chunk.blend_zone
		color = lerp(lower_color, upper_color, blend_factor)
	
	return get_dominant_color(color)


## Calculates bilinearly interpolated color for flat cells.
func _calc_bilinear_color(x: float, z: float, source_map: PackedColorArray) -> Color:
	var idx = cell.cell_coords.y * chunk.dimensions.x + cell.cell_coords.x
	var ab_color : Color = lerp(source_map[idx], source_map[idx + 1], x)
	var cd_color : Color = lerp(source_map[idx + chunk.dimensions.x], source_map[idx + chunk.dimensions.x + 1], x)
	
	if chunk.terrain_system.blend_mode != 1:
		return get_dominant_color(lerp(ab_color, cd_color, z))  # Mixed triangles
	return source_map[idx]  # hard squares/hard triangles


## Selects the appropriate color interpolation method.
func _interpolate_vertex_color(
	x: float, y: float, z: float,
	source_map: PackedColorArray,
	diag_midpoint: bool,
	lower_color: Color,
	upper_color: Color
	) -> Color:
	if diag_midpoint:
		return _calc_diagonal_color(source_map)
	
	if cell_is_boundary:
		return _calc_boundary_color(y, source_map, lower_color, upper_color)
	
	return _calc_bilinear_color(x, z, source_map)


static func get_dominant_color(c: Color) -> Color:
	var max_val = c.r
	var idx : int = 0
	
	if c.g > max_val:
		max_val = c.g
		idx = 1
	if c.b > max_val:
		max_val = c.b
		idx = 2
	if c.a > max_val:
		idx = 3
	
	var new_color = Color(0, 0, 0, 0)
	match idx:
		0: new_color.r = 1.0
		1: new_color.g = 1.0
		2: new_color.b = 1.0
		3: new_color.a = 1.0
	
	return new_color


# Convert color pair to texture index (0-255).
# Supports both legacy 4×4 channel encoding (0-15) and the new byte encoding.
func get_texture_index_from_colors(c0: Color, c1: Color) -> int:
	var c0_sum = c0.r + c0.g + c0.b + c0.a
	var c1_sum = c1.r + c1.g + c1.b + c1.a
	var c0_max = max(max(c0.r, c0.g), max(c0.b, c0.a))
	var c1_max = max(max(c1.r, c1.g), max(c1.b, c1.a))
	var looks_legacy = (abs(c0_sum - 1.0) < 0.01 and abs(c1_sum - 1.0) < 0.01 and c0_max > 0.99 and c1_max > 0.99)
	if looks_legacy:
		var c0_idx = 0
		var c0_m = c0.r
		if c0.g > c0_m: c0_m = c0.g; c0_idx = 1
		if c0.b > c0_m: c0_m = c0.b; c0_idx = 2
		if c0.a > c0_m: c0_idx = 3
		
		var c1_idx = 0
		var c1_m = c1.r
		if c1.g > c1_m: c1_m = c1.g; c1_idx = 1
		if c1.b > c1_m: c1_m = c1.b; c1_idx = 2
		if c1.a > c1_m: c1_idx = 3
		
		return c0_idx * 4 + c1_idx
	
	return clampi(int(round(clampf(c0.r, 0.0, 1.0) * 255.0)), 0, 255)


# Convert texture index (0-255) to color pair.
func texture_index_to_colors(idx: int) -> Array[Color]:
	idx = clampi(idx, 0, 255)
	return [Color(float(idx) / 255.0, 0, 0, 0), Color(0, 0, 0, 0)]


# Calculate 2 dominant textures for current cell 
func calculate_cell_material_pair(source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> void:
	var cell_coords = cell.cell_coords
	var tex_a : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x])
	var tex_b : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1])
	var tex_c : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x])
	var tex_d : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1])
	
	var tex_counts : Dictionary = {}
	tex_counts[tex_a] = tex_counts.get(tex_a, 0) + 1
	tex_counts[tex_b] = tex_counts.get(tex_b, 0) + 1
	tex_counts[tex_c] = tex_counts.get(tex_c, 0) + 1
	tex_counts[tex_d] = tex_counts.get(tex_d, 0) + 1
	
	var sorted_textures : Array = tex_counts.keys()
	sorted_textures.sort_custom(func(a, b): return tex_counts[a] > tex_counts[b])
	
	cell_mat_a = sorted_textures[0]
	cell_mat_b = sorted_textures[1] if sorted_textures.size() > 1 else sorted_textures[0]
	cell_mat_c = sorted_textures[2] if sorted_textures.size() > 2 else cell_mat_b


# Calculate blend data for up to 3 textures.
# New encoding for 256 slots:
#   CUSTOM2.rgb = mat_a, mat_b, mat_c (0..255) as floats
#   CUSTOM2.a   = weight_a (0..1)
#   CUSTOM0.r   = weight_b (0..1)
func calculate_material_blend_data(vert_x: float, vert_z: float, source_map_0: PackedColorArray, source_map_1: PackedColorArray) -> Color:
	var cell_coords = cell.cell_coords
	var tex_a : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x])
	var tex_b : int = get_texture_index_from_colors(
		source_map_0[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[cell_coords.y * chunk.dimensions.x + cell_coords.x + 1])
	var tex_c : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x])
	var tex_d : int = get_texture_index_from_colors(
		source_map_0[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1],
		source_map_1[(cell_coords.y + 1) * chunk.dimensions.x + cell_coords.x + 1])
	
	# Position weights for bilinear interpolation
	var w_a : float = (1.0 - vert_x) * (1.0 - vert_z)
	var w_b : float = vert_x * (1.0 - vert_z)
	var w_c : float = (1.0 - vert_x) * vert_z
	var w_d : float = vert_x * vert_z
	
	# Accumulate weights for all 3 cell materials
	var weight_mat_a : float = 0.0
	var weight_mat_b : float = 0.0
	var weight_mat_c : float = 0.0
	
	if tex_a == cell_mat_a: weight_mat_a += w_a
	elif tex_a == cell_mat_b: weight_mat_b += w_a
	elif tex_a == cell_mat_c: weight_mat_c += w_a
	
	if tex_b == cell_mat_a: weight_mat_a += w_b
	elif tex_b == cell_mat_b: weight_mat_b += w_b
	elif tex_b == cell_mat_c: weight_mat_c += w_b
	
	if tex_c == cell_mat_a: weight_mat_a += w_c
	elif tex_c == cell_mat_b: weight_mat_b += w_c
	elif tex_c == cell_mat_c: weight_mat_c += w_c
	
	if tex_d == cell_mat_a: weight_mat_a += w_d
	elif tex_d == cell_mat_b: weight_mat_b += w_d
	elif tex_d == cell_mat_c: weight_mat_c += w_d
	
	# Normalize weights
	var total_weight : float = weight_mat_a + weight_mat_b + weight_mat_c
	if total_weight > 0.001:
		weight_mat_a /= total_weight
		weight_mat_b /= total_weight
	
	cell_weight_b = weight_mat_b
	return Color(float(cell_mat_a), float(cell_mat_b), float(cell_mat_c), weight_mat_a)

#endregion
