@tool
extends Node3D
class_name MarchingSquaresTerrain

# Uses global class_name MSTDataHandler (static utility).

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

# Runtime texture baking queue (prevents huge hitches by baking one chunk at a time).
var _runtime_bake_active: bool = false
var _runtime_bake_queue: Array[MarchingSquaresTerrainChunk] = []

## True after external storage has been initialized.
## Used to detect when migration from embedded data is needed.
@export_storage var _storage_initialized : bool = false

## Tracks the mode used during the last successful save for reporting purposes.
@export_storage var _last_storage_mode : StorageMode = StorageMode.BAKED

## One-time mesh migration flag: walls are now tagged via UV sentinel so shaders reliably detect walls.
## Existing chunks need a one-time regen to pick up the new UV values.
@export_storage var _uv_wall_sentinel_migrated : bool = false

## One-time mesh migration flag: wall vertices now compute their dominant materials from wall maps.
## Existing chunks need a one-time regen to pick up corrected wall material indices.
@export_storage var _wall_material_pair_migrated : bool = false

@export_category("Maintenance")
## When enabled, the editor will automatically migrate embedded chunk data (old scenes)
## into external storage (data_directory) on load.
@export var auto_migrate_embedded_data: bool = true

## When enabled, the editor will automatically apply one-time mesh migrations
## (e.g. wall-tagging/wall-material fixes) by regenerating chunk meshes once.
@export var auto_apply_one_time_migrations: bool = true

## One-click operations (acts like buttons; will always appear unchecked).
@export var migrate_embedded_data_now: bool:
	get: return false
	set(v):
		if not v:
			return
		if not EngineWrapper.instance.is_editor():
			push_warning("[MST] 'Migrate Embedded Data Now' is editor-only.")
			return
		call_deferred("_maintenance_migrate_embedded_data")

@export var save_all_chunks_now: bool:
	get: return false
	set(v):
		if not v:
			return
		if not EngineWrapper.instance.is_editor():
			push_warning("[MST] 'Save All Chunks Now' is editor-only (it saves external .res files).")
			return
		call_deferred("_maintenance_save_all_chunks")

@export var rebuild_all_chunks_now: bool:
	get: return false
	set(v):
		if not v:
			return
		call_deferred("_maintenance_rebuild_all_chunks")

@export var rebuild_all_chunk_meshes_now: bool:
	get: return false
	set(v):
		if not v:
			return
		call_deferred("_maintenance_rebuild_all_chunk_meshes")

@export var cleanup_orphaned_storage_now: bool:
	get: return false
	set(v):
		if not v:
			return
		if not EngineWrapper.instance.is_editor():
			push_warning("[MST] 'Cleanup Orphaned Storage Now' is editor-only.")
			return
		call_deferred("_maintenance_cleanup_orphaned_storage")

@export_category("Terrain")
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
		_request_chunk_regen(null, true)
@export_custom(PROPERTY_HINT_RANGE, "9, 32", PROPERTY_USAGE_STORAGE) var extra_collision_layer : int = 9:
	set(value):
		extra_collision_layer = value
		_request_chunk_regen(null, true)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_flat_normals : bool = false:
	set(value):
		use_flat_normals = value
		terrain_material.set_shader_parameter("use_flat_normals", value)
		_request_grass_regen()
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.mark_dirty()

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var detail_normal_texture: Texture2D:
	set(value):
		detail_normal_texture = value
		terrain_material.set_shader_parameter("detail_normal_texture", value)

@export_custom(PROPERTY_HINT_RANGE, "0.001,5.0,0.001", PROPERTY_USAGE_STORAGE) var detail_normal_scale: float = 0.25:
	set(value):
		detail_normal_scale = clampf(float(value), 0.001, 5.0)
		terrain_material.set_shader_parameter("detail_normal_scale", detail_normal_scale)

@export_custom(PROPERTY_HINT_RANGE, "0.0,1.0,0.01", PROPERTY_USAGE_STORAGE) var detail_normal_strength: float = 0.0:
	set(value):
		detail_normal_strength = clampf(float(value), 0.0, 1.0)
		terrain_material.set_shader_parameter("detail_normal_strength", detail_normal_strength)

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_cell_shading : bool = true:
	set(value):
		use_cell_shading = value
		terrain_material.set_shader_parameter("use_cell_shading", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("use_cell_shading", value)

enum OutlineMode { OFF = 0, BLACK_SILHOUETTE = 1 }

# Outline mode selector
@export_custom(PROPERTY_HINT_ENUM, "Off,Black Silhouette", PROPERTY_USAGE_STORAGE) var outline_mode: int = OutlineMode.OFF:
	set(value):
		var new_mode := clampi(int(value), 0, 1)
		if outline_mode == new_mode:
			return
		outline_mode = new_mode
		_request_outline_apply()

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var collision_depth: float = 0.0:
	set(value):
		collision_depth = value
		if not is_batch_updating:
			_request_chunk_mesh_regen()
@export_custom(PROPERTY_HINT_RANGE, "0.005,0.5,0.005", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.25: # Determines what part of the terrain's mesh are walls
	set(value):
		wall_threshold = clampf(float(value), 0.005, 0.5)
		terrain_material.set_shader_parameter("wall_threshold", wall_threshold)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", wall_threshold)
		_request_grass_regen()
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

@export_custom(PROPERTY_HINT_RANGE, "0.0,1.0,0.01", PROPERTY_USAGE_STORAGE) var global_noise_scroll: float = 0.0:
	set(value):
		global_noise_scroll = clampf(float(value), 0.0, 1.0)
		terrain_material.set_shader_parameter("global_noise_scroll", global_noise_scroll)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("global_noise_scroll", global_noise_scroll)

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var global_noise_texture : Texture2D:
	set(value):
		global_noise_texture = value
		terrain_material.set_shader_parameter("global_noise_texture", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("global_noise_texture", value)

@export_category("Grass")
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
			if not chunk.grass_planter or not chunk.grass_planter.multimesh:
				continue
			chunk.grass_planter.multimesh.instance_count = (dimensions.x-1) * (dimensions.z-1) * grass_subdivisions * grass_subdivisions
		_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size : Vector2 = Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		var scale_factor := (cell_size.x + cell_size.y) / 4.0
		var scaled_value := value * scale_factor

		# Update the shared grass mesh first (safe even before chunks initialize).
		if grass_mesh:
			grass_mesh.size = scaled_value
			grass_mesh.center_offset.y = scaled_value.y / 2.0

		# Chunks may not have created GrassPlanter/Multimesh yet during early startup.
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			if not chunk or not chunk.grass_planter or not chunk.grass_planter.multimesh or not chunk.grass_planter.multimesh.mesh:
				continue
			chunk.grass_planter.multimesh.mesh.size = scaled_value
			chunk.grass_planter.multimesh.mesh.center_offset.y = scaled_value.y / 2.0
@export_custom(PROPERTY_HINT_RANGE, "0.0, 1.0, 0.01", PROPERTY_USAGE_STORAGE) var grass_size_variation : float = 0.0:
	set(value):
		grass_size_variation = clampf(value, 0.0, 1.0)
		if not is_batch_updating and Engine.is_editor_hint():
			_request_grass_regen()
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

@export_category("Legacy (compat)")
@export_group("Legacy Terrain Textures (1-15)")
#region vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_1 : Texture2D = null:
	set(value):
		texture_1 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(0, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D = null:
	set(value):
		texture_2 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(1, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D = null:
	set(value):
		texture_3 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(2, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D = null:
	set(value):
		texture_4 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(3, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D = null:
	set(value):
		texture_5 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(4, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D = null:
	set(value):
		texture_6 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(5, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D:
	set(value):
		texture_7 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(6, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D:
	set(value):
		texture_8 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(7, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D:
	set(value):
		texture_9 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(8, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D:
	set(value):
		texture_10 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(9, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D:
	set(value):
		texture_11 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(10, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D:
	set(value):
		texture_12 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(11, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D:
	set(value):
		texture_13 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(12, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D:
	set(value):
		texture_14 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(13, value)
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D:
	set(value):
		texture_15 = value
		if not is_batch_updating:
			_set_legacy_texture_slot(14, value)
			_request_grass_regen()
#endregion

@export_group("")
@export_category("Texture Slots (256)")
#region texture slots (256)
const MAX_TEXTURE_SLOTS := 256
# Keep legacy VOID behavior for now (texture_15 in the old system).
const VOID_TEXTURE_SLOT := 15

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_slots: Array[MarchingSquaresTextureSlot] = []
@export_custom(PROPERTY_HINT_RANGE, "1,256,1", PROPERTY_USAGE_STORAGE) var visible_texture_slot_count: int = 6

# Runtime-built Texture2DArrays. Intentionally NOT stored in scenes (prevents .tscn bloat).
var _runtime_texture_array: Texture2DArray = null
var _runtime_grass_texture_array: Texture2DArray = null

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR) var texture_array: Texture2DArray:
	get:
		return _runtime_texture_array
	set(value):
		# Ignore any serialized value from older scenes; we always rebuild at runtime.
		pass

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR) var grass_texture_array: Texture2DArray:
	get:
		return _runtime_grass_texture_array
	set(value):
		pass

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var _grass_slots_migrated: bool = false

# Warn about normalization/mismatches only once per slot to avoid editor spam.
var _warned_texture_array_slots: Dictionary = {}
var _warned_grass_array_slots: Dictionary = {}
#endregion

@export_category("Legacy (compat)")
@export_group("Legacy Grass Textures (1-6)")
#region grass textures (legacy exports -> slot grass_texture)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_1 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_1 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[0].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[1].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[2].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[3].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[4].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[5].grass_texture = value
			rebuild_grass_texture_array()
			_request_grass_regen()
#endregion

@export_group("Legacy Has Grass Flags (1-6)")
#region has grass variables (legacy exports -> slot has_grass)
# Texture 1 was historically always-on; now exposed so "Base Grass" can be disabled.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_has_grass : bool = true:
	set(value):
		tex1_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[0].has_grass = tex1_has_grass
			_request_grass_regen()

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool = true:
	set(value):
		tex2_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[1].has_grass = tex2_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool = true:
	set(value):
		tex3_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[2].has_grass = tex3_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool = true:
	set(value):
		tex4_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[3].has_grass = tex4_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool = true:
	set(value):
		tex5_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[4].has_grass = tex5_has_grass
			_request_grass_regen()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool = true:
	set(value):
		tex6_has_grass = bool(value) if value != null else true
		if not is_batch_updating:
			_ensure_texture_slots()
			_maybe_migrate_legacy_grass()
			texture_slots[5].has_grass = tex6_has_grass
			_request_grass_regen()
#endregion

@export_group("Legacy Migration Colors (1-6)")
#region texture albedos
#These are just for migration into the Palette system
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex1_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_color_1 : Color = Color("647851ff")

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_color_1 : Color = Color("647851ff")

#endregion

@export_group("Legacy Texture Scales (1-15)")
#region texture scales
# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float = 1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(0, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float = 1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(1, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float = 1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(2, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float = 1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(3, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float = 1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(4, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float = 1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(5, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float = 1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(6, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float = 1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(7, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float = 1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(8, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float = 1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(9, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float = 1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(10, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float = 1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(11, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float = 1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(12, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float = 1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(13, value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float = 1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating:
			_set_legacy_texture_scale(14, value)
#endregion

@export_group("")
@export_category("Presets")
@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null

@export_category("Vertex Painter")
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
# slot_outline_widths[slot] controls the thickness of the per-material "foam" outline when textures meet.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_outline_widths: Array[float] = [
	6.0, 6.0, 6.0, 6.0, 6.0,
	6.0, 6.0, 6.0, 6.0, 6.0,
	6.0, 6.0, 6.0, 6.0, 6.0,
]

# Wetness controls (per texture slot)
# slot_wet_enabled[slot] toggles wetness effects on/off for that slot.
# slot_wet_modes[slot]: 0 = Wet (darken only), 1 = Glossy puddles (noise-masked).
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wet_enabled: Array[bool] = [
	false, false, false, false, false,
	false, false, false, false, false,
	false, false, false, false, false,
]
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_wet_modes: Array[int] = [
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
]

# slot_roughnesses[slot] controls surface roughness (0 = shiny/wet, 1 = matte/dry).
# (UI presents this as "Wetness" by storing roughness = 1 - wetness)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var slot_roughnesses: Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
]

@export_custom(PROPERTY_HINT_RANGE, "0.0,32.0,0.25", PROPERTY_USAGE_STORAGE) var outline_px: float = 2.0:
	set(value):
		outline_px = clampf(float(value), 0.0, 32.0)
		if not is_batch_updating:
			_request_outline_apply()

@export_custom(PROPERTY_HINT_RANGE, "0.25,32.0,0.25", PROPERTY_USAGE_STORAGE) var outline_width: float = 6.0:
	set(value):
		outline_width = clampf(value, 0.25, 32.0)
		if not is_batch_updating and terrain_material:
			terrain_material.set_shader_parameter("outline_width", outline_width)
			_request_outline_apply()


# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture : int = 5:
	set(value):
		var old := default_wall_texture
		default_wall_texture = clampi(int(value), 0, 255)
		if is_batch_updating:
			return
		_apply_default_wall_texture_change(old, default_wall_texture)


func _apply_default_wall_texture_change(old_idx: int, new_idx: int) -> void:
	if chunks.is_empty():
		return
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		var changed: bool = bool(chunk.apply_default_wall_texture(old_idx, new_idx))
		# Also update "unpainted" wall cells (those matching ground) to follow the new default.
		changed = bool(chunk.apply_default_wall_to_unpainted(new_idx)) or changed
		if changed:
			_request_chunk_regen(chunk, true)

signal load_finished

var void_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/void_texture.tres")
var placeholder_wind_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/wind_noise_texture.tres") # Change to your own texture

var terrain_material : ShaderMaterial = null
var outline_next_pass_material : ShaderMaterial = null
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
	terrain_material = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_terrain_shader.tres").duplicate(true)
	outline_next_pass_material = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_outline_nextpass.tres").duplicate(true)
	var base_grass_mesh := preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_grass_mesh.tres")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)
	print_verbose("Last storage mode: ", _last_storage_mode)

	_apply_outline_next_pass()

	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()


func request_runtime_texture_bake(chunk: MarchingSquaresTerrainChunk) -> void:
	if chunk == null or not is_instance_valid(chunk):
		return
	if EngineWrapper.instance.is_editor():
		return
	if not enable_runtime_texture_baking:
		return
	# Runtime baking is only intended when outlines are OFF (otherwise we want the live shader).
	if outline_mode != OutlineMode.OFF:
		return

	# De-dupe requests.
	if _runtime_bake_queue.has(chunk):
		return
	_runtime_bake_queue.append(chunk)
	if not _runtime_bake_active:
		_runtime_bake_active = true
		call_deferred("_runtime_bake_step")


func _runtime_bake_step() -> void:
	if outline_mode != OutlineMode.OFF or not enable_runtime_texture_baking:
		_runtime_bake_queue.clear()
		_runtime_bake_active = false
		return

	while not _runtime_bake_queue.is_empty():
		var chunk: MarchingSquaresTerrainChunk = _runtime_bake_queue.pop_front()
		if not is_instance_valid(chunk):
			continue
		# Skip if the chunk doesn't have a mesh yet.
		if chunk.mesh == null or not (chunk.mesh is ArrayMesh):
			continue

		var baker := MarchingSquaresGeometryBaker.new()
		baker.terrain_system = self
		baker.polygon_texture_resolution = polygon_texture_resolution
		baker.finished.connect(func(mesh_: Mesh, _original: MeshInstance3D, img: Image):
			if is_instance_valid(chunk):
				chunk.mesh = mesh_
				var mat: Material
				if bake_material_override:
					mat = bake_material_override.duplicate()
				else:
					mat = chunk.bake_material.duplicate()
					baker.transfer_shader_props(terrain_material, mat)

				if mat is StandardMaterial3D:
					mat.albedo_texture = ImageTexture.create_from_image(img)
				elif mat is ShaderMaterial:
					mat.set_shader_parameter("texture_albedo", ImageTexture.create_from_image(img))
				if chunk.mesh and chunk.mesh.get_surface_count() > 0:
					chunk.mesh.surface_set_material(0, mat)

			# Continue with the next chunk on the next frame.
			call_deferred("_runtime_bake_step")
		, CONNECT_ONE_SHOT)

		baker.bake_geometry_texture(chunk, get_tree())
		return

	_runtime_bake_active = false


func get_chunk_surface_material() -> Material:
	# Black silhouette outline must render BEFORE the terrain, otherwise it gets depth-tested away.
	if outline_mode == OutlineMode.BLACK_SILHOUETTE and outline_next_pass_material and terrain_material:
		outline_next_pass_material.set_shader_parameter("outline_px", outline_px)
		# World-space fallback (used only if outline_px is set to 0).
		outline_next_pass_material.set_shader_parameter("outline_thickness", 0.02)
		outline_next_pass_material.next_pass = terrain_material
		return outline_next_pass_material

	if outline_next_pass_material:
		outline_next_pass_material.next_pass = null
	return terrain_material


var _outline_apply_deferred: bool = false
var _outline_apply_timer: Timer = null
var _outline_apply_pending: bool = false

# Internal edge outlines: rebuild gradually to avoid editor freezes when enabling silhouette on many chunks.
var _internal_outline_rebuild_active: bool = false
var _internal_outline_rebuild_queue: Array[MarchingSquaresTerrainChunk] = []

var _grass_regen_timer: Timer = null
var _grass_regen_pending: bool = false

var _chunk_regen_timer: Timer = null
var _chunk_regen_pending: bool = false
var _chunk_regen_all: bool = false
var _chunk_regen_use_threads: bool = true
var _chunk_regen_set: Dictionary = {} # MarchingSquaresTerrainChunk -> true

var _chunk_mesh_regen_timer: Timer = null
var _chunk_mesh_regen_pending: bool = false


func _request_grass_regen() -> void:
	if is_batch_updating:
		return

	# Coalesce editor slider drags into a single grass rebuild.
	if EngineWrapper.instance.is_editor():
		# Tool scripts can run while the node is not inside the scene tree (e.g. during load).
		# Timers cannot be started until we're inside the tree.
		if not is_inside_tree():
			_grass_regen_pending = true
			return
		if _grass_regen_timer == null:
			_grass_regen_timer = Timer.new()
			_grass_regen_timer.name = "_mst_grass_regen_timer"
			_grass_regen_timer.one_shot = true
			add_child(_grass_regen_timer)
			_grass_regen_timer.timeout.connect(_apply_grass_regen)
		_grass_regen_timer.wait_time = 0.12
		_grass_regen_timer.start()
		return

	_apply_grass_regen()


func _apply_grass_regen() -> void:
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if chunk and chunk.grass_planter:
			chunk.grass_planter.regenerate_all_cells()


func _request_chunk_regen(chunk: MarchingSquaresTerrainChunk = null, use_threads: bool = true) -> void:
	if is_batch_updating:
		return
	_chunk_regen_use_threads = _chunk_regen_use_threads or use_threads
	if chunk != null:
		_chunk_regen_set[chunk] = true
	else:
		_chunk_regen_all = true

	# Coalesce editor slider drags into a single chunk rebuild.
	if EngineWrapper.instance.is_editor():
		if not is_inside_tree():
			_chunk_regen_pending = true
			return
		if _chunk_regen_timer == null:
			_chunk_regen_timer = Timer.new()
			_chunk_regen_timer.name = "_mst_chunk_regen_timer"
			_chunk_regen_timer.one_shot = true
			add_child(_chunk_regen_timer)
			_chunk_regen_timer.timeout.connect(_apply_chunk_regen)
		_chunk_regen_timer.wait_time = 0.12
		_chunk_regen_timer.start()
		return

	_apply_chunk_regen()


func _apply_chunk_regen() -> void:
	var use_threads := _chunk_regen_use_threads
	_chunk_regen_use_threads = true

	if _chunk_regen_all:
		_chunk_regen_all = false
		_chunk_regen_set.clear()
		for c: MarchingSquaresTerrainChunk in chunks.values():
			if c:
				c.regenerate_all_cells(use_threads)
		return

	var keys := _chunk_regen_set.keys()
	_chunk_regen_set.clear()
	for c in keys:
		if is_instance_valid(c):
			(c as MarchingSquaresTerrainChunk).regenerate_all_cells(use_threads)


func _request_chunk_mesh_regen() -> void:
	if is_batch_updating:
		return

	if EngineWrapper.instance.is_editor():
		if not is_inside_tree():
			_chunk_mesh_regen_pending = true
			return
		if _chunk_mesh_regen_timer == null:
			_chunk_mesh_regen_timer = Timer.new()
			_chunk_mesh_regen_timer.name = "_mst_chunk_mesh_regen_timer"
			_chunk_mesh_regen_timer.one_shot = true
			add_child(_chunk_mesh_regen_timer)
			_chunk_mesh_regen_timer.timeout.connect(_apply_chunk_mesh_regen)
		_chunk_mesh_regen_timer.wait_time = 0.12
		_chunk_mesh_regen_timer.start()
		return

	_apply_chunk_mesh_regen()


func _apply_chunk_mesh_regen() -> void:
	var use_threads := EngineWrapper.instance.is_editor()
	for c: MarchingSquaresTerrainChunk in chunks.values():
		if c:
			c.regenerate_mesh(use_threads)


func _maintenance_migrate_embedded_data() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	_initialize_data_directory()
	if data_directory.is_empty():
		push_warning("[MST] Cannot migrate: data_directory is empty. Save the scene and try again.")
		return
	if not MSTDataHandler.needs_migration(self):
		push_warning("[MST] No embedded data migration needed.")
		return
	push_warning("[MST] Migrating embedded chunk data to external storage: %s" % data_directory)
	MSTDataHandler.migrate_to_external_storage(self)
	push_warning("[MST] Migration finished. Please save the scene to persist changes.")


func _maintenance_save_all_chunks() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	_initialize_data_directory()
	MSTDataHandler.save_all_chunks(self)
	push_warning("[MST] Saved dirty chunks to external storage. (If you recently migrated, save the scene too.)")


func _maintenance_rebuild_all_chunks() -> void:
	# Coalesced by regen debouncer in-editor.
	_request_chunk_regen(null, true)


func _maintenance_rebuild_all_chunk_meshes() -> void:
	# This is a heavy operation; prefer threads in-editor.
	var use_threads := EngineWrapper.instance.is_editor()
	# If this rebuild is being used to pick up one-time mesh migrations, mark them applied
	# so we don't keep prompting on every load.
	if EngineWrapper.instance.is_editor():
		_uv_wall_sentinel_migrated = true
		_wall_material_pair_migrated = true
	for c: MarchingSquaresTerrainChunk in chunks.values():
		if c:
			c.regenerate_mesh(use_threads)
	push_warning("[MST] Rebuilt all chunk meshes. Please save the scene if this was a migration rebuild.")


func _maintenance_cleanup_orphaned_storage() -> void:
	if not EngineWrapper.instance.is_editor():
		return
	MSTDataHandler.cleanup_orphaned_chunk_files(self)
	MSTDataHandler.cleanup_orphaned_terrain_directories(self)
	push_warning("[MST] Cleaned up orphaned MST storage directories/files (if any).")


func _request_outline_apply() -> void:
	if is_batch_updating:
		return

	# Editor changes (slider drags, rapid UI updates) should coalesce into a single apply.
	if EngineWrapper.instance.is_editor():
		# Tool scripts can run while the node is not inside the scene tree (e.g. during load).
		# Timers cannot be started until we're inside the tree.
		if not is_inside_tree():
			_outline_apply_pending = true
			return
		if _outline_apply_timer == null:
			_outline_apply_timer = Timer.new()
			_outline_apply_timer.name = "_mst_outline_apply_timer"
			_outline_apply_timer.one_shot = true
			add_child(_outline_apply_timer)
			_outline_apply_timer.timeout.connect(_apply_outline_next_pass)
		_outline_apply_timer.wait_time = 0.05
		_outline_apply_timer.start()
		return

	# Runtime: coalesce within a frame.
	if _outline_apply_deferred:
		return
	_outline_apply_deferred = true
	call_deferred("_apply_outline_next_pass_deferred")


func _apply_outline_next_pass_deferred() -> void:
	_outline_apply_deferred = false
	_apply_outline_next_pass()


func _start_internal_outline_rebuild() -> void:
	if _internal_outline_rebuild_active:
		return
	_internal_outline_rebuild_queue.clear()
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if chunk and chunk.get("_internal_outline_dirty") == true:
			_internal_outline_rebuild_queue.append(chunk)
	if _internal_outline_rebuild_queue.is_empty():
		return
	_internal_outline_rebuild_active = true
	call_deferred("_internal_outline_rebuild_step")


func _internal_outline_rebuild_step() -> void:
	# Abort if silhouette got disabled mid-queue.
	if outline_mode != OutlineMode.BLACK_SILHOUETTE or outline_px <= 0.0:
		_internal_outline_rebuild_queue.clear()
		_internal_outline_rebuild_active = false
		return

	var per_frame := 1
	while per_frame > 0 and not _internal_outline_rebuild_queue.is_empty():
		var chunk: MarchingSquaresTerrainChunk = _internal_outline_rebuild_queue.pop_back()
		if is_instance_valid(chunk):
			chunk.rebuild_internal_edge_outline_mesh()
		per_frame -= 1

	if _internal_outline_rebuild_queue.is_empty():
		_internal_outline_rebuild_active = false
	else:
		call_deferred("_internal_outline_rebuild_step")


func _apply_outline_next_pass() -> void:
	if not terrain_material:
		return

	var use_black_silhouette := (outline_mode == OutlineMode.BLACK_SILHOUETTE)

	# We no longer use terrain_material.next_pass for silhouette outlines because the order is wrong.
	terrain_material.next_pass = null
	if outline_next_pass_material:
		outline_next_pass_material.next_pass = null

	# Configure pass chain + choose the active material used by chunk surfaces.
	var active_mat: Material = terrain_material
	if use_black_silhouette and outline_next_pass_material:
		outline_next_pass_material.set_shader_parameter("outline_px", outline_px)
		# World-space fallback (used only if outline_px is set to 0).
		outline_next_pass_material.set_shader_parameter("outline_thickness", 0.02)
		outline_next_pass_material.next_pass = terrain_material
		active_mat = outline_next_pass_material

	# Ensure all chunk meshes are using the correct base material.
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		if chunk and chunk.mesh and chunk.mesh.get_surface_count() > 0:
			chunk.mesh.surface_set_material(0, active_mat)
		# Internal edge outline overlay (seams + wall edges inside the chunk).
		if chunk:
			chunk.apply_internal_edge_outline_settings(use_black_silhouette, outline_px)

	# Rebuild internal edge meshes gradually when enabling silhouette, so we don't stall the editor.
	if use_black_silhouette and outline_px > 0.0:
		_start_internal_outline_rebuild()
	else:
		_internal_outline_rebuild_queue.clear()
		_internal_outline_rebuild_active = false



func _ensure_texture_slots() -> void:
	if texture_slots.size() != MAX_TEXTURE_SLOTS:
		texture_slots.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			texture_slots[i] = MarchingSquaresTextureSlot.new()
		# Default any missing 'active' to true (older saves won't have it).
		if texture_slots[i] != null and texture_slots[i].get("active") == null:
			texture_slots[i].active = true
		
		# Slot->base texture mapping (older saves won't have it).
		if texture_slots[i] != null and texture_slots[i].get("terrain_texture_index") == null:
			if i == VOID_TEXTURE_SLOT:
				texture_slots[i].terrain_texture_index = VOID_TEXTURE_SLOT
			elif i < 15:
				texture_slots[i].terrain_texture_index = i
			else:
				texture_slots[i].terrain_texture_index = 0
		elif texture_slots[i] != null:
			texture_slots[i].terrain_texture_index = clampi(int(texture_slots[i].terrain_texture_index), 0, 15)
		
		# Default any missing grass fields (older saves / older slot resources).
		# Slot 0 (Texture 1) defaults to having grass enabled.
		if texture_slots[i] != null and texture_slots[i].get("has_grass") == null:
			texture_slots[i].has_grass = (i == 0)
		# grass_texture can be null; only coerce if the key is missing (avoid nil variants).
		if texture_slots[i] != null and texture_slots[i].get("grass_texture") == null:
			texture_slots[i].grass_texture = null

	# Ensure legacy VOID slot always has a valid texture.
	if texture_slots.size() > VOID_TEXTURE_SLOT and texture_slots[VOID_TEXTURE_SLOT] and texture_slots[VOID_TEXTURE_SLOT].texture == null:
		texture_slots[VOID_TEXTURE_SLOT].texture = void_texture


func _ensure_palette_settings() -> void:
	# Expand palette-per-slot structures to 256 so shader uniform arrays are always valid.
	if slot_color_indices.size() != MAX_TEXTURE_SLOTS:
		slot_color_indices.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slot_color_indices[i] == null:
			slot_color_indices[i] = []

	if slot_blend_modes.size() != MAX_TEXTURE_SLOTS:
		slot_blend_modes.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slot_blend_modes[i] == null:
			slot_blend_modes[i] = 3

	if slot_has_outline.size() != MAX_TEXTURE_SLOTS:
		slot_has_outline.resize(MAX_TEXTURE_SLOTS)
	if slot_outline_modes.size() != MAX_TEXTURE_SLOTS:
		slot_outline_modes.resize(MAX_TEXTURE_SLOTS)
	if slot_outline_widths.size() != MAX_TEXTURE_SLOTS:
		slot_outline_widths.resize(MAX_TEXTURE_SLOTS)
	if slot_wet_enabled.size() != MAX_TEXTURE_SLOTS:
		slot_wet_enabled.resize(MAX_TEXTURE_SLOTS)
	if slot_wet_modes.size() != MAX_TEXTURE_SLOTS:
		slot_wet_modes.resize(MAX_TEXTURE_SLOTS)
	if slot_roughnesses.size() != MAX_TEXTURE_SLOTS:
		slot_roughnesses.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slot_has_outline[i] == null:
			slot_has_outline[i] = false
		if slot_outline_modes[i] == null:
			slot_outline_modes[i] = 0
		slot_outline_modes[i] = clampi(int(slot_outline_modes[i]), 0, 1)
		if slot_outline_widths[i] == null:
			slot_outline_widths[i] = outline_width
		slot_outline_widths[i] = clampf(float(slot_outline_widths[i]), 0.25, 32.0)
		if slot_wet_enabled[i] == null:
			slot_wet_enabled[i] = false
		if slot_wet_modes[i] == null:
			slot_wet_modes[i] = 0
		slot_wet_modes[i] = clampi(int(slot_wet_modes[i]), 0, 1)
		if slot_roughnesses[i] == null:
			slot_roughnesses[i] = 1.0
		slot_roughnesses[i] = clampf(float(slot_roughnesses[i]), 0.0, 1.0)


func _maybe_migrate_legacy_textures() -> void:
	# One-time migration: if slots are empty/uninitialized, copy old exported vars into slots 0..14.
	var any_slot_set := false
	for i in range(mini(15, texture_slots.size())):
		var s := texture_slots[i]
		if s != null and s.texture != null:
			any_slot_set = true
			break

	var legacy_textures: Array[Texture2D] = [
		texture_1, texture_2, texture_3, texture_4, texture_5,
		texture_6, texture_7, texture_8, texture_9, texture_10,
		texture_11, texture_12, texture_13, texture_14, texture_15,
	]
	var any_legacy_set := false
	for t in legacy_textures:
		if t != null:
			any_legacy_set = true
			break

	if any_slot_set or not any_legacy_set:
		return

	for i in range(15):
		if texture_slots[i] == null:
			texture_slots[i] = MarchingSquaresTextureSlot.new()
		texture_slots[i].texture = legacy_textures[i]

	# Legacy scales -> slot scales
	var legacy_scales: Array[float] = [
		texture_scale_1, texture_scale_2, texture_scale_3, texture_scale_4, texture_scale_5,
		texture_scale_6, texture_scale_7, texture_scale_8, texture_scale_9, texture_scale_10,
		texture_scale_11, texture_scale_12, texture_scale_13, texture_scale_14, texture_scale_15,
	]
	for i in range(15):
		texture_slots[i].scale = legacy_scales[i]


func _maybe_migrate_legacy_grass() -> void:
	# One-time migration: copy legacy grass exports into slots 0..5.
	# Legacy behavior: Texture 1 grass always on; textures 2-6 are toggleable.
	if _grass_slots_migrated:
		return
	_grass_slots_migrated = true
	_ensure_texture_slots()

	# Ensure slots exist.
	for i in range(6):
		if texture_slots[i] == null:
			texture_slots[i] = MarchingSquaresTextureSlot.new()

	# Sprites (legacy exports) -> slots
	texture_slots[0].grass_texture = grass_sprite_tex_1
	texture_slots[1].grass_texture = grass_sprite_tex_2
	texture_slots[2].grass_texture = grass_sprite_tex_3
	texture_slots[3].grass_texture = grass_sprite_tex_4
	texture_slots[4].grass_texture = grass_sprite_tex_5
	texture_slots[5].grass_texture = grass_sprite_tex_6

	# Has grass flags -> slots (cast to bool; older scenes can deserialize these as Nil)
	var t1 := tex1_has_grass
	if t1 == null:
		t1 = true
	var t2 := tex2_has_grass
	if t2 == null:
		t2 = true
	var t3 := tex3_has_grass
	if t3 == null:
		t3 = true
	var t4 := tex4_has_grass
	if t4 == null:
		t4 = true
	var t5 := tex5_has_grass
	if t5 == null:
		t5 = true
	var t6 := tex6_has_grass
	if t6 == null:
		t6 = true
	texture_slots[0].has_grass = bool(t1)
	texture_slots[1].has_grass = bool(t2)
	texture_slots[2].has_grass = bool(t3)
	texture_slots[3].has_grass = bool(t4)
	texture_slots[4].has_grass = bool(t5)
	texture_slots[5].has_grass = bool(t6)


func _set_legacy_texture_slot(slot_idx: int, tex: Texture2D) -> void:
	_ensure_texture_slots()
	if slot_idx < 0 or slot_idx >= 15:
		return
	texture_slots[slot_idx].texture = tex
	rebuild_texture_array()


func _set_legacy_texture_scale(slot_idx: int, scale: float) -> void:
	_ensure_texture_slots()
	if slot_idx < 0 or slot_idx >= 15:
		return
	texture_slots[slot_idx].scale = scale
	_push_tex_scales()


func _push_tex_scales() -> void:
	_ensure_texture_slots()
	var scales := PackedFloat32Array()
	scales.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		scales[i] = float(texture_slots[i].scale) if texture_slots[i] != null else 1.0
	terrain_material.set_shader_parameter("tex_scales", scales)


func _get_decompressed_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		var d := img.duplicate()
		d.decompress()
		# Some Godot builds don't return an Error code from decompress(), so verify via state.
		if d.is_compressed():
			return null
		img = d
	return img


const _PS_LOG_NORMALIZATION_WARNINGS := "mst/debug/log_texture_array_normalization_warnings"

func _warn_once(cache: Dictionary, key, message: String) -> void:
	# These mismatches are auto-healed by normalization. To avoid noisy editor logs,
	# we only warn if the user explicitly enables this debug ProjectSetting.
	if not bool(ProjectSettings.get_setting(_PS_LOG_NORMALIZATION_WARNINGS, false)):
		return
	if cache.has(key):
		return
	cache[key] = true
	push_warning(message)


func _normalize_image_for_texture_array(src: Image, w: int, h: int) -> Image:
	# Ensure a stable, uncompressed format (RGBA8), matching size, and no mipmaps.
	# This prevents noisy "mismatches texture array format/size" warnings and avoids
	# placeholder fallback when one texture is imported differently.
	if src == null:
		return null
	var img := src
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != w or img.get_height() != h:
		img = img.duplicate()
		# Nearest keeps pixel art crisp if a texture has the wrong size.
		img.resize(w, h, Image.INTERPOLATE_NEAREST)

	# Strip mipmaps by copying only the base layer into a fresh image.
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(0, 0))
	return out


func rebuild_texture_array() -> void:
	# Build ONLY the 16 base layers used by the shader (0..15). All 0..255 slots map
	# onto these base layers via slot_tex_index_tex.
	_ensure_texture_slots()
	var canonical_w := 1
	var canonical_h := 1

	# Find canonical size from the first non-null base texture (0..14).
	for i in range(15):
		var tex := texture_slots[i].texture if texture_slots[i] != null else null
		if tex == null:
			continue
		var img := _get_decompressed_image(tex)
		if img == null:
			continue
		canonical_w = img.get_width()
		canonical_h = img.get_height()
		break

	# IMPORTANT: The terrain shader uses alpha scissoring. If placeholder layers are
	# transparent, the floor disappears. Use an opaque white placeholder so palette
	# tinting still renders even when a base texture is unset.
	var placeholder := Image.create_empty(canonical_w, canonical_h, false, Image.FORMAT_RGBA8)
	placeholder.fill(Color(1, 1, 1, 1))
	var void_placeholder := Image.create_empty(canonical_w, canonical_h, false, Image.FORMAT_RGBA8)
	void_placeholder.fill(Color(0, 0, 0, 0))

	var images: Array[Image] = []
	images.resize(16)
	for i in range(16):
		var is_void := i == VOID_TEXTURE_SLOT
		var slot_placeholder := (void_placeholder if is_void else placeholder)

		var tex := texture_slots[i].texture if (i < texture_slots.size() and texture_slots[i] != null) else null
		if is_void:
			# Force VOID layer to be transparent.
			images[i] = void_placeholder.duplicate()
			continue
		if tex == null:
			images[i] = slot_placeholder.duplicate()
			continue

		var src := _get_decompressed_image(tex)
		if src == null:
			images[i] = slot_placeholder.duplicate()
			continue

		var needs_norm := src.get_width() != canonical_w or src.get_height() != canonical_h or src.get_format() != Image.FORMAT_RGBA8 or src.get_mipmap_count() > 1
		if needs_norm:
			_warn_once(
				_warned_texture_array_slots,
				i,
				"[MST] Base texture %d mismatches size/format/mipmaps; auto-normalizing to %dx%d RGBA8." % [i, canonical_w, canonical_h]
			)

		var img := _normalize_image_for_texture_array(src, canonical_w, canonical_h)
		images[i] = img if img != null else slot_placeholder.duplicate()

	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err != OK:
		push_warning("[MST] Failed to build terrain Texture2DArray (err=%s)." % str(err))
		return

	_runtime_texture_array = arr
	terrain_material.set_shader_parameter("vc_tex_array", _runtime_texture_array)


func rebuild_grass_texture_array() -> void:
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if grass_mesh == null or grass_mesh.material == null:
		return

	# Find canonical size from the first non-null grass sprite.
	var canonical_w := 1
	var canonical_h := 1
	for i in range(MAX_TEXTURE_SLOTS):
		var tex := texture_slots[i].grass_texture if texture_slots[i] != null else null
		if tex == null:
			continue
		var img := _get_decompressed_image(tex)
		if img == null:
			continue
		canonical_w = img.get_width()
		canonical_h = img.get_height()
		break

	# Transparent placeholder for "no sprite".
	var placeholder := Image.create_empty(canonical_w, canonical_h, false, Image.FORMAT_RGBA8)
	placeholder.fill(Color(1, 1, 1, 0))

	var images: Array[Image] = []
	images.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		var tex := texture_slots[i].grass_texture if texture_slots[i] != null else null
		if tex == null:
			images[i] = placeholder.duplicate()
			continue
		var src := _get_decompressed_image(tex)
		if src == null:
			images[i] = placeholder.duplicate()
			continue

		var needs_norm := src.get_width() != canonical_w or src.get_height() != canonical_h or src.get_format() != Image.FORMAT_RGBA8 or src.get_mipmap_count() > 1
		if needs_norm:
			_warn_once(
				_warned_grass_array_slots,
				i,
				"[MST] Grass slot %d mismatches size/format/mipmaps; auto-normalizing to %dx%d RGBA8." % [i, canonical_w, canonical_h]
			)

		var img := _normalize_image_for_texture_array(src, canonical_w, canonical_h)
		images[i] = img if img != null else placeholder.duplicate()

	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err != OK:
		push_warning("[MST] Failed to build grass Texture2DArray (err=%s)." % str(err))
		return

	_runtime_grass_texture_array = arr
	var grass_mat := grass_mesh.material as ShaderMaterial
	grass_mat.set_shader_parameter("grass_texture_array", _runtime_grass_texture_array)


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
	# NOTE: Chunks can legitimately be "dirty" in editor (e.g. after property edits).
	# Never abort initialization because that prevents terrain from loading/rendering.
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			pass
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
		# Embedded chunks exist (old scenes). Optionally migrate them to external storage.
		if auto_migrate_embedded_data:
			push_warning("[MST] Embedded chunk data detected; migrating to external storage: %s" % data_directory)
			MSTDataHandler.migrate_to_external_storage(self)
			push_warning("[MST] Migration finished. Please save the scene to persist changes.")
		else:
			push_warning("[MST] Embedded chunk data detected, but auto_migrate_embedded_data is disabled. Use Maintenance -> Migrate Embedded Data Now.")
	
	# Apply all persisted textures/colors to this terrain's unique shader materials
	# This is needed because _init() creates fresh duplicated materials that don't have
	# the terrain's saved texture values - only the base resource defaults
	# IMPORTANT: do this BEFORE chunk initialization so runtime texture baking sees correct uniforms.
	migrate_colors_to_palette()
	force_batch_update()
	
	# Legacy safety: wall_threshold=0 makes many walls classify as floor (due to smoothed normals).
	# If the saved value is effectively "unset", migrate it to a sane default.
	if wall_threshold < 0.005:
		wall_threshold = 0.25
	
	# One-time editor migrations: regenerate meshes so new wall tagging/material selection is present in geometry.
	var force_regen_for_wall_fixes : bool = false
	if EngineWrapper.instance.is_editor():
		var needs_wall_migration := (not _uv_wall_sentinel_migrated) or (not _wall_material_pair_migrated)
		if needs_wall_migration and auto_apply_one_time_migrations:
			_uv_wall_sentinel_migrated = true
			_wall_material_pair_migrated = true
			force_regen_for_wall_fixes = true
			push_warning("[MST] Applying one-time mesh migration (wall tagging/material fix). Rebuilding chunk meshes once; please save the scene afterwards.")
		elif needs_wall_migration:
			push_warning("[MST] One-time mesh migration is pending (wall tagging/material fix). Enable auto_apply_one_time_migrations or use Maintenance -> Rebuild All Chunk Meshes Now, then save the scene.")
	
	# Initialize all chunks (regenerate mesh/grass from loaded data)
	for chunk : MarchingSquaresTerrainChunk in chunks.values():
		chunk.initialize_terrain(true)
		if force_regen_for_wall_fixes:
			chunk.regenerate_mesh(true)
	
	# Chunks now exist; apply current outline mode so materials + per-chunk overlays are generated.
	_outline_apply_pending = false
	_apply_outline_next_pass()
	
	# If any tool-script setters tried to schedule work before we entered the tree,
	# flush it now.
	if _grass_regen_pending:
		_grass_regen_pending = false
		_apply_grass_regen()
	if _chunk_regen_pending:
		_chunk_regen_pending = false
		_apply_chunk_regen()
	if _chunk_mesh_regen_pending:
		_chunk_mesh_regen_pending = false
		_apply_chunk_mesh_regen()
	
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
		
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var cell := Vector2i(x, z)
				plugin.current_draw_pattern[chunk_coords][cell] = 1.0
		
		plugin.draw_pattern(self) # Apply the current selected quick paint to the new chunk on creation
		plugin.current_draw_pattern.clear()
	
	var chunk_left : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left and not chunk_left.height_map.is_empty() and not new_chunk.height_map.is_empty():
		for z in range(0, dimensions.z):
			if z < chunk_left.height_map.size() and z < new_chunk.height_map.size() and chunk_left.height_map[z].size() >= dimensions.x and new_chunk.height_map[z].size() >= 1:
				new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right and not chunk_right.height_map.is_empty() and not new_chunk.height_map.is_empty():
		for z in range(0, dimensions.z):
			if z < chunk_right.height_map.size() and z < new_chunk.height_map.size() and chunk_right.height_map[z].size() >= 1 and new_chunk.height_map[z].size() >= dimensions.x:
				new_chunk.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up and not chunk_up.height_map.is_empty() and not new_chunk.height_map.is_empty():
		if chunk_up.height_map.size() >= dimensions.z and new_chunk.height_map.size() >= 1:
			for x in range(0, dimensions.x):
				if x < chunk_up.height_map[dimensions.z - 1].size() and x < new_chunk.height_map[0].size():
					new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down : MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down and not chunk_down.height_map.is_empty() and not new_chunk.height_map.is_empty():
		if chunk_down.height_map.size() >= 1 and new_chunk.height_map.size() >= dimensions.z:
			for x in range(0, dimensions.x):
				if x < chunk_down.height_map[0].size() and x < new_chunk.height_map[dimensions.z - 1].size():
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
	# Keep legacy behavior of ensuring textures are hooked up on startup,
	# but now via Texture2DArray.
	var need_tex_array := terrain_material.get_shader_parameter("vc_tex_array") == null
	if need_tex_array:
		_ensure_texture_slots()
		_maybe_migrate_legacy_textures()
		rebuild_texture_array()
		_push_tex_scales()

	# Even if the texture array exists (existing projects), we still need to ensure
	# the palette/slot lookup textures are present; otherwise the shader may sample defaults.
	var need_palette := (
		terrain_material.get_shader_parameter("palette_colors_tex") == null
		or terrain_material.get_shader_parameter("palette_weights_tex") == null
		or terrain_material.get_shader_parameter("palette_meta_tex") == null
		or terrain_material.get_shader_parameter("palette_outline_width_tex") == null
		or terrain_material.get_shader_parameter("slot_tex_index_tex") == null
	)
	if need_palette:
		_ensure_texture_slots()
		_ensure_palette_settings()
		_rebuild_palette_uniforms()

	if grass_mat.get_shader_parameter("grass_texture_array") == null:
		_ensure_texture_slots()
		_maybe_migrate_legacy_grass()
		rebuild_grass_texture_array()
	
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
	# IMPORTANT: We cannot store slot palette data in large uniform arrays on all GPUs.
	# Some devices have a 64KB uniform buffer limit and will break when we use vec4[2048].
	# Instead, we upload palette data via small lookup textures.
	_ensure_palette_weights()
	_ensure_palette_settings()
	_ensure_texture_slots()

	var img_colors := Image.create_empty(8, MAX_TEXTURE_SLOTS, false, Image.FORMAT_RGBAF)
	var img_weights := Image.create_empty(8, MAX_TEXTURE_SLOTS, false, Image.FORMAT_RGBAF)
	var img_meta := Image.create_empty(1, MAX_TEXTURE_SLOTS, false, Image.FORMAT_RGBA8)
	var img_outline_width := Image.create_empty(1, MAX_TEXTURE_SLOTS, false, Image.FORMAT_RGBAF)
	var img_slot_tex_index := Image.create_empty(1, MAX_TEXTURE_SLOTS, false, Image.FORMAT_R8)

	# Palette colors are edited/stored as sRGB-style values (e.g. 100/255 = 0.392...).
	# Shaders operate in linear space, so convert to linear before uploading.
	var fallback := Color(0.392, 0.471, 0.318, 1.0).srgb_to_linear()

	for slot in range(MAX_TEXTURE_SLOTS):
		var indices: Array = slot_color_indices[slot]
		var count := mini(indices.size(), 8)
		var out_count := maxi(count, 1)

		# Meta packing (0..255 per channel)
		var mode := clampi(int(slot_blend_modes[slot]), 0, 3)
		var has_outline := 1 if bool(slot_has_outline[slot]) else 0
		var outline_mode := clampi(int(slot_outline_modes[slot]), 0, 1)
		img_meta.set_pixel(0, slot, Color(float(out_count) / 255.0, float(mode) / 255.0, float(has_outline) / 255.0, float(outline_mode) / 255.0))
		var wet_on := 1.0 if bool(slot_wet_enabled[slot]) else 0.0
		var wet_mode := float(clampi(int(slot_wet_modes[slot]), 0, 1))
		img_outline_width.set_pixel(0, slot, Color(float(slot_outline_widths[slot]), float(slot_roughnesses[slot]), wet_on, wet_mode))

		# Slot->base texture mapping (0..15 stored as 0..255)
		var base_idx := 0
		if slot == VOID_TEXTURE_SLOT:
			base_idx = VOID_TEXTURE_SLOT
		else:
			var s := texture_slots[slot] if slot < texture_slots.size() else null
			if s != null and s.get("terrain_texture_index") != null:
				base_idx = clampi(int(s.terrain_texture_index), 0, 15)
			else:
				base_idx = slot if slot < 15 else 0
		img_slot_tex_index.set_pixel(0, slot, Color(float(base_idx) / 255.0, 0.0, 0.0, 1.0))

		for i in range(8):
			var c := Color(1.0, 1.0, 1.0, 1.0)
			var w := 0.0
			if i < count and indices[i] < palette_colors.size():
				c = palette_colors[indices[i]].srgb_to_linear()
				w = (float(palette_weights[indices[i]]) / 100.0) if indices[i] < palette_weights.size() else 1.0
			elif i == 0 and count == 0:
				# Ensure every slot has at least 1 entry for the shader.
				c = fallback
				w = 1.0
			img_colors.set_pixel(i, slot, c)
			img_weights.set_pixel(i, slot, Color(w, 0.0, 0.0, 1.0))

	var tex_colors := ImageTexture.create_from_image(img_colors)
	var tex_weights := ImageTexture.create_from_image(img_weights)
	var tex_meta := ImageTexture.create_from_image(img_meta)
	var tex_outline_width := ImageTexture.create_from_image(img_outline_width)
	var tex_slot_tex_index := ImageTexture.create_from_image(img_slot_tex_index)

	terrain_material.set_shader_parameter("palette_colors_tex", tex_colors)
	terrain_material.set_shader_parameter("palette_weights_tex", tex_weights)
	terrain_material.set_shader_parameter("palette_meta_tex", tex_meta)
	terrain_material.set_shader_parameter("palette_outline_width_tex", tex_outline_width)
	terrain_material.set_shader_parameter("slot_tex_index_tex", tex_slot_tex_index)

	var grass_mat := grass_mesh.material as ShaderMaterial
	grass_mat.set_shader_parameter("palette_colors_tex", tex_colors)
	grass_mat.set_shader_parameter("palette_weights_tex", tex_weights)
	grass_mat.set_shader_parameter("palette_meta_tex", tex_meta)
	grass_mat.set_shader_parameter("palette_outline_width_tex", tex_outline_width)


func _push_slot_blend_modes() -> void:
	# Blend modes are packed into palette_meta_tex now.
	_rebuild_palette_uniforms()


func _ensure_outline_settings() -> void:
	_ensure_palette_settings()


func _push_slot_outline_settings() -> void:
	# Outline flags/modes are packed into palette_meta_tex now.
	_rebuild_palette_uniforms()


## Applies all shader parameters and regenerates grass once
## Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("chunk_size", dimensions)
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Texture2DArray + per-slot scales
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	rebuild_texture_array()
	_push_tex_scales()
	_ensure_palette_settings()
	_rebuild_palette_uniforms()
	
	# GRASS MATERIAL - Grass Textures (Texture2DArray)
	_maybe_migrate_legacy_grass()
	rebuild_grass_texture_array()
	
	# GRASS MATERIAL - Wind
	grass_mat.set_shader_parameter("wind_mode", wind_mode)
	grass_mat.set_shader_parameter("wind_intensity", wind_intensity)
	grass_mat.set_shader_parameter("wind_tip_color", wind_tip_color)
	grass_mat.set_shader_parameter("wind_tip_strength", wind_tip_strength)
	
	# GLOBAL NOISE - Dark-light Hues
	terrain_material.set_shader_parameter("global_noise_texture", global_noise_texture)
	terrain_material.set_shader_parameter("global_noise_scale", global_noise_scale)
	terrain_material.set_shader_parameter("global_noise_strength", global_noise_strength)
	terrain_material.set_shader_parameter("global_noise_scroll", global_noise_scroll)

	# DETAIL NORMAL - Break up lighting/spec on flat terrain.
	terrain_material.set_shader_parameter("detail_normal_texture", detail_normal_texture)
	terrain_material.set_shader_parameter("detail_normal_scale", detail_normal_scale)
	terrain_material.set_shader_parameter("detail_normal_strength", detail_normal_strength)

	# Edge Highlights is handled via a next_pass outline material.
	_apply_outline_next_pass()
	grass_mat.set_shader_parameter("global_noise_texture", global_noise_texture)
	grass_mat.set_shader_parameter("global_noise_scale", global_noise_scale)
	grass_mat.set_shader_parameter("global_noise_strength", global_noise_strength)
	grass_mat.set_shader_parameter("global_noise_scroll", global_noise_scroll)
	# Keep terrain scroll direction/speed in sync with the grass material.
	var wd = grass_mat.get_shader_parameter("wind_direction")
	if wd != null:
		terrain_material.set_shader_parameter("wind_direction", wd)
	var ws = grass_mat.get_shader_parameter("wind_speed")
	if ws != null:
		terrain_material.set_shader_parameter("wind_speed", ws)
	grass_mat.set_shader_parameter("color_variation_scale", color_variation_scale)
	grass_mat.set_shader_parameter("color_variation_strength", color_variation_strength)

	terrain_material.set_shader_parameter("outline_width", outline_width)
	_apply_outline_next_pass()


## Syncs and saves current UI texture values to the given preset resource
## Called by marching_squares_ui.gd when saving monitoring settings changes
const _PRESET_CHUNK_KEYS = [
	"dimensions",
	"cell_size",
	"collision_depth",
	"blend_mode",
	"noise_hmap",
	"extra_collision_layer",
]
const _PRESET_VERTEX_PAINTER_KEYS = [
	"wall_threshold",
	"default_wall_texture",
	"use_ridge_texture",
	"use_ledge_texture",
	"ridge_threshold",
	"ledge_threshold",
	"use_flat_normals",
	"detail_normal_texture",
	"detail_normal_scale",
	"detail_normal_strength",
	"use_cell_shading",
	"outline_width",
	"outline_mode",
	"outline_px",
]
const _PRESET_GRASS_KEYS = [
	"animation_fps",
	"grass_subdivisions",
	"grass_size",
	"grass_size_variation",
	"global_noise_texture",
	"global_noise_scroll",
	"global_noise_scale",
	"global_noise_strength",
	"wind_mode",
	"wind_intensity",
	"wind_tip_color",
	"wind_tip_strength",
]

func _get_property_name_set() -> Dictionary:
	var out: Dictionary = {}
	for p in get_property_list():
		if p is Dictionary and p.has("name"):
			out[p["name"]] = true
	return out

func _gather_preset_terrain_settings(preset: MarchingSquaresTexturePreset) -> Dictionary:
	var settings: Dictionary = {}
	if preset == null:
		return settings

	var prop_names := _get_property_name_set()
	var keys: Array[String] = []

	if preset.get("apply_chunk_settings") != null and bool(preset.apply_chunk_settings):
		keys.append_array(_PRESET_CHUNK_KEYS)
	if preset.get("apply_vertex_painter_settings") != null and bool(preset.apply_vertex_painter_settings):
		keys.append_array(_PRESET_VERTEX_PAINTER_KEYS)
	if preset.get("apply_grass_settings") != null and bool(preset.apply_grass_settings):
		keys.append_array(_PRESET_GRASS_KEYS)

	for k in keys:
		if prop_names.has(k):
			settings[k] = get(k)
	return settings

func _apply_preset_terrain_settings(settings: Dictionary) -> void:
	if settings == null or settings.is_empty():
		return
	var prop_names := _get_property_name_set()
	for k in settings.keys():
		if prop_names.has(k):
			set(k, settings[k])

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
	
	# Grass sprites (slot-based)
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if current_texture_preset.new_textures.grass_sprites.size() != MAX_TEXTURE_SLOTS:
		current_texture_preset.new_textures.grass_sprites.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		current_texture_preset.new_textures.grass_sprites[i] = texture_slots[i].grass_texture if texture_slots[i] != null else null
	
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
	current_texture_preset.slot_outline_widths = slot_outline_widths.duplicate()
	current_texture_preset.slot_wet_enabled = slot_wet_enabled.duplicate()
	current_texture_preset.slot_wet_modes = slot_wet_modes.duplicate()
	current_texture_preset.slot_roughnesses = slot_roughnesses.duplicate()
	
	# Has grass flags (slot-based)
	_ensure_texture_slots()
	_maybe_migrate_legacy_grass()
	if current_texture_preset.new_textures.has_grass.size() != MAX_TEXTURE_SLOTS:
		current_texture_preset.new_textures.has_grass.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		current_texture_preset.new_textures.has_grass[i] = bool(texture_slots[i].has_grass) if texture_slots[i] != null else false

	# Slot->base texture mapping (slot-based)
	if current_texture_preset.new_textures.get("terrain_texture_indices") is Array:
		if current_texture_preset.new_textures.terrain_texture_indices.size() != MAX_TEXTURE_SLOTS:
			current_texture_preset.new_textures.terrain_texture_indices.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			var s := texture_slots[i]
			var idx := 0
			if i == VOID_TEXTURE_SLOT:
				idx = VOID_TEXTURE_SLOT
			elif s != null and s.get("terrain_texture_index") != null:
				idx = clampi(int(s.terrain_texture_index), 0, 15)
			else:
				idx = i if i < 15 else 0
			current_texture_preset.new_textures.terrain_texture_indices[i] = idx

	# Optional: store global terrain settings in the preset (visual-only by default).
	if current_texture_preset.get("apply_terrain_settings") != null and bool(current_texture_preset.apply_terrain_settings):
		current_texture_preset.terrain_settings = _gather_preset_terrain_settings(current_texture_preset)
	
	ResourceSaver.save(current_texture_preset)


func load_from_preset(preset: MarchingSquaresTexturePreset) -> void:
	if preset == null:
		return
	
	# Optional: apply stored global terrain settings.
	if preset.get("apply_terrain_settings") != null and bool(preset.apply_terrain_settings):
		if preset.get("terrain_settings") is Dictionary:
			_apply_preset_terrain_settings(preset.terrain_settings)
	
	var has_real_palette_data := false
	for arr in preset.slot_color_indices:
		if arr.size() > 0:
			has_real_palette_data = true
			break

	if (preset.slot_color_indices.size() == 15 or preset.slot_color_indices.size() == MAX_TEXTURE_SLOTS) and has_real_palette_data:
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

	if preset.slot_blend_modes.size() == 15 or preset.slot_blend_modes.size() == MAX_TEXTURE_SLOTS:
		slot_blend_modes = preset.slot_blend_modes.duplicate()
	else:
		slot_blend_modes = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

	if preset.slot_has_outline.size() == 15 or preset.slot_has_outline.size() == MAX_TEXTURE_SLOTS:
		slot_has_outline = preset.slot_has_outline.duplicate()
	else:
		slot_has_outline = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]

	if preset.slot_outline_modes.size() == 15 or preset.slot_outline_modes.size() == MAX_TEXTURE_SLOTS:
		slot_outline_modes = preset.slot_outline_modes.duplicate()
	else:
		slot_outline_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	if preset.get("slot_outline_widths") is Array and (preset.slot_outline_widths.size() == 15 or preset.slot_outline_widths.size() == MAX_TEXTURE_SLOTS):
		slot_outline_widths = preset.slot_outline_widths.duplicate()
	else:
		slot_outline_widths = [6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0]

	if preset.get("slot_wet_enabled") is Array and (preset.slot_wet_enabled.size() == 15 or preset.slot_wet_enabled.size() == MAX_TEXTURE_SLOTS):
		slot_wet_enabled = preset.slot_wet_enabled.duplicate()
	else:
		slot_wet_enabled = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]

	if preset.get("slot_wet_modes") is Array and (preset.slot_wet_modes.size() == 15 or preset.slot_wet_modes.size() == MAX_TEXTURE_SLOTS):
		slot_wet_modes = preset.slot_wet_modes.duplicate()
	else:
		slot_wet_modes = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

	if preset.get("slot_roughnesses") is Array and (preset.slot_roughnesses.size() == 15 or preset.slot_roughnesses.size() == MAX_TEXTURE_SLOTS):
		slot_roughnesses = preset.slot_roughnesses.duplicate()
	else:
		slot_roughnesses = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

	_ensure_outline_settings()
	terrain_material.set_shader_parameter("outline_width", outline_width)

	_rebuild_palette_uniforms()
	_push_slot_blend_modes()
	_push_slot_outline_settings()

	# Apply textures + grass from the preset.
	is_batch_updating = true
	_ensure_texture_slots()
	_maybe_migrate_legacy_textures()
	_maybe_migrate_legacy_grass()

	# Terrain textures (first 15)
	if preset.new_textures != null and preset.new_textures.terrain_textures.size() >= 15:
		texture_1 = preset.new_textures.terrain_textures[0]
		texture_2 = preset.new_textures.terrain_textures[1]
		texture_3 = preset.new_textures.terrain_textures[2]
		texture_4 = preset.new_textures.terrain_textures[3]
		texture_5 = preset.new_textures.terrain_textures[4]
		texture_6 = preset.new_textures.terrain_textures[5]
		texture_7 = preset.new_textures.terrain_textures[6]
		texture_8 = preset.new_textures.terrain_textures[7]
		texture_9 = preset.new_textures.terrain_textures[8]
		texture_10 = preset.new_textures.terrain_textures[9]
		texture_11 = preset.new_textures.terrain_textures[10]
		texture_12 = preset.new_textures.terrain_textures[11]
		texture_13 = preset.new_textures.terrain_textures[12]
		texture_14 = preset.new_textures.terrain_textures[13]
		texture_15 = preset.new_textures.terrain_textures[14]

		for i in range(15):
			if texture_slots[i] == null:
				texture_slots[i] = MarchingSquaresTextureSlot.new()
			texture_slots[i].texture = preset.new_textures.terrain_textures[i]

	# Texture scales (first 15)
	if preset.new_textures != null and preset.new_textures.texture_scales.size() >= 15:
		texture_scale_1 = preset.new_textures.texture_scales[0]
		texture_scale_2 = preset.new_textures.texture_scales[1]
		texture_scale_3 = preset.new_textures.texture_scales[2]
		texture_scale_4 = preset.new_textures.texture_scales[3]
		texture_scale_5 = preset.new_textures.texture_scales[4]
		texture_scale_6 = preset.new_textures.texture_scales[5]
		texture_scale_7 = preset.new_textures.texture_scales[6]
		texture_scale_8 = preset.new_textures.texture_scales[7]
		texture_scale_9 = preset.new_textures.texture_scales[8]
		texture_scale_10 = preset.new_textures.texture_scales[9]
		texture_scale_11 = preset.new_textures.texture_scales[10]
		texture_scale_12 = preset.new_textures.texture_scales[11]
		texture_scale_13 = preset.new_textures.texture_scales[12]
		texture_scale_14 = preset.new_textures.texture_scales[13]
		texture_scale_15 = preset.new_textures.texture_scales[14]

		for i in range(15):
			if texture_slots[i] == null:
				texture_slots[i] = MarchingSquaresTextureSlot.new()
			texture_slots[i].scale = float(preset.new_textures.texture_scales[i])

	# Grass sprites + has-grass flags (slot-based 0..255)
	var p_sprites: Array = []
	var p_has: Array = []
	if preset.new_textures != null and preset.new_textures.get("grass_sprites") is Array:
		p_sprites = preset.new_textures.grass_sprites
	if preset.new_textures != null and preset.new_textures.get("has_grass") is Array:
		p_has = preset.new_textures.has_grass

	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			texture_slots[i] = MarchingSquaresTextureSlot.new()
		texture_slots[i].grass_texture = p_sprites[i] if i < p_sprites.size() else null
		# Default: first 6 enabled (legacy behavior), rest disabled.
		texture_slots[i].has_grass = bool(p_has[i]) if i < p_has.size() else (i < 6)

	# Slot->base texture mapping (0..15 per slot)
	var p_map: Array = []
	if preset.new_textures != null and preset.new_textures.get("terrain_texture_indices") is Array:
		p_map = preset.new_textures.terrain_texture_indices
	for i in range(MAX_TEXTURE_SLOTS):
		if texture_slots[i] == null:
			texture_slots[i] = MarchingSquaresTextureSlot.new()
		var idx := i if i < 15 else 0
		if i == VOID_TEXTURE_SLOT:
			idx = VOID_TEXTURE_SLOT
		if i < p_map.size() and p_map[i] != null:
			idx = clampi(int(p_map[i]), 0, 15)
		texture_slots[i].terrain_texture_index = idx

	# Keep legacy inspector fields in sync (first 6)
	if p_sprites.size() > 0:
		grass_sprite_tex_1 = p_sprites[0] if p_sprites.size() > 0 else grass_sprite_tex_1
		grass_sprite_tex_2 = p_sprites[1] if p_sprites.size() > 1 else grass_sprite_tex_2
		grass_sprite_tex_3 = p_sprites[2] if p_sprites.size() > 2 else grass_sprite_tex_3
		grass_sprite_tex_4 = p_sprites[3] if p_sprites.size() > 3 else grass_sprite_tex_4
		grass_sprite_tex_5 = p_sprites[4] if p_sprites.size() > 4 else grass_sprite_tex_5
		grass_sprite_tex_6 = p_sprites[5] if p_sprites.size() > 5 else grass_sprite_tex_6
	if p_has.size() > 0:
		tex1_has_grass = bool(p_has[0]) if p_has.size() > 0 else tex1_has_grass
		tex2_has_grass = bool(p_has[1]) if p_has.size() > 1 else tex2_has_grass
		tex3_has_grass = bool(p_has[2]) if p_has.size() > 2 else tex3_has_grass
		tex4_has_grass = bool(p_has[3]) if p_has.size() > 3 else tex4_has_grass
		tex5_has_grass = bool(p_has[4]) if p_has.size() > 4 else tex5_has_grass
		tex6_has_grass = bool(p_has[5]) if p_has.size() > 5 else tex6_has_grass

	is_batch_updating = false
	force_batch_update()
	_request_grass_regen()

#endregion
