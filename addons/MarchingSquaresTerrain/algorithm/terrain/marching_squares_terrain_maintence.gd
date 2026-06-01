@tool
extends RefCounted
class_name MSTTerrainMaintenance
## Editor maintenance and migration helpers for MarchingSquaresTerrain.


static func migrate_embedded_data(terrain: MarchingSquaresTerrain) -> void:
	if not EngineWrapper.instance.is_editor():
		return
	terrain._initialize_data_directory()
	if terrain.data_directory.is_empty():
		push_warning("[MST] Cannot migrate: data_directory is empty. Save the scene and try again.")
		return
	if not MSTDataHandler.needs_migration(terrain):
		push_warning("[MST] No embedded data migration needed.")
		return
	push_warning("[MST] Migrating embedded chunk data to external storage: %s" % terrain.data_directory)
	MSTDataHandler.migrate_to_external_storage(terrain)
	push_warning("[MST] Migration finished. Please save the scene to persist changes.")


static func save_all_chunks(terrain: MarchingSquaresTerrain) -> void:
	if not EngineWrapper.instance.is_editor():
		return
	terrain._initialize_data_directory()
	MSTDataHandler.save_all_chunks(terrain)
	push_warning("[MST] Saved dirty chunks to external storage. (If you recently migrated, save the scene too.)")


static func rebuild_all_chunks(terrain: MarchingSquaresTerrain) -> void:
	# Coalesced by regen debouncer in-editor.
	terrain._request_chunk_regen(null, true)


static func rebuild_all_chunk_meshes(terrain: MarchingSquaresTerrain) -> void:
	# This is a heavy operation; prefer threads in-editor.
	var use_threads := EngineWrapper.instance.is_editor()
	# If this rebuild is being used to pick up one-time mesh migrations, mark them applied
	# so we don't keep prompting on every load.
	if EngineWrapper.instance.is_editor():
		terrain._uv_wall_sentinel_migrated = true
		terrain._wall_material_pair_migrated = true
	for chunk : MarchingSquaresTerrainChunk in terrain.chunks.values():
		if chunk:
			chunk.regenerate_mesh(use_threads)
	push_warning("[MST] Rebuilt all chunk meshes. Please save the scene if this was a migration rebuild.")


static func cleanup_orphaned_storage(terrain: MarchingSquaresTerrain) -> void:
	if not EngineWrapper.instance.is_editor():
		return
	MSTDataHandler.cleanup_orphaned_chunk_files(terrain)
	MSTDataHandler.cleanup_orphaned_terrain_directories(terrain)
	push_warning("[MST] Cleaned up orphaned MST storage directories/files (if any).")


static func maybe_migrate_embedded_data_on_load(terrain: MarchingSquaresTerrain) -> void:
	if not EngineWrapper.instance.is_editor():
		return
	if not MSTDataHandler.needs_migration(terrain):
		return
	# Embedded chunks exist (old scenes). Optionally migrate them to external storage.
	if terrain.auto_migrate_embedded_data:
		push_warning("[MST] Embedded chunk data detected; migrating to external storage: %s" % terrain.data_directory)
		MSTDataHandler.migrate_to_external_storage(terrain)
		push_warning("[MST] Migration finished. Please save the scene to persist changes.")
	else:
		push_warning("[MST] Embedded chunk data detected, but auto_migrate_embedded_data is disabled. Use Maintenance -> Migrate Embedded Data Now.")


static func maybe_migrate_wall_threshold_default(terrain: MarchingSquaresTerrain) -> void:
	# Legacy safety: wall_threshold=0 makes many walls classify as floor (due to smoothed normals).
	# If the saved value is effectively "unset", migrate it to a sane default.
	if terrain.wall_threshold < 0.005:
		terrain.wall_threshold = 0.25


static func maybe_apply_one_time_mesh_migrations_on_load(terrain: MarchingSquaresTerrain) -> bool:
	# One-time editor migrations: regenerate meshes so new wall tagging/material selection is present in geometry.
	if not EngineWrapper.instance.is_editor():
		return false
	var needs_wall_migration := (not terrain._uv_wall_sentinel_migrated) or (not terrain._wall_material_pair_migrated)
	if needs_wall_migration and terrain.auto_apply_one_time_migrations:
		terrain._uv_wall_sentinel_migrated = true
		terrain._wall_material_pair_migrated = true
		push_warning("[MST] Applying one-time mesh migration (wall tagging/material fix). Rebuilding chunk meshes once; please save the scene afterwards.")
		return true
	elif needs_wall_migration:
		push_warning("[MST] One-time mesh migration is pending (wall tagging/material fix). Enable auto_apply_one_time_migrations or use Maintenance -> Rebuild All Chunk Meshes Now, then save the scene.")
	return false


static func maybe_migrate_legacy_textures(terrain: MarchingSquaresTerrain) -> void:
	# One-time migration: if slots are empty/uninitialized, copy old exported vars into slots 0..14.
	var any_slot_set := false
	for i in range(mini(15, terrain.texture_slots.size())):
		var s := terrain.texture_slots[i]
		if s != null and s.texture != null:
			any_slot_set = true
			break

	var legacy_textures : Array[Texture2D] = [
		terrain.texture_1, terrain.texture_2, terrain.texture_3, terrain.texture_4, terrain.texture_5,
		terrain.texture_6, terrain.texture_7, terrain.texture_8, terrain.texture_9, terrain.texture_10,
		terrain.texture_11, terrain.texture_12, terrain.texture_13, terrain.texture_14, terrain.texture_15,
	]
	var any_legacy_set := false
	for texture in legacy_textures:
		if texture != null:
			any_legacy_set = true
			break

	if any_slot_set or not any_legacy_set:
		return

	for i in range(15):
		if terrain.texture_slots[i] == null:
			terrain.texture_slots[i] = MarchingSquaresTextureSlot.new()
		terrain.texture_slots[i].texture = legacy_textures[i]

	# Legacy scales -> slot scales
	var legacy_scales : Array[float] = [
		terrain.texture_scale_1, terrain.texture_scale_2, terrain.texture_scale_3, terrain.texture_scale_4, terrain.texture_scale_5,
		terrain.texture_scale_6, terrain.texture_scale_7, terrain.texture_scale_8, terrain.texture_scale_9, terrain.texture_scale_10,
		terrain.texture_scale_11, terrain.texture_scale_12, terrain.texture_scale_13, terrain.texture_scale_14, terrain.texture_scale_15,
	]
	for i in range(15):
		terrain.texture_slots[i].scale = legacy_scales[i]


static func maybe_migrate_legacy_grass(terrain: MarchingSquaresTerrain) -> void:
	# One-time migration: copy legacy grass exports into slots 0..5.
	# Legacy behavior: Texture 1 grass always on; textures 2-6 are toggleable.
	if terrain._grass_slots_migrated:
		return
	terrain._grass_slots_migrated = true
	terrain._ensure_texture_slots()

	# Ensure slots exist.
	for i in range(6):
		if terrain.texture_slots[i] == null:
			terrain.texture_slots[i] = MarchingSquaresTextureSlot.new()

	# Sprites (legacy exports) -> slots
	terrain.texture_slots[0].grass_texture = terrain.grass_sprite_tex_1
	terrain.texture_slots[1].grass_texture = terrain.grass_sprite_tex_2
	terrain.texture_slots[2].grass_texture = terrain.grass_sprite_tex_3
	terrain.texture_slots[3].grass_texture = terrain.grass_sprite_tex_4
	terrain.texture_slots[4].grass_texture = terrain.grass_sprite_tex_5
	terrain.texture_slots[5].grass_texture = terrain.grass_sprite_tex_6

	# Has grass flags -> slots (cast to bool; older scenes can deserialize these as Nil)
	var tex1_has_grass_value := terrain.tex1_has_grass
	if tex1_has_grass_value == null:
		tex1_has_grass_value = true
	var tex2_has_grass_value := terrain.tex2_has_grass
	if tex2_has_grass_value == null:
		tex2_has_grass_value = true
	var tex3_has_grass_value := terrain.tex3_has_grass
	if tex3_has_grass_value == null:
		tex3_has_grass_value = true
	var tex4_has_grass_value := terrain.tex4_has_grass
	if tex4_has_grass_value == null:
		tex4_has_grass_value = true
	var tex5_has_grass_value := terrain.tex5_has_grass
	if tex5_has_grass_value == null:
		tex5_has_grass_value = true
	var tex6_has_grass_value := terrain.tex6_has_grass
	if tex6_has_grass_value == null:
		tex6_has_grass_value = true

	terrain.texture_slots[0].has_grass = bool(tex1_has_grass_value)
	terrain.texture_slots[1].has_grass = bool(tex2_has_grass_value)
	terrain.texture_slots[2].has_grass = bool(tex3_has_grass_value)
	terrain.texture_slots[3].has_grass = bool(tex4_has_grass_value)
	terrain.texture_slots[4].has_grass = bool(tex5_has_grass_value)
	terrain.texture_slots[5].has_grass = bool(tex6_has_grass_value)


static func migrate_colors_to_palette(terrain: MarchingSquaresTerrain) -> void:
	if terrain.palette_colors.size() > 0:
		return  # Already migrated, skip

	terrain.palette_colors.resize(128)
	terrain.palette_colors[0] = terrain.tex1_color_1
	terrain.palette_colors[1] = terrain.tex2_color_1
	terrain.palette_colors[2] = terrain.tex3_color_1
	terrain.palette_colors[3] = terrain.tex4_color_1
	terrain.palette_colors[4] = terrain.tex5_color_1
	terrain.palette_colors[5] = terrain.tex6_color_1

	for i in range(6, 128):
		terrain.palette_colors[i] = Color("647851ff")

	terrain.palette_weights.resize(128)
	for i in range(128):
		terrain.palette_weights[i] = 100.0

	terrain.slot_color_indices = [[0], [1], [2], [3], [4], [5], [], [], [], [], [], [], [], [], []]
