extends Node3D
class_name LodChunkManager

# Runtime streaming LOD manager for MST chunk data.
# - Streams chunk metadata.res from MarchingSquaresTerrain.data_directory when available.
# - Builds raw mesh arrays on worker threads.
# - Applies ArrayMesh to pooled LodChunk nodes on main thread with a per-frame budget.

const LodMeshBuilderScript = preload("res://addons/MarchingSquaresTerrain/runtime_lod/LodMeshBuilder.gd")

@export var terrain: Node
@export var terrain_path: NodePath
@export var camera_paths: Array[NodePath] = []

# When using the LOD system, the source MarchingSquaresTerrain is typically used as a data source
# (metadata + material params) and should not render at the same time (avoids z-fighting).
# NOTE: We do NOT hide the whole terrain node (that would also hide any children like LodChunks).
# Instead we hide the terrain's generated chunk nodes.
@export var hide_source_terrain_visuals: bool = false

# MST-only streaming: only toggles MST chunk visibility by distance.
# No proxy meshes/chunks are spawned or built.
@export var mst_only_streaming: bool = false

# Hybrid mode: show real MST chunks near the camera and use LOD proxy farther away.
@export var hybrid_use_mst_near: bool = false
@export var mst_near_radius_chunks: int = 2
@export var mst_near_use_circle: bool = true

# Prevents “holes” at the handoff by keeping MST visible until the proxy mesh is ready.
@export var hybrid_keep_mst_until_proxy_ready: bool = true

@export var debug_print: bool = false

# If true, chunk coordinates/origin are computed in the terrain's local space instead of the manager.
# This keeps chunks aligned even if the terrain is moved/rotated.
@export var anchor_to_terrain_transform: bool = true

# If true, chunks are spawned under a helper node on the terrain (keeps scene tree tidy).
@export var spawn_chunks_under_terrain: bool = true

# Safety cap to avoid accidental massive allocations/crashes if you type huge radii in the inspector.
@export var radius_safety_cap_chunks: int = 64

@export var view_radius_chunks: int = 6
@export var unload_radius_chunks: int = 7

@export var lod_count: int = 4
@export var lod_distances: PackedFloat32Array = PackedFloat32Array([0.0, 80.0, 160.0, 320.0])
@export var lod_hysteresis: float = 0.15

@export var update_interval_sec: float = 0.20

@export var use_async: bool = true
@export var max_builds_in_flight: int = 2
@export var max_mesh_applies_per_frame: int = 2

@export var skirt_depth: float = 8.0

@export var max_cached_meshes: int = 512
@export var max_cached_sources: int = 256

# Optional overrides if you don't want to depend on terrain node.
@export var fallback_dimensions_xz: int = 33
@export var fallback_cell_size: Vector2 = Vector2(2.0, 2.0)
@export var fallback_height_range: float = 32.0
@export var fallback_noise: Noise

# If the terrain has a data_directory and a chunk's metadata.res is missing, by default we DO NOT
# generate a fake chunk from noise (prevents "extra terrain" beyond authored area).
@export var allow_noise_fallback_when_missing_chunk_data: bool = false

@export var material_override: Material
@export var debug_color_by_lod: bool = false

# If no terrain material (and no override) is available, use a simple fallback so proxy chunks
# don't appear unlit/black by default.
@export var use_fallback_material_if_none: bool = true
@export var fallback_material_albedo: Color = Color(0.45, 0.45, 0.45, 1.0)

var _chunk_world_size_x: float = 64.0
var _chunk_world_size_z: float = 64.0

var _time_accum: float = 0.0

var _active: Dictionary = {} # key -> LodChunk
var _pool: Array[LodChunk] = []

# Cached source data: key -> {heights: PackedFloat32Array, ground_idx: PackedByteArray, dims_x, dims_z, cell_size}
var _source_cache: Dictionary = {}
var _source_cache_order: Array[String] = []

# Mesh cache: mesh_key -> ArrayMesh
var _mesh_cache: Dictionary = {}
var _mesh_cache_order: Array[String] = []

# Track queued/in-flight builds to prevent duplicates.
var _pending_jobs: Dictionary = {} # mesh_key -> true

# Build pipeline
var _build_queue: Array[Dictionary] = []
var _build_in_flight: int = 0
var _results_mutex: Mutex = Mutex.new()
var _results: Array[Dictionary] = []

var _debug_mats: Array[StandardMaterial3D] = []
var _fallback_mat: StandardMaterial3D

var _chunk_parent: Node3D
var _warned_no_camera: bool = false

# MST-only streaming state (hysteresis: keep visible until outside unload radius)
var _mst_streamed_visible: Dictionary = {} # key -> true

var _shutting_down: bool = false
var _task_ids: Array[int] = []


func _ready() -> void:
	_chunk_parent = self
	_recompute_chunk_world_size()
	_rebuild_debug_materials()
	_rebuild_fallback_material()
	call_deferred("_post_ready")


func _post_ready() -> void:
	# Runs after sibling nodes (including terrain) have had their _ready called.
	var t := _get_terrain()
	if spawn_chunks_under_terrain and t != null:
		var parent_node: Node3D = t
		var existing := t.get_node_or_null("LodChunks")
		if existing is Node3D:
			parent_node = existing
		else:
			var holder := Node3D.new()
			holder.name = "LodChunks"
			t.add_child(holder)
			parent_node = holder
		_chunk_parent = parent_node

	if hide_source_terrain_visuals and t != null and not hybrid_use_mst_near:
		_set_source_terrain_chunk_visuals_enabled(t, false)

	_recompute_chunk_world_size()


func _get_terrain() -> MarchingSquaresTerrain:
	if terrain is MarchingSquaresTerrain:
		return terrain
	if not terrain_path.is_empty():
		var n := get_node_or_null(terrain_path)
		if n is MarchingSquaresTerrain:
			return n
	return null


func _rebuild_debug_materials() -> void:
	_debug_mats.clear()
	for i in range(max(1, lod_count)):
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		sm.albedo_color = Color.from_hsv(float(i) / max(1.0, float(lod_count)), 0.7, 0.8)
		_debug_mats.append(sm)


func _rebuild_fallback_material() -> void:
	_fallback_mat = StandardMaterial3D.new()
	_fallback_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_fallback_mat.albedo_color = fallback_material_albedo


func _recompute_chunk_world_size() -> void:
	var dims_x := maxi(2, _get_dims_x())
	var dims_z := maxi(2, _get_dims_z())
	var cs := _get_cell_size()
	# Avoid division by zero / NaNs if cell_size or dimensions are invalid.
	if cs.x <= 0.0 or cs.y <= 0.0:
		cs = fallback_cell_size
		if cs.x <= 0.0 or cs.y <= 0.0:
			cs = Vector2(1.0, 1.0)
	_chunk_world_size_x = maxf(0.001, float(dims_x - 1) * cs.x)
	_chunk_world_size_z = maxf(0.001, float(dims_z - 1) * cs.y)


func _process(delta: float) -> void:
	if _shutting_down:
		return
	if not mst_only_streaming:
		_apply_results_budgeted()
		_submit_builds_budgeted()

	_time_accum += delta
	if _time_accum < update_interval_sec:
		return
	_time_accum = 0.0
	_update_streaming()


func _update_streaming() -> void:
	_recompute_chunk_world_size()
	var cams := _resolve_cameras()
	if cams.is_empty():
		return

	_trim_caches()

	var t := _get_terrain()
	var cap: int = clampi(radius_safety_cap_chunks, 1, 128)

	# MST-only mode: stream MST chunk visibility only.
	# No proxy meshes/chunks are spawned or built.
	if mst_only_streaming:
		var view_r: int = clampi(view_radius_chunks, 0, cap)
		var unload_r: int = clampi(unload_radius_chunks, 0, cap)

		var wanted: Dictionary = {}
		for cam in cams:
			var cc := _world_to_chunk_coords(cam.global_position)
			for dz in range(-view_r, view_r + 1):
				for dx in range(-view_r, view_r + 1):
					wanted[_key(cc.x + dx, cc.y + dz)] = true

		var keep: Dictionary = {}
		for cam in cams:
			var cc := _world_to_chunk_coords(cam.global_position)
			for dz in range(-unload_r, unload_r + 1):
				for dx in range(-unload_r, unload_r + 1):
					keep[_key(cc.x + dx, cc.y + dz)] = true

		# Update hysteresis state.
		for k in wanted.keys():
			_mst_streamed_visible[k] = true
		var to_erase: Array[String] = []
		for k in _mst_streamed_visible.keys():
			if not keep.has(k):
				to_erase.append(k)
		for k in to_erase:
			_mst_streamed_visible.erase(k)

		if t != null:
			# MST-only implies we want MST chunks visible (ignore hide_source_terrain_visuals).
			_set_source_terrain_chunk_visuals_enabled(t, true)
			for coords in t.chunks.keys():
				var mst_chunk := t.chunks.get(coords)
				if mst_chunk is Node3D:
					var c: Vector2i = coords
					var kk := _key(c.x, c.y)
					(mst_chunk as Node3D).visible = _mst_streamed_visible.has(kk)

		# Ensure proxy system is fully off.
		if not _active.is_empty():
			var keys: Array[String] = []
			for k in _active.keys():
				keys.append(k)
			for k in keys:
				_unload_chunk(k)
		_build_queue.clear()
		_pending_jobs.clear()
		_results_mutex.lock()
		_results.clear()
		_results_mutex.unlock()
		return

	var view_r: int = clampi(view_radius_chunks, 0, cap)
	var unload_r: int = clampi(unload_radius_chunks, 0, cap)

	var needed: Dictionary = {}
	for cam in cams:
		var cc := _world_to_chunk_coords(cam.global_position)
		for dz in range(-view_r, view_r + 1):
			for dx in range(-view_r, view_r + 1):
				var cx := cc.x + dx
				var cz := cc.y + dz
				needed[_key(cx, cz)] = Vector2i(cx, cz)

	# Unload chunks outside unload radius.
	var keep: Dictionary = {}
	for cam in cams:
		var cc := _world_to_chunk_coords(cam.global_position)
		for dz in range(-unload_r, unload_r + 1):
			for dx in range(-unload_r, unload_r + 1):
				keep[_key(cc.x + dx, cc.y + dz)] = true

	var to_remove: Array[String] = []
	for k in _active.keys():
		if not keep.has(k):
			to_remove.append(k)
	for k in to_remove:
		_unload_chunk(k)

	var mst_near: Dictionary = {}
	if hybrid_use_mst_near:
		mst_near = _compute_near_chunk_set(cams)
		_update_mst_chunk_visibility(t, mst_near, needed)

	# Ensure needed chunks exist and have correct LOD.
	# IMPORTANT: process nearest chunks first so you don't see a big "hole" while far chunks build.
	var needed_list: Array[Dictionary] = []
	needed_list.resize(needed.size())
	var ni := 0
	for k in needed.keys():
		var coords: Vector2i = needed[k]
		var d := _distance_to_nearest_camera_center(cams, coords)
		needed_list[ni] = {"key": k, "coords": coords, "dist": d}
		ni += 1
	needed_list.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))

	for item in needed_list:
		var k: String = item["key"]
		var coords: Vector2i = item["coords"]
		var d: float = float(item["dist"])

		# In hybrid mode, if this coord is handled by MST, hide proxy chunk here.
		if hybrid_use_mst_near and mst_near.has(k):
			var existing_proxy: LodChunk = _active.get(k)
			if existing_proxy != null:
				existing_proxy.visible = false
				existing_proxy.mesh_instance.mesh = null
			continue

		var chunk: LodChunk = _active.get(k)
		if chunk == null:
			chunk = _acquire_chunk()
			chunk.key = k
			chunk.coords = coords
			chunk.lod = 0
			chunk.global_position = _chunk_origin_world(coords.x, coords.y)
			_active[k] = chunk

		var desired := _choose_lod(d, chunk.lod)
		if desired != chunk.lod:
			_request_mesh(coords.x, coords.y, desired, d)
			chunk.lod = desired

		if chunk.mesh_instance.mesh == null:
			_request_mesh(coords.x, coords.y, chunk.lod, d)


func _resolve_cameras() -> Array[Camera3D]:
	var cams: Array[Camera3D] = []
	for p in camera_paths:
		var n := get_node_or_null(p)
		if n is Camera3D:
			cams.append(n)

	# Fallback 1: current camera for THIS viewport.
	var vp_cam := get_viewport().get_camera_3d()
	if vp_cam and not cams.has(vp_cam):
		cams.append(vp_cam)

	# Fallback 2: current camera for the terrain's viewport (useful when terrain is in a SubViewport).
	var t := _get_terrain()
	if t and t.get_viewport():
		var tvp_cam := t.get_viewport().get_camera_3d()
		if tvp_cam and not cams.has(tvp_cam):
			cams.append(tvp_cam)

	# Fallback 3: find any camera in the scene tree.
	if cams.is_empty():
		var any := get_tree().root.find_children("*", "Camera3D", true, false)
		for n in any:
			if n is Camera3D:
				var c: Camera3D = n
				if c.current and not cams.has(c):
					cams.append(c)
					break
		# If none marked current, just take the first camera.
		if cams.is_empty() and not any.is_empty() and any[0] is Camera3D:
			cams.append(any[0])

	if cams.is_empty() and not _warned_no_camera:
		_warned_no_camera = true
		if debug_print:
			push_warning("[LodChunkManager] No cameras found. Set camera_paths or ensure a Camera3D is current.")
	elif not cams.is_empty():
		_warned_no_camera = false

	return cams


func _compute_near_chunk_set(cams: Array[Camera3D]) -> Dictionary:
	var near: Dictionary = {}
	var cap := clampi(radius_safety_cap_chunks, 1, 128)
	var r: int = clampi(mst_near_radius_chunks, 0, cap)
	var r2: int = r * r
	for cam in cams:
		var cc := _world_to_chunk_coords(cam.global_position)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if mst_near_use_circle and (dx * dx + dz * dz) > r2:
					continue
				var cx := cc.x + dx
				var cz := cc.y + dz
				near[_key(cx, cz)] = true
	return near


func _update_mst_chunk_visibility(t: MarchingSquaresTerrain, mst_near: Dictionary, needed: Dictionary) -> void:
	if t == null:
		return
	# Hide/show ALL MST chunks based on near set.
	# In hybrid mode, optionally keep MST visible until the proxy mesh is ready to avoid holes.
	for coords in t.chunks.keys():
		var mst_chunk := t.chunks.get(coords)
		if mst_chunk is Node3D:
			var c: Vector2i = coords
			var k := _key(c.x, c.y)
			var show := mst_near.has(k)
			if not show and hybrid_keep_mst_until_proxy_ready and needed.has(k):
				var proxy: LodChunk = _active.get(k)
				var proxy_ready := (proxy != null and proxy.mesh_instance.mesh != null and proxy.visible)
				if not proxy_ready:
					show = true
			(mst_chunk as Node3D).visible = show


func _set_source_terrain_chunk_visuals_enabled(t: MarchingSquaresTerrain, enabled: bool) -> void:
	# Hide the MST-generated chunk nodes, but keep the terrain node visible so LodChunks (child node)
	# can still render.
	var chunks := t.find_children("*", "MarchingSquaresTerrainChunk", true, false)
	for n in chunks:
		if n is Node3D:
			(n as Node3D).visible = enabled


func _origin_node() -> Node3D:
	if anchor_to_terrain_transform:
		var t := _get_terrain()
		if t != null:
			return t
	return self


func _world_to_chunk_coords(world_pos: Vector3) -> Vector2i:
	if _chunk_world_size_x <= 0.001 or _chunk_world_size_z <= 0.001:
		return Vector2i(0, 0)
	var local := _origin_node().to_local(world_pos)
	return Vector2i(
		int(floor(local.x / _chunk_world_size_x)),
		int(floor(local.z / _chunk_world_size_z))
	)


func _chunk_origin_world(cx: int, cz: int) -> Vector3:
	var local_origin := Vector3(float(cx) * _chunk_world_size_x, 0.0, float(cz) * _chunk_world_size_z)
	return _origin_node().to_global(local_origin)


func _distance_to_nearest_camera_center(cams: Array[Camera3D], coords: Vector2i) -> float:
	var center := _chunk_origin_world(coords.x, coords.y) + Vector3(_chunk_world_size_x * 0.5, 0.0, _chunk_world_size_z * 0.5)
	var best := INF
	for cam in cams:
		best = min(best, cam.global_position.distance_to(center))
	return best


func _choose_lod(dist: float, current_lod: int) -> int:
	var l := clampi(current_lod, 0, max(0, lod_count - 1))
	while l + 1 < lod_count and dist > _enter_dist(l + 1):
		l += 1
	while l - 1 >= 0 and dist < _exit_dist(l):
		l -= 1
	return l


func _enter_dist(lod: int) -> float:
	lod = clampi(lod, 0, max(0, lod_count - 1))
	if lod_distances.size() > lod:
		return float(lod_distances[lod])
	return float(lod) * 80.0


func _exit_dist(lod: int) -> float:
	var enter := _enter_dist(lod)
	return enter * (1.0 - clampf(lod_hysteresis, 0.0, 0.95))


func _acquire_chunk() -> LodChunk:
	var c: LodChunk
	if not _pool.is_empty():
		c = _pool.pop_back()
	else:
		c = LodChunk.new()
		c.name = "LodChunk"
		(_chunk_parent if _chunk_parent != null else self).add_child(c)
	c.visible = true
	return c


func _unload_chunk(key: String) -> void:
	var c: LodChunk = _active.get(key)
	if c == null:
		return
	_active.erase(key)
	c.reset()
	_pool.append(c)

	# Opportunistically evict caches for chunks that are no longer active.
	_trim_caches()


func _request_mesh(cx: int, cz: int, lod: int, priority: float = 0.0) -> void:
	var mesh_key := _mesh_key(cx, cz, lod)
	var chunk_key := _key(cx, cz)
	var chunk: LodChunk = _active.get(chunk_key)
	if chunk == null:
		return

	var cached: ArrayMesh = _mesh_cache.get(mesh_key)
	if cached:
		_apply_mesh_to_chunk(chunk, cached, lod)
		return

	if _pending_jobs.has(mesh_key):
		return

	var source := _get_or_load_source(cx, cz)
	if source.is_empty():
		return

	_pending_jobs[mesh_key] = true
	_build_queue.append({
		"cx": cx,
		"cz": cz,
		"lod": lod,
		"priority": float(priority),
		"dims_x": source["dims_x"],
		"dims_z": source["dims_z"],
		"cell_size": source["cell_size"],
		"heights": source["heights"],
		"ground_idx": source["ground_idx"],
		"skirt_depth": skirt_depth,
	})


func _get_or_load_source(cx: int, cz: int) -> Dictionary:
	var k := _key(cx, cz)
	if _source_cache.has(k):
		return _source_cache[k]

	var dims_x := _get_dims_x()
	var dims_z := _get_dims_z()
	var cs := _get_cell_size()

	var heights := PackedFloat32Array()
	heights.resize(dims_x * dims_z)
	var ground_idx := PackedByteArray()
	ground_idx.resize(dims_x * dims_z)

	var loaded := false
	var t := _get_terrain()
	var has_data_dir := (t != null and not t.data_directory.is_empty())
	var metadata_missing := false
	if has_data_dir:
		var metadata_path := t.data_directory.path_join("chunk_%d_%d" % [cx, cz]).path_join("metadata.res")
		# Deletion can race with scanning/loading. Use file_exists + type-check to avoid crashes.
		if FileAccess.file_exists(metadata_path):
			var data := ResourceLoader.load(metadata_path)
			if data is MSTChunkData:
				_loaded_from_chunk_data(data, dims_x, dims_z, heights, ground_idx)
				loaded = true
			else:
				metadata_missing = true
		else:
			metadata_missing = true

	if not loaded:
		# If we're using authored/baked chunk data and this chunk doesn't exist on disk, don't invent it.
		if has_data_dir and metadata_missing and not allow_noise_fallback_when_missing_chunk_data:
			return {}
		_generated_from_noise(cx, cz, dims_x, dims_z, heights)
		var noise_slot := _pick_noise_fallback_ground_slot(t)
		for i in range(ground_idx.size()):
			ground_idx[i] = noise_slot

	var source := {
		"dims_x": dims_x,
		"dims_z": dims_z,
		"cell_size": cs,
		"heights": heights,
		"ground_idx": ground_idx,
	}
	_source_cache[k] = source
	_source_cache_order.append(k)
	_trim_source_cache()
	return source


func _loaded_from_chunk_data(data: MSTChunkData, dims_x: int, dims_z: int, heights: PackedFloat32Array, ground_idx: PackedByteArray) -> void:
	if data.height_map and data.height_map.size() == dims_z:
		for z in range(dims_z):
			var row = data.height_map[z]
			for x in range(dims_x):
				heights[z * dims_x + x] = float(row[x])
	if not data.ground_texture_idx.is_empty() and data.ground_texture_idx.size() == ground_idx.size():
		for i in range(ground_idx.size()):
			ground_idx[i] = data.ground_texture_idx[i]


func _pick_noise_fallback_ground_slot(t: MarchingSquaresTerrain) -> int:
	# Noise-generated chunks have no authored vertex-paint, so we must choose a sane default slot.
	# Slot 0 is often unset in palettes/presets (leading to green/black fallback shading), so we try
	# to pick the first active slot with palette indices, skipping the VOID slot.
	if t == null:
		return 0
	var void_slot := 15
	if t.get("VOID_TEXTURE_SLOT") != null:
		void_slot = int(t.VOID_TEXTURE_SLOT)
	
	var slots: Array = t.texture_slots if t.get("texture_slots") != null else []
	var slot_indices: Array = t.slot_color_indices if t.get("slot_color_indices") != null else []
	
	# Prefer a slot that actually has palette indices assigned (best visual match).
	for i in range(mini(256, slots.size())):
		if i == void_slot:
			continue
		var s = slots[i]
		if s == null or (s.get("active") != null and not bool(s.active)):
			continue
		var indices: Array = (slot_indices[i] as Array) if i < slot_indices.size() else []
		if indices != null and not indices.is_empty():
			return i
	
	# Fallback: first active non-void slot.
	for i in range(mini(256, slots.size())):
		if i == void_slot:
			continue
		var s = slots[i]
		if s == null or (s.get("active") != null and not bool(s.active)):
			continue
		return i
	
	return 0


func _generated_from_noise(cx: int, cz: int, dims_x: int, dims_z: int, heights: PackedFloat32Array) -> void:
	var t := _get_terrain()
	var n: Noise = fallback_noise
	if t and t.noise_hmap:
		n = t.noise_hmap
	var height_range := fallback_height_range
	if t:
		height_range = float(t.dimensions.y)

	for z in range(dims_z):
		for x in range(dims_x):
			var gx := cx * (dims_x - 1) + x
			var gz := cz * (dims_z - 1) + z
			var h := 0.0
			if n:
				h = n.get_noise_2d(gx, gz) * height_range
			heights[z * dims_x + x] = h


func _apply_results_budgeted() -> void:
	if _shutting_down:
		return
	var applied := 0
	while applied < max_mesh_applies_per_frame:
		var result: Dictionary = {}
		_results_mutex.lock()
		if not _results.is_empty():
			result = _results.pop_front()
		_results_mutex.unlock()
		if result.is_empty():
			return

		_build_in_flight = max(0, _build_in_flight - 1)

		var cx := int(result.get("cx", 0))
		var cz := int(result.get("cz", 0))
		var lod := int(result.get("lod", 0))
		var mesh_key := _mesh_key(cx, cz, lod)
		_pending_jobs.erase(mesh_key)
		var chunk_key := _key(cx, cz)
		var chunk: LodChunk = _active.get(chunk_key)
		if chunk == null or chunk.lod != lod:
			applied += 1
			continue

		var arrays = result.get("arrays")
		var fmt := int(result.get("format", 0))
		if arrays == null:
			applied += 1
			continue

		var mesh: ArrayMesh = _mesh_cache.get(mesh_key)
		if mesh == null:
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
			_mesh_cache[mesh_key] = mesh
			_mesh_cache_order.append(mesh_key)
			_trim_mesh_cache()
		_apply_mesh_to_chunk(chunk, mesh, lod)
		applied += 1


func _apply_mesh_to_chunk(chunk: LodChunk, mesh: ArrayMesh, lod: int) -> void:
	chunk.global_position = _chunk_origin_world(chunk.coords.x, chunk.coords.y)
	var mat := material_override
	var t := _get_terrain()
	if mat == null and t:
		# Prefer the actual MST chunk surface material (can be runtime-baked per chunk).
		var mst_chunk := t.chunks.get(chunk.coords)
		if mst_chunk is MeshInstance3D:
			var mi: MeshInstance3D = mst_chunk
			if mi.mesh and mi.mesh.get_surface_count() > 0:
				var smat := mi.mesh.surface_get_material(0)
				if smat:
					mat = smat
		if mat == null:
			mat = t.get_chunk_surface_material()
			if mat == null and t.terrain_material:
				mat = t.terrain_material
	if mat == null:
		if debug_color_by_lod and lod >= 0 and lod < _debug_mats.size():
			mat = _debug_mats[lod]
		elif use_fallback_material_if_none:
			mat = _fallback_mat
	chunk.apply_mesh(mesh, mat)


func _pop_best_build_job() -> Dictionary:
	# Pick the closest-to-camera job first (lowest priority).
	var best_i := -1
	var best_p := INF
	for i in range(_build_queue.size()):
		var j: Dictionary = _build_queue[i]
		var p := float(j.get("priority", 0.0))
		if p < best_p:
			best_p = p
			best_i = i
	if best_i < 0:
		return {}
	var job: Dictionary = _build_queue[best_i]
	_build_queue.remove_at(best_i)
	return job


func _submit_builds_budgeted() -> void:
	if _shutting_down:
		return
	if not use_async:
		if _build_queue.is_empty():
			return
		var job: Dictionary = _pop_best_build_job()
		if job.is_empty():
			return
		var result: Dictionary = LodMeshBuilderScript.build_heightfield(job)
		_results_mutex.lock()
		_results.append(result)
		_results_mutex.unlock()
		return

	while _build_in_flight < max_builds_in_flight and not _build_queue.is_empty():
		var job: Dictionary = _pop_best_build_job()
		if job.is_empty():
			return
		_build_in_flight += 1
		var id: int = WorkerThreadPool.add_task(Callable(self, "_thread_build").bind(job))
		_task_ids.append(id)


func _thread_build(job: Dictionary) -> void:
	var result: Dictionary = LodMeshBuilderScript.build_heightfield(job)
	if _shutting_down:
		return
	_results_mutex.lock()
	_results.append(result)
	_results_mutex.unlock()


func _exit_tree() -> void:
	# Ensure worker tasks finish before this node is freed to avoid rare crashes on scene close.
	_shutting_down = true
	set_process(false)
	_build_queue.clear()
	_pending_jobs.clear()
	_results_mutex.lock()
	_results.clear()
	_results_mutex.unlock()
	for id in _task_ids:
		WorkerThreadPool.wait_for_task_completion(id)
	_task_ids.clear()


func _get_dims_x() -> int:
	var t := _get_terrain()
	if t:
		return int(t.dimensions.x)
	return fallback_dimensions_xz


func _get_dims_z() -> int:
	var t := _get_terrain()
	if t:
		return int(t.dimensions.z)
	return fallback_dimensions_xz


func _get_cell_size() -> Vector2:
	var t := _get_terrain()
	if t:
		return t.cell_size
	return fallback_cell_size


func _key(cx: int, cz: int) -> String:
	return "%d:%d" % [cx, cz]


func _mesh_key(cx: int, cz: int, lod: int) -> String:
	return "%d:%d:%d" % [cx, cz, lod]


func _trim_caches() -> void:
	_trim_mesh_cache()
	_trim_source_cache()


func _trim_mesh_cache() -> void:
	if max_cached_meshes <= 0:
		return
	var i := 0
	while _mesh_cache.size() > max_cached_meshes and i < _mesh_cache_order.size():
		var k := _mesh_cache_order[i]
		if _mesh_cache.has(k) and not _mesh_key_in_use(k):
			_mesh_cache.erase(k)
			_mesh_cache_order.remove_at(i)
			continue
		i += 1


func _mesh_key_in_use(mesh_key: String) -> bool:
	var parts := mesh_key.split(":")
	if parts.size() != 3:
		return false
	var chunk_key := "%s:%s" % [parts[0], parts[1]]
	var c: LodChunk = _active.get(chunk_key)
	if c == null:
		return false
	return c.lod == int(parts[2])


func _trim_source_cache() -> void:
	if max_cached_sources <= 0:
		return
	var i := 0
	while _source_cache.size() > max_cached_sources and i < _source_cache_order.size():
		var k := _source_cache_order[i]
		if _source_cache.has(k) and not _active.has(k):
			_source_cache.erase(k)
			_source_cache_order.remove_at(i)
			continue
		i += 1
