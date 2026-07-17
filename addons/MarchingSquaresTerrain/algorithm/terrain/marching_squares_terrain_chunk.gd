@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunk

# Explicit preloads avoid tool-script class resolution issues.
const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")
const MSTTerrainCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_cell.gd")
const MSTPrefabCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/prefab/marching_squares_prefab_cell.gd")
const MSTDataHandler := preload("res://addons/MarchingSquaresTerrain/resources/mst_data_handler.gd")
const MAX_WALL_PAINT_STAMPS := 64

enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}
enum GrassMode {GRASS, GRASSLESS}

const MERGE_MODE = {
	Mode.CUBIC: 0.6,
	Mode.POLYHEDRON: 1.3,
	Mode.ROUNDED_POLYHEDRON: 2.1,
	Mode.SEMI_ROUND: 5.0,
	Mode.SPHERICAL: 20.0,
}

# These two need to be normal export vars or else godot's internal logic crashes the plugin
@export var terrain_system : MarchingSquaresTerrain
@export var chunk_coords : Vector2i = Vector2i.ZERO

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var merge_mode : Mode = Mode.POLYHEDRON: # The max height distance between points before a wall is created between them
	set(mode):
		merge_mode = mode
		if is_inside_tree() and grass_planter and grass_planter.multimesh:
			var grass_mat : ShaderMaterial = grass_planter.multimesh.mesh.material as ShaderMaterial
			if mode == Mode.SEMI_ROUND or mode == Mode.SPHERICAL:
				grass_mat.set_shader_parameter("is_merge_round", true)
			else:
				grass_mat.set_shader_parameter("is_merge_round", false)
			merge_threshold = MERGE_MODE[mode]
			regenerate_all_cells(true)
@export_storage var height_map : Array # Stores the heights from the heightmap
#region cell_geometry storage
# Color maps are now ephemeral and created at runtime
# Persisted via MSTDataHandler
var color_map_0 : PackedColorArray # Stores the colors from vertex_color_0 (ground)
var color_map_1 : PackedColorArray # Stores the colors from vertex_color_1 (ground)
var wall_color_map_0 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 0)
var wall_color_map_1 : PackedColorArray # Stores the colors for wall vertices (slot encoding channel 1)
var grass_mask_map : PackedColorArray # Stores if a cell should have grass or not
#endregion

var merge_threshold : float = MERGE_MODE[Mode.POLYHEDRON]

var grass_planter : MarchingSquaresGrassPlanter
var wall_paint_stamp_positions : PackedVector3Array = PackedVector3Array()
var wall_paint_stamp_normals : PackedVector3Array = PackedVector3Array()
var wall_paint_stamp_radii : PackedFloat32Array = PackedFloat32Array()
var wall_paint_stamp_texture_indices : PackedInt32Array = PackedInt32Array()

var global_position_cached : Vector3 = Vector3.ZERO

var cell_generation_mutex : Mutex = Mutex.new()

var bake_material : ShaderMaterial = preload("res://addons/MarchingSquaresTerrain/resources/plugin_materials/mst_terrain_baked.tres")

#region chunk variables
# Size of the 2 dimensional cell array (xz value) and y scale (y value)
var dimensions : Vector3i:
	get:
		return terrain_system.dimensions
# Unit XZ size of a single cell
var cell_size : Vector2:
	get:
		return terrain_system.cell_size
#endregion

var st : SurfaceTool # The surfacetool used to construct the current terrain

var cell_geometry : Dictionary = {} # Stores all generated tiles so that their geometry can quickly be reused

var needs_update : Array[Array] # Stores which tiles need to be updated because one of their corners' heights was changed.
var _skip_save_on_exit : bool = false # Set to true when chunk is removed temporarily (undo/redo)
var _data_dirty : bool = false # Set to true when source data changes, triggers save in MSTDataHandler

#region temporary storage vars
# Temporary storage for ephemeral resources during scene save
var _temp_mesh : ArrayMesh
var _temp_grass_multimesh : MultiMesh
var _temp_collision_shapes : Array[ConcavePolygonShape3D] = []  # COMMENT: Old scenes may have duplicates
var _temp_height_map : Array  # Source data - saved to external storage, not scene file
#endregion

var _grass_regen_queued: bool = false
var _mesh_regen_queued: bool = false
var _suppress_grass_mode_side_effects: bool = false


func set_skip_save_on_exit(value: bool) -> void:
	_skip_save_on_exit = value

#region blend option vars
# Terrain blend options to allow for smooth color and height blend influence at transitions and at different heights
var lower_thresh : float = 0.3 # Sharp bands: < 0.3 = lower color
var upper_thresh : float = 0.7 #, > 0.7 = upper color, middle = blend
var blend_zone := upper_thresh - lower_thresh
#endregion


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_mode : GrassMode = GrassMode.GRASS:
	set(value):
		grass_mode = value
		if _suppress_grass_mode_side_effects:
			return
		_temp_grass_multimesh = null
		if is_inside_tree():
			_apply_grass_mode()
			if grass_planter:
				_queue_grass_regen()
		mark_dirty()


func _apply_shadow_visibility_settings() -> void:
	cast_shadow = SHADOW_CASTING_SETTING_ON
	if terrain_system == null:
		return
	var world_w := float(max(dimensions.x - 1, 1)) * cell_size.x
	var world_d := float(max(dimensions.z - 1, 1)) * cell_size.y
	var world_h := float(max(dimensions.y, 1))
	extra_cull_margin = max(max(world_w, world_d), world_h)


func _clear_grass_planter() -> void:
	_temp_grass_multimesh = null
	if grass_planter:
		if grass_planter.multimesh:
			grass_planter.multimesh = null
		grass_planter.owner = null
		grass_planter.free()
	grass_planter = null


func _ensure_grass_planter() -> bool:
	grass_planter = get_node_or_null("GrassPlanter")
	if not grass_planter:
		grass_planter = MarchingSquaresGrassPlanter.new()
		if not color_map_0 or not color_map_1:
			generate_color_maps()
		if not grass_mask_map:
			generate_grass_mask_map()
		add_child(grass_planter)
	grass_planter.name = "GrassPlanter"
	grass_planter._chunk = self
	grass_planter.terrain_system = terrain_system
	grass_planter.setup(self)
	EngineWrapper.instance.set_owner_recursive(grass_planter)

	var grass_count_changed := false
	if _temp_grass_multimesh:
		grass_planter.multimesh = _temp_grass_multimesh
	if grass_planter.multimesh == null:
		grass_planter.setup(self)
		grass_count_changed = true
	grass_count_changed = grass_planter.ensure_multimesh_count() or grass_count_changed
	if not grass_planter.multimesh:
		grass_planter.setup(self)
		grass_count_changed = true
	if grass_planter.multimesh:
		grass_planter.multimesh.mesh = terrain_system.grass_mesh
	return grass_count_changed


func _apply_grass_mode() -> void:
	if grass_mode == GrassMode.GRASSLESS:
		_clear_grass_planter()
	else:
		_ensure_grass_planter()

# Called by TerrainSystem parent
func initialize_terrain(should_regenerate_mesh: bool =  true):
	_apply_shadow_visibility_settings()
	needs_update = []
	# Initally all cells will need to be updated to show the newly loaded height
	for z in range(dimensions.z - 1):
		needs_update.append([])
		for x in range(dimensions.x - 1):
			needs_update[z].append(true)

	var has_baked_grass_multimesh := _temp_grass_multimesh != null and grass_mode == GrassMode.GRASS
	var grass_count_changed := false
	if grass_mode == GrassMode.GRASS:
		grass_count_changed = _ensure_grass_planter()
	else:
		_clear_grass_planter()

	# Generate maps if not loaded from external storage (works for both editor and runtime)
	# Validate height_map shape — serialized scenes may contain empty arrays or malformed rows.
	var need_hm := true
	if height_map and height_map is Array and height_map.size() == dimensions.z:
		need_hm = false
		for row in height_map:
			if not (row is Array) or row.size() !=  dimensions.x:
				need_hm = true
				break
	if need_hm:
		generate_height_map()
	# Validate color maps sizes
	if not (color_map_0 is PackedColorArray) or color_map_0.size() !=  dimensions.z * dimensions.x or not (color_map_1 is PackedColorArray) or color_map_1.size() != dimensions.z * dimensions.x:
		generate_color_maps()
	if not (wall_color_map_0 is PackedColorArray) or wall_color_map_0.size() !=  dimensions.z * dimensions.x or not (wall_color_map_1 is PackedColorArray) or wall_color_map_1.size() != dimensions.z * dimensions.x:
		generate_wall_color_maps()
	if not (grass_mask_map is PackedColorArray) or grass_mask_map.size() !=  dimensions.z * dimensions.x:
		generate_grass_mask_map()

	if not mesh and should_regenerate_mesh:
		regenerate_mesh(true)
	elif mesh:
		if terrain_system:
			_apply_chunk_surface_material()
		if not _temp_collision_shapes.is_empty():
			_recreate_collision_body()
		else:
			for child in get_children():
				if child is StaticBody3D:
					child.free()
			create_trimesh_collision()
			_apply_collision_layers()

	# Respect deferred initialization: chunk creation adds the node first, then paints/seams it,
	# and only after that should the first full mesh/grass build happen.
	var can_generate_grass_now := should_regenerate_mesh or mesh != null or has_baked_grass_multimesh
	if grass_mode == GrassMode.GRASS and grass_planter and can_generate_grass_now and (not has_baked_grass_multimesh or grass_count_changed):
		if mesh != null and not has_baked_grass_multimesh:
			_queue_grass_regen()
		else:
			grass_planter.regenerate_all_cells()

	var has_texture_array_source := (
		terrain_system.get("texture_library") != null
		or str(terrain_system.get("baked_albedo_array_path")) != ""
	)
	if not EngineWrapper.instance.is_editor() and terrain_system.enable_runtime_texture_baking and not has_texture_array_source:
		var baker := MarchingSquaresGeometryBaker.new()
		baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution
		baker.finished.connect(func(mesh_: Mesh, _original: MeshInstance3D, img: Image):
			mesh = mesh_
			var mat : Material
			if terrain_system.bake_material_override:
				mat = terrain_system.bake_material_override.duplicate()
			else:
				mat = bake_material.duplicate()

			if mat is StandardMaterial3D:
				mat.albedo_texture = ImageTexture.create_from_image(img)
			elif mat is ShaderMaterial:
				mat.set_shader_parameter("texture_albedo", ImageTexture.create_from_image(img))
			if mesh and mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, mat)
		, CONNECT_ONE_SHOT)
		baker.bake_geometry_texture(self, get_tree())


func _save_external_data_before_scene_strip() -> bool:
	if not terrain_system or _skip_save_on_exit:
		return false
	var dir_path := terrain_system.data_directory
	if dir_path == null or dir_path == "":
		return false
	var needs_save := _data_dirty
	if not needs_save:
		needs_save = not MSTDataHandler.metadata_exists(dir_path, chunk_coords)
	if not needs_save:
		return true
	if not MSTDataHandler.ensure_directory_exists(dir_path):
		return false
	if not MSTDataHandler.save_chunk_resources(terrain_system, self):
		return false
	_data_dirty = false
	terrain_system._storage_initialized = true
	return MSTDataHandler.metadata_exists(dir_path, chunk_coords)

func _notification(what: int) -> void:
	if not EngineWrapper.instance.is_editor():
		return

	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			var can_strip_scene_data := _save_external_data_before_scene_strip()
			if not can_strip_scene_data:
				push_error("MST: Refusing to strip chunk source data because external save failed for " + str(chunk_coords))
				return
			# Store height_map and clear - source data saved to external storage, not scene
			_skip_save_on_exit = _skip_save_on_exit # Surpress warning
			_temp_height_map = height_map
			height_map = []

			# Clear in-memory cache of generated cell geometry to avoid serializing Vector2i keys
			cell_geometry.clear()

			# Store mesh and clear to prevent serialization
			_temp_mesh = mesh
			mesh = null

			# Store grass multimesh and clear
			if grass_planter and grass_planter.multimesh:
				_temp_grass_multimesh = grass_planter.multimesh
				grass_planter.multimesh = null

			# Handle ALL collision bodies (old scenes may have multiple duplicates!)
			_temp_collision_shapes.clear()
			var bodies_to_free : Array[StaticBody3D] = []
			for child in get_children():
				if child is StaticBody3D:
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
							_temp_collision_shapes.append(shape_child.shape)
							shape_child.shape = null  # Clear to prevent sub_resource save
						shape_child.owner = null
					child.owner = null
					bodies_to_free.append(child)
			# Free all bodies (after iteration to avoid modifying while iterating)
			for body in bodies_to_free:
				body.name += "_"
				body.queue_free()

		NOTIFICATION_EDITOR_POST_SAVE:
			# Restore height_map
			if _temp_height_map:
				height_map = _temp_height_map
				_temp_height_map = []

			# Restore mesh
			if _temp_mesh:
				mesh = _temp_mesh
				_temp_mesh = null

			# Restore grass multimesh
			if _temp_grass_multimesh and grass_planter:
				grass_planter.multimesh = _temp_grass_multimesh
				_temp_grass_multimesh = null

			# Recreate ONE collision body (only need one, even if old scene had duplicates)
			if not _temp_collision_shapes.is_empty():
				_recreate_collision_body.call_deferred()

		NOTIFICATION_PREDELETE:
			# Safety cleanup - clear owner on ALL collision nodes
			for child in get_children():
				if child is StaticBody3D:
					child.owner = null
					for shape_child in child.get_children():
						if shape_child is CollisionShape3D:
							shape_child.owner = null


func _enter_tree() -> void:
	if not terrain_system:
		return
	# Defensive: clear any serialized runtime caches that can cause variant lookup errors.
	if cell_geometry and cell_geometry.size() > 0:
		# Ensure keys are Vector2i; if not, dump and clear to avoid variant errors on load.
		var keys_valid := true
		for k in cell_geometry.keys():
			if not (k is Vector2i):
				keys_valid = false
				break
		if not keys_valid:
			cell_geometry.clear()
			push_warning("[MST] Cleared unexpected serialized cell_geometry: please re-save the scene to remove runtime caches.")

	if get_parent() !=  terrain_system:
		push_error("Chunk must remain within its parent!")
		return
	terrain_system.chunks[chunk_coords] = self


func _exit_tree() -> void:
	# Clear temp references
	_temp_height_map = []
	_temp_mesh = null
	_temp_grass_multimesh = null
	_temp_collision_shapes.clear()

	# Clear owner on ALL collision nodes to prevent serialization edge cases
	if EngineWrapper.instance.is_editor():
		for child in get_children():
			if child is StaticBody3D:
				child.owner = null
				for shape_child in child.get_children():
					if shape_child is CollisionShape3D:
						shape_child.owner = null

	# Only erase if terrain_system still has THIS chunk at chunk_coords
	if terrain_system and terrain_system.chunks.get(chunk_coords) == self:
		terrain_system.chunks.erase(chunk_coords)


func regenerate_mesh(use_threads: bool =  false):
	_apply_shadow_visibility_settings()
	var previous_mesh := mesh
	st = SurfaceTool.new()
	if mesh and mesh.get_surface_count() > 0:
		st.create_from(mesh, 0)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)

	var start_time : int = Time.get_ticks_msec()

	generate_terrain_cells(use_threads)

	st.generate_normals()
	st.index()
	# Create a new mesh out of floor, and add the wall surface to it
	var committed_mesh := st.commit()
	var has_valid_surface := committed_mesh != null and committed_mesh.get_surface_count() > 0
	if not has_valid_surface:
		if previous_mesh != null and previous_mesh.get_surface_count() > 0:
			mesh = previous_mesh
			push_warning("[MST] Skipped replacing chunk mesh with an empty surface set. The previous mesh was preserved.")
		else:
			mesh = null
	else:
		mesh = committed_mesh

	if mesh and terrain_system and mesh.get_surface_count() > 0:
		_apply_chunk_surface_material()

	for child in get_children():
		if child is StaticBody3D:
			child.free()
	if mesh != null and mesh.get_surface_count() > 0:
		create_trimesh_collision()
		_apply_collision_layers()

	var elapsed_time : int = Time.get_ticks_msec() - start_time
	print_verbose("Generated terrain in "+str(elapsed_time)+"ms")


func generate_terrain_cells(use_threads: bool):
	if not cell_geometry:
		cell_geometry = {}

	global_position_cached = global_position if is_inside_tree() else position
	var thread_pool := MarchingSquaresThreadPool.new(max(1, OS.get_processor_count()))

	for z in range(dimensions.z - 1):
		for x in range(dimensions.x - 1):
			var cell_coords = Vector2i(x, z)
			var work_load : Callable
			# If geometry did not change, copy already generated geometry and skip this cell
			if not needs_update[z][x]:
				# If cached geometry is missing or malformed, fallback to regenerating this cell.
				if not cell_geometry.has(cell_coords):
					needs_update[z][x] = true
					# fall through to generation

					# continue to next iteration so generation handles it
					# (avoid executing the cached-copy branch)
					# Note: do NOT call continue here because we want the generation code below to run in this iteration.
					pass
				else:
					work_load =  func():
						cell_generation_mutex.lock()
						# Safely fetch cached arrays; if anything is missing, unlock and bail so generation occurs.
						if not cell_geometry.has(cell_coords):
							cell_generation_mutex.unlock()
							return
						var entry = cell_geometry[cell_coords]
						if not entry.has("verts"):
							cell_generation_mutex.unlock()
							return
						var verts = entry["verts"]
						var uvs = entry["uvs"]
						var uv2s = entry["uv2s"]
						var color_0s = entry["color_0s"]
						var color_1s = entry["color_1s"]
						var custom_1_values = entry["custom_1_values"]
						var mat_blend = entry["mat_blend"]
						var is_floor = entry["is_floor"]
						for i in range(len(verts)):
							st.set_smooth_group(0 if is_floor[i] == true else -1)
							st.set_uv(uvs[i])
							st.set_uv2(uv2s[i])
							st.set_color(color_0s[i])
							st.set_custom(0, color_1s[i])
							st.set_custom(1, custom_1_values[i])
							st.set_custom(2, mat_blend[i])
							st.add_vertex(verts[i])
						cell_generation_mutex.unlock()
					if use_threads:
						thread_pool.enqueue(work_load)
					else:
						work_load.call()
					continue

			# Cell is now being updated
			needs_update[z][x] = false

			# If geometry did change or none exists yet,
			# Create an entry for this cell (will also override any existing one)
			cell_geometry[cell_coords] = {
				"verts": PackedVector3Array(),
				"uvs": PackedVector2Array(),
				"uv2s": PackedVector2Array(),
				"color_0s": PackedColorArray(),
				"color_1s": PackedColorArray(),
				"custom_1_values": PackedColorArray(),
				"mat_blend": PackedColorArray(),
				"is_floor": [],
			}

			var color_helper := MSTVertexColorHelper.new()
			# Defensive: guard against malformed/serialized height_map rows
			var h00 := 0.0
			var h01 := 0.0
			var h10 := 0.0
			var h11 := 0.0
			if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x:
				h00 = float(height_map[z][x])
			if height_map is Array and height_map.size() > z and height_map[z] is Array and height_map[z].size() > x+1:
				h01 = float(height_map[z][x+1])
			else:
				h01 = h00
			if height_map is Array and height_map.size() > z+1 and height_map[z+1] is Array and height_map[z+1].size() > x:
				h10 = float(height_map[z+1][x])
			else:
				h10 = h00
			if height_map is Array and height_map.size() > z+1 and height_map[z+1] is Array and height_map[z+1].size() > x+1:
				h11 = float(height_map[z+1][x+1])
			else:
				h11 = h00
			var cell
			if terrain_system != null and terrain_system.prefab_set != null:
				cell = MSTPrefabCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
			else:
				cell = MSTTerrainCell.new(self, color_helper, h00, h01, h10, h11, merge_threshold)
			color_helper.chunk = self
			color_helper.cell = cell

			work_load =  func():
				cell.generate_geometry(cell_coords)
				if not use_threads and EngineWrapper.instance.is_editor() and grass_planter and grass_planter.terrain_system:
					grass_planter.generate_grass_on_cell(cell_coords)
			if use_threads:
				thread_pool.enqueue(work_load)
			else:
				work_load.call()

	if use_threads:
		thread_pool.start()
		thread_pool.wait()


func add_polygons(
	cell_coords : Vector2i,
	pts : PackedVector3Array,
	uvs : PackedVector2Array,
	uv2s : PackedVector2Array,
	color_0s : PackedColorArray,
	color_1s : PackedColorArray,
	custom_1_values : PackedColorArray,
	mat_blends : PackedColorArray,
	floors : PackedByteArray,
	):
		assert(pts.size() % 3 == 0)
		assert(pts.size() == uvs.size())
		assert(pts.size() == uv2s.size())
		assert(pts.size() == color_0s.size())
		assert(pts.size() == color_1s.size())
		assert(pts.size() == custom_1_values.size())
		assert(pts.size() == mat_blends.size())
		assert(pts.size() == floors.size())

		cell_generation_mutex.lock()
		var floor_mode : bool = true
		st.set_smooth_group(0)
		for i in range(pts.size()):
			if floor_mode and not floors[i]:
				floor_mode = false
				st.set_smooth_group(-1)
			elif not floor_mode and floors[i]:
				floor_mode = true
				st.set_smooth_group(0)
			_add_point(cell_coords, pts[i], uvs[i], uv2s[i], color_0s[i], color_1s[i], custom_1_values[i], mat_blends[i], floors[i])
		cell_generation_mutex.unlock()


# Adds a point. Coordinates are relative to the top-left corner (not mesh origin relative)
# UV.x is closeness to the bottom of an edge. UV.Y is closeness to the edge of a cliff
func _add_point(cell_coords: Vector2i, vert: Vector3, uv: Vector2, uv2: Vector2, color_0: Color, color_1: Color, custom_1_value: Color, mat_blend: Color, is_floor: bool):
	st.set_color(color_0)
	st.set_custom(0, color_1)
	st.set_custom(1, custom_1_value)
	st.set_custom(2, mat_blend)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(vert)

	cell_geometry[cell_coords]["verts"].append(vert)
	cell_geometry[cell_coords]["uvs"].append(uv)
	cell_geometry[cell_coords]["uv2s"].append(uv2)
	cell_geometry[cell_coords]["color_0s"].append(color_0)
	cell_geometry[cell_coords]["color_1s"].append(color_1)
	cell_geometry[cell_coords]["custom_1_values"].append(custom_1_value)
	cell_geometry[cell_coords]["mat_blend"].append(mat_blend)
	cell_geometry[cell_coords]["is_floor"].append(is_floor)

#region cell_geometry generators (on being empty)

func generate_height_map(base_height: float = 0.0):
	height_map = []
	height_map.resize(dimensions.z)
	for z in range(dimensions.z):
		height_map[z] = []
		height_map[z].resize(dimensions.x)
		for x in range(dimensions.x):
			height_map[z][x] = base_height

	var noise := terrain_system.noise_hmap
	if noise:
		for z in range(dimensions.z):
			for x in range(dimensions.x):
				var noise_x = (chunk_coords.x * (dimensions.x - 1)) + x
				var noise_z = (chunk_coords.y * (dimensions.z -1)) + z
				var noise_sample = noise.get_noise_2d(noise_x, noise_z)
				height_map[z][x] = base_height + (noise_sample * dimensions.y)


func generate_height_map_from_surfaces(base_height: float = 0.0, source_root: Node = null) -> bool:
	generate_height_map(base_height)

	var chunk_world_origin := terrain_system.to_global(Vector3(
		float(chunk_coords.x) * float(dimensions.x - 1) * cell_size.x,
		0.0,
		float(chunk_coords.y) * float(dimensions.z - 1) * cell_size.y
	))
	var chunk_max_world := chunk_world_origin + Vector3(
		float(dimensions.x - 1) * cell_size.x,
		0.0,
		float(dimensions.z - 1) * cell_size.y
	)
	var chunk_min_x := minf(chunk_world_origin.x, chunk_max_world.x) - cell_size.x
	var chunk_max_x := maxf(chunk_world_origin.x, chunk_max_world.x) + cell_size.x
	var chunk_min_z := minf(chunk_world_origin.z, chunk_max_world.z) - cell_size.y
	var chunk_max_z := maxf(chunk_world_origin.z, chunk_max_world.z) + cell_size.y

	var terrain_tree := terrain_system.get_tree() if terrain_system else null
	if terrain_tree == null:
		return false

	if source_root == null:
		source_root = terrain_tree.edited_scene_root
	if source_root == null:
		source_root = terrain_tree.current_scene
	if source_root == null:
		return false

	var all_surface_instances: Array[MeshInstance3D] = []
	_collect_surface_instances(source_root, all_surface_instances)
	var surface_instances: Array[MeshInstance3D] = []
	for surface_instance in all_surface_instances:
		if _surface_overlaps_chunk_xz(
			surface_instance,
			chunk_min_x,
			chunk_max_x,
			chunk_min_z,
			chunk_max_z
		):
			surface_instances.append(surface_instance)
	if surface_instances.is_empty():
		return false

	var surface_sample_cache: Array[Dictionary] = []
	var highest_surface_y := chunk_world_origin.y + float(dimensions.y) * 8.0 + 100.0
	for surface_instance in surface_instances:
		var cache := _build_surface_sample_cache(
			surface_instance,
			chunk_min_x,
			chunk_max_x,
			chunk_min_z,
			chunk_max_z
		)
		if cache.is_empty():
			continue
		surface_sample_cache.append(cache)
		highest_surface_y = maxf(highest_surface_y, float(cache["max_y"]))

	if surface_sample_cache.is_empty():
		return false

	var ray_direction := Vector3.DOWN
	var any_hit := false
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			var world_point := chunk_world_origin + Vector3(
				float(x) * cell_size.x,
				0.0,
				float(z) * cell_size.y
			)
			var ray_origin := Vector3(world_point.x, highest_surface_y, world_point.z)
			var best_y := -INF
			for cache in surface_sample_cache:
				var sampled_y := _sample_surface_height_from_cache(cache, ray_origin, ray_direction)
				if sampled_y > best_y:
					best_y = sampled_y
			if best_y > -INF:
				height_map[z][x] = best_y
				any_hit = true

	return any_hit


func _collect_surface_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child == null:
			continue
		if child == self or child is MarchingSquaresTerrainChunk:
			continue
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.visible:
				out.append(mesh_instance)
		_collect_surface_instances(child, out)


func _surface_overlaps_chunk_xz(
	surface_instance: MeshInstance3D,
	chunk_min_x: float,
	chunk_max_x: float,
	chunk_min_z: float,
	chunk_max_z: float
	) -> bool:
	var local_aabb := surface_instance.get_aabb()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for corner in _get_aabb_corners(local_aabb):
		var world_corner := surface_instance.global_transform * corner
		min_x = minf(min_x, world_corner.x)
		max_x = maxf(max_x, world_corner.x)
		min_z = minf(min_z, world_corner.z)
		max_z = maxf(max_z, world_corner.z)

	if max_x < chunk_min_x or min_x > chunk_max_x:
		return false
	if max_z < chunk_min_z or min_z > chunk_max_z:
		return false
	return true


func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	return [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]


func _build_surface_sample_cache(
	surface_instance: MeshInstance3D,
	chunk_min_x: float,
	chunk_max_x: float,
	chunk_min_z: float,
	chunk_max_z: float
	) -> Dictionary:
	if surface_instance.mesh == null:
		return {}

	var faces := surface_instance.mesh.get_faces()
	if faces.is_empty():
		return {}

	var transform := surface_instance.global_transform
	var triangles: Array[Dictionary] = []
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var max_y := -INF

	for i in range(0, faces.size(), 3):
		var a := transform * faces[i]
		var b := transform * faces[i + 1]
		var c := transform * faces[i + 2]
		var tri_min_x := minf(a.x, minf(b.x, c.x))
		var tri_max_x := maxf(a.x, maxf(b.x, c.x))
		var tri_min_z := minf(a.z, minf(b.z, c.z))
		var tri_max_z := maxf(a.z, maxf(b.z, c.z))

		if tri_max_x < chunk_min_x or tri_min_x > chunk_max_x:
			continue
		if tri_max_z < chunk_min_z or tri_min_z > chunk_max_z:
			continue

		min_x = minf(min_x, tri_min_x)
		max_x = maxf(max_x, tri_max_x)
		min_z = minf(min_z, tri_min_z)
		max_z = maxf(max_z, tri_max_z)
		max_y = maxf(max_y, maxf(a.y, maxf(b.y, c.y)))

		triangles.append({
			"a": a,
			"b": b,
			"c": c,
			"min_x": tri_min_x,
			"max_x": tri_max_x,
			"min_z": tri_min_z,
			"max_z": tri_max_z,
		})

	if triangles.is_empty():
		return {}

	return {
		"triangles": triangles,
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
		"max_y": max_y,
	}


func _sample_surface_height_from_cache(
	cache: Dictionary,
	ray_origin: Vector3,
	ray_direction: Vector3
	) -> float:
	if cache.is_empty():
		return -INF

	if ray_origin.x < float(cache["min_x"]) or ray_origin.x > float(cache["max_x"]):
		return -INF
	if ray_origin.z < float(cache["min_z"]) or ray_origin.z > float(cache["max_z"]):
		return -INF

	var best_y := -INF
	for triangle in cache["triangles"]:
		if ray_origin.x < float(triangle["min_x"]) or ray_origin.x > float(triangle["max_x"]):
			continue
		if ray_origin.z < float(triangle["min_z"]) or ray_origin.z > float(triangle["max_z"]):
			continue

		var hit := Geometry3D.ray_intersects_triangle(
			ray_origin,
			ray_direction,
			triangle["a"],
			triangle["b"],
			triangle["c"]
		)
		if hit != null and hit is Vector3:
			var hit_point := hit as Vector3
			if hit_point.y > best_y:
				best_y = hit_point.y

	return best_y


func generate_color_maps():
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	color_map_0.resize(dimensions.z * dimensions.x)
	color_map_1.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			color_map_0[z*dimensions.x + x] = Color(0,0,0,0)
			color_map_1[z*dimensions.x + x] = Color(0,0,0,0)


func generate_wall_color_maps():
	wall_color_map_0 = PackedColorArray()
	wall_color_map_1 = PackedColorArray()
	wall_color_map_0.resize(dimensions.z * dimensions.x)
	wall_color_map_1.resize(dimensions.z * dimensions.x)
	var default_idx := 0
	if terrain_system !=  null:
		default_idx = int(terrain_system.default_wall_texture)
	var cols := MSTVertexColorHelper.texture_index_to_colors(default_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			wall_color_map_0[z*dimensions.x + x] = c0
			wall_color_map_1[z*dimensions.x + x] = c1


func apply_default_wall_texture(old_idx: int, new_idx: int) -> bool:
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	if old_idx == new_idx:
		return false
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	for i in range(wall_color_map_0.size()):
		var idx := MSTVertexColorHelper.get_texture_index_from_colors(wall_color_map_0[i], wall_color_map_1[i])
		if idx == old_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_unpainted(new_idx: int) -> bool:
	# "Unpainted" is defined as wall map still matching ground map.
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	if not color_map_0 or not color_map_1:
		return false
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	var count := min(wall_color_map_0.size(), color_map_0.size())
	for i in range(count):
		var wall_idx := MSTVertexColorHelper.get_texture_index_from_colors(wall_color_map_0[i], wall_color_map_1[i])
		var ground_idx := MSTVertexColorHelper.get_texture_index_from_colors(color_map_0[i], color_map_1[i])
		if wall_idx == ground_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_legacy_init(new_idx: int) -> bool:
	# Legacy wall map initialization used Color(1,0,0,0) for BOTH channels to mean "texture 0".
	# This breaks default wall texture behavior and should be treated as unpainted.
	if not wall_color_map_0 or not wall_color_map_1:
		return false
	var legacy := Color(1, 0, 0, 0)
	var cols := MSTVertexColorHelper.texture_index_to_colors(new_idx)
	var c0 : Color = cols[0]
	var c1 : Color = cols[1]
	var changed := false
	for i in range(wall_color_map_0.size()):
		if wall_color_map_0[i] == legacy and wall_color_map_1[i] == legacy:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true
	if changed:
		mark_dirty()
	return changed


func generate_grass_mask_map():
	grass_mask_map = PackedColorArray()
	grass_mask_map.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			grass_mask_map[z*dimensions.x + x] = Color(1.0, 1.0, 1.0, 1.0)

#endregion

#region cell_geometry getters

func get_height(cc: Vector2i) -> float:
	return height_map[cc.y][cc.x]


func get_color_0(cc: Vector2i) -> Color:
	return color_map_0[cc.y*dimensions.x + cc.x]


func get_color_1(cc: Vector2i) -> Color:
	return color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_0(cc: Vector2i) -> Color:
	return wall_color_map_0[cc.y*dimensions.x + cc.x]


func get_wall_color_1(cc: Vector2i) -> Color:
	return wall_color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_map_state() -> Dictionary:
	return {
		"color_0": wall_color_map_0.duplicate(),
		"color_1": wall_color_map_1.duplicate(),
	}


func get_grass_mask(cc: Vector2i) -> Color:
	return grass_mask_map[cc.y*dimensions.x + cc.x]

#endregion

#region cell_geometry setters

# Draw to height.
# Returns the coordinates of all additional chunks affected by this height change.
# Empty for inner points, neightoring edge for non-corner edges, and 3 other corners for corner points.
func draw_height(x: int, z: int, y: float):
	# Contains chunks that were updated
	height_map[z][x] = y
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_0(x: int, z: int, color: Color):
	color_map_0[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_color_1(x: int, z: int, color: Color):
	color_map_1[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_0(x: int, z: int, color: Color):
	wall_color_map_0[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_wall_color_1(x: int, z: int, color: Color):
	wall_color_map_1[z*dimensions.x + x] = color
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func draw_grass_mask(x: int, z: int, masked: Color):
	grass_mask_map[z*dimensions.x + x] = masked
	mark_dirty()
	notify_needs_update(z, x)
	notify_needs_update(z, x-1)
	notify_needs_update(z-1, x)
	notify_needs_update(z-1, x-1)


func set_wall_color_map_state(state: Dictionary, use_threads: bool = false) -> void:
	wall_color_map_0 = state.get("color_0", PackedColorArray()).duplicate()
	wall_color_map_1 = state.get("color_1", PackedColorArray()).duplicate()
	mark_dirty()
	regenerate_all_cells(use_threads)


func get_wall_paint_stamp_state() -> Dictionary:
	return {
		"positions": wall_paint_stamp_positions.duplicate(),
		"normals": wall_paint_stamp_normals.duplicate(),
		"radii": wall_paint_stamp_radii.duplicate(),
		"texture_indices": wall_paint_stamp_texture_indices.duplicate(),
	}


func set_wall_paint_stamp_state(state: Dictionary) -> void:
	wall_paint_stamp_positions = state.get("positions", PackedVector3Array())
	wall_paint_stamp_normals = state.get("normals", PackedVector3Array())
	wall_paint_stamp_radii = state.get("radii", PackedFloat32Array())
	wall_paint_stamp_texture_indices = state.get("texture_indices", PackedInt32Array())
	mark_dirty()
	_apply_chunk_surface_material()


func append_wall_paint_stamp_to_state(state: Dictionary, world_pos: Vector3, world_normal: Vector3, radius: float, texture_idx: int) -> Dictionary:
	var positions: PackedVector3Array = state.get("positions", PackedVector3Array()).duplicate()
	var normals: PackedVector3Array = state.get("normals", PackedVector3Array()).duplicate()
	var radii: PackedFloat32Array = state.get("radii", PackedFloat32Array()).duplicate()
	var texture_indices: PackedInt32Array = state.get("texture_indices", PackedInt32Array()).duplicate()
	if positions.size() >= MAX_WALL_PAINT_STAMPS:
		positions.remove_at(0)
		normals.remove_at(0)
		radii.remove_at(0)
		texture_indices.remove_at(0)
	positions.append(world_pos)
	normals.append(world_normal.normalized())
	radii.append(maxf(radius, 0.001))
	texture_indices.append(clampi(texture_idx, 0, 255))
	return {
		"positions": positions,
		"normals": normals,
		"radii": radii,
		"texture_indices": texture_indices,
	}


func append_wall_paint_stamp(world_pos: Vector3, world_normal: Vector3, radius: float, texture_idx: int) -> Dictionary:
	return append_wall_paint_stamp_to_state(get_wall_paint_stamp_state(), world_pos, world_normal, radius, texture_idx)

#endregion


func _apply_chunk_surface_material() -> void:
	if mesh == null or terrain_system == null or mesh.get_surface_count() <= 0:
		return
	var base_mat := terrain_system.get_chunk_surface_material()
	if base_mat == null or not (base_mat is ShaderMaterial):
		mesh.surface_set_material(0, base_mat)
		return
	var mat: ShaderMaterial = (base_mat as ShaderMaterial).duplicate(true)
	_sync_wall_paint_shader_params(mat)
	mesh.surface_set_material(0, mat)


func refresh_surface_material() -> void:
	_apply_chunk_surface_material()


func queue_mesh_regen(use_threads: bool = false) -> void:
	if _mesh_regen_queued:
		return
	_mesh_regen_queued = true
	call_deferred("_run_deferred_mesh_regen", use_threads)


func _run_deferred_mesh_regen(use_threads: bool = false) -> void:
	_mesh_regen_queued = false
	if not is_inside_tree():
		return
	regenerate_mesh(use_threads)


func _queue_grass_regen() -> void:
	if _grass_regen_queued:
		return
	_grass_regen_queued = true
	call_deferred("_run_deferred_grass_regen")


func _run_deferred_grass_regen() -> void:
	_grass_regen_queued = false
	if grass_mode != GrassMode.GRASS or not is_inside_tree() or not is_instance_valid(grass_planter):
		return
	grass_planter.regenerate_all_cells()


func _sync_wall_paint_shader_params(mat: ShaderMaterial) -> void:
	var positions: Array[Vector4] = []
	var data_b: Array[Vector4] = []
	var stamp_count := min(
		wall_paint_stamp_positions.size(),
		min(wall_paint_stamp_normals.size(), min(wall_paint_stamp_radii.size(), wall_paint_stamp_texture_indices.size()))
	)
	stamp_count = mini(stamp_count, MAX_WALL_PAINT_STAMPS)
	for i in range(MAX_WALL_PAINT_STAMPS):
		if i < stamp_count:
			var p := wall_paint_stamp_positions[i]
			var n := wall_paint_stamp_normals[i].normalized()
			positions.append(Vector4(p.x, p.y, p.z, float(wall_paint_stamp_radii[i])))
			data_b.append(Vector4(n.x, n.y, n.z, float(wall_paint_stamp_texture_indices[i])))
		else:
			positions.append(Vector4.ZERO)
			data_b.append(Vector4.ZERO)
	mat.set_shader_parameter("wall_paint_count", stamp_count)
	mat.set_shader_parameter("wall_paint_stamps_a", positions)
	mat.set_shader_parameter("wall_paint_stamps_b", data_b)
	mat.set_shader_parameter("wall_paint_plane_thickness", maxf(minf(cell_size.x, cell_size.y) * 0.08, 0.03))
	mat.set_shader_parameter("wall_paint_blend_width", maxf(minf(cell_size.x, cell_size.y) * 0.18, 0.06))

func notify_needs_update(z: int, x: int):
	if z < 0 or z >=  terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return

	needs_update[z][x] = true


## Mark chunk as having modified source data - triggers save in MSTDataHandler.
func mark_dirty() -> void:
	_data_dirty = true


## Recreate collision body after scene save (deferred call for proper physics refresh).
func _recreate_collision_body() -> void:
	if not is_inside_tree() or _temp_collision_shapes.is_empty():
		_temp_collision_shapes.clear()
		return

	for child in get_children():
		if child is StaticBody3D:
			child.free()

	# Only create ONE body with the FIRST shape
	var shape : ConcavePolygonShape3D = null
	if _temp_collision_shapes.size() > 0 and _temp_collision_shapes[0] !=  null:
		shape = _temp_collision_shapes[0]
	_temp_collision_shapes.clear()
	if shape == null:
		# Nothing to create
		return

	var body := StaticBody3D.new()
	body.name = name + "_col"
	body.collision_layer = 17
	if terrain_system:
		body.set_collision_layer_value(terrain_system.extra_collision_layer, true)

	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	col_shape.shape = shape
	col_shape.visible = false
	body.add_child(col_shape)
	add_child(body)

	# Set owner for editor visibility at first, but we clear it later
	if EngineWrapper.instance.is_editor():
		var scene_root = EngineWrapper.instance.get_root_for_node(self)
		if scene_root:
			body.owner = scene_root
			col_shape.owner = scene_root
		for group in get_groups():
			if group.begins_with("navmesh_"):
				body.add_to_group(group)


func _apply_collision_layers() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.collision_layer = 17
			child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
			for _child in child.get_children():
				if _child is CollisionShape3D:
					_child.set_visible(false)


func regenerate_all_cells(use_threads: bool):
	for z in range(dimensions.z-1):
		for x in range(dimensions.x-1):
			needs_update[z][x] = true

	regenerate_mesh(use_threads)


@export_tool_button("Export GLB") var bake =  func():
	var tree := get_tree()

	var baker = MarchingSquaresGeometryBaker.new()
	baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution

	var f := func(bakedMesh: Mesh, original: MeshInstance3D, bakedTexture: Image):
		var dialog := FileDialog.new()
		get_tree().root.add_child(dialog)
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM

		var inst := MeshInstance3D.new()
		inst.mesh = bakedMesh
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(bakedTexture)
		if inst.mesh and inst.mesh.get_surface_count() > 0:
			inst.mesh.surface_set_material(0, mat)
		var file_selected := func(path: String):
			var state := GLTFState.new()
			var doc := GLTFDocument.new()
			doc.append_from_scene(inst, state)
			doc.write_to_filesystem(state, path)
			dialog.queue_free()
		dialog.add_filter("*.glb", "GLB file")
		dialog.connect("file_selected", file_selected)
		dialog.popup_centered()

	baker.finished.connect(f, CONNECT_ONE_SHOT)
	baker.bake_geometry_texture(self, tree)
