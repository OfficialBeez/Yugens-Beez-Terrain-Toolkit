@tool
extends ScrollContainer
class_name MarchingSquaresToolAttributes


signal setting_changed(setting: String, value: Variant)
signal terrain_setting_changed(setting: String, value: Variant)

const TEXTURE_PRESETS_PATH : String= "res://addons/MarchingSquaresTerrain/resources/texture_presets/"
const GLOBAL_QUICK_PAINTS_PATH : String = "res://addons/MarchingSquaresTerrain/resources/quick_paints/global/"

enum SettingType {
	CHECKBOX,
	SLIDER,
	OPTION,
	TEXT,
	CHUNK,
	TERRAIN,
	PRESET,
	QUICK_PAINT,
	ERROR,
}

# Add/move settings between groups freely — the UI updates automatically.
var terrain_settings_data : Dictionary = {
	"Chunk Settings": {
		"dimensions": "Vector3i",
		"cell_size": "Vector2",
		"blend_mode": "OptionButton",
		"extra_collision_layer": "OptionButton",
		"noise_hmap": "EditorResourcePicker",
		"collision_depth": "EditorSpinSlider",
	},
	"Vertex Painter Settings": {
		"default_wall_texture": "OptionButton",
		"use_ridge_texture": "CheckBox",
		"use_ledge_texture": "CheckBox",
		"ridge_threshold": "EditorSpinSlider",
		"ledge_threshold": "EditorSpinSlider",
		"wall_threshold": "EditorSpinSlider",
		"use_flat_normals": "CheckBox",
		"use_cell_shading": "CheckBox",
	},
	"Grass Settings": {
		"global_noise_scale": "EditorSpinSlider",
		"global_noise_strength": "EditorSpinSlider",
		"grass_subdivisions": "SpinBox",
		"grass_size": "Vector2",
		"grass_size_variation": "EditorSpinSlider",
		"animation_fps": "SpinBox",
		"wind_mode": "OptionButton",
		"wind_intensity": "EditorSpinSlider",
		"wind_tip_color": "ColorPickerButton",
		"wind_tip_strength": "EditorSpinSlider",
	},
}

var plugin : MarchingSquaresTerrainPlugin
var attribute_list : MarchingSquaresToolAttributesList
var settings : Dictionary = {}

var last_setting_type : SettingType = SettingType.ERROR
var selected_chunk : MarchingSquaresTerrainChunk
var current_available_chunks : Array[MarchingSquaresTerrainChunk] = []

var hbox_container


func _ready() -> void:
	set_custom_minimum_size(Vector2(0, 35))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func show_tool_attributes(tool_index: int) -> void:
	hbox_container = HBoxContainer.new()
	hbox_container.add_theme_constant_override("separation", 5)
	hbox_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_container.size_flags_vertical = Control.SIZE_FILL
	
	if not visible:
		return
	
	for child in get_children():
		child.queue_free()
	settings.clear()
	
	if not plugin.toolbar.toolbox:
		return
	
	if tool_index == 7 and plugin.selected_chunk == null and not plugin.current_terrain_node.chunks.is_empty(): # Chunk management tool
		plugin.selected_chunk = plugin.current_terrain_node.chunks.values().pick_random()
		selected_chunk = plugin.selected_chunk
	
	var tool := plugin.toolbar.toolbox.tools.get(tool_index)
	var tool_attributes : MarchingSquaresToolAttributeSettings = tool.get("attributes")
	var type_map = {
		"slider": SettingType.SLIDER,
		"checkbox": SettingType.CHECKBOX,
		"option": SettingType.OPTION,
		"text": SettingType.TEXT,
		"chunk": SettingType.CHUNK,
		"terrain": SettingType.TERRAIN,
		"preset": SettingType.PRESET,
		"quick_paint": SettingType.QUICK_PAINT,
	}
	
	var new_attributes := []
	if tool_attributes.chunk_management:
		new_attributes.append(attribute_list.chunk_management)
	if tool_attributes.terrain_settings:
		new_attributes.append(attribute_list.terrain_settings)
	
	if tool_attributes.brush_type:
		new_attributes.append(attribute_list.brush_type)
	if tool_attributes.size:
		new_attributes.append(attribute_list.size)
	if tool_attributes.ease_value:
		new_attributes.append(attribute_list.ease_value)
	if tool_attributes.height:
		new_attributes.append(attribute_list.height)
	if tool_attributes.strength:
		new_attributes.append(attribute_list.strength)
	if tool_attributes.flatten:
		new_attributes.append(attribute_list.flatten)
	if tool_attributes.falloff:
		new_attributes.append(attribute_list.falloff)
	if tool_attributes.mask_mode:
		new_attributes.append(attribute_list.mask_mode)
	if tool_attributes.material:
		new_attributes.append(attribute_list.material)
	if tool_attributes.texture_name:
		new_attributes.append(attribute_list.texture_name)
	if tool_attributes.texture_preset:
		new_attributes.append(attribute_list.texture_preset)
	if tool_attributes.quick_paint_selection:
		new_attributes.append(attribute_list.quick_paint_selection)
	if tool_attributes.paint_walls:
		new_attributes.append(attribute_list.paint_walls)
	
	# Rebuild material names from the live terrain node
	var terrain_names : Array = []
	if plugin.current_terrain_node and plugin.current_terrain_node.texture_names.size() > 0:
		terrain_names = plugin.current_terrain_node.texture_names
	else:
		terrain_names = attribute_list.vp_tex_names.texture_names  # fallback
	attribute_list.material["options"] = terrain_names
	
	for attribute in new_attributes:
		var setting_dict : Dictionary = attribute
		if setting_dict.has("type") and setting_dict["type"] is String:
			setting_dict["type"] = type_map.get(setting_dict["type"], SettingType.ERROR)
		add_setting(setting_dict)
	
	add_child(hbox_container)
	last_setting_type = SettingType.ERROR # Reset the setting type for correct VSeparators
	
	plugin.gizmo_plugin.trigger_redraw(plugin.current_terrain_node)


func add_setting(p_params: Dictionary) -> void:
	var setting_name : String = p_params.get("name", "")
	var setting_type : SettingType = p_params.get("type", SettingType.ERROR)
	var label_text : String = p_params.get("label", setting_name)
	
	if last_setting_type != SettingType.ERROR:
		if last_setting_type == SettingType.SLIDER and setting_type == SettingType.SLIDER:
			pass
		elif last_setting_type != setting_type:
			hbox_container.add_child(VSeparator.new())
	
	var add_label := true
	if setting_type == SettingType.CHUNK or setting_type == SettingType.TERRAIN:
		add_label = false
	if add_label:
		var label := Label.new()
		label.set_text(label_text + ':')
		label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		label.set_custom_minimum_size(Vector2(50, 25))
		
		var c_cont := CenterContainer.new()
		c_cont.set_custom_minimum_size(Vector2(50, 35))
		c_cont.add_child(label, true)
		hbox_container.add_child(c_cont, true)
	
	var cont
	var saved_setting_value := _get_setting_value(setting_name)
	match setting_type:
		SettingType.CHECKBOX:
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = p_params.get("default", false) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				checkbox.button_pressed = saved_setting_value
			checkbox.toggled.connect(func(pressed): _on_setting_changed(setting_name, pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 25))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(checkbox, true)
			hbox_container.add_child(cont, true)
		SettingType.SLIDER:
			var range_data := p_params.get("range", Vector3(1.0, 50.0, 0.5))
			var cell_scale_factor := clamp(((plugin.current_terrain_node.cell_size.x + plugin.current_terrain_node.cell_size.y) / 4.0), 0.3, 1.0)
			var dimensions_scale_factor := clamp((((plugin.current_terrain_node.dimensions.x / 33) + (plugin.current_terrain_node.dimensions.z / 33)) / 2.0), 0.5, 2.0)
			var scale_factor : float = dimensions_scale_factor * cell_scale_factor
			var default_value := p_params.get("default", 10.0) # Fallback base value
			if setting_name == "size":
				range_data *= scale_factor
				default_value *= scale_factor
			var range_min = range_data.x
			var range_max = range_data.y
			var range_step = range_data.z
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				default_value = saved_setting_value
			
			cont = MarginContainer.new()
			cont.set_custom_minimum_size(Vector2(80, 35))
			if setting_name == "height" or setting_name == "ease_value":
				var spin_slider := EditorSpinSlider.new()
				spin_slider.set_flat(true)
				spin_slider.allow_greater = true
				spin_slider.allow_lesser = true
				spin_slider.set_min(range_min)
				spin_slider.set_max(range_max)
				spin_slider.set_step(range_step)
				spin_slider.set_value(default_value)
				spin_slider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				spin_slider.set_custom_minimum_size(Vector2(80, 35))
				
				cont.add_theme_constant_override("margin_top", -5)
				cont.add_child(spin_slider, true)
			else:
				var hslider := HSlider.new()
				hslider.set_min(range_min)
				hslider.set_max(range_max)
				hslider.set_step(range_step)
				hslider.set_value(default_value)
				hslider.value_changed.connect(func(value): _on_setting_changed(setting_name, value))
				hslider.set_custom_minimum_size(Vector2(80, 35))
				
				cont.add_theme_constant_override("margin_right", 10)
				cont.add_theme_constant_override("margin_left", -3)
				cont.add_child(hslider, true)
			hbox_container.add_child(cont, true)
		SettingType.OPTION:
			var options : Array = p_params.get("options", [])
			var option_button := OptionButton.new()
			for option in options:
				option_button.add_item(option)
			var default_value := p_params.get("default", 0) # Fallback base value
			if saved_setting_value is not String and str(saved_setting_value) != "ERROR":
				default_value = saved_setting_value
			option_button.selected = default_value
			
			option_button.set_flat(true)
			option_button.item_selected.connect(func(index): _on_setting_changed(setting_name, index))
			option_button.set_custom_minimum_size(Vector2(65, 35))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(option_button, true)
			hbox_container.add_child(cont, true)
		SettingType.TEXT:
			var line_edit := LineEdit.new()
			line_edit.set_flat(true)
			line_edit.expand_to_text_length = true
			line_edit.placeholder_text = p_params.get("default", "New text here...")
			line_edit.text_submitted.connect(func(new_text): _on_setting_changed(setting_name, new_text))
			line_edit.text_submitted.connect(func(_text): line_edit.clear())
			line_edit.set_custom_minimum_size(Vector2(25, 25))
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(35, 35))
			cont.add_child(line_edit, true)
			hbox_container.add_child(cont, true)
		SettingType.PRESET:
			var preset_button := OptionButton.new()
			var dir : DirAccess
			var file_name : String
			preset_button.add_item("None") # First option is no preset
			preset_button.set_item_metadata(0, null)
			if setting_name == "texture_preset":
				dir = DirAccess.open(TEXTURE_PRESETS_PATH)
				if dir:
					dir.list_dir_begin()
					file_name = dir.get_next()
					while file_name != "":
						if file_name.ends_with(".tres") or file_name.ends_with(".res"):
							var texture_preset := load(TEXTURE_PRESETS_PATH + file_name) as MarchingSquaresTexturePreset
							if texture_preset:
								preset_button.add_item(texture_preset.preset_name)
								preset_button.set_item_metadata(preset_button.item_count - 1, texture_preset)
						file_name = dir.get_next()
					dir.list_dir_end()
				
				preset_button.set_flat(true)
				preset_button.item_selected.connect(func(index):
					var selected_texture_preset = preset_button.get_item_metadata(index)
					_on_setting_changed(setting_name, selected_texture_preset)
				)
				preset_button.set_custom_minimum_size(Vector2(100, 35))
				
				# Sync dropdown selection with current plugin.current_texture_preset
				var current_texture_preset = plugin.current_texture_preset
				if current_texture_preset == null:
					preset_button.select(0)  # Select "None"
				else:
					# Find matching preset in dropdown
					for i in range(preset_button.item_count):
						if preset_button.get_item_metadata(i) == current_texture_preset:
							preset_button.select(i)
							break
				
				cont = CenterContainer.new()
				cont.set_custom_minimum_size(Vector2(100, 35))
				cont.add_child(preset_button, true)
				hbox_container.add_child(cont, true)
			else: # Can be used for e.g. terrain settings presets in the future
				pass
		SettingType.QUICK_PAINT:
			var quick_paint_button := OptionButton.new()
			quick_paint_button.add_item("None")  # First option is no paint. #TODO Doesn't seem to work right now and needs to be fixed later.
			quick_paint_button.set_item_metadata(0, null)
			
			# 1. Load GLOBAL quick paints from folder (always available)
			var dir := DirAccess.open(GLOBAL_QUICK_PAINTS_PATH)
			if dir:
				dir.list_dir_begin()
				var file_name := dir.get_next()
				while file_name != "":
					if file_name.ends_with(".tres") or file_name.ends_with(".res"):
						var quick_paint := load(GLOBAL_QUICK_PAINTS_PATH + file_name) as MarchingSquaresQuickPaint
						if quick_paint:
							quick_paint_button.add_item(quick_paint.paint_name)
							quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint)
					file_name = dir.get_next()
				dir.list_dir_end()
			
			# 2. Load PRESET-SPECIFIC quick paints (if preset is selected and has any)
			var terrain := MarchingSquaresTerrainPlugin.instance.current_terrain_node
			if terrain and terrain.current_texture_preset:
				var preset := terrain.current_texture_preset
				if preset.quick_paints.size() > 0:
					quick_paint_button.add_separator()  # Visual separator
					for quick_paint in preset.quick_paints:
						if quick_paint:
							quick_paint_button.add_item(quick_paint.paint_name)
							quick_paint_button.set_item_metadata(quick_paint_button.item_count - 1, quick_paint)
			
			quick_paint_button.set_flat(true)
			quick_paint_button.item_selected.connect(func(index):
				var selected_quick_paint = quick_paint_button.get_item_metadata(index)
				_on_setting_changed(setting_name, selected_quick_paint)
			)
			quick_paint_button.set_custom_minimum_size(Vector2(100, 35))
			
			# Sync dropdown selection with current plugin.current_quick_paint
			var current_quick_paint = _get_setting_value(setting_name)
			if current_quick_paint == null:
				quick_paint_button.select(0)  # Select "None"
			else:
				# Find matching quick paint in dropdown
				for i in range(quick_paint_button.item_count):
					if quick_paint_button.get_item_metadata(i) == current_quick_paint:
						quick_paint_button.select(i)
						break
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(100, 35))
			cont.add_child(quick_paint_button, true)
			hbox_container.add_child(cont, true)
		SettingType.CHUNK:
			if plugin.current_terrain_node.get_child_count() == 0:
				return
			
			current_available_chunks.clear()
			
			var terrain_children : Array = plugin.current_terrain_node.get_children()
			var chunk_button := OptionButton.new()
			for child in terrain_children:
				if child is MarchingSquaresTerrainChunk:
					chunk_button.add_item("Chunk " + str(child.chunk_coords))
					current_available_chunks.append(child)
			chunk_button.selected = current_available_chunks.find(plugin.selected_chunk) if not current_available_chunks.is_empty() and plugin.selected_chunk else -1
			if not current_available_chunks.is_empty() and plugin.selected_chunk:
				selected_chunk = plugin.selected_chunk
			
			var option_button := OptionButton.new()
			option_button.set_flat(true)
			option_button.set_custom_minimum_size(Vector2(65, 35))
			for mode in MarchingSquaresTerrainChunk.Mode:
				option_button.add_item(_format_constant_string(mode))
			option_button.selected = plugin.selected_chunk.merge_mode if not current_available_chunks.is_empty() and plugin.selected_chunk else -1
			option_button.item_selected.connect(_on_chunk_mode_changed)
			
			chunk_button.set_flat(true)
			chunk_button.item_selected.connect(func(chunk): _on_chunk_selected(option_button, chunk_button.get_item_text(chunk)))
			chunk_button.set_custom_minimum_size(Vector2(65, 35))
			
			var mult_apply_button := Button.new()
			mult_apply_button.set_custom_minimum_size(Vector2(65, 30))
			mult_apply_button.pressed.connect(_apply_mode_to_all_chunks)
			mult_apply_button.text = "Apply mode to all chunks"
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(chunk_button, true)
			hbox_container.add_child(cont, true)
			
			var v_sep := VSeparator.new()
			hbox_container.add_child(v_sep, true)
			
			cont = CenterContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_child(option_button, true)
			hbox_container.add_child(cont, true)
			
			v_sep = VSeparator.new()
			hbox_container.add_child(v_sep, true)
			
			cont = MarginContainer.new()
			cont.set_custom_minimum_size(Vector2(65, 35))
			cont.add_theme_constant_override("margin_bottom", 3)
			cont.add_child(mult_apply_button, true)
			hbox_container.add_child(cont, true)
		SettingType.TERRAIN:
			# Build one FoldableContainer per group, laid out horizontally
			for group_name in terrain_settings_data.keys():
				var group_settings : Dictionary = terrain_settings_data[group_name]

				var fold := FoldableContainer.new()
				fold.title = group_name
				fold.folded = true # start collapsed for a clean default
				fold.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

				# Inner scroll lets a single tall group scroll vertically if needed
				var inner_scroll := ScrollContainer.new()
				inner_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				inner_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
				inner_scroll.set_custom_minimum_size(Vector2(260, 140))   # was Vector2(260, 0)
				inner_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
				fold.add_child(inner_scroll)

				var vbox := VBoxContainer.new()
				vbox.add_theme_constant_override("separation", 4)
				vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				inner_scroll.add_child(vbox)

				for setting in group_settings.keys():
					vbox.add_child(_make_terrain_setting_row(setting, group_settings[setting]))

				hbox_container.add_child(fold)
				hbox_container.add_child(VSeparator.new())


func _make_terrain_setting_row(setting: String, editor_setting: String) -> HBoxContainer:
	var s_value = plugin.current_terrain_node.get(setting)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = _make_editor_name(setting) + ":"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_custom_minimum_size(Vector2(110, 25))
	hbox.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var editor : Control = _make_terrain_setting_editor(setting, editor_setting, s_value)
	if editor:
		hbox.add_child(editor)
	return hbox


func _make_terrain_setting_editor(setting: String, editor_setting: String, s_value) -> Control:
	match editor_setting:
		"Vector2", "Vector3i":
			return _make_vector_editor(editor_setting, s_value, setting)
		"SpinBox":
			var spin_box := SpinBox.new()
			spin_box.value = s_value
			spin_box.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
			spin_box.set_custom_minimum_size(Vector2(80, 25))
			return spin_box
		"EditorSpinSlider":
			var spin_slider := EditorSpinSlider.new()
			spin_slider.set_flat(true)
			if setting == "wall_threshold":
				spin_slider.set_min(0.005)
				spin_slider.set_max(0.5)
			elif setting == "collision_depth":
				spin_slider.set_min(0.0)
				spin_slider.set_max(1.0)
				spin_slider.allow_greater = true
			else:
				spin_slider.set_min(0.005)
				spin_slider.set_max(1.0)
			spin_slider.set_step(0.1)
			spin_slider.set_value(s_value if s_value != null else 0.0)
			spin_slider.value_changed.connect(func(value): _on_terrain_setting_changed(setting, value))
			spin_slider.set_custom_minimum_size(Vector2(120, 25))
			return spin_slider
		"EditorResourcePicker":
			var picker := EditorResourcePicker.new()
			picker.set_base_type("Noise" if setting == "noise_hmap" else "Texture2D")
			picker.edited_resource = s_value
			_hide_textures(picker)
			picker.resource_changed.connect(func(resource): _on_terrain_setting_changed(setting, resource))
			picker.set_custom_minimum_size(Vector2(120, 25))
			return picker
		"ColorPickerButton":
			var c_pick := ColorPickerButton.new()
			c_pick.color = s_value
			c_pick.color_changed.connect(func(color): _on_terrain_setting_changed(setting, color))
			c_pick.set_custom_minimum_size(Vector2(120, 25))
			return c_pick
		"CheckBox":
			var checkbox := CheckBox.new()
			checkbox.set_flat(true)
			checkbox.button_pressed = s_value
			checkbox.toggled.connect(func(pressed): _on_terrain_setting_changed(setting, pressed))
			return checkbox
		"OptionButton":
			var option_button := OptionButton.new()
			option_button.set_flat(true)
			if setting == "default_wall_texture":
				for tex_name in attribute_list.vp_tex_names.texture_names:
					option_button.add_item(tex_name)
				option_button.selected = s_value
			elif setting == "blend_mode":
				option_button.add_item("Smoothed Triangles")
				option_button.add_item("Hard Squares")
				option_button.add_item("Hard Triangles")
				option_button.selected = s_value
			elif setting == "extra_collision_layer":
				for i in range(24):
					option_button.add_item(str(i + 9))
				option_button.selected = s_value - 9
			elif setting == "wind_mode":
				option_button.add_item("Smooth")
				option_button.add_item("Gust")
				option_button.add_item("Pulse")
				option_button.add_item("Turbulence")
				option_button.selected = s_value
			else:
				option_button.selected = s_value
			option_button.item_selected.connect(func(index): _on_terrain_setting_changed(setting, index))
			option_button.set_custom_minimum_size(Vector2(140, 25))
			return option_button
		"LineEdit":
			var line_edit := LineEdit.new()
			line_edit.set_flat(true)
			line_edit.text = str(s_value)
			line_edit.text_submitted.connect(func(new_text): _on_terrain_setting_changed(setting, new_text))
			line_edit.set_custom_minimum_size(Vector2(200, 25))
			return line_edit
		"FolderPicker":
			var folder_hbox := HBoxContainer.new()
			folder_hbox.add_theme_constant_override("separation", 4)
			var path_edit := LineEdit.new()
			path_edit.set_flat(true)
			path_edit.text = str(s_value)
			path_edit.placeholder_text = "(auto - scene relative)"
			path_edit.text_submitted.connect(func(new_text): _on_terrain_setting_changed(setting, new_text))
			path_edit.set_custom_minimum_size(Vector2(180, 25))
			folder_hbox.add_child(path_edit)
			var browse_btn := Button.new()
			browse_btn.text = "..."
			browse_btn.set_custom_minimum_size(Vector2(30, 25))
			browse_btn.pressed.connect(func(): _open_folder_dialog(setting, path_edit))
			folder_hbox.add_child(browse_btn)
			return folder_hbox
	return null


func _get_setting_value(p_setting_name: String) -> Variant:
	match p_setting_name:
		"brush_type":
			return plugin.current_brush_index
		"size":
			return plugin.brush_size
		"ease_value":
			return plugin.ease_value
		"height":
			return plugin.height
		"strength":
			return plugin.height
		"flatten":
			return plugin.flatten
		"falloff":
			return plugin.falloff
		"mask_mode":
			return plugin.should_mask_grass
		"material":
			return plugin.vertex_color_idx
		"texture_name":
			pass
		"texture_preset":
			return plugin.current_texture_preset
		"quick_paint_selection":
			return plugin.current_quick_paint
		"paint_walls":
			return plugin.paint_walls_mode
		"chunk_management":
			pass
		"terrain_settings":
			pass
		_:
			push_error("Couldn't find tool attributes setting name")
	return "ERROR"


func _open_folder_dialog(setting_name: String, path_edit: LineEdit) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.title = "Select Directory"
	
	# Set initial path from current value or project root
	var current_path : String = path_edit.text
	if current_path.is_empty():
		dialog.current_dir = "res://"
	else:
		dialog.current_dir = current_path.get_base_dir()
	
	dialog.dir_selected.connect(func(dir: String):
		path_edit.text = dir
		_on_terrain_setting_changed(setting_name, dir)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	
	# Add to editor base control for proper modal behavior
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))

#region on-signal functions

func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("setting_changed", p_setting_name, p_value)


func _on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("terrain_setting_changed", p_setting_name, p_value)


func _on_chunk_selected(option_button: OptionButton, p_chunk: String) -> void:
	var terrain := plugin.current_terrain_node
	var chunk : MarchingSquaresTerrainChunk = terrain.find_child(p_chunk)
	
	option_button.selected = chunk.merge_mode
	selected_chunk = plugin.current_terrain_node.find_child(p_chunk)
	plugin.selected_chunk = selected_chunk
	
	plugin.gizmo_plugin.trigger_redraw(terrain)


func _apply_mode_to_all_chunks() -> void:
	for child in plugin.current_terrain_node.get_children():
		if child is MarchingSquaresTerrainChunk:
			_change_chunk_mode(child, selected_chunk.merge_mode)


func _on_chunk_mode_changed(m_mode: int) -> void:
	_change_chunk_mode(selected_chunk, m_mode)


func _change_chunk_mode(_chunk: MarchingSquaresTerrainChunk, m_mode: int) -> void:
	match MarchingSquaresTerrainChunk.Mode.find_key(m_mode):
		"CUBIC":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.CUBIC
		"POLYHEDRON":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.POLYHEDRON
		"ROUNDED_POLYHEDRON":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.ROUNDED_POLYHEDRON
		"SEMI_ROUND":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SEMI_ROUND
		"SPHERICAL":
			_chunk.merge_mode = MarchingSquaresTerrainChunk.Mode.SPHERICAL

#endregion

#region UI-helpers

func _make_vector_editor(type: String, value: Variant, setting_name: String) -> HBoxContainer:
	var hbox_cont := HBoxContainer.new()
	
	if type == "Vector2":
		var spin_x := make_spinbox(value.x, 0.1)
		var spin_y := make_spinbox(value.y, 0.1)
		
		var handler_x := func(v):
			var updated_val = Vector2(v, spin_y.value)
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y := func(v):
			var updated_val = Vector2(spin_x.value, v)
			_on_terrain_setting_changed(setting_name, updated_val)
		
		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		
		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
	
	elif type == "Vector3i":
		var spin_x := make_spinbox(value.x, 1.0)
		var spin_y := make_spinbox(value.y, 1.0)
		var spin_z := make_spinbox(value.z, 1.0)
		
		var handler_x := func(v):
			var updated_val = Vector3i(int(v), int(spin_y.value), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_y := func(v):
			var updated_val = Vector3i(int(spin_x.value), int(v), int(spin_z.value))
			_on_terrain_setting_changed(setting_name, updated_val)
		var handler_z := func(v):
			var updated_val = Vector3i(int(spin_x.value), int(spin_y.value), int(v))
			_on_terrain_setting_changed(setting_name, updated_val)
		
		spin_x.value_changed.connect(handler_x)
		spin_y.value_changed.connect(handler_y)
		spin_z.value_changed.connect(handler_z)
		
		hbox_cont.add_child(spin_x)
		hbox_cont.add_child(spin_y)
		hbox_cont.add_child(spin_z)
	
	return hbox_cont


func make_spinbox(val: float, step: float) -> SpinBox:
	var spin_box := SpinBox.new()
	spin_box.set_step(step)
	spin_box.set_value(float(val))
	spin_box.set_custom_minimum_size(Vector2(50, 25))
	return spin_box


func _make_editor_name(var_name: String) -> String:
	var loose_words := var_name.split("_")
	for word in loose_words:
		loose_words[loose_words.find(word)] = word.capitalize()
	return " ".join(loose_words)


func _hide_textures(texture_node: Node) -> void:
	var texture_button := texture_node.get_child(0) as Button
	texture_button.visible = false


func _format_constant_string(text: String) -> String:
	var words := text.to_lower().split("_")
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)

#endregion
