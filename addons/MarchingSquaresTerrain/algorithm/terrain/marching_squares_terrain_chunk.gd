@tool
extends MeshInstance3D
class_name MarchingSquaresTerrainChunk

# Explicit preloads avoid tool-script class resolution issues.
const MSTVertexColorHelper := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_vertex_color_helper.gd")
const MSTTerrainCell := preload("res://addons/MarchingSquaresTerrain/algorithm/terrain/marching_squares_terrain_cell.gd")

enum Mode {CUBIC, POLYHEDRON, ROUNDED_POLYHEDRON, SEMI_ROUND, SPHERICAL}

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

var global_position_cached : Vector3 = Vector3.ZERO

var cell_generation_mutex : Mutex = Mutex.new()

var bake_material : ShaderMaterial = preload("uid://cbbvkbnwmr2em")

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


# Collision nodes (reused to avoid destroying/recreating nodes every mesh regen)
var _collision_body: StaticBody3D = null
var _collision_shape_node: CollisionShape3D = null

# Internal edge outline overlay (generated mesh; never saved).
const _INTERNAL_OUTLINE_SHADER := preload("res://addons/MarchingSquaresTerrain/resources/shaders/mst_internal_edge_outline.gdshader")
var _internal_outline_instance: MeshInstance3D = null
var _internal_outline_material: ShaderMaterial = null

#region blend option vars
# Terrain blend options to allow for smooth color and height blend influence at transitions and at different heights 
var lower_thresh : float = 0.3 # Sharp bands: < 0.3 = lower color
var upper_thresh : float = 0.7 #, > 0.7 = upper color, middle = blend
var blend_zone := upper_thresh - lower_thresh
#endregion

# Called by TerrainSystem parent
func initialize_terrain(should_regenerate_mesh: bool = true):
	needs_update = []
	# Initally all cells will need to be updated to show the newly loaded height
	for z in range(dimensions.z - 1):
		needs_update.append([])
		for x in range(dimensions.x - 1):
			needs_update[z].append(true)

	_cleanup_old_chunk_outline_overlays()
	
	if not get_node_or_null("GrassPlanter"):
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
		grass_planter.setup(self)
		EngineWrapper.instance.set_owner_recursive(grass_planter)
	else:
		if not grass_planter:
			grass_planter = get_node_or_null("GrassPlanter")
		grass_planter.terrain_system = terrain_system
		grass_planter._chunk = self
		
	if _temp_grass_multimesh:
		grass_planter.multimesh = _temp_grass_multimesh
	grass_planter.ensure_multimesh_count()
	if not grass_planter.multimesh:
		grass_planter.setup(self)
		grass_planter.regenerate_all_cells()
	grass_planter.multimesh.mesh = terrain_system.grass_mesh
	
	# Generate maps if not loaded from external storage (works for both editor and runtime)
	if not height_map:
		generate_height_map()
	if not color_map_0 or not color_map_1:
		generate_color_maps()
	var migrated_wall_defaults := false
	if not wall_color_map_0 or not wall_color_map_1:
		generate_wall_color_maps()
	else:
		# Auto-fix legacy/uninitialized wall maps (often all slot 0) so Default Wall actually applies.
		migrated_wall_defaults = _migrate_uninitialized_wall_color_maps()
	if not grass_mask_map:
		generate_grass_mask_map()
	
	# If we migrated wall defaults, we MUST rebuild even in baked-mode loads (should_regenerate_mesh can be false).
	if migrated_wall_defaults:
		regenerate_mesh(true)
	elif should_regenerate_mesh and not mesh:
		regenerate_mesh(true)
	elif mesh:
		if terrain_system:
			if mesh and mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, terrain_system.get_chunk_surface_material())
		if not _temp_collision_shapes.is_empty():
			_recreate_collision_body()
		else:
			for child in get_children():
				if child is StaticBody3D:
					child.free()
			create_collision_with_depth(terrain_system.collision_depth)
	
	# If any outline mode is enabled we keep the live shader so the outline stays visible.
	var _outline_mode: int = int(terrain_system.outline_mode) if terrain_system else 0
	if not EngineWrapper.instance.is_editor() and terrain_system.enable_runtime_texture_baking and _outline_mode == 0:
		var baker := MarchingSquaresGeometryBaker.new()
		baker.terrain_system = terrain_system
		baker.polygon_texture_resolution = terrain_system.polygon_texture_resolution
		baker.finished.connect(func(mesh_: Mesh, _original: MeshInstance3D, img: Image):
			mesh = mesh_
			var mat : Material
			if terrain_system.bake_material_override: 
				mat = terrain_system.bake_material_override.duplicate()
			else:
				mat = bake_material.duplicate()
				baker.transfer_shader_props(terrain_system.terrain_material, mat)
			
			if mat is StandardMaterial3D:
				mat.albedo_texture = ImageTexture.create_from_image(img)
			elif mat is ShaderMaterial:
				mat.set_shader_parameter("texture_albedo", ImageTexture.create_from_image(img))
			if mesh and mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, mat)
		, CONNECT_ONE_SHOT)
		baker.bake_geometry_texture(self, get_tree())


func _notification(what: int) -> void:
	if not EngineWrapper.instance.is_editor():
		return
	
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			# Store height_map and clear - source data saved to external storage, not scene
			_skip_save_on_exit = _skip_save_on_exit # Surpress warning
			_temp_height_map = height_map
			height_map = []
			
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
	if get_parent() != terrain_system:
		push_error("Chunk must remain within its parent!")
	terrain_system.chunks[chunk_coords] = self


func _exit_tree() -> void:
	# If we're leaving the scene in the editor (e.g. switching scenes), persist dirty chunk data
	# to external storage so edits aren't lost.
	if EngineWrapper.instance.is_editor() and _data_dirty and not _skip_save_on_exit and terrain_system and not terrain_system.data_directory.is_empty() and height_map and not height_map.is_empty():
		MSTDataHandler.save_chunk_resources(terrain_system, self)
		_data_dirty = false
	
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


func regenerate_mesh(use_threads: bool = false):
	st = SurfaceTool.new()
	# NOTE: create_from() is unnecessary here because we immediately begin() a fresh surface.
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
	st.set_custom_format(2, SurfaceTool.CUSTOM_RGBA_FLOAT)
	
	var start_time : int = Time.get_ticks_msec()
	
	generate_terrain_cells(use_threads)
	
	st.generate_normals()
	st.index()
	# Create a new mesh out of floor, and add the wall surface to it
	mesh = st.commit()
	
	if mesh and terrain_system:
		if mesh.get_surface_count() > 0:
			mesh.surface_set_material(0, terrain_system.get_chunk_surface_material())
	
	create_collision_with_depth(terrain_system.collision_depth)
	_regenerate_internal_edge_outline_mesh()
	
	var elapsed_time : int = Time.get_ticks_msec() - start_time
	print_verbose("Generated terrain in "+str(elapsed_time)+"ms")


func _cleanup_old_chunk_outline_overlays() -> void:
	# Option 2 (Chunk Outline) was removed. Old scenes might still have these generated overlay nodes.
	for legacy_name in ["WallBoundaryOutline", "SeamOutline"]:
		var n := get_node_or_null(legacy_name)
		if n:
			n.queue_free()


func apply_internal_edge_outline_settings(enabled: bool, px: float) -> void:
	if not enabled or px <= 0.0:
		if _internal_outline_instance:
			_internal_outline_instance.mesh = null
			_internal_outline_instance.visible = false
		return
	_ensure_internal_edge_outline_instance()
	_internal_outline_instance.visible = true
	if _internal_outline_material:
		_internal_outline_material.set_shader_parameter("outline_px", px)
	# If toggled on after being off, we need to rebuild once.
	if _internal_outline_instance.mesh == null:
		_regenerate_internal_edge_outline_mesh()


func _ensure_internal_edge_outline_instance() -> void:
	if _internal_outline_instance == null:
		var existing := get_node_or_null("InternalEdgeOutline")
		if existing is MeshInstance3D:
			_internal_outline_instance = existing
		else:
			_internal_outline_instance = MeshInstance3D.new()
			_internal_outline_instance.name = "InternalEdgeOutline"
			_internal_outline_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_internal_outline_instance)
		_internal_outline_instance.owner = null

	if _internal_outline_material == null:
		_internal_outline_material = ShaderMaterial.new()
		_internal_outline_material.shader = _INTERNAL_OUTLINE_SHADER
		_internal_outline_material.set_shader_parameter("outline_color", Color(0, 0, 0, 1))
		_internal_outline_material.set_shader_parameter("outline_px", 2.0)
		_internal_outline_material.set_shader_parameter("depth_bias", 0.00035)
		_internal_outline_material.render_priority = 3


func _quant_v3i(v: Vector3, quant_scale: float) -> Vector3i:
	return Vector3i(
		int(round(v.x * quant_scale)),
		int(round(v.y * quant_scale)),
		int(round(v.z * quant_scale))
	)


func _v3i_greater(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x > b.x
	if a.y != b.y:
		return a.y > b.y
	return a.z > b.z


func _edge_key(a: Vector3, b: Vector3, quant_scale: float) -> String:
	# Order-independent, quantized edge key so A-B equals B-A.
	var qa := _quant_v3i(a, quant_scale)
	var qb := _quant_v3i(b, quant_scale)
	if _v3i_greater(qa, qb):
		var t := qa
		qa = qb
		qb = t
	return "%d,%d,%d|%d,%d,%d" % [qa.x, qa.y, qa.z, qb.x, qb.y, qb.z]


func _accum_internal_edge(a: Vector3, b: Vector3, tri_is_floor: bool, quant_scale: float,
		edge_points: Dictionary, floor_counts: Dictionary, wall_counts: Dictionary) -> void:
	var k = _edge_key(a, b, quant_scale)
	if not edge_points.has(k):
		edge_points[k] = [a, b]
	if tri_is_floor:
		floor_counts[k] = int(floor_counts.get(k, 0)) + 1
	else:
		wall_counts[k] = int(wall_counts.get(k, 0)) + 1


func _regenerate_internal_edge_outline_mesh() -> void:
	if terrain_system == null:
		return

	var enabled := (int(terrain_system.outline_mode) == int(MarchingSquaresTerrain.OutlineMode.BLACK_SILHOUETTE))
	var px := float(terrain_system.outline_px)
	if not enabled or px <= 0.0:
		apply_internal_edge_outline_settings(false, 0.0)
		return

	_ensure_internal_edge_outline_instance()
	apply_internal_edge_outline_settings(true, px)

	var have_cell_geo := not (cell_geometry == null or cell_geometry.is_empty())
	if not have_cell_geo:
		_internal_outline_instance.mesh = null
		return

	var edge_points: Dictionary = {}
	var floor_counts: Dictionary = {}
	var wall_counts: Dictionary = {}

	# Quantize to stabilize shared edge keys across tiny float differences.
	# Keep this very small so we don't accidentally merge nearby-but-distinct edges.
	var quant_step: float = 0.0005
	var quant_scale: float = 1.0 / quant_step

	for cell_coords in cell_geometry.keys():
		var verts: PackedVector3Array = cell_geometry[cell_coords].get("verts", PackedVector3Array())
		var is_floor_arr: Array = cell_geometry[cell_coords].get("is_floor", [])
		var has_is_floor := is_floor_arr != null and is_floor_arr.size() == verts.size()
		var tri_count: int = verts.size() / 3
		for t in range(tri_count):
			var i := t * 3
			var p0: Vector3 = verts[i]
			var p1: Vector3 = verts[i + 1]
			var p2: Vector3 = verts[i + 2]
			var tri_is_floor := bool(is_floor_arr[i]) if has_is_floor else true
			_accum_internal_edge(p0, p1, tri_is_floor, quant_scale, edge_points, floor_counts, wall_counts)
			_accum_internal_edge(p1, p2, tri_is_floor, quant_scale, edge_points, floor_counts, wall_counts)
			_accum_internal_edge(p2, p0, tri_is_floor, quant_scale, edge_points, floor_counts, wall_counts)

	var st_outline := SurfaceTool.new()
	st_outline.begin(Mesh.PRIMITIVE_TRIANGLES)

	var c_neg := Color(0, 0, 0, 1) # COLOR.r < 0.5 => -1 side
	var c_pos := Color(1, 0, 0, 1) # COLOR.r >= 0.5 => +1 side

	for k in edge_points.keys():
		var wc := int(wall_counts.get(k, 0))
		var fc := int(floor_counts.get(k, 0))
		# Draw seams (floor<->wall) and wall boundary edges (outer wall contour & step walls).
		if not ((wc > 0 and fc > 0) or wc == 1):
			continue
		var pts: Array = edge_points[k]
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[1]
		var d: Vector3 = b - a
		var dl2 := d.length_squared()
		if dl2 < 1e-10:
			continue
		d = d / sqrt(dl2)

		# Quad made of two triangles, expanded in shader based on NORMAL (edge dir) + COLOR.r (side).
		st_outline.set_normal(d)
		st_outline.set_color(c_neg)
		st_outline.add_vertex(a)
		st_outline.set_normal(d)
		st_outline.set_color(c_neg)
		st_outline.add_vertex(b)
		st_outline.set_normal(d)
		st_outline.set_color(c_pos)
		st_outline.add_vertex(b)

		st_outline.set_normal(d)
		st_outline.set_color(c_neg)
		st_outline.add_vertex(a)
		st_outline.set_normal(d)
		st_outline.set_color(c_pos)
		st_outline.add_vertex(b)
		st_outline.set_normal(d)
		st_outline.set_color(c_pos)
		st_outline.add_vertex(a)

	var outline_mesh: ArrayMesh = st_outline.commit()
	if outline_mesh == null or outline_mesh.get_surface_count() == 0:
		_internal_outline_instance.mesh = null
		return

	_internal_outline_instance.mesh = outline_mesh
	if _internal_outline_material:
		outline_mesh.surface_set_material(0, _internal_outline_material)


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
				work_load = func():
					cell_generation_mutex.lock()
					var verts = cell_geometry[cell_coords]["verts"]
					var uvs = cell_geometry[cell_coords]["uvs"]
					var uv2s = cell_geometry[cell_coords]["uv2s"]
					var color_0s = cell_geometry[cell_coords]["color_0s"]
					var color_1s = cell_geometry[cell_coords]["color_1s"]
					var custom_1_values = cell_geometry[cell_coords]["custom_1_values"]
					var mat_blend = cell_geometry[cell_coords]["mat_blend"]
					var is_floor = cell_geometry[cell_coords]["is_floor"]
					
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
			var cell := MSTTerrainCell.new(self, color_helper, height_map[z][x], height_map[z][x+1], height_map[z+1][x], height_map[z+1][x+1], merge_threshold)
			color_helper.chunk = self
			color_helper.cell = cell
			
			work_load = func():
				cell.generate_geometry(cell_coords)
				if grass_planter and grass_planter.terrain_system:
					grass_planter.generate_grass_on_cell(cell_coords)
				# Break RefCounted cycles (cell <-> helper) so temporary objects can be freed.
				color_helper.cell = null
				color_helper.chunk = null
				cell.color_helper = null
				cell.chunk = null
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
# UV.x is closeness to the bottom of an edge. UV.y is closeness to the edge of a cliff.
# Walls use a sentinel UV outside [0..1] (currently 2,2) so shaders can reliably detect walls.
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
				height_map[z][x] = noise_sample * dimensions.y


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

	# Initialize walls to the terrain's Default Wall Texture.
	# We encode indices in the "byte in c0.r" form (0..255) so it works with the 256-slot path,
	# but decoding still supports legacy one-hot values.
	var default_idx := 0
	if terrain_system:
		default_idx = clampi(int(terrain_system.default_wall_texture), 0, 255)
	var enc := _encode_texture_index_colors(default_idx)
	var c0 : Color = enc[0]
	var c1 : Color = enc[1]

	for z in range(dimensions.z):
		for x in range(dimensions.x):
			wall_color_map_0[z*dimensions.x + x] = c0
			wall_color_map_1[z*dimensions.x + x] = c1


func generate_grass_mask_map():
	grass_mask_map = PackedColorArray()
	grass_mask_map.resize(dimensions.z * dimensions.x)
	for z in range(dimensions.z):
		for x in range(dimensions.x):
			grass_mask_map[z*dimensions.x + x] = Color(1.0, 1.0, 1.0, 1.0)


static func _encode_texture_index_colors(idx: int) -> Array[Color]:
	idx = clampi(int(idx), 0, 255)
	return [Color(float(idx) / 255.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0)]


static func _decode_texture_index(c0: Color, c1: Color) -> int:
	# Mirror MarchingSquaresTerrainVertexColorHelper.get_texture_index_from_colors so wall maps can be mixed legacy/new.
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


func _migrate_uninitialized_wall_color_maps() -> bool:
	if not terrain_system or not wall_color_map_0 or not wall_color_map_1:
		return false

	var default_idx := clampi(int(terrain_system.default_wall_texture), 0, 255)
	var enc := _encode_texture_index_colors(default_idx)
	var def_c0 : Color = enc[0]
	var def_c1 : Color = enc[1]

	# 1) If the map is uniform (common on legacy loads), assume it was just a default and remap to Default Wall.
	var first_idx := _decode_texture_index(wall_color_map_0[0], wall_color_map_1[0])
	var uniform := true
	for i in range(1, wall_color_map_0.size()):
		if _decode_texture_index(wall_color_map_0[i], wall_color_map_1[i]) != first_idx:
			uniform = false
			break

	if uniform:
		if first_idx == default_idx:
			return false
		for i in range(wall_color_map_0.size()):
			wall_color_map_0[i] = def_c0
			wall_color_map_1[i] = def_c1
		mark_dirty()
		return true

	# 2) Heuristic fix: if most wall indices equal the ground indices, walls will render as "floor".
	# This typically indicates older/bad data, not intentional painting. Only touch wall cells that match ground.
	if not color_map_0 or not color_map_1 or color_map_0.size() != wall_color_map_0.size():
		return false

	var same_as_ground := 0
	for i in range(wall_color_map_0.size()):
		var w_idx := _decode_texture_index(wall_color_map_0[i], wall_color_map_1[i])
		var g_idx := _decode_texture_index(color_map_0[i], color_map_1[i])
		if w_idx == g_idx:
			same_as_ground += 1

	# Only apply if it's a strong signal (avoid clobbering deliberate wall painting).
	if float(same_as_ground) / float(max(1, wall_color_map_0.size())) < 0.75:
		return false

	var changed := false
	for i in range(wall_color_map_0.size()):
		var w_idx := _decode_texture_index(wall_color_map_0[i], wall_color_map_1[i])
		var g_idx := _decode_texture_index(color_map_0[i], color_map_1[i])
		if w_idx == g_idx and w_idx != default_idx:
			wall_color_map_0[i] = def_c0
			wall_color_map_1[i] = def_c1
			changed = true

	if changed:
		mark_dirty()
	return changed


func apply_default_wall_texture(old_idx: int, new_idx: int) -> bool:
	if not wall_color_map_0 or not wall_color_map_1:
		return false

	old_idx = clampi(int(old_idx), 0, 255)
	new_idx = clampi(int(new_idx), 0, 255)
	if old_idx == new_idx:
		return false

	var enc := _encode_texture_index_colors(new_idx)
	var c0 : Color = enc[0]
	var c1 : Color = enc[1]

	var changed := false
	for i in range(wall_color_map_0.size()):
		if _decode_texture_index(wall_color_map_0[i], wall_color_map_1[i]) == old_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true

	if changed:
		mark_dirty()
	return changed


func apply_default_wall_to_unpainted(default_idx: int) -> bool:
	# Treat any wall cell that matches the ground cell as "unpainted" (or legacy-corrupted) and remap it.
	if not wall_color_map_0 or not wall_color_map_1 or not color_map_0 or not color_map_1:
		return false
	if color_map_0.size() != wall_color_map_0.size() or color_map_1.size() != wall_color_map_1.size():
		return false

	default_idx = clampi(int(default_idx), 0, 255)
	var enc := _encode_texture_index_colors(default_idx)
	var c0 : Color = enc[0]
	var c1 : Color = enc[1]

	var changed := false
	for i in range(wall_color_map_0.size()):
		var w_idx := _decode_texture_index(wall_color_map_0[i], wall_color_map_1[i])
		var g_idx := _decode_texture_index(color_map_0[i], color_map_1[i])
		if w_idx == g_idx and w_idx != default_idx:
			wall_color_map_0[i] = c0
			wall_color_map_1[i] = c1
			changed = true

	if changed:
		mark_dirty()
	return changed

#endregion

#region cell_geometry getters

func get_height(cc: Vector2i) -> float:
	return height_map[cc.y][cc.x]


func _sample_height_bilinear(local_x: float, local_z: float) -> float:
	# local_x/local_z are in chunk-local space (same as mesh vertices).
	if height_map == null or height_map.is_empty():
		return 0.0
	var max_x: float = (dimensions.x - 1) * cell_size.x
	var max_z: float = (dimensions.z - 1) * cell_size.y
	var x := clampf(local_x, 0.0, max_x)
	var z := clampf(local_z, 0.0, max_z)
	var fx := x / cell_size.x
	var fz := z / cell_size.y
	var x0 := clampi(int(floor(fx)), 0, dimensions.x - 1)
	var z0 := clampi(int(floor(fz)), 0, dimensions.z - 1)
	var x1 := clampi(x0 + 1, 0, dimensions.x - 1)
	var z1 := clampi(z0 + 1, 0, dimensions.z - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00: float = height_map[z0][x0]
	var h10: float = height_map[z0][x1]
	var h01: float = height_map[z1][x0]
	var h11: float = height_map[z1][x1]
	var hx0 := lerpf(h00, h10, tx)
	var hx1 := lerpf(h01, h11, tx)
	return lerpf(hx0, hx1, tz)


func get_color_0(cc: Vector2i) -> Color:
	return color_map_0[cc.y*dimensions.x + cc.x]


func get_color_1(cc: Vector2i) -> Color:
	return color_map_1[cc.y*dimensions.x + cc.x]


func get_wall_color_0(cc: Vector2i) -> Color:
	return wall_color_map_0[cc.y*dimensions.x + cc.x]


func get_wall_color_1(cc: Vector2i) -> Color:
	return wall_color_map_1[cc.y*dimensions.x + cc.x]


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

#endregion

func notify_needs_update(z: int, x: int):
	if z < 0 or z >= terrain_system.dimensions.z-1 or x < 0 or x >= terrain_system.dimensions.x-1:
		return
	
	needs_update[z][x] = true


## Mark chunk as having modified source data - triggers save in MSTDataHandler.
func mark_dirty() -> void:
	_data_dirty = true
	# Terrain source data is stored externally; ensure the editor scene is marked dirty
	# so users are prompted to save when switching scenes.
	if EngineWrapper.instance.is_editor():
		var editor_interface = Engine.get_singleton('EditorInterface')
		if editor_interface and editor_interface.has_method("mark_scene_as_unsaved"):
			editor_interface.mark_scene_as_unsaved()


## Recreate collision body after scene save (deferred call for proper physics refresh).
func _recreate_collision_body() -> void:
	if not is_inside_tree() or _temp_collision_shapes.is_empty():
		_temp_collision_shapes.clear()
		return
		
	for child in get_children():
		if child is StaticBody3D:
			child.free()
	
	# Only create ONE body with the FIRST shape
	var shape : ConcavePolygonShape3D = _temp_collision_shapes[0]
	_temp_collision_shapes.clear()
	
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

func _ensure_collision_body() -> void:
		# Reuse a single collision body + shape node to avoid editor tree churn and allocations.
		if _collision_body != null and is_instance_valid(_collision_body) and _collision_body.get_parent() == self:
			pass
		else:
			_collision_body = null
			_collision_shape_node = null

		if _collision_body == null:
			var existing: Array[StaticBody3D] = []
			for child in get_children():
				if child is StaticBody3D:
					existing.append(child)
			if existing.size() > 0:
				_collision_body = existing[0]
				for i in range(1, existing.size()):
					existing[i].queue_free()
			else:
				_collision_body = StaticBody3D.new()
				add_child(_collision_body)

		_collision_body.name = name + "_col"

		var shapes: Array[CollisionShape3D] = []
		for c in _collision_body.get_children():
			if c is CollisionShape3D:
				shapes.append(c)
		if shapes.size() > 0:
			_collision_shape_node = shapes[0]
			for i in range(1, shapes.size()):
				shapes[i].queue_free()
		else:
			_collision_shape_node = CollisionShape3D.new()
			_collision_shape_node.name = "CollisionShape3D"
			_collision_body.add_child(_collision_shape_node)

		_collision_shape_node.visible = false

		if EngineWrapper.instance.is_editor():
			var scene_root = EngineWrapper.instance.get_root_for_node(self)
			if scene_root:
				_collision_body.owner = scene_root
				_collision_shape_node.owner = scene_root
			for group in get_groups():
				if group.begins_with("navmesh_"):
					_collision_body.add_to_group(group)


# This just redoes the create_trimesh but adds depth up to 1 unit
func create_collision_with_depth(depth: float) -> void:
		if mesh == null:
			return
		_ensure_collision_body()

		var surface_faces: PackedVector3Array = mesh.get_faces()
		var all_faces: PackedVector3Array = surface_faces

		if depth > 0.0:
			var extra_faces := PackedVector3Array()
			var thr: float = terrain_system.wall_threshold if terrain_system else 0.25
			var i := 0
			while i < surface_faces.size():
				var v0 := surface_faces[i]
				var v1 := surface_faces[i + 1]
				var v2 := surface_faces[i + 2]
				var normal := (v1 - v0).cross(v2 - v0).normalized()
				if absf(normal.y) > thr:
					var d := Vector3(0, -depth, 0)
					var v0b := v0 + d
					var v1b := v1 + d
					var v2b := v2 + d
					# Bottom face (flipped winding)
					extra_faces.append_array([v0b, v2b, v1b])
					# Side walls
					extra_faces.append_array([v0, v1, v1b, v0, v1b, v0b])
					extra_faces.append_array([v1, v2, v2b, v1, v2b, v1b])
					extra_faces.append_array([v2, v0, v0b, v2, v0b, v2b])
				i += 3

			all_faces = PackedVector3Array()
			all_faces.append_array(surface_faces)
			all_faces.append_array(extra_faces)

		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(all_faces)
		_collision_shape_node.shape = shape

		_apply_collision_layers()


func _apply_collision_layers() -> void:
		if _collision_body != null and is_instance_valid(_collision_body):
			_collision_body.collision_layer = 17
			if terrain_system:
				_collision_body.set_collision_layer_value(terrain_system.extra_collision_layer, true)
			if _collision_shape_node != null and is_instance_valid(_collision_shape_node):
				_collision_shape_node.visible = false
			return
		# Legacy fallback (shouldn't happen, but keep it safe).
		for child in get_children():
			if child is StaticBody3D:
				child.collision_layer = 17
				if terrain_system:
					child.set_collision_layer_value(terrain_system.extra_collision_layer, true)
				for _child in child.get_children():
					if _child is CollisionShape3D:
						_child.set_visible(false)


func regenerate_all_cells(use_threads: bool):
	for z in range(dimensions.z-1):
		for x in range(dimensions.x-1):
			needs_update[z][x] = true
	
	regenerate_mesh(use_threads)


@export_tool_button("Export GLB") var bake = func():
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
