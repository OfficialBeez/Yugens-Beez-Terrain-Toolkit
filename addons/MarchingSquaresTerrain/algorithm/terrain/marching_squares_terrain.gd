@tool
extends Node3D
class_name MarchingSquaresTerrain


signal chunk_dimensions_changed (value : Vector3i)

enum StorageMode {
	## Saves load time. Loads a pre-built visual mesh from disk.
	## The collision mesh, grass etc. are generated when the scene loads.
	## (faster load, slightly larger files).
	BAKED,
	## Saves disk space. Generates everything from heightmaps when the scene loads.
	## This is overkill for most games.
	## (slower load, smallest files).
	RUNTIME,
}

@export_category("Storage Options")
## The storage mode for terrain data. 
@export var storage_mode : StorageMode = StorageMode.BAKED:
	set(value):
		if storage_mode != value:
			storage_mode = value
			# Mark all chunks dirty to force re-save of data/meshes
			if chunks:
				for chunk in chunks.values():
					chunk.mark_dirty()
			print_verbose("[MST] Storage mode changed. All chunks marked for save.")
		notify_property_list_changed()

## If true, storage will include grass data, ignored if storage_mode = RUNTIME
@export var bake_grass : bool = true:
	set(value):
		bake_grass = value
		for chunk : MarchingSquaresTerrainChunk in chunks.values():
			chunk.mark_dirty()

## If true, storage will include collision data, ignored if storage_mode = RUNTIME
@export var bake_collision : bool = true:
	set(value):
		bake_collision = value
		for chunk : MarchingSquaresTerrainChunk in chunks.values():
			chunk.mark_dirty()

## The folder where this terrain's data is saved. 
## If left empty, it automatically fills with a folder name relative to your scene file.
## Note: Manually setting a path locks the save location even if you rename the terrain node later.
@export_dir var data_directory : String = "":
	get():
		if EngineWrapper.instance.is_editor() and data_directory.is_empty():
			var auto_path := MSTDataHandler.generate_data_directory(self)
			if not auto_path.is_empty():
				data_directory = auto_path
		return data_directory

@export_category("Runtime Baking")
## If this option is true, the textures will be baked into a texture atlas
## at runtime. This will improve rendering performance, but increase cost of generation
## slightly.
@export var enable_runtime_texture_baking : bool = true

## The resolution used per polygon when baking the texture atlas. Increase this value
## when using high-res textures. Higher values increase the baking time and memory usage.
@export var polygon_texture_resolution : int = 32

## Used for overriding the material of the baked terrain texture.
@export var bake_material_override : Material

## True after external storage has been initialized.
## Used to detect when migration from embedded data is needed.
@export_storage var _storage_initialized : bool = false

## Tracks the mode used during the last successful save for reporting purposes.
@export_storage var _last_storage_mode : StorageMode = StorageMode.BAKED

#region global terrain settings
# Terrain Settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var dimensions : Vector3i = Vector3i(33, 32, 33): # Total amount of height values in X and Z direction, and total height range
	set(value):
		dimensions = value
		terrain_material.set_shader_parameter("chunk_size", value)
		if EngineWrapper.instance.is_editor():
			emit_signal("chunk_dimensions_changed", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var cell_size : Vector2 = Vector2(2.0, 2.0): # XZ Unit size of each cell
	set(value):
		cell_size = value
		terrain_material.set_shader_parameter("cell_size", value)
		grass_size = grass_size
@export_custom(PROPERTY_HINT_RANGE, "0, 2", PROPERTY_USAGE_STORAGE) var blend_mode : int = 0:
	set(value):
		blend_mode = value
		if value == 1 or value == 2:
			terrain_material.set_shader_parameter("use_hard_textures", true)
		else:
			terrain_material.set_shader_parameter("use_hard_textures", false)
		terrain_material.set_shader_parameter("blend_mode", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells(true)
@export_custom(PROPERTY_HINT_RANGE, "9, 32", PROPERTY_USAGE_STORAGE) var extra_collision_layer : int = 9:
	set(value):
		extra_collision_layer = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells(true)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_flat_normals : bool = false:
	set(value):
		use_flat_normals = value
		terrain_material.set_shader_parameter("use_flat_normals", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
			chunk.mark_dirty()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_cell_shading : bool = true:
	set(value):
		use_cell_shading = value
		terrain_material.set_shader_parameter("use_cell_shading", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("use_cell_shading", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var collision_depth: float = 0.0:
	set(value):
		collision_depth = value
		if not is_batch_updating:
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.regenerate_mesh()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.0: # Determines what part of the terrain's mesh are walls
	set(value):
		wall_threshold = value
		terrain_material.set_shader_parameter("wall_threshold", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ridge_threshold: float = 1.0:
	set(value):
		ridge_threshold = value
		terrain_material.set_shader_parameter("ridge_threshold", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ledge_threshold: float = 1.0:
	set(value):
		ledge_threshold = value
		terrain_material.set_shader_parameter("ledge_threshold", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ridge_texture: bool = true:
	set(value):
		use_ridge_texture = value
		terrain_material.set_shader_parameter("use_ridge_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ledge_texture: bool = true:
	set(value):
		use_ledge_texture = value
		terrain_material.set_shader_parameter("use_ledge_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var noise_hmap : Noise # used to generate smooth initial heights for more natrual looking terrain. if null, initial terrain will be flat
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var global_noise_scale: float = 0.08:
	set(value):
		global_noise_scale = value
		terrain_material.set_shader_parameter("global_noise_scale", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("global_noise_scale", value)

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var global_noise_strength: float = 0.0:
	set(value):
		global_noise_strength = value
		terrain_material.set_shader_parameter("global_noise_strength", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("global_noise_strength", value)

# Grass settings
@export var rebuild_grass_now: bool = false:
	set(value):
		rebuild_grass_now = false
		if not value:
			return
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if chunk and chunk.grass_planter:
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var animation_fps : int = 0:
	set(value):
		animation_fps = clamp(value, 0, 30)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("fps", clamp(value, 0, 30))
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wind_mode : int = 0:
	set(value):
		wind_mode = value
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wind_mode", value)
@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var wind_intensity : float = 0.5:
	set(value):
		wind_intensity = value
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wind_intensity", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wind_tip_color : Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		wind_tip_color = value
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wind_tip_color", value)
@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var wind_tip_strength : float = 0.3:
	set(value):
		wind_tip_strength = value
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wind_tip_strength", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_subdivisions : int = 3:
	set(value):
		grass_subdivisions = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.multimesh.instance_count = (dimensions.x-1) * (dimensions.z-1) * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		var scale_factor := (cell_size.x + cell_size.y) / 4.0
		var scaled_value := value * scale_factor
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.multimesh.mesh.size = scaled_value
			chunk.grass_planter.multimesh.mesh.center_offset.y = scaled_value.y / 2.0
@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var grass_size_variation : float = 0.0:
	set(value):
		grass_size_variation = clampf(value, 0.0, 1.0)
		if not is_batch_updating and Engine.is_editor_hint():
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				if chunk.grass_planter:
					chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_RANGE, "0.005, 0.5, 0.005", PROPERTY_USAGE_STORAGE) var color_variation_scale : float = 0.08:
	set(value):
		color_variation_scale = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("color_variation_scale", value)
@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var color_variation_strength : float = 1.0:
	set(value):
		color_variation_strength = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("color_variation_strength", value)
#endregion

#region vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_1 : Texture2D = null:
	set(value):
		texture_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_1:
				grass_mat.set_shader_parameter("use_base_color_1", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_1", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D = null:
	set(value):
		texture_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_2:
				grass_mat.set_shader_parameter("use_base_color_2", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_2", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D = null:
	set(value):
		texture_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rb", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_3:
				grass_mat.set_shader_parameter("use_base_color_3", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_3", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D = null:
	set(value):
		texture_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ra", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_4:
				grass_mat.set_shader_parameter("use_base_color_4", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_4", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D = null:
	set(value):
		texture_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_5:
				grass_mat.set_shader_parameter("use_base_color_5", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_5", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D = null:
	set(value):
		texture_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_6:
				grass_mat.set_shader_parameter("use_base_color_6", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_6", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D:
	set(value):
		texture_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gb", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D:
	set(value):
		texture_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ga", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D:
	set(value):
		texture_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_br", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D:
	set(value):
		texture_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bg", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D:
	set(value):
		texture_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bb", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D:
	set(value):
		texture_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ba", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D:
	set(value):
		texture_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ar", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D:
	set(value):
		texture_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ag", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D:
	set(value):
		texture_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ab", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
#endregion

#region grass textures
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_1 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_1 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : Texture2D = preload("uid://cxvnfgy865wsk"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_6", value)
#endregion

#region has grass variables
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool = true:
	set(value):
		tex2_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool = true:
	set(value):
		tex3_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool = true:
	set(value):
		tex4_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool = true:
	set(value):
		tex5_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool = true:
	set(value):
		tex6_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_6", value)
#endregion

#region texture albedos
#These are just for migration into the Palette system
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_color_1 : Color = Color("647851ff")

#endregion

#region texture scales
# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float = 1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float = 1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float = 1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float = 1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float = 1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float = 1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float = 1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_7", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float = 1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_8", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float = 1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_9", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float = 1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_10", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float = 1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_11", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float = 1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_12", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float = 1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_13", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float = 1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_14", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float = 1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("tex_scale_15", value)
#endregion

@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null

# Palette System
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var palette_colors: Array[Color] = []
# Per palette-index weight (0-100). Used to control per-slot palette distribution.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var palette_weights: Array[float] = []
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_color_indices: Array = [
	[], [], [], [], [], [], [], [], [], [], [], [], [], [], []
]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_blend_modes: Array[int] = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

# Outline settings (per texture slot)
# slot_has_outline[slot] enables a thin edge/foam line where that texture blends with another.
# slot_outline_modes[slot]: 0 = darken Color 1, 1 = use last palette color
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_has_outline: Array[bool] = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_outline_modes: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

@export_custom(PROPERTY_HINT_RANGE, "0.25,32.0,0.25", PROPERTY_USAGE_STORAGE) var outline_width: float = 6.0:
	set(value):
		outline_width = clampf(value, 0.25, 32.0)
		if not is_batch_updating and terrain_material:
			terrain_material.set_shader_parameter("outline_width", outline_width)

# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture : int = 5

signal load_finished

var void_texture := preload("uid://csvthlqhb8g5j")
var placeholder_wind_texture := preload("uid://dk1t5hy2tiil7") # Change to your own texture

var terrain_material : ShaderMaterial = null
var grass_mesh : QuadMesh = null 

var is_batch_updating : bool = false

var chunks : Dictionary = {}


func _validate_property(property: Dictionary) -> void:
	if property.name in ["bake_grass", "bake_collision"]:
		if storage_mode != StorageMode.BAKED:
			property.usage = PROPERTY_USAGE_NO_EDITOR


func _init() -> void:
	# Create unique copies of shared resources for this node instance
	# This prevents texture/material changes from affecting other MarchingSquaresTerrain nodes
	terrain_material = preload("uid://bahbybbjwkhlg").duplicate(true)
	var base_grass_mesh := preload("uid://h41fuxldpf1u")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)
	print_verbose("Last storage mode: ", _last_storage_mode)


func _notification(what: int) -> void:
	# Save all dirty chunks to external storage before scene save
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if EngineWrapper.instance.is_editor():
			MSTDataHandler.save_all_chunks(self)


func _enter_tree() -> void:
	_deferred_enter_tree.call_deferred()


func _initialize_data_directory() -> void:
	var copy_from_dir := ""
	if EngineWrapper.instance.is_editor() and not data_directory.is_empty() and not MSTDataHandler.is_data_directory_unique(self):
		copy_from_dir = data_directory
		data_directory = ""
	
	if EngineWrapper.instance.is_editor() and (data_directory.is_empty()):
		var auto_path := MSTDataHandler.generate_data_directory(self)
		if not auto_path.is_empty():
			data_directory = auto_path
	if copy_from_dir:
		MSTDataHandler.copy_recursive(copy_from_dir, data_directory)


func _deferred_enter_tree() -> void:
	_initialize_data_directory()
	
	print_verbose("Terrain data dir: ", data_directory)
	
	# Populate chunks dictionary from scene children
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			if chunk._data_dirty:
				return
	chunks.clear()
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			chunks[chunk.chunk_coords] = chunk
			chunk.terrain_system = self
			chunk.grass_planter = null
	
	# Load external data if storage was previously initialized
	if _storage_initialized:
		MSTDataHandler.load_terrain_data(self)
	elif EngineWrapper.instance.is_editor() and MSTDataHandler.needs_migration(self):
		# Auto-migrate embedded data to external storage (editor only)
		MSTDataHandler.migrate_to_external_storage(self)
	
	# Initialize all chunks (regenerate mesh/grass from loaded data)
	for chunk : MarchingSquaresTerrainChunk in chunks.values():
		chunk.initialize_terrain(true)
		
	# Apply all persisted textures/colors to this terrain's unique shader materials
	# This is needed because _init() creates fresh duplicated materials that don't have
	# the terrain's saved texture values - only the base resource defaults
	migrate_colors_to_palette()
	force_batch_update()
	grass_size = grass_size
	
	load_finished.emit()


func has_chunk(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x, z))


func add_new_chunk(chunk_x: int, chunk_z: int, plugin):
	var chunk_coords := Vector2i(chunk_x, chunk_z)
	var new_chunk := MarchingSquaresTerrainChunk.new()
	new_chunk.name = "Chunk "+str(chunk_coords)
	new_chunk.terrain_system = self
	
	new_chunk.generate_height_map(plugin.height)
	new_chunk.mark_dirty()
	
	add_chunk(chunk_coords, new_chunk, plugin, false)
	
	if plugin.current_quick_paint:
		plugin.current_draw_pattern.clear()
		plugin.current_draw_pattern[chunk_coords] = {}
		
		for z in range(dimensions.x):
			for x in range(dimensions.z):
				var cell := Vector2i(x, z)
				plugin.current_draw_pattern[chunk_coords][cell] = 1.0
		
		plugin.draw_pattern(self) # Apply the current selected quick paint to the new chunk on creation
		plugin.current_draw_pattern.clear()
	
	var chunk_left : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left:
		for z in range(0, dimensions.z):
			new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right:
		for z in range(0, dimensions.z):
			chunk_right.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up:
		for x in range(0, dimensions.x):
			new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down:
		for x in range(0, dimensions.x):
			new_chunk.height_map[dimensions.z - 1][x] = chunk_down.height_map[0][x]
	
	new_chunk.regenerate_mesh()


func remove_chunk(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk.free()
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			if child is MarchingSquaresTerrainChunk:
				plugin.selected_chunk = child
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)


# Remove a chunk but still keep it in memory (so that undo can restore it)
func remove_chunk_from_tree(x: int, z: int, plugin):
	var chunk_coords := Vector2i(x, z)
	var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk._skip_save_on_exit = true  # Prevent mesh save during undo/redo
	remove_child(chunk)
	chunk.owner = null
	
	if plugin.selected_chunk and plugin.selected_chunk.chunk_coords == chunk.chunk_coords:
		var temp_chunk := MarchingSquaresTerrainChunk.new()
		temp_chunk.chunk_coords = Vector2i(99999, 99999)
		plugin.selected_chunk = temp_chunk
		for child in get_children():
			if child is MarchingSquaresTerrainChunk:
				plugin.selected_chunk = child
				break
	plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
	plugin.gizmo_plugin.trigger_redraw(self)


func add_chunk(coords: Vector2i, chunk: MarchingSquaresTerrainChunk, plugin, regenerate_mesh: bool = true):
	chunk.terrain_system = self
	chunk.chunk_coords = coords
	chunk._skip_save_on_exit = false  # Reset flag when chunk is re-added (undo restores chunk)
	add_child(chunk)
	chunks[coords] = chunk
	
	# Use position instead of global_position to avoid "is_inside_tree()" errors
	# when multiple scenes with MarchingSquaresTerrain are open in editor tabs.
	# Since chunks are direct children of terrain, position equals global_position.
	chunk.position = Vector3(
		coords.x * ((dimensions.x - 1) * cell_size.x),
		0,
		coords.y * ((dimensions.z - 1) * cell_size.y)
	)
	
	EngineWrapper.instance.set_owner_recursive(chunk)
	chunk.initialize_terrain(regenerate_mesh)
	print_verbose("[MST] Added new chunk to terrain system at ", chunk)
	if plugin:
		if not plugin.selected_chunk or plugin.selected_chunk.chunk_coords == Vector2i(99999, 99999):
			plugin.selected_chunk = chunk
		plugin.ui.tool_attributes.show_tool_attributes(plugin.TerrainToolMode.CHUNK_MANAGEMENT)
		plugin.gizmo_plugin.trigger_redraw(self)

#region texture (set) functions

# WARNING: this function is currently not being used anymore. [Q] Yūgen: was that intentional?
# This (legacy) function is mainly there to ensure the plugin works on startup in a new project
func _ensure_textures() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	if not grass_mat.get_shader_parameter("use_base_color_1") and terrain_material.get_shader_parameter("vc_tex_rr") == null:
		terrain_material.set_shader_parameter("vc_tex_rr", texture_1)
	if not grass_mat.get_shader_parameter("use_base_color_2") and terrain_material.get_shader_parameter("vc_tex_rg") == null:
		terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	if not grass_mat.get_shader_parameter("use_base_color_3") and terrain_material.get_shader_parameter("vc_tex_rb") == null:
		terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	if not grass_mat.get_shader_parameter("use_base_color_4") and terrain_material.get_shader_parameter("vc_tex_ra") == null:
		terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	if not grass_mat.get_shader_parameter("use_base_color_5") and terrain_material.get_shader_parameter("vc_tex_gr") == null:
		terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	if not grass_mat.get_shader_parameter("use_base_color_6") and terrain_material.get_shader_parameter("vc_tex_gg") == null:
		terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	
	if grass_mat.get_shader_parameter("use_grass_tex_2") and terrain_material.get_shader_parameter("vc_tex_rg") == null:
		terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	if grass_mat.get_shader_parameter("use_grass_tex_3") and terrain_material.get_shader_parameter("vc_tex_rb") == null:
		terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	if grass_mat.get_shader_parameter("use_grass_tex_4") and terrain_material.get_shader_parameter("vc_tex_ra") == null:
		terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	if grass_mat.get_shader_parameter("use_grass_tex_5") and terrain_material.get_shader_parameter("vc_tex_gr") == null:
		terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	if grass_mat.get_shader_parameter("use_grass_tex_6") and terrain_material.get_shader_parameter("vc_tex_gg") == null:
		terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	
	if grass_sprite_tex_1 and grass_mat.get_shader_parameter("grass_texture_1") == null:
		grass_mat.set_shader_parameter("grass_texture_1", grass_sprite_tex_1)
	if grass_sprite_tex_2 and grass_mat.get_shader_parameter("grass_texture_2") == null:
		grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	if grass_sprite_tex_3 and grass_mat.get_shader_parameter("grass_texture_3") == null:
		grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	if grass_sprite_tex_4 and grass_mat.get_shader_parameter("grass_texture_4") == null:
		grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	if grass_sprite_tex_5 and grass_mat.get_shader_parameter("grass_texture_5") == null:
		grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	if grass_sprite_tex_6 and grass_mat.get_shader_parameter("grass_texture_6") == null:
		grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	
	if terrain_material.get_shader_parameter("vc_tex_aa") == null:
		terrain_material.set_shader_parameter("vc_tex_aa", void_texture)
	
	if grass_mat.get_shader_parameter("wind_texture") == null:
		grass_mat.set_shader_parameter("wind_texture", placeholder_wind_texture)


func migrate_colors_to_palette() -> void:
	if palette_colors.size() > 0:
		return  # Already migrated, skip
	
	palette_colors.resize(128)
	palette_colors[0] = tex1_color_1
	palette_colors[1] = tex2_color_1
	palette_colors[2] = tex3_color_1
	palette_colors[3] = tex4_color_1
	palette_colors[4] = tex5_color_1
	palette_colors[5] = tex6_color_1
	
	for i in range(6, 128):
		palette_colors[i] = Color("647851ff")
	
	palette_weights.resize(128)
	for i in range(128):
		palette_weights[i] = 100.0
	
	slot_color_indices = [[0], [1], [2], [3], [4], [5], [], [], [], [], [], [], [], [], []]


func _ensure_palette_weights() -> void:
	if palette_weights.size() != 128:
		palette_weights.resize(128)
	for i in range(128):
		if palette_weights[i] == null:
			palette_weights[i] = 100.0
		palette_weights[i] = clampf(float(palette_weights[i]), 0.0, 100.0)


func _rebuild_palette_uniforms() -> void:
	_ensure_palette_weights()
	var colors: Array = []
	colors.resize(120)
	
	var weights: Array = []
	weights.resize(120)
	
	var counts: Array = []
	counts.resize(15)
	
	for slot in range(15):
		var indices: Array = slot_color_indices[slot] if slot < slot_color_indices.size() else []
		var count := mini(indices.size(), 8)
		counts[slot] = maxi(count, 1)
		for i in range(8):
			if i < count and indices[i] < palette_colors.size():
				colors[slot * 8 + i] = palette_colors[indices[i]]
				weights[slot * 8 + i] = palette_weights[indices[i]] if indices[i] < palette_weights.size() else 100.0
			else:
				colors[slot * 8 + i] = Color.WHITE
				weights[slot * 8 + i] = 0.0
	
	terrain_material.set_shader_parameter("slot_colors", colors)
	terrain_material.set_shader_parameter("slot_color_weights", weights)
	terrain_material.set_shader_parameter("slot_color_counts", counts)
	(grass_mesh.material as ShaderMaterial).set_shader_parameter("slot_colors", colors)
	(grass_mesh.material as ShaderMaterial).set_shader_parameter("slot_color_weights", weights)
	(grass_mesh.material as ShaderMaterial).set_shader_parameter("slot_color_counts", counts)


func _push_slot_blend_modes() -> void:
	var modes := PackedInt32Array(slot_blend_modes)
	terrain_material.set_shader_parameter("slot_blend_modes", modes)
	(grass_mesh.material as ShaderMaterial).set_shader_parameter("slot_blend_modes", modes)


func _ensure_outline_settings() -> void:
	if slot_has_outline.size() != 15:
		slot_has_outline.resize(15)
	if slot_outline_modes.size() != 15:
		slot_outline_modes.resize(15)
	for i in range(15):
		if slot_has_outline[i] == null:
			slot_has_outline[i] = false
		if slot_outline_modes[i] == null:
			slot_outline_modes[i] = 0
		slot_outline_modes[i] = clampi(int(slot_outline_modes[i]), 0, 1)


func _push_slot_outline_settings() -> void:
	_ensure_outline_settings()
	var enabled := PackedInt32Array()
	enabled.resize(15)
	var modes_arr := PackedInt32Array()
	modes_arr.resize(15)
	for i in range(15):
		enabled[i] = 1 if slot_has_outline[i] else 0
		modes_arr[i] = clampi(int(slot_outline_modes[i]), 0, 1)
	terrain_material.set_shader_parameter("slot_has_outline", enabled)
	terrain_material.set_shader_parameter("slot_outline_modes", modes_arr)


## Applies all shader parameters and regenerates grass once
## Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("chunk_size", dimensions)
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Ground Textures
	terrain_material.set_shader_parameter("vc_tex_rr", texture_1)
	terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	terrain_material.set_shader_parameter("vc_tex_gb", texture_7)
	terrain_material.set_shader_parameter("vc_tex_ga", texture_8)
	terrain_material.set_shader_parameter("vc_tex_br", texture_9)
	terrain_material.set_shader_parameter("vc_tex_bg", texture_10)
	terrain_material.set_shader_parameter("vc_tex_bb", texture_11)
	terrain_material.set_shader_parameter("vc_tex_ba", texture_12)
	terrain_material.set_shader_parameter("vc_tex_ar", texture_13)
	terrain_material.set_shader_parameter("vc_tex_ag", texture_14)
	terrain_material.set_shader_parameter("vc_tex_ab", texture_15)
	
	# TERRAIN MATERIAL - Per-Texture UV Scales
	terrain_material.set_shader_parameter("tex_scale_1", texture_scale_1)
	terrain_material.set_shader_parameter("tex_scale_2", texture_scale_2)
	terrain_material.set_shader_parameter("tex_scale_3", texture_scale_3)
	terrain_material.set_shader_parameter("tex_scale_4", texture_scale_4)
	terrain_material.set_shader_parameter("tex_scale_5", texture_scale_5)
	terrain_material.set_shader_parameter("tex_scale_6", texture_scale_6)
	terrain_material.set_shader_parameter("tex_scale_7", texture_scale_7)
	terrain_material.set_shader_parameter("tex_scale_8", texture_scale_8)
	terrain_material.set_shader_parameter("tex_scale_9", texture_scale_9)
	terrain_material.set_shader_parameter("tex_scale_10", texture_scale_10)
	terrain_material.set_shader_parameter("tex_scale_11", texture_scale_11)
	terrain_material.set_shader_parameter("tex_scale_12", texture_scale_12)
	terrain_material.set_shader_parameter("tex_scale_13", texture_scale_13)
	terrain_material.set_shader_parameter("tex_scale_14", texture_scale_14)
	terrain_material.set_shader_parameter("tex_scale_15", texture_scale_15)
	
	# GRASS MATERIAL - Grass Textures 
	grass_mat.set_shader_parameter("grass_texture_1", grass_sprite_tex_1)
	grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	
	
	# GRASS MATERIAL - Use Base Color Flags 
	grass_mat.set_shader_parameter("use_base_color_1", texture_1 == null)
	grass_mat.set_shader_parameter("use_base_color_2", texture_2 == null)
	grass_mat.set_shader_parameter("use_base_color_3", texture_3 == null)
	grass_mat.set_shader_parameter("use_base_color_4", texture_4 == null)
	grass_mat.set_shader_parameter("use_base_color_5", texture_5 == null)
	grass_mat.set_shader_parameter("use_base_color_6", texture_6 == null)
	
	# GRASS MATERIAL - Has Grass Flags 
	grass_mat.set_shader_parameter("use_grass_tex_2", tex2_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_3", tex3_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_4", tex4_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_5", tex5_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_6", tex6_has_grass)
	
	# GRASS MATERIAL - Wind
	grass_mat.set_shader_parameter("wind_mode", wind_mode)
	grass_mat.set_shader_parameter("wind_intensity", wind_intensity)
	grass_mat.set_shader_parameter("wind_tip_color", wind_tip_color)
	grass_mat.set_shader_parameter("wind_tip_strength", wind_tip_strength)
	
	# GLOBAL NOISE - Dark-light Hues
	terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
	terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
	grass_mat.set_shader_parameter("global_noise_scale", global_noise_scale)
	grass_mat.set_shader_parameter("global_noise_strength", global_noise_strength)
	grass_mat.set_shader_parameter("color_variation_scale", color_variation_scale)
	grass_mat.set_shader_parameter("color_variation_strength", color_variation_strength)

	# PALETTE SYSTEM - replaces all individual color uniforms
	_rebuild_palette_uniforms()
	_push_slot_blend_modes()
	_push_slot_outline_settings()
	terrain_material.set_shader_parameter("outline_width", outline_width)


## Syncs and saves current UI texture values to the given preset resource
## Called by marching_squares_ui.gd when saving monitoring settings changes
func save_to_preset() -> void:
	if current_texture_preset == null or current_texture_preset.resource_path.is_empty():
		return
	
	# Terrain textures
	current_texture_preset.new_textures.terrain_textures[0] = texture_1
	current_texture_preset.new_textures.terrain_textures[1] = texture_2
	current_texture_preset.new_textures.terrain_textures[2] = texture_3
	current_texture_preset.new_textures.terrain_textures[3] = texture_4
	current_texture_preset.new_textures.terrain_textures[4] = texture_5
	current_texture_preset.new_textures.terrain_textures[5] = texture_6
	current_texture_preset.new_textures.terrain_textures[6] = texture_7
	current_texture_preset.new_textures.terrain_textures[7] = texture_8
	current_texture_preset.new_textures.terrain_textures[8] = texture_9
	current_texture_preset.new_textures.terrain_textures[9] = texture_10
	current_texture_preset.new_textures.terrain_textures[10] = texture_11
	current_texture_preset.new_textures.terrain_textures[11] = texture_12
	current_texture_preset.new_textures.terrain_textures[12] = texture_13
	current_texture_preset.new_textures.terrain_textures[13] = texture_14
	current_texture_preset.new_textures.terrain_textures[14] = texture_15
	
	# Texture scales
	current_texture_preset.new_textures.texture_scales[0] = texture_scale_1
	current_texture_preset.new_textures.texture_scales[1] = texture_scale_2
	current_texture_preset.new_textures.texture_scales[2] = texture_scale_3
	current_texture_preset.new_textures.texture_scales[3] = texture_scale_4
	current_texture_preset.new_textures.texture_scales[4] = texture_scale_5
	current_texture_preset.new_textures.texture_scales[5] = texture_scale_6
	current_texture_preset.new_textures.texture_scales[6] = texture_scale_7
	current_texture_preset.new_textures.texture_scales[7] = texture_scale_8
	current_texture_preset.new_textures.texture_scales[8] = texture_scale_9
	current_texture_preset.new_textures.texture_scales[9] = texture_scale_10
	current_texture_preset.new_textures.texture_scales[10] = texture_scale_11
	current_texture_preset.new_textures.texture_scales[11] = texture_scale_12
	current_texture_preset.new_textures.texture_scales[12] = texture_scale_13
	current_texture_preset.new_textures.texture_scales[13] = texture_scale_14
	current_texture_preset.new_textures.texture_scales[14] = texture_scale_15
	
	# Grass sprites
	current_texture_preset.new_textures.grass_sprites[0] = grass_sprite_tex_1
	current_texture_preset.new_textures.grass_sprites[1] = grass_sprite_tex_2
	current_texture_preset.new_textures.grass_sprites[2] = grass_sprite_tex_3
	current_texture_preset.new_textures.grass_sprites[3] = grass_sprite_tex_4
	current_texture_preset.new_textures.grass_sprites[4] = grass_sprite_tex_5
	current_texture_preset.new_textures.grass_sprites[5] = grass_sprite_tex_6
	
	# Palette system
	current_texture_preset.new_textures.grass_colors.resize(128)
	for i in range(128):
		current_texture_preset.new_textures.grass_colors[i] = palette_colors[i]
	_ensure_palette_weights()
	current_texture_preset.palette_weights = palette_weights.duplicate()
	current_texture_preset.slot_color_indices = slot_color_indices.duplicate(true)
	current_texture_preset.slot_blend_modes = slot_blend_modes.duplicate()
	_ensure_outline_settings()
	current_texture_preset.slot_has_outline = slot_has_outline.duplicate()
	current_texture_preset.slot_outline_modes = slot_outline_modes.duplicate()
	
	# Has grass flags
	current_texture_preset.new_textures.has_grass[0] = tex2_has_grass
	current_texture_preset.new_textures.has_grass[1] = tex3_has_grass
	current_texture_preset.new_textures.has_grass[2] = tex4_has_grass
	current_texture_preset.new_textures.has_grass[3] = tex5_has_grass
	current_texture_preset.new_textures.has_grass[4] = tex6_has_grass
	
	ResourceSaver.save(current_texture_preset)


func load_from_preset(preset: MarchingSquaresTexturePreset) -> void:
	if preset == null:
		return
	
	var has_real_palette_data := false
	for arr in preset.slot_color_indices:
		if arr.size() > 0:
			has_real_palette_data = true
			break

	if preset.slot_color_indices.size() == 15 and has_real_palette_data:
		slot_color_indices = preset.slot_color_indices.duplicate(true)
		if preset.new_textures.grass_colors.size() == 128:
			palette_colors = preset.new_textures.grass_colors.duplicate()
		if preset.palette_weights.size() == 128:
			palette_weights = preset.palette_weights.duplicate()
		else:
			palette_weights.resize(128)
			for i in range(128):
				palette_weights[i] = 100.0
	else:
		# Old preset — reset everything to clean defaults
		slot_color_indices = [[0], [1], [2], [3], [4], [5], [], [], [], [], [], [], [], [], []]
		palette_colors.resize(128)
		palette_weights.resize(128)
		for i in range(128):
			palette_colors[i] = Color("647851ff")
			palette_weights[i] = 100.0

	if preset.slot_blend_modes.size() == 15:
		slot_blend_modes = preset.slot_blend_modes.duplicate()
	else:
		slot_blend_modes = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

	if preset.slot_has_outline.size() == 15:
		slot_has_outline = preset.slot_has_outline.duplicate()
	else:
		slot_has_outline = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]

	if preset.slot_outline_modes.size() == 15:
		slot_outline_modes = preset.slot_outline_modes.duplicate()
	else:
		slot_outline_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	_ensure_outline_settings()
	terrain_material.set_shader_parameter("outline_width", outline_width)

	_rebuild_palette_uniforms()
	_push_slot_blend_modes()
	_push_slot_outline_settings()

#endregion
