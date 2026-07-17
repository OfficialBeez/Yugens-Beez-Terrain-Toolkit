@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin
var vp_tex_names : MarchingSquaresTextureNames = preload("uid://dd7fens03aosa")
var _built_for_terrain_id: int = 0

const MAX_TEXTURE_SLOTS := 256
const TEXTURE_SETTINGS_MIN_WIDTH_SMALL := 205
const TEXTURE_SETTINGS_MIN_WIDTH_LARGE := 324
const LARGE_EDITOR_RESOLUTION := Vector2i(1920, 1080)
const SLOT_PREVIEW_SIZE_SMALL := 96
const SLOT_PREVIEW_SIZE_LARGE := 128
const TEXTURE_PRESET_DIR := "res://addons/MarchingSquaresTerrain/resources/texture_presets/"

# Avoid hard class_name dependency in headless/script-cache runs.
const _TEXTURE_SLOT_SCRIPT := preload("uid://blcngv6fs1rut")
const MarchingSquaresBaker := preload("uid://bvqkmycahgowa")
const MarchingSquaresTerrainHelpers := preload("uid://b33pjajd0cl83")
const MSTextureLibraryScript := preload("uid://iyvy0c8carkd")

const _TEXTURE_EDIT_WINDOW := preload("uid://58vqrcbqc0jm")

var texture_import_dialog: AcceptDialog
var texture_import_name_input: LineEdit
var texture_import_save_path_input: LineEdit
var texture_import_albedo_dir_input: LineEdit
var texture_import_normal_dir_input: LineEdit
var texture_import_bake_check: CheckBox

const VAR_NAMES : Array[Dictionary] = [
	{
		"tex_var": "texture_1",
		"scale_var": "texture_scale_1",
		"sprite_var": "grass_sprite_tex_1",
	},
	{
		"tex_var": "texture_2",
		"scale_var": "texture_scale_2",
		"sprite_var": "grass_sprite_tex_2",
		"use_grass_var": "tex2_has_grass",
	},
	{
		"tex_var": "texture_3",
		"scale_var": "texture_scale_3",
		"sprite_var": "grass_sprite_tex_3",
		"use_grass_var": "tex3_has_grass",
	},
	{
		"tex_var": "texture_4",
		"scale_var": "texture_scale_4",
		"sprite_var": "grass_sprite_tex_4",
		"use_grass_var": "tex4_has_grass",
	},
	{
		"tex_var": "texture_5",
		"scale_var": "texture_scale_5",
		"sprite_var": "grass_sprite_tex_5",
		"use_grass_var": "tex5_has_grass",
	},
	{
		"tex_var": "texture_6",
		"scale_var": "texture_scale_6",
		"sprite_var": "grass_sprite_tex_6",
		"use_grass_var": "tex6_has_grass",
	},
	{
		"tex_var": "texture_7",
		"scale_var": "texture_scale_7",
	},
	{
		"tex_var": "texture_8",
		"scale_var": "texture_scale_8",
	},
	{
		"tex_var": "texture_9",
		"scale_var": "texture_scale_9",
	},
	{
		"tex_var": "texture_10",
		"scale_var": "texture_scale_10",
	},
	{
		"tex_var": "texture_11",
		"scale_var": "texture_scale_11",
	},
	{
		"tex_var": "texture_12",
		"scale_var": "texture_scale_12",
	},
	{
		"tex_var": "texture_13",
		"scale_var": "texture_scale_13",
	},
	{
		"tex_var": "texture_14",
		"scale_var": "texture_scale_14",
	},
	{
		"tex_var": "texture_15",
		"scale_var": "texture_scale_15",
	},
]


func _ready() -> void:
	# Reserve enough width for slot previews and labels on larger editor layouts.
	set_custom_minimum_size(Vector2(_get_texture_settings_min_width(), 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_create_texture_import_dialog()


func _get_texture_settings_min_width() -> int:
	var editor_window := get_window()
	var window_size := editor_window.size if editor_window != null else DisplayServer.screen_get_size()
	if window_size.x > LARGE_EDITOR_RESOLUTION.x and window_size.y > LARGE_EDITOR_RESOLUTION.y:
		return TEXTURE_SETTINGS_MIN_WIDTH_LARGE
	return TEXTURE_SETTINGS_MIN_WIDTH_SMALL


func _use_large_editor_layout() -> bool:
	var editor_window := get_window()
	var window_size := editor_window.size if editor_window != null else DisplayServer.screen_get_size()
	return window_size.x > LARGE_EDITOR_RESOLUTION.x and window_size.y > LARGE_EDITOR_RESOLUTION.y


func _get_slot_preview_size() -> int:
	return SLOT_PREVIEW_SIZE_LARGE if _use_large_editor_layout() else SLOT_PREVIEW_SIZE_SMALL


func _create_texture_import_dialog() -> void:
	if texture_import_dialog != null:
		return
	texture_import_dialog = AcceptDialog.new()
	texture_import_dialog.title = "Texture Import"
	texture_import_dialog.unresizable = true
	texture_import_dialog.exclusive = false
	texture_import_dialog.confirmed.connect(_on_texture_import_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("separation", 8)
	
	var name_label := Label.new()
	name_label.text = "Preset name:"
	cont.add_child(name_label)
	
	texture_import_name_input = LineEdit.new()
	texture_import_name_input.placeholder_text = "new_texture_import"
	cont.add_child(texture_import_name_input)
	
	var save_path_label := Label.new()
	save_path_label.text = "Save path:"
	cont.add_child(save_path_label)
	
	texture_import_save_path_input = LineEdit.new()
	texture_import_save_path_input.text = TEXTURE_PRESET_DIR
	texture_import_save_path_input.placeholder_text = TEXTURE_PRESET_DIR
	cont.add_child(texture_import_save_path_input)
	
	cont.add_child(_build_texture_import_path_row(
		"Albedo or Diffuse Maps Folder:",
		"Select the folder that contains albedo or diffuse textures.",
		func(line_edit: LineEdit): _open_texture_import_folder_dialog(line_edit, "Select Albedo or Diffuse Maps Folder")
	))
	texture_import_albedo_dir_input = cont.get_child(cont.get_child_count() - 1).get_meta("path_input")
	
	cont.add_child(_build_texture_import_path_row(
		"Normal Maps Folder:",
		"Select the folder that contains normal textures.",
		func(line_edit: LineEdit): _open_texture_import_folder_dialog(line_edit, "Select Normal Maps Folder")
	))
	texture_import_normal_dir_input = cont.get_child(cont.get_child_count() - 1).get_meta("path_input")
	
	texture_import_bake_check = CheckBox.new()
	texture_import_bake_check.text = "Bake arrays after import"
	texture_import_bake_check.tooltip_text = "Immediately bake Texture2DArray resources for the imported preset."
	cont.add_child(texture_import_bake_check)
	
	texture_import_dialog.add_child(cont)
	add_child(texture_import_dialog)


func _build_texture_import_path_row(label_text: String, tooltip_text: String, on_browse: Callable) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip_text
	wrapper.add_child(label)
	
	var row := HBoxContainer.new()
	var line_edit := LineEdit.new()
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.placeholder_text = "res://"
	line_edit.tooltip_text = tooltip_text
	row.add_child(line_edit)
	
	var browse_btn := Button.new()
	browse_btn.text = "Browse"
	browse_btn.pressed.connect(func(): on_browse.call(line_edit))
	row.add_child(browse_btn)
	wrapper.add_child(row)
	wrapper.set_meta("path_input", line_edit)
	return wrapper


func _open_texture_import_dialog() -> void:
	if texture_import_dialog == null:
		_create_texture_import_dialog()
	texture_import_name_input.text = "new_texture_import"
	texture_import_save_path_input.text = TEXTURE_PRESET_DIR
	texture_import_albedo_dir_input.text = ""
	texture_import_normal_dir_input.text = ""
	texture_import_bake_check.button_pressed = false
	texture_import_dialog.popup_centered(Vector2i(520, 260))
	texture_import_name_input.grab_focus()
	texture_import_name_input.select_all()


func _open_texture_import_folder_dialog(path_edit: LineEdit, title: String) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = title
	dialog.exclusive = false
	dialog.current_dir = path_edit.text if not path_edit.text.is_empty() else "res://"
	dialog.dir_selected.connect(func(dir: String):
		path_edit.text = dir
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _ensure_terrain_arrays(terrain: Object) -> bool:
	if terrain == null:
		return false

	# Avoid calling into the terrain script from the editor UI.
	# In editor reload/order edge-cases the selected node can be a plain Node3D or a placeholder script,
	# Which makes method calls like _ensure_texture_slots() fail even though exported properties exist.
	var slots_var = terrain.get("texture_slots")
	if not (slots_var is Array):
		push_error("[MST] Selected node doesn't expose texture_slots. Select the MarchingSquaresTerrain node (with script attached).")
		return false
	if slots_var.size() != MAX_TEXTURE_SLOTS:
		slots_var.resize(MAX_TEXTURE_SLOTS)
	var default_visible_count := 6
	if terrain.get("visible_texture_slot_count") != null:
		default_visible_count = clampi(int(terrain.get("visible_texture_slot_count")), 6, MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slots_var[i] == null:
			slots_var[i] = _TEXTURE_SLOT_SCRIPT.new()
		# Default missing 'active' from the current visible range instead of enabling all 256 slots.
		if slots_var[i] != null and slots_var[i].get("active") == null:
			slots_var[i].active = (i < default_visible_count and i != 15)
		# Default grass fields for older slot resources.
		if slots_var[i] != null and slots_var[i].get("has_grass") == null:
			slots_var[i].has_grass = (i == 0)
		if slots_var[i] != null and slots_var[i].get("grass_texture") == null:
			slots_var[i].grass_texture = null

	# Palette-per-slot arrays (all optional, but expected for the UI).
	var slot_color_indices = terrain.get("slot_color_indices")
	if slot_color_indices is Array:
		if slot_color_indices.size() != MAX_TEXTURE_SLOTS:
			slot_color_indices.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_color_indices[i] == null:
				slot_color_indices[i] = []

	var slot_blend_modes = terrain.get("slot_blend_modes")
	if slot_blend_modes is Array:
		if slot_blend_modes.size() != MAX_TEXTURE_SLOTS:
			slot_blend_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_blend_modes[i] == null:
				slot_blend_modes[i] = MarchingSquaresTerrainHelpers.default_slot_blend_mode(i)

	var slot_wet_enabled = terrain.get("slot_wet_enabled")
	if slot_wet_enabled is Array:
		if slot_wet_enabled.size() != MAX_TEXTURE_SLOTS:
			slot_wet_enabled.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_enabled[i] == null:
				slot_wet_enabled[i] = false

	var slot_wet_modes = terrain.get("slot_wet_modes")
	if slot_wet_modes is Array:
		if slot_wet_modes.size() != MAX_TEXTURE_SLOTS:
			slot_wet_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_modes[i] == null:
				slot_wet_modes[i] = 0
			slot_wet_modes[i] = clampi(int(slot_wet_modes[i]), 0, 1)

	var slot_roughnesses = terrain.get("slot_roughnesses")
	if slot_roughnesses is Array:
		var old_roughness_size: int = slot_roughnesses.size()
		if slot_roughnesses.size() != MAX_TEXTURE_SLOTS:
			slot_roughnesses.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_roughnesses[i] == null:
				slot_roughnesses[i] = 1.0
			if i >= old_roughness_size:
				slot_roughnesses[i] = 1.0
			slot_roughnesses[i] = clampf(float(slot_roughnesses[i]), 0.0, 1.0)

	var slot_grass_wetnesses = terrain.get("slot_grass_wetnesses")
	if slot_grass_wetnesses is Array:
		var old_grass_wetness_size: int = slot_grass_wetnesses.size()
		if slot_grass_wetnesses.size() != MAX_TEXTURE_SLOTS:
			slot_grass_wetnesses.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_grass_wetnesses[i] == null:
				slot_grass_wetnesses[i] = 0.0
			if i >= old_grass_wetness_size:
				slot_grass_wetnesses[i] = 0.0
			slot_grass_wetnesses[i] = clampf(float(slot_grass_wetnesses[i]), 0.0, 1.0)

	_ensure_slot_noise_arrays(terrain)
	return true


func _ensure_slot_noise_arrays(terrain) -> void:
	var strength_default := 1.0
	var strength_value: Variant = terrain.get("global_noise_strength")
	if strength_value is float or strength_value is int:
		strength_default = float(strength_value)
	var scale_default := 0.037

	var defs: Array = [
		["slot_floor_noise_enabled", false],
		["slot_floor_noise_strengths", strength_default],
		["slot_floor_noise_scales", scale_default],
		["slot_wall_noise_enabled", false],
		["slot_wall_noise_strengths", strength_default],
		["slot_wall_noise_scales", scale_default],
	]
	for def in defs:
		var prop := String(def[0])
		var default_value = def[1]
		var arr = terrain.get(prop)
		if not (arr is Array):
			continue
		if arr.size() != MAX_TEXTURE_SLOTS:
			arr.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if arr[i] == null:
				arr[i] = default_value
			if prop.ends_with("_strengths"):
				arr[i] = clampf(float(arr[i]), 0.0, 1.0)
			elif prop.ends_with("_scales"):
				arr[i] = clampf(float(arr[i]), 0.001, 1.0)


func _get_texture_library(terrain) -> Resource:
	if terrain == null or not terrain.has_method("get"):
		return null
	var lib_res: Resource = terrain.get("texture_library")
	if lib_res != null and lib_res is MSTextureLibraryScript:
		if lib_res.has_method("ensure_length"):
			lib_res.ensure_length()
		return lib_res
	if lib_res is Resource and lib_res.resource_path != null and not str(lib_res.resource_path).is_empty():
		var loaded := ResourceLoader.load(str(lib_res.resource_path))
		if loaded != null and loaded is MSTextureLibraryScript:
			if loaded.has_method("ensure_length"):
				loaded.ensure_length()
			terrain.set("texture_library", loaded)
			return loaded
	return null


func _save_resource_if_external(res: Resource) -> void:
	if res != null and res.resource_path != null and not str(res.resource_path).is_empty():
		ResourceSaver.save(res, res.resource_path)


func _is_valid_texture2d(tex) -> bool:
	if tex == null or not (tex is Texture2D):
		return false
	return tex.get_class() != "Texture2D"


func _coerce_texture2d(tex) -> Texture2D:
	return tex as Texture2D if _is_valid_texture2d(tex) else null


func _get_slot_albedo_texture(terrain, slot_idx: int) -> Texture2D:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS:
		return null
	if terrain.texture_slots.size() > slot_idx and terrain.texture_slots[slot_idx] != null:
		var slot_tex := _coerce_texture2d(terrain.texture_slots[slot_idx].texture)
		if slot_tex != null:
			return slot_tex
	var lib_res := _get_texture_library(terrain)
	if lib_res != null and slot_idx < lib_res.albedo_textures.size():
		return _coerce_texture2d(lib_res.albedo_textures[slot_idx])
	return null


func _sync_texture_library_from_slots(terrain, lib_res) -> void:
	if terrain == null or lib_res == null or not _ensure_terrain_arrays(terrain):
		return
	if lib_res.has_method("ensure_length"):
		lib_res.ensure_length()
	for i in range(min(MAX_TEXTURE_SLOTS, terrain.texture_slots.size())):
		var slot = terrain.texture_slots[i]
		if slot == null:
			continue
		if i < lib_res.albedo_textures.size():
			var slot_tex := _coerce_texture2d(slot.texture)
			if slot_tex != null:
				lib_res.albedo_textures[i] = slot_tex
			else:
				lib_res.albedo_textures[i] = null
		if i < lib_res.grass_textures.size():
			var grass_tex := _coerce_texture2d(slot.grass_texture)
			if grass_tex != null:
				lib_res.grass_textures[i] = grass_tex
			else:
				lib_res.grass_textures[i] = null
	_save_resource_if_external(lib_res)


func _sync_slot_legacy_fields(terrain, slot_idx: int) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= 15:
		return
	var slot = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
	var tex: Texture2D = _coerce_texture2d(slot.texture) if slot != null else null
	var scale = float(slot.scale) if slot != null and slot.get("scale") != null else 1.0
	var was_batch = terrain.get("is_batch_updating") if terrain.has_method("get") else null
	if was_batch != null:
		terrain.set("is_batch_updating", true)
	terrain.set("texture_%d" % (slot_idx + 1), tex)
	terrain.set("texture_scale_%d" % (slot_idx + 1), scale)
	if was_batch != null:
		terrain.set("is_batch_updating", was_batch)


func _default_texture_slot_label(slot_idx: int) -> String:
	if slot_idx == 15:
		return "Void"
	var display_number := slot_idx + 1
	if slot_idx > 15:
		display_number -= 1
	return "Texture %d" % display_number


func _reset_slot_display_name(terrain, slot_idx: int) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS:
		return
	var default_label := _default_texture_slot_label(slot_idx)
	var preset = terrain.get("current_texture_preset") if terrain.has_method("get") else null
	if preset != null and preset.get("new_tex_names") != null and preset.new_tex_names != null:
		var names_res = preset.new_tex_names
		if names_res.get("texture_names") is Array:
			var names: Array = names_res.get("texture_names")
			if slot_idx < names.size():
				names[slot_idx] = default_label
				names_res.set("texture_names", names)
				return
	if vp_tex_names != null and vp_tex_names.get("texture_names") is Array:
		var global_names: Array = vp_tex_names.get("texture_names")
		if slot_idx < global_names.size():
			global_names[slot_idx] = default_label
			vp_tex_names.set("texture_names", global_names)


func _refresh_slot_runtime(
	terrain,
	p_refresh_ui: bool = false,
	p_rebuild_grass_array: bool = true,
	p_request_grass_regen: bool = true,
	p_save_current_preset: bool = true
) -> void:
	if terrain == null:
		return
	terrain.set("baked_albedo_array_path", "")
	terrain.set("baked_normal_array_path", "")
	terrain.set("baked_dense_slot_lookup", PackedInt32Array())
	if terrain.has_method("invalidate_grass_bake_state"):
		terrain.invalidate_grass_bake_state()
	else:
		terrain.set("baked_grass_array_path", "")
		terrain.set("baked_dense_slot_lookup", PackedInt32Array())
	if terrain.has_method("rebuild_texture_array"):
		terrain.rebuild_texture_array()
	if p_rebuild_grass_array and terrain.has_method("rebuild_grass_texture_array"):
		terrain.rebuild_grass_texture_array()
	if terrain.has_method("_push_tex_scales"):
		terrain._push_tex_scales()
	if terrain.has_method("_rebuild_palette_uniforms"):
		terrain._rebuild_palette_uniforms()
	if terrain.has_method("refresh_chunk_surface_materials"):
		terrain.refresh_chunk_surface_materials()
	if p_request_grass_regen and terrain.has_method("_request_grass_regen"):
		terrain._request_grass_regen()
	if p_save_current_preset and terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
		terrain.save_to_preset()
	if plugin and plugin.ui and plugin.ui.tool_attributes:
		plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
	if p_refresh_ui:
		call_deferred("add_texture_settings")


# PURGE SCRIPT STARTS HERE
func _texture_slot_from_colors(c0: Color, c1: Color) -> int:
	var c0_sum = c0.r + c0.g + c0.b + c0.a
	var c1_sum = c1.r + c1.g + c1.b + c1.a
	var c0_max = max(max(c0.r, c0.g), max(c0.b, c0.a))
	var c1_max = max(max(c1.r, c1.g), max(c1.b, c1.a))
	var looks_legacy: bool = (abs(c0_sum - 1.0) < 0.01 and abs(c1_sum - 1.0) < 0.01 and c0_max > 0.99 and c1_max > 0.99)
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


func _collect_used_slots_from_maps(map_0, map_1, used_slots: Dictionary) -> void:
	if not (map_0 is PackedColorArray) or not (map_1 is PackedColorArray):
		return
	var count := mini(map_0.size(), map_1.size())
	for i in range(count):
		var idx := _texture_slot_from_colors(map_0[i], map_1[i])
		used_slots[idx] = true


func _collect_used_texture_slots(terrain) -> Dictionary:
	var used_slots := {}
	if terrain == null:
		return used_slots

	# Slot 0 is intentionally kept available as the base/default slot in the UI workflow.
	used_slots[0] = true
	# Keep the reserved Void slot intact.
	used_slots[15] = true

	var seen_chunks := {}
	var chunk_list: Array = []
	var chunks_dict = terrain.get("chunks") if terrain.has_method("get") else null
	if chunks_dict is Dictionary:
		for chunk_coords in chunks_dict.keys():
			var c = chunks_dict[chunk_coords]
			if c != null:
				chunk_list.append(c)
				seen_chunks[c.get_instance_id()] = true
	for child in terrain.get_children():
		if child == null:
			continue
		if child.has_method("get") and child.get("chunk_coords") != null:
			var id: int = child.get_instance_id()
			if not seen_chunks.has(id):
				chunk_list.append(child)
				seen_chunks[id] = true

	for chunk in chunk_list:
		_collect_used_slots_from_maps(chunk.get("color_map_0"), chunk.get("color_map_1"), used_slots)
		_collect_used_slots_from_maps(chunk.get("wall_color_map_0"), chunk.get("wall_color_map_1"), used_slots)
		var stamp_indices = chunk.get("wall_paint_stamp_texture_indices")
		if stamp_indices is PackedInt32Array:
			for idx in stamp_indices:
				used_slots[clampi(int(idx), 0, MAX_TEXTURE_SLOTS - 1)] = true

	return used_slots


func _purge_unused_slots(terrain) -> void:
	if terrain == null or not _ensure_terrain_arrays(terrain):
		return

	var used_slots := _collect_used_texture_slots(terrain)
	var purged_count := 0
	for slot_idx in range(MAX_TEXTURE_SLOTS):
		if slot_idx == 0 or slot_idx == 15:
			continue
		if used_slots.has(slot_idx):
			continue
		_clear_slot(terrain, slot_idx, false, false, false, false)
		purged_count += 1

	_shrink_visible_texture_slots(terrain)
	_refresh_slot_runtime(terrain, true, true, true, false)
	EditorInterface.mark_scene_as_unsaved()

	if purged_count > 0:
		print_verbose("[MST] Purged %d unused texture slot(s)." % purged_count)
	else:
		print_verbose("[MST] Purge complete: no unused slots found.")
# PURGE SCRIPT ENDS HERE


func _apply_slot_albedo(terrain, slot_idx: int, resource: Variant, p_refresh_ui: bool = false) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	var texture : Texture2D = _coerce_texture2d(resource)
	if not _ensure_terrain_arrays(terrain):
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	terrain.texture_slots[slot_idx].active = true
	terrain.texture_slots[slot_idx].texture = texture
	terrain.texture_slots[slot_idx].albedo = _compute_slot_albedo_color(terrain, texture)
	_sync_slot_legacy_fields(terrain, slot_idx)
	var lib_res := _get_texture_library(terrain)
	if lib_res != null and slot_idx < lib_res.albedo_textures.size():
		lib_res.albedo_textures[slot_idx] = texture
		_save_resource_if_external(lib_res)
	_refresh_slot_runtime(terrain, p_refresh_ui)


func _compute_slot_albedo_color(terrain, texture: Texture2D) -> Color:
	if terrain == null or texture == null:
		return Color(1, 1, 1, 0)
	if not terrain.has_method("_get_decompressed_image"):
		return Color(1, 1, 1, 0)
	var img: Image = terrain._get_decompressed_image(texture)
	if img == null or img.is_empty():
		return Color(1, 1, 1, 0)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var sample_img: Image = img
	var max_dim := maxi(sample_img.get_width(), sample_img.get_height())
	if max_dim > 16:
		var scale := 16.0 / float(max_dim)
		var target_w := maxi(1, int(round(sample_img.get_width() * scale)))
		var target_h := maxi(1, int(round(sample_img.get_height() * scale)))
		sample_img = sample_img.duplicate()
		sample_img.resize(target_w, target_h, Image.INTERPOLATE_BILINEAR)
	var accum := Color(0, 0, 0, 0)
	var count := 0.0
	for y in range(sample_img.get_height()):
		for x in range(sample_img.get_width()):
			var px: Color = sample_img.get_pixel(x, y)
			if px.a <= 0.001:
				continue
			accum.r += px.r
			accum.g += px.g
			accum.b += px.b
			count += 1.0
	if count <= 0.0:
		return Color(1, 1, 1, 0)
	return Color(accum.r / count, accum.g / count, accum.b / count, 1.0)


func _apply_slot_normal(terrain, slot_idx: int, resource: Variant) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	var texture: Texture2D = _coerce_texture2d(resource)
	if not _ensure_terrain_arrays(terrain):
		return
	var lib_res := _get_texture_library(terrain)
	if lib_res != null and slot_idx < lib_res.normal_textures.size():
		lib_res.normal_textures[slot_idx] = texture
		_save_resource_if_external(lib_res)
	_refresh_slot_runtime(terrain, false)


func _apply_slot_scale(terrain, slot_idx: int, value: Variant) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	if not _ensure_terrain_arrays(terrain):
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	terrain.texture_slots[slot_idx].scale = maxf(float(value), 0.001)
	_sync_slot_legacy_fields(terrain, slot_idx)
	if terrain.has_method("_push_tex_scales"):
		terrain._push_tex_scales()
	if terrain.has_method("refresh_chunk_surface_materials"):
		terrain.refresh_chunk_surface_materials()
	if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
		terrain.save_to_preset()


func _is_slot_inactive(slot_obj) -> bool:
	return slot_obj == null or bool(slot_obj.get("active")) == false


func _get_effective_visible_slot_count(terrain) -> int:
	if terrain == null or not _ensure_terrain_arrays(terrain):
		return 1
	var highest_active_slot := 0
	for idx in range(min(MAX_TEXTURE_SLOTS, terrain.texture_slots.size())):
		if idx == 15:
			continue
		var slot_obj = terrain.texture_slots[idx]
		if idx == 0 or not _is_slot_inactive(slot_obj):
			highest_active_slot = idx
	return clampi(max(highest_active_slot + 1, 6), 1, MAX_TEXTURE_SLOTS)


func _activate_next_texture_slot(terrain) -> bool:
	if terrain == null or not _ensure_terrain_arrays(terrain):
		return false

	var current_visible := _get_effective_visible_slot_count(terrain)
	var preferred_indices: Array[int] = []

	# First fill any inactive holes that already exist inside the visible range.
	for idx in range(1, min(current_visible, MAX_TEXTURE_SLOTS)):
		if idx == 15:
			continue
		preferred_indices.append(idx)

	# Then grow to the next logical visible slot.
	for idx in range(current_visible, min(MAX_TEXTURE_SLOTS, current_visible + 2)):
		if idx == 15:
			continue
		if not preferred_indices.has(idx):
			preferred_indices.append(idx)

	# Finally, search the remaining slots.
	for idx in range(current_visible + 1, MAX_TEXTURE_SLOTS):
		if idx == 15:
			continue
		preferred_indices.append(idx)

	for idx in preferred_indices:
		if idx < 0 or idx >= terrain.texture_slots.size():
			continue
		if terrain.texture_slots[idx] == null:
			terrain.texture_slots[idx] = _TEXTURE_SLOT_SCRIPT.new()
		if _is_slot_inactive(terrain.texture_slots[idx]):
			terrain.texture_slots[idx].active = true
			terrain.visible_texture_slot_count = clampi(max(current_visible, idx + 1), 6, MAX_TEXTURE_SLOTS)
			return true

	return false


func _reset_slot_palette_state(terrain, slot_idx: int) -> void:
	if slot_idx >= 0 and slot_idx < terrain.slot_color_indices.size():
		terrain.slot_color_indices[slot_idx] = []
	if slot_idx >= 0 and slot_idx < terrain.slot_blend_modes.size():
		terrain.slot_blend_modes[slot_idx] = 3
	if terrain.get("slot_wet_enabled") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wet_enabled.size():
		terrain.slot_wet_enabled[slot_idx] = false
	if terrain.get("slot_wet_modes") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wet_modes.size():
		terrain.slot_wet_modes[slot_idx] = 0
	if terrain.get("slot_roughnesses") is Array and slot_idx >= 0 and slot_idx < terrain.slot_roughnesses.size():
		terrain.slot_roughnesses[slot_idx] = 1.0
	if terrain.get("slot_grass_wetnesses") is Array and slot_idx >= 0 and slot_idx < terrain.slot_grass_wetnesses.size():
		terrain.slot_grass_wetnesses[slot_idx] = 0.0
	if terrain.get("slot_floor_noise_enabled") is Array and slot_idx >= 0 and slot_idx < terrain.slot_floor_noise_enabled.size():
		terrain.slot_floor_noise_enabled[slot_idx] = false
	if terrain.get("slot_floor_noise_strengths") is Array and slot_idx >= 0 and slot_idx < terrain.slot_floor_noise_strengths.size():
		terrain.slot_floor_noise_strengths[slot_idx] = terrain.global_noise_strength
	if terrain.get("slot_floor_noise_scales") is Array and slot_idx >= 0 and slot_idx < terrain.slot_floor_noise_scales.size():
		terrain.slot_floor_noise_scales[slot_idx] = 0.037
	if terrain.get("slot_wall_noise_enabled") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wall_noise_enabled.size():
		terrain.slot_wall_noise_enabled[slot_idx] = false
	if terrain.get("slot_wall_noise_strengths") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wall_noise_strengths.size():
		terrain.slot_wall_noise_strengths[slot_idx] = terrain.global_noise_strength
	if terrain.get("slot_wall_noise_scales") is Array and slot_idx >= 0 and slot_idx < terrain.slot_wall_noise_scales.size():
		terrain.slot_wall_noise_scales[slot_idx] = 0.037


func _shrink_visible_texture_slots(terrain) -> void:
	if terrain == null or not _ensure_terrain_arrays(terrain):
		return
	terrain.visible_texture_slot_count = _get_effective_visible_slot_count(terrain)


func _clear_slot(
	terrain,
	slot_idx: int,
	p_refresh_ui: bool = true,
	p_save_current_preset: bool = true,
	p_save_library: bool = true,
	p_refresh_runtime: bool = true
) -> void:
	if terrain == null or slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return
	if not _ensure_terrain_arrays(terrain):
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	var slot_res = terrain.texture_slots[slot_idx]
	var had_grass_sprite := _coerce_texture2d(slot_res.grass_texture) != null
	var had_grass_flag := bool(slot_res.get("has_grass")) if slot_res.get("has_grass") != null else false
	terrain.texture_slots[slot_idx].active = false
	terrain.texture_slots[slot_idx].texture = null
	terrain.texture_slots[slot_idx].scale = 1.0
	terrain.texture_slots[slot_idx].grass_texture = null
	terrain.texture_slots[slot_idx].has_grass = false
	_reset_slot_display_name(terrain, slot_idx)
	_reset_slot_palette_state(terrain, slot_idx)
	_sync_slot_legacy_fields(terrain, slot_idx)
	if slot_idx < 6:
		terrain.set("tex%d_has_grass" % (slot_idx + 1), false)
		terrain.set("grass_sprite_tex_%d" % (slot_idx + 1), null)
	_shrink_visible_texture_slots(terrain)
	var lib_res := _get_texture_library(terrain)
	if lib_res != null:
		if slot_idx < lib_res.albedo_textures.size():
			lib_res.albedo_textures[slot_idx] = null
		if slot_idx < lib_res.normal_textures.size():
			lib_res.normal_textures[slot_idx] = null
		if slot_idx < lib_res.grass_textures.size():
			lib_res.grass_textures[slot_idx] = null
		if p_save_library:
			_save_resource_if_external(lib_res)
	if p_refresh_runtime:
		_refresh_slot_runtime(terrain, p_refresh_ui, had_grass_sprite, had_grass_sprite or had_grass_flag, p_save_current_preset)


func _make_slot_preview(texture: Texture2D, size: int = 64) -> TextureRect:
	var thumb := TextureRect.new()
	thumb.texture = texture
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.custom_minimum_size = Vector2(size, size)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return thumb


func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	if terrain == null:
		_built_for_terrain_id = 0
		return
	_built_for_terrain_id = terrain.get_instance_id()
	
	# Ensure slot/palette arrays are initialized before we build UI.
	if not _ensure_terrain_arrays(terrain):
		return
	
	var vbox := VBoxContainer.new()
	# Match the dock width so slot cards do not collapse into unreadable previews/labels.
	var texture_settings_min_width := _get_texture_settings_min_width()
	var slot_preview_size := _get_slot_preview_size()
	vbox.set_custom_minimum_size(Vector2(texture_settings_min_width, 0))
	
	var preset := terrain.current_texture_preset
	var names : Array[String] = []
	if preset and preset.new_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		names = preset.new_tex_names.get("texture_names")
	elif vp_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(vp_tex_names)
		names = vp_tex_names.get("texture_names")
	
	# "Ghost" slot: Global Noise (not a texture slot).
	var gn_label := Label.new()
	gn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gn_label.text = "Global Noise"
	gn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gn_label.set_custom_minimum_size(Vector2(160, 25))
	gn_label.tooltip_text = "Texture used by the shader's global noise multiplier (not a texture slot)"
	vbox.add_child(gn_label, true)
	
	var gn_picker := EditorResourcePicker.new()
	gn_picker.set_base_type("Texture2D")
	var gn_tex: Texture2D = _coerce_texture2d(terrain.get("global_noise_texture"))
	gn_picker.edited_resource = gn_tex
	gn_picker.set_custom_minimum_size(Vector2(150, 25))
	gn_picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	gn_picker.resource_changed.connect(func(resource):
		resource = _coerce_texture2d(resource)
		terrain.set("global_noise_texture", resource)
	)
	gn_picker.resource_selected.connect(func(resource: Resource, inspect: bool):
		if inspect and resource != null:
			EditorInterface.inspect_object(resource)
	)
	var gn_picker_center := CenterContainer.new()
	gn_picker_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gn_picker_center.add_child(gn_picker)
	vbox.add_child(gn_picker_center, true)
	
	# Strength/scale controls for Global Noise (stored on the terrain node).
	var gn_strength_hbox := HBoxContainer.new()
	gn_strength_hbox.set_custom_minimum_size(Vector2(150, 20))
	var gn_strength_label := Label.new()
	gn_strength_label.text = "Strength:"
	gn_strength_label.set_custom_minimum_size(Vector2(70, 20))
	gn_strength_hbox.add_child(gn_strength_label)
	var gn_strength_slider := EditorSpinSlider.new()
	gn_strength_slider.set_flat(true)
	gn_strength_slider.set_min(0.0)
	gn_strength_slider.set_max(1.0)
	gn_strength_slider.set_step(0.01)
	var gn_strength_val = terrain.get("global_noise_strength")
	if gn_strength_val is float or gn_strength_val is int:
		gn_strength_slider.set_value(float(gn_strength_val))
	else:
		gn_strength_slider.set_value(1.0)
	gn_strength_slider.value_changed.connect(func(v): terrain.set("global_noise_strength", float(v)))
	gn_strength_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_strength_hbox.add_child(gn_strength_slider)
	gn_strength_hbox.visible = false
	
	var gn_scale_hbox := HBoxContainer.new()
	gn_scale_hbox.set_custom_minimum_size(Vector2(150, 20))
	var gn_scale_label := Label.new()
	gn_scale_label.text = "Scale:"
	gn_scale_label.set_custom_minimum_size(Vector2(70, 20))
	gn_scale_hbox.add_child(gn_scale_label)
	var gn_scale_slider := EditorSpinSlider.new()
	gn_scale_slider.set_flat(true)
	gn_scale_slider.set_min(0.001)
	gn_scale_slider.set_max(1.0)
	gn_scale_slider.set_step(0.001)
	var gn_scale_val = terrain.get("global_noise_scale")
	if gn_scale_val is float or gn_scale_val is int:
		gn_scale_slider.set_value(float(gn_scale_val))
	else:
		gn_scale_slider.set_value(0.037)
	gn_scale_slider.value_changed.connect(func(v): terrain.set("global_noise_scale", float(v)))
	gn_scale_slider.set_custom_minimum_size(Vector2(95, 25))
	gn_scale_hbox.add_child(gn_scale_slider)
	gn_scale_hbox.visible = false
	
	var import_texture_folder_btn := Button.new()
	import_texture_folder_btn.text = "Import Texture Folder"
	import_texture_folder_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_texture_folder_btn.pressed.connect(_open_texture_import_dialog)
	vbox.add_child(import_texture_folder_btn, true)
	
	vbox.add_child(HSeparator.new())
	
	var visible_count := _get_effective_visible_slot_count(terrain)
	
	# Compact slot list
	var actions_v := VBoxContainer.new()
	actions_v.set_custom_minimum_size(Vector2(120, 56))
	actions_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add_compact := Button.new()
	add_compact.text = "+ Add Texture"
	add_compact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_compact.pressed.connect(func():
		if not _ensure_terrain_arrays(terrain):
			return
		_activate_next_texture_slot(terrain)
		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
		EditorInterface.mark_scene_as_unsaved()
		call_deferred("add_texture_settings")
	)
	actions_v.add_child(add_compact)
	var purge_btn := Button.new()
	purge_btn.text = "Purge Unused Textures"
	purge_btn.tooltip_text = "Clears slots not referenced by chunk paint data (ground/wall/stamps), without remapping slot indices."
	purge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purge_btn.pressed.connect(func():
		_purge_unused_slots(terrain)
	)
	actions_v.add_child(purge_btn)
	var bake_btn := Button.new()
	bake_btn.text = "Bake Texture Arrays"
	bake_btn.tooltip_text = "Bake assigned textures into external Texture2DArray .res files (uses texture_library on the terrain)."
	bake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bake_btn.pressed.connect(self._on_bake_pressed)
	actions_v.add_child(bake_btn)
	var export_compact := MarchingSquaresTexturePresetExporter.new()
	export_compact.current_terrain_node = terrain
	export_compact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_v.add_child(export_compact)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	var rendered_slot_count := 0
	for i in range(visible_count):
		var slot_idx := i
		if slot_idx == 15:
			continue
		var slot_obj = terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		# Hide inactive slots; slot 0 remains always visible.
		if slot_idx != 0 and _is_slot_inactive(slot_obj):
			continue
		if rendered_slot_count > 0:
			var divider := HSeparator.new()
			divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(divider)
		var __si := slot_idx
		var tile := VBoxContainer.new()
		tile.set_custom_minimum_size(Vector2(texture_settings_min_width - 20, slot_preview_size + 60))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tex_var : Texture2D = _get_slot_albedo_texture(terrain, slot_idx)
		var thumb := _make_slot_preview(tex_var, slot_preview_size)
		var thumb_center := CenterContainer.new()
		thumb_center.add_child(thumb)
		tile.add_child(thumb_center)
		var nameplate := PanelContainer.new()
		nameplate.set_custom_minimum_size(Vector2(texture_settings_min_width - 52, 24))
		nameplate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var lbl := Label.new()
		lbl.text = names[slot_idx] if slot_idx < names.size() else ("Texture " + str(slot_idx + 1))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.set_custom_minimum_size(Vector2(texture_settings_min_width - 60, 20))
		nameplate.add_child(lbl)
		var nameplate_center := CenterContainer.new()
		nameplate_center.add_child(nameplate)
		tile.add_child(nameplate_center)
		var btn_h := HBoxContainer.new()
		btn_h.alignment = BoxContainer.ALIGNMENT_CENTER
		var edit_btn := Button.new()
		edit_btn.text = "Edit"
		edit_btn.set_custom_minimum_size(Vector2(48, 24))
		edit_btn.pressed.connect(func(): _open_texture_edit_window(__si))
		btn_h.add_child(edit_btn)
		var rem_btn := Button.new()
		rem_btn.text = "X"
		rem_btn.set_custom_minimum_size(Vector2(28, 24))
		rem_btn.disabled = slot_idx == 0
		rem_btn.pressed.connect(func(): _clear_slot(terrain, __si, true))
		btn_h.add_child(rem_btn)
		var btn_center := CenterContainer.new()
		btn_center.add_child(btn_h)
		tile.add_child(btn_center)
		grid.add_child(tile)
		rendered_slot_count += 1
	vbox.add_child(grid, true)
	vbox.add_child(actions_v, true)
	add_child(vbox, true)


func is_built_for_current_terrain() -> bool:
	var terrain := plugin.current_terrain_node if plugin != null else null
	return terrain != null and _built_for_terrain_id == terrain.get_instance_id() and get_child_count() > 0


func _open_texture_edit_window(slot_idx: int) -> void:
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	
	var existing := get_tree().get_root().get_node_or_null("TextureEditWindow")
	if existing:
		existing.queue_free()
	
	var dialog : MarchingSquaresTextureEditWindow = _TEXTURE_EDIT_WINDOW.instantiate()
	dialog.title = "Edit Texture %d" % (slot_idx + 1)
	
	# Texture preview
	dialog.texture_preview.texture = EditorInterface.get_editor_viewport_3d().get_texture()
	
	# Texture name edit
	var preset := terrain.current_texture_preset
	var names : Array = []
	if preset and preset.new_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		names = preset.new_tex_names.get("texture_names")
	elif vp_tex_names:
		names = vp_tex_names.get("texture_names")
	dialog.texture_name_edit.text = names[slot_idx] if slot_idx < names.size() else ("Texture " + str(slot_idx + 1))
	
	# Albedo texture picker
	var existing_alb_tex : Texture2D = _get_slot_albedo_texture(terrain, slot_idx)
	if existing_alb_tex != null:
		dialog.albedo_picker.edited_resource = existing_alb_tex
	dialog.albedo_picker.resource_changed.connect(func(res):
		var preview_tex : Texture2D = _coerce_texture2d(res)
		_apply_slot_albedo(terrain, slot_idx, res, true)
	)
	
	# Normal texture picker
	var lib_res : Resource = terrain.get("texture_library") if terrain.has_method("get") else null
	var initial_norm_tex : Texture2D = null
	if lib_res != null and lib_res is MSTextureLibraryScript and slot_idx < lib_res.normal_textures.size():
		var possible_nrm_tex = lib_res.normal_textures[slot_idx]
		initial_norm_tex = _coerce_texture2d(possible_nrm_tex)
	dialog.normal_picker.edited_resource = initial_norm_tex
	dialog.normal_picker.resource_changed.connect(func(resource):
		_apply_slot_normal(terrain, slot_idx, resource)
	)
	
	# Scale slider
	var slot_scale := 1.0
	if slot_idx < terrain.texture_slots.size() and terrain.texture_slots[slot_idx] != null and terrain.texture_slots[slot_idx].get("scale") != null:
		slot_scale = maxf(float(terrain.texture_slots[slot_idx].scale), 0.001)
	dialog.texture_scale_slider.set_value(slot_scale)
	dialog.texture_scale_slider.value_changed.connect(func(value: float):
		_apply_slot_scale(terrain, slot_idx, value)
	)
	
	# Color section
	_connect_color_ui(dialog, terrain, slot_idx)
	
	# Dialog window confirmation
	dialog.confirmed.connect(func(): _on_slot_settings_confirmed(slot_idx))
	# Parent window to the scene root so rebuilding it won't free it
	var root := get_tree().get_root()
	if root != null:
		root.add_child(dialog)
	else:
		add_child(dialog)
	dialog.popup_centered()
	
	# Ensure the window content is fully laid out and in-sync
	call_deferred("_refresh_slot_editor", dialog, slot_idx)


func _refresh_slot_editor(dialog: MarchingSquaresTextureEditWindow, slot_idx: int) -> void:
	if dialog == null:
		return
	
	# Rebuild UI in-place
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	
	for child in dialog.colors_container.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	if not is_instance_valid(dialog):
		return
	
	_connect_color_ui(dialog, terrain, slot_idx)


func _on_slot_settings_confirmed(slot_idx: int) -> void:
	var dialog : MarchingSquaresTextureEditWindow = get_tree().get_root().get_node_or_null("TextureEditWindow")
	if dialog == null:
		return
	var texture_name_edit := dialog.texture_name_edit
	var terrain := plugin.current_terrain_node
	if terrain == null:
		dialog.queue_free()
		return
	if not _ensure_terrain_arrays(terrain):
		dialog.queue_free()
		return
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	# Texture changes are applied immediately by the picker callbacks.
	
	# Persist name into preset if available
	var preset := terrain.current_texture_preset
	if preset != null and preset.new_tex_names != null:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		var n := preset.new_tex_names.get("texture_names")
		if n is Array and slot_idx < n.size():
			n[slot_idx] = (texture_name_edit.text if texture_name_edit != null else n[slot_idx])
			preset.new_tex_names.set("texture_names", n)
			if preset.resource_path != null and not str(preset.resource_path).is_empty():
				ResourceSaver.save(preset)
	dialog.queue_free()
	call_deferred("add_texture_settings")


func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("texture_setting_changed", p_setting_name, p_value)


func _ensure_palette_capacity(terrain) -> void:
	if terrain == null:
		return
	if terrain.palette_colors.size() < 128:
		terrain.palette_colors.resize(128)
	if terrain.palette_weights.size() < 128:
		terrain.palette_weights.resize(128)
	for i in range(128):
		if terrain.palette_colors[i] == null:
			terrain.palette_colors[i] = _default_palette_color_for_slot(i)
		if terrain.palette_weights[i] == null:
			terrain.palette_weights[i] = 100.0


func _default_palette_color_for_slot(slot: int) -> Color:
	return MarchingSquaresTerrainHelpers.default_palette_color_for_slot(slot)


func _next_free_palette_index(terrain, used: Dictionary) -> int:
	for idx in range(128):
		if not used.has(idx):
			return idx
	return -1


func _repair_slot_palette_indices(terrain, slot: int) -> void:
	if terrain == null or slot < 0 or slot >= MAX_TEXTURE_SLOTS:
		return
	_ensure_palette_capacity(terrain)
	var used_elsewhere := {}
	for si in range(MAX_TEXTURE_SLOTS):
		if si == slot:
			continue
		for idx in terrain.slot_color_indices[si]:
			used_elsewhere[int(idx)] = true
	var seen_in_slot := {}
	var indices: Array = terrain.slot_color_indices[slot]
	var changed := false
	for i in range(indices.size()):
		var pidx := int(indices[i])
		if pidx < 0 or pidx >= 128:
			pidx = -1
		var needs_new := pidx < 0 or seen_in_slot.has(pidx) or used_elsewhere.has(pidx)
		if needs_new:
			var used_all := used_elsewhere.duplicate()
			for seen_idx in seen_in_slot.keys():
				used_all[int(seen_idx)] = true
			var next_idx := _next_free_palette_index(terrain, used_all)
			if next_idx < 0:
				push_error("[MST] Palette is full (128 colors max)")
				return
			if pidx >= 0 and pidx < 128:
				terrain.palette_colors[next_idx] = terrain.palette_colors[pidx]
				terrain.palette_weights[next_idx] = terrain.palette_weights[pidx]
			else:
				terrain.palette_colors[next_idx] = _default_palette_color_for_slot(slot)
				terrain.palette_weights[next_idx] = 100.0
			indices[i] = next_idx
			pidx = next_idx
			changed = true
		seen_in_slot[pidx] = true
	if changed:
		terrain.slot_color_indices[slot] = indices
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()


func _connect_color_ui(dialog: MarchingSquaresTextureEditWindow, terrain: MarchingSquaresTerrain, slot: int) -> void:
	#print("children before ui rebuild: ", dialog.colors_container.get_child_count())
	_repair_slot_palette_indices(terrain, slot)
	
	# Blend mode dropdown
	dialog.blend_mode_button.selected = terrain.slot_blend_modes[slot]
	dialog.blend_mode_button.item_selected.connect(func(idx):
		terrain.slot_blend_modes[slot] = idx
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	
	# Color rows
	var slot_indices : Array = terrain.slot_color_indices[slot]
	var weight_labels := {}
	var weight_sliders := {}
	
	var update_weight_controls := func(indices: Array) -> void:
		for idx in indices:
			var pidx := int(idx)
			var new_text := str(int(round(float(terrain.palette_weights[pidx])))) + "%"
			var label := weight_labels.get(pidx) as Label
			if label != null:
				label.text = new_text
			var slider := weight_sliders.get(pidx) as HSlider
			if slider != null:
				slider.set_block_signals(true)
				slider.value = clampf(float(terrain.palette_weights[pidx]), 0.0, 100.0)
				slider.set_block_signals(false)
	
	for ci in range(slot_indices.size()):
		var current_color_container := dialog.SINGLE_COLOR_CONTAINER.instantiate() as MSTSingleColorContainer
		dialog.colors_container.add_child(current_color_container)
		
		var palette_idx : int = slot_indices[ci]
		
		# Color (index) label
		current_color_container.color_label.text = str(ci + 1)
		
		# Color picker
		current_color_container.color_picker.color = terrain.palette_colors[palette_idx]
		current_color_container.color_picker.color_changed.connect(func(new_color, s = slot, pidx = palette_idx):
			if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
				return
			if pidx < 0 or pidx >= terrain.palette_colors.size():
				return
			terrain.palette_colors[pidx] = new_color
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
		
		# Inline weight display (only if multiple colors)
		if slot_indices.size() > 1:
			current_color_container.color_weight_h_box.visible = true
			
			terrain._ensure_palette_weights()
			current_color_container.weight_percentage_label.text = str(int(round(terrain.palette_weights[palette_idx]))) + "%"
			weight_labels[palette_idx] = current_color_container.weight_percentage_label
			
			current_color_container.weight_slider.value = clampf(float(terrain.palette_weights[palette_idx]), 0.0, 100.0)
			weight_sliders[palette_idx] = current_color_container.weight_slider
			current_color_container.weight_slider.value_changed.connect(func(val, s = slot, pidx = palette_idx):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
					return
				terrain._ensure_palette_weights()
				var indices: Array = terrain.slot_color_indices[s]
				if indices.size() <= 1:
					return
				if pidx < 0 or pidx >= terrain.palette_weights.size():
					return
				var new_v := clampf(float(val), 0.0, 100.0)
				terrain.palette_weights[pidx] = new_v
				var remaining := 100.0 - new_v
				var others: Array = []
				var total_other := 0.0
				for idx in indices:
					if idx == pidx:
						continue
					others.append(idx)
					total_other += float(terrain.palette_weights[idx])
				if others.size() > 0:
					if total_other <= 0.0001:
						var each := remaining / float(others.size())
						for idx in others:
							terrain.palette_weights[idx] = each
					else:
						for idx in others:
							terrain.palette_weights[idx] = float(terrain.palette_weights[idx]) / total_other * remaining
				update_weight_controls.call(indices)
				terrain._rebuild_palette_uniforms()
			)
			current_color_container.weight_slider.drag_ended.connect(func(_ended):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
					return
				terrain.save_to_preset()
				add_texture_settings()
			)
		else:
			current_color_container.color_weight_h_box.visible = false
		
		# Remove button
		current_color_container.remove_color_button.pressed.connect(func(s = slot, pidx = palette_idx):
			if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
				return
			var remove_at: int = terrain.slot_color_indices[s].find(pidx)
			if remove_at < 0:
				return
			terrain.slot_color_indices[s].remove_at(remove_at)
			terrain._ensure_palette_weights()
			var indices: Array = terrain.slot_color_indices[s]
			if indices.size() > 0:
				var each := 100.0 / float(indices.size())
				for idx in indices:
					terrain.palette_weights[idx] = each
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
			# Refresh window in-place if open
			if get_tree().get_root().has_node("TextureEditWindow"):
				call_deferred("_refresh_slot_editor", dialog, s)
		)
	
	# Add color button
	dialog.add_color_button.pressed.connect(func(s = slot):
		if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
			return
		# Find first unused palette index
		_ensure_palette_capacity(terrain)
		var used := {}
		for si in range(MAX_TEXTURE_SLOTS):
			for idx in terrain.slot_color_indices[si]:
				used[int(idx)] = true
		var next_idx := _next_free_palette_index(terrain, used)
		if next_idx < 0:
			push_error("[MST] Palette is full (128 colors max)")
			return
		terrain.palette_colors[next_idx] = _default_palette_color_for_slot(s)
		terrain.slot_color_indices[s].append(next_idx)
		terrain._ensure_palette_weights()
		var indices: Array = terrain.slot_color_indices[s]
		var each := 100.0 / float(max(indices.size(), 1))
		for idx in indices:
			terrain.palette_weights[idx] = each
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
		var dlg := get_tree().get_root().get_node_or_null("TextureEditWindow")
		if dlg != null:
			# Rebuild on the next idle step so the newly added row is part of the refreshed tree.
			call_deferred("_refresh_slot_editor", dialog, s)
		else:
			call_deferred("add_texture_settings")
	)
	
	# Has grass checkbox
	var slot_res = terrain.texture_slots[slot]
	var has_grass_var := bool(slot_res.has_grass) if slot_res != null else (slot == 0)
	dialog.has_grass_check_box.button_pressed = has_grass_var
	
	# Grass sprite texture picker
	var grass_tex_var : Texture2D = _coerce_texture2d(slot_res.grass_texture) if slot_res != null else null
	if grass_tex_var == null and slot >= 0 and slot < 6:
		grass_tex_var = _coerce_texture2d(terrain.get("grass_sprite_tex_%d" % (slot + 1)))
	dialog.grass_texture_picker.edited_resource = grass_tex_var
	dialog.grass_texture_picker.visible = dialog.has_grass_check_box.button_pressed
	
	var __s_grass = slot
	dialog.grass_texture_picker.visible = dialog.has_grass_check_box.button_pressed
	dialog.has_grass_check_box.toggled.connect(func(pressed: bool):
		dialog.grass_texture_picker.visible = pressed
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[__s_grass] == null:
			terrain.texture_slots[__s_grass] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[__s_grass].has_grass = pressed
		
		# Always request a grass regen when toggling Has Grass so scene reflects change immediately.
		if terrain.has_method("_request_grass_regen"):
			terrain._request_grass_regen()
		
		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if __s_grass >= 0 and __s_grass < 6:
			terrain.set("tex%d_has_grass" % (__s_grass + 1), pressed)
		else:
			if terrain.has_method("invalidate_grass_bake_state"):
				terrain.invalidate_grass_bake_state()
			else:
				terrain.set("baked_grass_array_path", "")
				terrain.set("baked_dense_slot_lookup", PackedInt32Array())
			if terrain.has_method("rebuild_grass_texture_array"):
				terrain.rebuild_grass_texture_array()
		
		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)
	
	var __s_grass2 = slot
	dialog.grass_texture_picker.resource_changed.connect(func(resource):
		resource = _coerce_texture2d(resource)
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[__s_grass2] == null:
			terrain.texture_slots[__s_grass2] = _TEXTURE_SLOT_SCRIPT.new()
		terrain.texture_slots[__s_grass2].grass_texture = resource
		
		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if __s_grass2 >= 0 and __s_grass2 < 6:
			terrain.set("grass_sprite_tex_%d" % (__s_grass2 + 1), resource)
		var lib_res := _get_texture_library(terrain)
		if lib_res != null and __s_grass2 < lib_res.grass_textures.size():
			lib_res.grass_textures[__s_grass2] = resource
			_save_resource_if_external(lib_res)
		if terrain.has_method("invalidate_grass_bake_state"):
			terrain.invalidate_grass_bake_state()
		else:
			terrain.set("baked_grass_array_path", "")
			terrain.set("baked_dense_slot_lookup", PackedInt32Array())
		# Always rebuild grass arrays + request regen so scene updates immediately when a grass texture is changed
		if terrain.has_method("rebuild_grass_texture_array"):
			terrain.rebuild_grass_texture_array()
		if terrain.has_method("_request_grass_regen"):
			terrain._request_grass_regen()
		
		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)
	
	# Floor & Wall noise
	if not _ensure_terrain_arrays(terrain):
		return
	
	for i in range(2):
		var noise_settings_container : Control
		
		var enabled_arr : Array
		var strength_arr : Array
		var scale_arr : Array
		
		var noise_enabled_prop : String
		var noise_strength_prop : String
		var noise_scale_prop : String
		
		var slot_checkbox : CheckBox
		var strength_slider : EditorSpinSlider
		var scale_slider : EditorSpinSlider
		
		match(i):
			0:
				noise_settings_container = dialog.floor_noise_attributes
				
				enabled_arr = terrain.get("slot_floor_noise_enabled")
				strength_arr = terrain.get("slot_floor_noise_strengths")
				scale_arr = terrain.get("slot_floor_noise_scales")
				
				noise_enabled_prop = "slot_floor_noise_enabled"
				noise_strength_prop = "slot_floor_noise_strengths"
				noise_scale_prop = "slot_floor_noise_scales"
				
				slot_checkbox = dialog.floor_noise_check_box
				strength_slider = dialog.floor_strength_slider
				scale_slider = dialog.floor_scale_slider
			1:
				noise_settings_container = dialog.wall_noise_attributes
				
				enabled_arr = terrain.get("slot_wall_noise_enabled")
				strength_arr = terrain.get("slot_wall_noise_strengths")
				scale_arr = terrain.get("slot_wall_noise_scales")
				
				noise_enabled_prop = "slot_wall_noise_enabled"
				noise_strength_prop = "slot_wall_noise_strengths"
				noise_scale_prop = "slot_wall_noise_scales"
				
				slot_checkbox = dialog.wall_noise_check_box
				strength_slider = dialog.wall_strength_slider
				scale_slider = dialog.wall_scale_slider
		
		var noise_enabled := bool(enabled_arr[slot]) if slot >= 0 and slot < enabled_arr.size() else false
		
		slot_checkbox.button_pressed = noise_enabled
		strength_slider.set_value(clampf(float(strength_arr[slot]), 0.0, 1.0))
		scale_slider.set_value(clampf(float(scale_arr[slot]), 0.001, 1.0))
		
		noise_settings_container.visible = slot_checkbox.button_pressed
		slot_checkbox.toggled.connect(func(pressed: bool):
			if not _ensure_terrain_arrays(terrain):
				return
			var current_enabled : Array = terrain.get(noise_enabled_prop)
			current_enabled[slot] = pressed
			noise_settings_container.visible = pressed
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
		strength_slider.value_changed.connect(func(value: float):
			if not _ensure_terrain_arrays(terrain):
				return
			var current_strengths: Array = terrain.get(noise_strength_prop)
			current_strengths[slot] = clampf(float(value), 0.0, 1.0)
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
		scale_slider.value_changed.connect(func(value: float):
			if not _ensure_terrain_arrays(terrain):
				return
			var current_scales: Array = terrain.get(noise_scale_prop)
			current_scales[slot] = clampf(float(value), 0.001, 1.0)
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
	
	# Wetness
	dialog.wetness_check_box.button_pressed = bool(terrain.slot_wet_enabled[slot]) if (terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size()) else false
	dialog.wetness_mode_button.selected = int(terrain.slot_wet_modes[slot]) if (terrain.get("slot_wet_modes") is Array and slot >= 0 and slot < terrain.slot_wet_modes.size()) else 0
	
	# Stored as roughness: roughness = 1 - wetness.
	if terrain.get("slot_roughnesses") is Array and slot >= 0 and slot < terrain.slot_roughnesses.size():
		dialog.wetness_terrain_slider.set_value(1.0 - float(terrain.slot_roughnesses[slot]))
	else:
		dialog.wetness_terrain_slider.set_value(0.0)
	
	if terrain.get("slot_grass_wetnesses") is Array and slot >= 0 and slot < terrain.slot_grass_wetnesses.size():
		dialog.wetness_grass_slider.set_value(float(terrain.slot_grass_wetnesses[slot]))
	else:
		dialog.wetness_grass_slider.set_value(0.0)
	
	dialog.wetness_attributes.visible = dialog.wetness_check_box.button_pressed
	dialog.wetness_check_box.toggled.connect(func(pressed: bool):
		dialog.wetness_attributes.visible = pressed
		
		if not _ensure_terrain_arrays(terrain):
			return
		
		if terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size():
			terrain.slot_wet_enabled[slot] = pressed
		
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	
	dialog.wetness_check_box.toggled.connect(func(pressed: bool):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size():
			terrain.slot_wet_enabled[slot] = pressed
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	
	dialog.wetness_mode_button.item_selected.connect(func(idx: int):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_modes") is Array and slot >= 0 and slot < terrain.slot_wet_modes.size():
			terrain.slot_wet_modes[slot] = idx
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	
	dialog.wetness_terrain_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_roughnesses") is Array and slot >= 0 and slot < terrain.slot_roughnesses.size():
			terrain.slot_roughnesses[slot] = clampf(1.0 - float(value), 0.0, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	
	dialog.wetness_grass_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_grass_wetnesses") is Array and slot >= 0 and slot < terrain.slot_grass_wetnesses.size():
			terrain.slot_grass_wetnesses[slot] = clampf(float(value), 0.0, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)


func _on_slider_drag_ended(ended: bool) -> void:
	if plugin == null or plugin.current_terrain_node == null:
		return
	if plugin.current_terrain_node.has_method("regenerate_all_chunk_grass"):
		plugin.current_terrain_node.regenerate_all_chunk_grass()
		return
	for chunk: MarchingSquaresTerrainChunk in plugin.current_terrain_node.chunks.values():
		if chunk != null and chunk.grass_planter:
			chunk.grass_planter.regenerate_all_cells()


func _on_texture_import_confirmed() -> void:
	var terrain := plugin.current_terrain_node if plugin != null else null
	if terrain == null:
		push_error("[MST] No terrain selected for texture import.")
		return
	if not _ensure_terrain_arrays(terrain):
		return
	
	var preset_name := texture_import_name_input.text.strip_edges()
	var preset_slug := preset_name.to_lower().to_snake_case()
	if preset_name.is_empty() or preset_slug.is_empty():
		push_error("[MST] Texture import requires a preset name.")
		return
	
	var albedo_dir := texture_import_albedo_dir_input.text.strip_edges()
	var normal_dir := texture_import_normal_dir_input.text.strip_edges()
	if albedo_dir.is_empty() or normal_dir.is_empty():
		push_error("[MST] Choose both an Albedo or Diffuse Maps folder and a Normal Maps folder.")
		return
	
	var pairs := _build_texture_import_pairs(albedo_dir, normal_dir)
	if pairs.is_empty():
		push_error("[MST] No matching albedo/diffuse and normal texture pairs were found.")
		return
	
	var save_dir := _normalize_texture_import_save_dir(texture_import_save_path_input.text)
	var preset_folder := save_dir.path_join(preset_slug)
	var preset_folder_abs := ProjectSettings.globalize_path(preset_folder)
	if not DirAccess.dir_exists_absolute(preset_folder_abs):
		DirAccess.make_dir_recursive_absolute(preset_folder_abs)
	
	var preset_path := preset_folder.path_join(preset_slug + ".tres")
	var texture_names_path := preset_folder.path_join("texture_names.tres")
	var texture_library_path := preset_folder.path_join("texture_library.tres")
	
	var names_res: MarchingSquaresTextureNames = vp_tex_names.duplicate(true)
	MarchingSquaresTerrainPlugin._ensure_texture_names_resource(names_res)
	var save_names_error := ResourceSaver.save(names_res, texture_names_path)
	if save_names_error != OK:
		push_error("[MST] Failed to save texture names resource for import.")
		return
	var saved_names := ResourceLoader.load(texture_names_path) as MarchingSquaresTextureNames
	if saved_names != null:
		names_res = saved_names
	
	var texture_library: Resource = MSTextureLibraryScript.new()
	if texture_library.has_method("ensure_length"):
		texture_library.ensure_length()
	var save_library_error := ResourceSaver.save(texture_library, texture_library_path)
	if save_library_error != OK:
		push_error("[MST] Failed to save texture library for import.")
		return
	var saved_library := ResourceLoader.load(texture_library_path)
	if saved_library != null:
		texture_library = saved_library
	if texture_library != null and texture_library.has_method("ensure_length"):
		texture_library.ensure_length()
	
	var imported_preset := MarchingSquaresTexturePreset.new()
	imported_preset.preset_name = preset_name
	imported_preset.new_tex_names = names_res
	imported_preset.texture_library = texture_library
	if terrain.current_texture_preset != null:
		imported_preset.apply_terrain_settings = bool(terrain.current_texture_preset.apply_terrain_settings)
		imported_preset.apply_chunk_settings = bool(terrain.current_texture_preset.apply_chunk_settings)
		imported_preset.apply_vertex_painter_settings = bool(terrain.current_texture_preset.apply_vertex_painter_settings)
		imported_preset.apply_grass_settings = bool(terrain.current_texture_preset.apply_grass_settings)
	var save_preset_error := ResourceSaver.save(imported_preset, preset_path)
	if save_preset_error != OK:
		push_error("[MST] Failed to save imported texture preset.")
		return
	var saved_preset := ResourceLoader.load(preset_path) as MarchingSquaresTexturePreset
	if saved_preset != null:
		imported_preset = saved_preset
	if imported_preset.texture_library == null:
		imported_preset.texture_library = texture_library
	if imported_preset.new_tex_names == null:
		imported_preset.new_tex_names = names_res
	
	terrain.set("current_texture_preset", imported_preset)
	terrain.set("texture_library", texture_library)
	
	var slots: Array = terrain.texture_slots
	for slot_idx in range(MAX_TEXTURE_SLOTS):
		if slots[slot_idx] == null:
			slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
		slots[slot_idx].texture = null
		slots[slot_idx].grass_texture = null
		slots[slot_idx].active = false
		slots[slot_idx].scale = 1.0
		slots[slot_idx].has_grass = (slot_idx == 0)
		if slot_idx < 15:
			terrain.set("texture_%d" % (slot_idx + 1), null)
			terrain.set("texture_scale_%d" % (slot_idx + 1), 1.0)
		if texture_library != null:
			if slot_idx < texture_library.albedo_textures.size():
				texture_library.albedo_textures[slot_idx] = null
			if slot_idx < texture_library.normal_textures.size():
				texture_library.normal_textures[slot_idx] = null
			if slot_idx < texture_library.grass_textures.size():
				texture_library.grass_textures[slot_idx] = null
	
	var occupied_slots := {}
	var explicit_pairs: Array = []
	var auto_pairs: Array = []
	for pair in pairs:
		var forced_slot := int(pair.get("slot_idx", -1))
		if forced_slot >= 0 and forced_slot < MAX_TEXTURE_SLOTS and forced_slot != 15:
			if not occupied_slots.has(forced_slot):
				explicit_pairs.append(pair)
				occupied_slots[forced_slot] = true
		else:
			auto_pairs.append(pair)
	
	var assigned := 0
	var highest_slot := -1
	for pair in explicit_pairs:
		var slot_idx := int(pair["slot_idx"])
		if _assign_texture_import_pair(terrain, texture_library, names_res, slot_idx, pair):
			assigned += 1
			highest_slot = maxi(highest_slot, slot_idx)
	
	var next_auto_slot := 0
	for pair in auto_pairs:
		next_auto_slot = _next_texture_import_slot(next_auto_slot, occupied_slots)
		if next_auto_slot < 0:
			break
		if _assign_texture_import_pair(terrain, texture_library, names_res, next_auto_slot, pair):
			occupied_slots[next_auto_slot] = true
			assigned += 1
			highest_slot = maxi(highest_slot, next_auto_slot)
		next_auto_slot += 1
	
	if assigned <= 0:
		push_error("[MST] Texture import found files but could not assign any valid pairs.")
		return
	
	terrain.visible_texture_slot_count = clampi(maxi(highest_slot + 1, 6), 6, MAX_TEXTURE_SLOTS)
	_save_resource_if_external(texture_library)
	_save_resource_if_external(names_res)
	_refresh_slot_runtime(terrain, true)
	terrain.save_to_preset()
	if texture_import_bake_check != null and texture_import_bake_check.button_pressed:
		if _bake_texture_arrays_for_terrain(terrain):
			terrain.save_to_preset()
	if plugin != null:
		plugin.current_texture_preset = imported_preset
	EditorInterface.mark_scene_as_unsaved()


func _normalize_texture_import_save_dir(raw_dir: String) -> String:
	var save_dir := raw_dir.strip_edges().replace("\\", "/")
	if save_dir.is_empty():
		save_dir = TEXTURE_PRESET_DIR
	if not save_dir.begins_with("res://"):
		save_dir = TEXTURE_PRESET_DIR
	if not save_dir.ends_with("/"):
		save_dir += "/"
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(save_dir):
		dir.make_dir_recursive(save_dir)
	return save_dir


func _assign_texture_import_pair(terrain, texture_library, names_res: MarchingSquaresTextureNames, slot_idx: int, pair: Dictionary) -> bool:
	if slot_idx < 0 or slot_idx >= MAX_TEXTURE_SLOTS or slot_idx == 15:
		return false
	var albedo_tex := ResourceLoader.load(str(pair["albedo"]), "Texture2D") as Texture2D
	var normal_tex := ResourceLoader.load(str(pair["normal"]), "Texture2D") as Texture2D
	if albedo_tex == null or normal_tex == null:
		push_warning("[MST] Skipping unreadable texture pair: " + str(pair))
		return false
	if terrain.texture_slots[slot_idx] == null:
		terrain.texture_slots[slot_idx] = _TEXTURE_SLOT_SCRIPT.new()
	terrain.texture_slots[slot_idx].active = true
	terrain.texture_slots[slot_idx].texture = albedo_tex
	terrain.texture_slots[slot_idx].grass_texture = null
	terrain.texture_slots[slot_idx].has_grass = (slot_idx == 0)
	terrain.texture_slots[slot_idx].scale = 1.0
	terrain.texture_slots[slot_idx].albedo = _compute_slot_albedo_color(terrain, albedo_tex)
	_sync_slot_legacy_fields(terrain, slot_idx)
	if texture_library != null:
		if slot_idx < texture_library.albedo_textures.size():
			texture_library.albedo_textures[slot_idx] = albedo_tex
		if slot_idx < texture_library.normal_textures.size():
			texture_library.normal_textures[slot_idx] = normal_tex
	if names_res != null:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(names_res)
		var names := names_res.texture_names
		if slot_idx < names.size():
			var display_name := str(pair.get("display_name", "")).strip_edges()
			if not display_name.is_empty():
				names[slot_idx] = display_name
			names_res.texture_names = names
	return true


func _build_texture_import_pairs(albedo_dir: String, normal_dir: String) -> Array:
	var albedo_files := _list_texture_import_files(albedo_dir)
	var normal_files := _list_texture_import_files(normal_dir)
	var normal_by_key := {}
	for path in normal_files:
		var normal_info := _texture_import_file_info(path, true)
		var normal_key := str(normal_info["key"])
		if not normal_by_key.has(normal_key):
			normal_by_key[normal_key] = path
	var pairs: Array = []
	for albedo_path in albedo_files:
		var albedo_info := _texture_import_file_info(albedo_path, false)
		var key := str(albedo_info["key"])
		if not normal_by_key.has(key):
			continue
		pairs.append({
			"key": key,
			"albedo": albedo_path,
			"normal": normal_by_key[key],
			"slot_idx": int(albedo_info["slot_idx"]),
			"display_name": str(albedo_info["display_name"]),
		})
	pairs.sort_custom(func(a, b):
		var a_slot := int(a["slot_idx"])
		var b_slot := int(b["slot_idx"])
		if a_slot >= 0 and b_slot >= 0:
			return a_slot < b_slot
		if a_slot >= 0:
			return true
		if b_slot >= 0:
			return false
		return str(a["key"]) < str(b["key"])
	)
	return pairs


func _list_texture_import_files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[MST] Directory not found: " + dir_path)
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var lower := name.to_lower()
			if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp") or lower.ends_with(".tga") or lower.ends_with(".exr"):
				out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _texture_import_file_info(path: String, is_normal: bool) -> Dictionary:
	var base := path.get_file().get_basename().strip_edges()
	var slot_info := _extract_texture_import_slot_prefix(base)
	var raw_name := str(slot_info["name"])
	var suffixes := _texture_import_normal_suffixes() if is_normal else _texture_import_albedo_suffixes()
	var key_name := _strip_texture_import_suffix(raw_name.to_lower(), suffixes)
	var display_name := _strip_texture_import_suffix_ignore_case(raw_name, suffixes)
	display_name = _collapse_texture_import_spaces(display_name.replace("_", " ").replace("-", " ").strip_edges())
	return {
		"slot_idx": int(slot_info["slot_idx"]),
		"key": _collapse_texture_import_spaces(key_name.replace("_", " ").replace("-", " ").strip_edges()),
		"display_name": display_name,
	}


func _extract_texture_import_slot_prefix(name: String) -> Dictionary:
	var idx := 0
	while idx < name.length() and _texture_import_is_ascii_digit(name.unicode_at(idx)):
		idx += 1
	if idx <= 0 or idx >= name.length():
		return {"slot_idx": -1, "name": name}
	var sep := name[idx]
	if sep != " " and sep != "_" and sep != "-":
		return {"slot_idx": -1, "name": name}
	var slot_number := int(name.substr(0, idx))
	if slot_number < 1 or slot_number > MAX_TEXTURE_SLOTS:
		return {"slot_idx": -1, "name": name}
	var raw_rest := name.substr(idx + 1).strip_edges()
	while raw_rest.begins_with("_") or raw_rest.begins_with("-"):
		raw_rest = raw_rest.substr(1).strip_edges()
	if raw_rest.is_empty():
		raw_rest = name
	return {"slot_idx": slot_number - 1, "name": raw_rest}


func _texture_import_is_ascii_digit(codepoint: int) -> bool:
	return codepoint >= 48 and codepoint <= 57


func _texture_import_albedo_suffixes() -> Array:
	return [
		"_albedo", "-albedo", " albedo", "-a",
		"_diffuse", "-diffuse", " diffuse", "-d",
		"_basecolor", "-basecolor",
		"_base_color", "-base_color",
		"_color", "-color"
	]


func _texture_import_normal_suffixes() -> Array:
	return ["_normal", "-normal", " normal", "_nrm", "-nrm", "_nor", "-nor", "_n", "-n"]


func _strip_texture_import_suffix_ignore_case(name: String, suffixes: Array) -> String:
	var lower_name := name.to_lower()
	for suffix in suffixes:
		if lower_name.ends_with(str(suffix)):
			return name.substr(0, name.length() - str(suffix).length())
	return name


func _strip_texture_import_suffix(name: String, suffixes: Array) -> String:
	for suffix in suffixes:
		var suffix_str := str(suffix)
		if name.ends_with(suffix_str):
			return name.substr(0, name.length() - suffix_str.length())
	return name


func _collapse_texture_import_spaces(value: String) -> String:
	var s := value
	while s.find("  ") != -1:
		s = s.replace("  ", " ")
	return s.strip_edges()


func _next_texture_import_slot(start_slot: int, occupied_slots: Dictionary) -> int:
	for slot_idx in range(maxi(start_slot, 0), MAX_TEXTURE_SLOTS):
		if slot_idx == 15:
			continue
		if occupied_slots.has(slot_idx):
			continue
		return slot_idx
	return -1


func _bake_texture_arrays_for_terrain(terrain) -> bool:
	if terrain == null:
		push_error("[MST] No terrain selected to bake textures for.")
		return false
	var lib = terrain.get("texture_library") if terrain.has_method("get") else null
	if lib == null:
		if terrain.has_method("ensure_texture_library_resource"):
			lib = terrain.ensure_texture_library_resource()
		if lib == null:
			push_error("[MST] Terrain has no texture_library assigned, and Codex could not create one from the current texture slots.")
			return false
	_sync_texture_library_from_slots(terrain, lib)
	var out_dir := "res://scenes/baked_texture_arrays"
	if terrain.get("data_directory") != null and terrain.get("data_directory") != "":
		out_dir = str(terrain.get("data_directory")).replace("\\", "/")
		if out_dir.ends_with("/"):
			out_dir = out_dir + "baked_texture_arrays"
		else:
			out_dir = out_dir + "/baked_texture_arrays"
	var baker := MarchingSquaresBaker.new()
	var runtime_size := int(terrain.get("runtime_baked_texture_size")) if terrain.get("runtime_baked_texture_size") != null else int(terrain.get("baked_texture_size"))
	var grass_size := int(terrain.get("baked_grass_texture_size")) if terrain.get("baked_grass_texture_size") != null else 64
	var results := baker.bake_library(lib, out_dir, runtime_size, grass_size)
	if results.size() == 0:
		push_error("[MST] Baking failed or produced no results.")
		return false
	if results.has("albedo_path") and results["albedo_path"] != "":
		terrain.set("baked_albedo_array_path", results["albedo_path"])
	if results.has("normal_path") and results["normal_path"] != "":
		terrain.set("baked_normal_array_path", results["normal_path"])
	if results.has("grass_path") and results["grass_path"] != "":
		terrain.set("baked_grass_array_path", results["grass_path"])
	if results.has("dense_slot_lookup"):
		terrain.set("baked_dense_slot_lookup", results["dense_slot_lookup"])
	MarchingSquaresTerrainHelpers.rebuild_texture_array(terrain)
	MarchingSquaresTerrainHelpers.rebuild_grass_texture_array(terrain)
	return true


func _on_bake_pressed() -> void:
	var terrain := plugin.current_terrain_node
	if _bake_texture_arrays_for_terrain(terrain) and terrain != null and terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
		terrain.save_to_preset()


# Helper: position the small color swatch inside the preview control (bottom-right)
func _position_preview_swatch(preview: Control, swatch: Control) -> void:
	if preview == null or swatch == null:
		return
	var psize: Vector2 = preview.get_size()
	if psize.x <= 0 or psize.y <= 0:
		# Try again later after layout
		call_deferred("_position_preview_swatch", preview, swatch)
		return
	var sw := Vector2(36, 36)
	if swatch.has_method("set_custom_minimum_size"):
		swatch.set_custom_minimum_size(sw)
	else:
		swatch.size = sw
	var padding := Vector2(8, 8)
	var pos := Vector2(max(0, psize.x - sw.x - padding.x), max(0, psize.y - sw.y - padding.y))
	swatch.position = pos
