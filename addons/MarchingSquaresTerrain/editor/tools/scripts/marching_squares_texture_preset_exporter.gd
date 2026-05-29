@tool
extends Button
class_name MarchingSquaresTexturePresetExporter


const PRESET_DIR = "res://addons/MarchingSquaresTerrain/resources/texture_presets/"
const TEXTURE_NAMES = preload("uid://dd7fens03aosa")

var current_terrain_node : MarchingSquaresTerrain

var texture_preset_data : MarchingSquaresTextureList
var filename_dialog : AcceptDialog
var filename_input : LineEdit


func _ready() -> void:
	text = "Export Texture Preset"
	pressed.connect(_export_to_texture_preset)
	_create_texture_export_dialog()


func _create_texture_export_dialog() -> void:
	filename_dialog = AcceptDialog.new()
	filename_dialog.title = "Save Preset"
	filename_dialog.unresizable = true
	filename_dialog.confirmed.connect(_on_filename_confirmed)
	
	var cont := VBoxContainer.new()
	cont.add_theme_constant_override("seperation", 10)
	
	var label := Label.new()
	label.text = "Enter preset name:"
	cont.add_child(label)
	
	filename_input = LineEdit.new()
	filename_input.placeholder_text = "new_texture_preset"
	cont.add_child(filename_input)
	
	filename_dialog.add_child(cont)
	
	add_child(filename_dialog)


func _export_to_texture_preset() -> void:
	MarchingSquaresTerrainPlugin._ensure_texture_names_resource(TEXTURE_NAMES)
	texture_preset_data = _get_current_texture_data()
	
	filename_input.text = "new_texture_preset"
	
	filename_dialog.popup_centered(Vector2(400, 150))
	filename_input.grab_focus()
	filename_input.select_all()


func _on_filename_confirmed() -> void:
	var filename := filename_input.text.strip_edges().to_lower().to_snake_case()
	
	if filename == "":
		push_error("Filename cannot be empty!")
		return
	
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(PRESET_DIR):
		dir.make_dir_recursive(PRESET_DIR)
	
	var path := PRESET_DIR + filename + ".tres"
	
	if FileAccess.file_exists(path):
		_show_overwrite_confirmation(path)
	else:
		_save_preset(path)


func _show_overwrite_confirmation(path: String) -> void:
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Overwrite File?"
	confirm_dialog.dialog_text = "A preset with this name already exists.\nDo you want to overwrite it?"
	
	confirm_dialog.confirmed.connect(
		func():
			_save_preset(path)
			confirm_dialog.queue_free()
	)
	
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()


func _save_preset(path: String) -> void:
	var new_tex_preset := MarchingSquaresTexturePreset.new()
	
	new_tex_preset.preset_name = filename_input.text
	new_tex_preset.new_textures = texture_preset_data
	
	# Copy per-slot names from the currently active preset (if present) so names persist.
	var src_names : MarchingSquaresTextureNames = TEXTURE_NAMES
	if current_terrain_node and current_terrain_node.current_texture_preset and current_terrain_node.current_texture_preset.new_tex_names:
		src_names = current_terrain_node.current_texture_preset.new_tex_names
	MarchingSquaresTerrainPlugin._ensure_texture_names_resource(src_names)
	new_tex_preset.new_tex_names = src_names.duplicate(true)
	
	# Copy palette/outline settings from the current terrain so the exported preset is a true "look" preset.
	if current_terrain_node != null:
		if current_terrain_node.get("slot_color_indices") is Array:
			new_tex_preset.slot_color_indices = current_terrain_node.slot_color_indices.duplicate(true)
		if current_terrain_node.get("slot_blend_modes") is Array:
			new_tex_preset.slot_blend_modes = current_terrain_node.slot_blend_modes.duplicate()
		if current_terrain_node.get("palette_weights") is Array:
			new_tex_preset.palette_weights = current_terrain_node.palette_weights.duplicate()
		if current_terrain_node.get("slot_has_outline") is Array:
			new_tex_preset.slot_has_outline = current_terrain_node.slot_has_outline.duplicate()
		if current_terrain_node.get("slot_outline_modes") is Array:
			new_tex_preset.slot_outline_modes = current_terrain_node.slot_outline_modes.duplicate()
		if current_terrain_node.get("slot_outline_widths") is Array:
			new_tex_preset.slot_outline_widths = current_terrain_node.slot_outline_widths.duplicate()
		if current_terrain_node.get("slot_wet_enabled") is Array:
			new_tex_preset.slot_wet_enabled = current_terrain_node.slot_wet_enabled.duplicate()
		if current_terrain_node.get("slot_wet_modes") is Array:
			new_tex_preset.slot_wet_modes = current_terrain_node.slot_wet_modes.duplicate()
		if current_terrain_node.get("slot_roughnesses") is Array:
			new_tex_preset.slot_roughnesses = current_terrain_node.slot_roughnesses.duplicate()
	
	# If a preset is currently selected, inherit its Global Settings apply flags so exports preserve intent.
	if current_terrain_node != null and current_terrain_node.current_texture_preset != null:
		var src_preset := current_terrain_node.current_texture_preset
		if src_preset.get("apply_terrain_settings") != null:
			new_tex_preset.apply_terrain_settings = bool(src_preset.apply_terrain_settings)
		if src_preset.get("apply_chunk_settings") != null:
			new_tex_preset.apply_chunk_settings = bool(src_preset.apply_chunk_settings)
		if src_preset.get("apply_vertex_painter_settings") != null:
			new_tex_preset.apply_vertex_painter_settings = bool(src_preset.apply_vertex_painter_settings)
		if src_preset.get("apply_grass_settings") != null:
			new_tex_preset.apply_grass_settings = bool(src_preset.apply_grass_settings)
	
	# Store the current terrain settings snapshot into the exported preset (applied only if apply_terrain_settings is enabled).
	if current_terrain_node != null and current_terrain_node.has_method("_gather_preset_terrain_settings"):
		new_tex_preset.terrain_settings = current_terrain_node._gather_preset_terrain_settings(new_tex_preset)
	
	var save_error := ResourceSaver.save(new_tex_preset, path)
	if save_error == OK:
		print("Texture preset saved to: " + path)
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Failed to save texture preset: ", save_error)


func _get_current_texture_data() -> MarchingSquaresTextureList:
	var new_texture_list := MarchingSquaresTextureList.new()
	
	# Terrain textures (first 15)
	for i_tex in range(new_texture_list.terrain_textures.size()):
		var tex : Texture2D = null
		match i_tex:
			0:
				tex = current_terrain_node.texture_1
			1:
				tex = current_terrain_node.texture_2
			2:
				tex = current_terrain_node.texture_3
			3:
				tex = current_terrain_node.texture_4
			4:
				tex = current_terrain_node.texture_5
			5:
				tex = current_terrain_node.texture_6
			6:
				tex = current_terrain_node.texture_7
			7:
				tex = current_terrain_node.texture_8
			8:
				tex = current_terrain_node.texture_9
			9:
				tex = current_terrain_node.texture_10
			10:
				tex = current_terrain_node.texture_11
			11:
				tex = current_terrain_node.texture_12
			12:
				tex = current_terrain_node.texture_13
			13:
				tex = current_terrain_node.texture_14
			14:
				tex = current_terrain_node.texture_15
		new_texture_list.terrain_textures[i_tex] = tex
	
	# Texture scales (first 15)
	for i_tex_scale in range(new_texture_list.texture_scales.size()):
		var scale : float = 1.0
		match i_tex_scale:
			0:
				scale = current_terrain_node.texture_scale_1
			1:
				scale = current_terrain_node.texture_scale_2
			2:
				scale = current_terrain_node.texture_scale_3
			3:
				scale = current_terrain_node.texture_scale_4
			4:
				scale = current_terrain_node.texture_scale_5
			5:
				scale = current_terrain_node.texture_scale_6
			6:
				scale = current_terrain_node.texture_scale_7
			7:
				scale = current_terrain_node.texture_scale_8
			8:
				scale = current_terrain_node.texture_scale_9
			9:
				scale = current_terrain_node.texture_scale_10
			10:
				scale = current_terrain_node.texture_scale_11
			11:
				scale = current_terrain_node.texture_scale_12
			12:
				scale = current_terrain_node.texture_scale_13
			13:
				scale = current_terrain_node.texture_scale_14
			14:
				scale = current_terrain_node.texture_scale_15
		new_texture_list.texture_scales[i_tex_scale] = scale
	
	# Palette colors (0..127) are stored in new_textures.grass_colors for historical reasons.
	if current_terrain_node.get("palette_colors") is Array:
		new_texture_list.grass_colors.resize(128)
		var pal_size := current_terrain_node.palette_colors.size()
		for i in range(128):
			new_texture_list.grass_colors[i] = current_terrain_node.palette_colors[i] if i < pal_size else Color.WHITE
	
	# Slot-based grass sprites + has-grass flags (0..255)
	if current_terrain_node.has_method("_ensure_texture_slots"):
		current_terrain_node._ensure_texture_slots()
	if current_terrain_node.get("texture_slots") is Array and current_terrain_node.texture_slots.size() >= MarchingSquaresTextureList.MAX_TEXTURE_SLOTS:
		new_texture_list.grass_sprites.resize(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS)
		new_texture_list.has_grass.resize(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS)
		for i in range(MarchingSquaresTextureList.MAX_TEXTURE_SLOTS):
			var slot = current_terrain_node.texture_slots[i]
			new_texture_list.grass_sprites[i] = slot.grass_texture if slot != null else null
			new_texture_list.has_grass[i] = bool(slot.has_grass) if slot != null else (i < 6)
	else:
		# Legacy fallback (first 6 only); keep arrays at MAX_TEXTURE_SLOTS.
		new_texture_list.grass_sprites[0] = current_terrain_node.grass_sprite_tex_1
		new_texture_list.grass_sprites[1] = current_terrain_node.grass_sprite_tex_2
		new_texture_list.grass_sprites[2] = current_terrain_node.grass_sprite_tex_3
		new_texture_list.grass_sprites[3] = current_terrain_node.grass_sprite_tex_4
		new_texture_list.grass_sprites[4] = current_terrain_node.grass_sprite_tex_5
		new_texture_list.grass_sprites[5] = current_terrain_node.grass_sprite_tex_6
		new_texture_list.has_grass[0] = bool(current_terrain_node.get("tex1_has_grass")) if current_terrain_node.get("tex1_has_grass") != null else true
		new_texture_list.has_grass[1] = bool(current_terrain_node.tex2_has_grass)
		new_texture_list.has_grass[2] = bool(current_terrain_node.tex3_has_grass)
		new_texture_list.has_grass[3] = bool(current_terrain_node.tex4_has_grass)
		new_texture_list.has_grass[4] = bool(current_terrain_node.tex5_has_grass)
		new_texture_list.has_grass[5] = bool(current_terrain_node.tex6_has_grass)
	
	return new_texture_list
