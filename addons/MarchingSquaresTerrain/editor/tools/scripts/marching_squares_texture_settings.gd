@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin
var vp_tex_names : MarchingSquaresTextureNames = preload("uid://dd7fens03aosa")

const VAR_NAMES : Array[Dictionary] = [
	{
		"tex_var": "texture_1",
		"scale_var": "texture_scale_1",
		"sprite_var": "grass_sprite_tex_1",
		"palette_colors": ["tex1_color_1", "tex1_color_2", "tex1_color_3", "tex1_color_4"],
	},
	{
		"tex_var": "texture_2",
		"scale_var": "texture_scale_2",
		"sprite_var": "grass_sprite_tex_2",
		"palette_colors": ["tex2_color_1", "tex2_color_2", "tex2_color_3", "tex2_color_4"],
		"use_grass_var": "tex2_has_grass",
	},
	{
		"tex_var": "texture_3",
		"scale_var": "texture_scale_3",
		"sprite_var": "grass_sprite_tex_3",
		"palette_colors": ["tex3_color_1", "tex3_color_2", "tex3_color_3", "tex3_color_4"],
		"use_grass_var": "tex3_has_grass",
	},
	{
		"tex_var": "texture_4",
		"scale_var": "texture_scale_4",
		"sprite_var": "grass_sprite_tex_4",
		"palette_colors": ["tex4_color_1", "tex4_color_2", "tex4_color_3", "tex4_color_4"],
		"use_grass_var": "tex4_has_grass",
	},
	{
		"tex_var": "texture_5",
		"scale_var": "texture_scale_5",
		"sprite_var": "grass_sprite_tex_5",
		"palette_colors": ["tex5_color_1", "tex5_color_2", "tex5_color_3", "tex5_color_4"],
		"use_grass_var": "tex5_has_grass",
	},
	{
		"tex_var": "texture_6",
		"scale_var": "texture_scale_6",
		"sprite_var": "grass_sprite_tex_6",
		"palette_colors": ["tex6_color_1", "tex6_color_2", "tex6_color_3", "tex6_color_4"],
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
	set_custom_minimum_size(Vector2(195, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	while terrain.texture_names.size() < 16:
		terrain.texture_names.append("Texture " + str(terrain.texture_names.size() + 1))
	
	var vbox := VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(150, 0))
	
	for i in range(15):
		# Texture name LineEdit
		var name_edit := LineEdit.new()
		name_edit.text = terrain.texture_names[i]
		name_edit.placeholder_text = "Texture " + str(i + 1)
		name_edit.set_custom_minimum_size(Vector2(150, 25))
		name_edit.text_submitted.connect(func(new_name):
			terrain.texture_names[i] = new_name
			plugin.ui.tool_attributes.show_tool_attributes(plugin.active_tool)
		)
		vbox.add_child(name_edit, true)
		
		# Ground texture picker
		var tex_var : Texture2D = terrain.get(VAR_NAMES[i].get("tex_var"))
		if tex_var != null and tex_var.get_class() == "Texture2D":
			tex_var = null
		
		var editor_r_picker := EditorResourcePicker.new()
		editor_r_picker.set_base_type("Texture2D")
		editor_r_picker.edited_resource = tex_var
		editor_r_picker.resource_changed.connect(func(resource): _on_texture_setting_changed(VAR_NAMES[i].get("tex_var"), resource))
		editor_r_picker.set_custom_minimum_size(Vector2(100, 25))
		vbox.add_child(editor_r_picker, true)
		
		# Scale slider
		if VAR_NAMES[i].has("scale_var"):
			var scale_var_name : String = VAR_NAMES[i].get("scale_var")
			var scale_value : float = terrain.get(scale_var_name) if terrain.get(scale_var_name) else 1.0
			
			var scale_hbox := HBoxContainer.new()
			scale_hbox.set_custom_minimum_size(Vector2(150, 20))
			
			var scale_label := Label.new()
			scale_label.text = "Scale:"
			scale_label.set_custom_minimum_size(Vector2(40, 20))
			scale_hbox.add_child(scale_label)
			
			var c_cont_2 := CenterContainer.new()
			var scale_slider := HSlider.new()
			scale_slider.min_value = 0.1
			scale_slider.max_value = 40.0
			scale_slider.step = 0.1
			scale_slider.value = scale_value
			scale_slider.set_custom_minimum_size(Vector2(80, 20))
			scale_slider.value_changed.connect(func(val): _on_texture_setting_changed(scale_var_name, val))
			scale_slider.drag_ended.connect(func(val): _on_slider_drag_ended(val))
			c_cont_2.add_child(scale_slider, true)
			scale_hbox.add_child(c_cont_2, true)
			
			var scale_value_label := Label.new()
			scale_value_label.text = str(scale_value)
			scale_value_label.set_custom_minimum_size(Vector2(25, 20))
			scale_slider.value_changed.connect(func(val): scale_value_label.text = str(snapped(val, 0.1)))
			scale_hbox.add_child(scale_value_label)
			
			vbox.add_child(scale_hbox, true)
		
		if i <= 5:
			# Grass sprite picker
			var sprite_var : Texture2D = terrain.get(VAR_NAMES[i].get("sprite_var"))
			if sprite_var != null and sprite_var.get_class() == "Texture2D":
				sprite_var = null
			
			var editor_r_picker2 := EditorResourcePicker.new()
			editor_r_picker2.set_base_type("Texture2D")
			editor_r_picker2.edited_resource = sprite_var
			editor_r_picker2.resource_changed.connect(func(resource): _on_texture_setting_changed(VAR_NAMES[i].get("sprite_var"), resource))
			editor_r_picker2.set_custom_minimum_size(Vector2(100, 25))
			vbox.add_child(editor_r_picker2, true)
			
			# 4 palette color pickers
			var palette_colors : Array = VAR_NAMES[i].get("palette_colors")
			for p_idx in range(4):
				var p_var_name : String = palette_colors[p_idx]
				var p_color : Color = terrain.get(p_var_name) if terrain.get(p_var_name) != null else Color.WHITE
				
				var p_hbox := HBoxContainer.new()
				p_hbox.set_custom_minimum_size(Vector2(150, 25))
				
				var p_label := Label.new()
				p_label.text = "Color " + str(p_idx + 1) + ":"
				p_label.set_custom_minimum_size(Vector2(50, 20))
				p_hbox.add_child(p_label, true)
				
				var p_btn := ColorPickerButton.new()
				p_btn.color = p_color
				p_btn.color_changed.connect(func(color, vn = p_var_name): _on_texture_setting_changed(vn, color))
				p_btn.set_custom_minimum_size(Vector2(95, 25))
				p_hbox.add_child(p_btn, true)
				
				vbox.add_child(p_hbox, true)
		
		if i >= 1 and i <= 5:
			# Has grass checkbox
			var use_grass_var : bool = terrain.get(VAR_NAMES[i].get("use_grass_var"))
			var checkbox := CheckBox.new()
			checkbox.text = "Has grass"
			checkbox.set_flat(true)
			checkbox.button_pressed = use_grass_var
			checkbox.toggled.connect(func(pressed): _on_texture_setting_changed(VAR_NAMES[i].get("use_grass_var"), pressed))
			checkbox.set_custom_minimum_size(Vector2(25, 15))
			
			var c_cont_3 := CenterContainer.new()
			c_cont_3.set_custom_minimum_size(Vector2(25, 25))
			c_cont_3.add_child(checkbox, true)
			vbox.add_child(c_cont_3, true)
		
		vbox.add_child(HSeparator.new())
	
	var m_cont := MarginContainer.new()
	m_cont.add_theme_constant_override("margin_bottom", 7)
	var export_button := MarchingSquaresTexturePresetExporter.new()
	export_button.current_terrain_node = terrain
	m_cont.add_child(export_button, true)
	vbox.add_child(m_cont, true)
	
	add_child(vbox, true)
	

func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	emit_signal("texture_setting_changed", p_setting_name, p_value)


func _on_slider_drag_ended(ended: bool) -> void:
	for chunk: MarchingSquaresTerrainChunk in plugin.current_terrain_node.chunks.values():
		chunk.grass_planter.regenerate_all_cells()
