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
	set_custom_minimum_size(Vector2(195, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	
	var vbox := VBoxContainer.new()
	# Wider panel so palette weight sliders fit without being clipped.
	vbox.set_custom_minimum_size(Vector2(260, 0))
	var preset := terrain.current_texture_preset
	
	for i in range(15):
		var name_label := Label.new()
		name_label.text = preset.new_tex_names.texture_names[i] if preset and preset.new_tex_names and i < preset.new_tex_names.texture_names.size() else "Texture " + str(i + 1)
		name_label.set_custom_minimum_size(Vector2(150, 25))
		vbox.add_child(name_label, true)
		
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
		
		# Grass settings (put directly under the texture picker)
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
			scale_slider.set_custom_minimum_size(Vector2(80, 20))
			scale_slider.drag_ended.connect(func(val): _on_slider_drag_ended(val))
			c_cont_2.add_child(scale_slider, true)
			scale_slider.set_value_no_signal(scale_value)
			scale_slider.value_changed.connect(func(val): _on_texture_setting_changed(scale_var_name, val))
			scale_hbox.add_child(c_cont_2, true)
			
			var scale_value_label := Label.new()
			scale_value_label.text = str(scale_value)
			scale_value_label.set_custom_minimum_size(Vector2(25, 20))
			scale_slider.value_changed.connect(func(val): scale_value_label.text = str(snapped(val, 0.1)))
			scale_hbox.add_child(scale_value_label)
			
			vbox.add_child(scale_hbox, true)
		
		# Palette UI for ALL slots
		_build_palette_ui(vbox, terrain, i)
		
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


func _build_palette_ui(vbox: VBoxContainer, terrain: MarchingSquaresTerrain, slot: int) -> void:
	# Blend mode dropdown
	var blend_hbox := HBoxContainer.new()
	var blend_label := Label.new()
	blend_label.text = "Blend:"
	blend_label.set_custom_minimum_size(Vector2(50, 20))
	blend_hbox.add_child(blend_label)
	
	var blend_opt := OptionButton.new()
	blend_opt.add_item("Gradient", 0)
	blend_opt.add_item("Retro", 1)
	blend_opt.add_item("Dithered", 2)
	blend_opt.add_item("Stippled", 3)
	blend_opt.selected = terrain.slot_blend_modes[slot]
	blend_opt.set_custom_minimum_size(Vector2(95, 25))
	blend_opt.item_selected.connect(func(idx):
		terrain.slot_blend_modes[slot] = idx
		terrain._push_slot_blend_modes()
		terrain.save_to_preset()
	)
	blend_hbox.add_child(blend_opt)
	vbox.add_child(blend_hbox, true)
	
	# Color rows
	var slot_indices : Array = terrain.slot_color_indices[slot]
	for ci in range(slot_indices.size()):
		var palette_idx : int = slot_indices[ci]
		var c_hbox := HBoxContainer.new()
		c_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c_hbox.set_custom_minimum_size(Vector2(0, 25))
		
		var c_label := Label.new()
		c_label.text = "Color " + str(ci + 1) + ":"
		c_label.set_custom_minimum_size(Vector2(50, 20))
		c_hbox.add_child(c_label)
		
		var c_btn := ColorPickerButton.new()
		c_btn.color = terrain.palette_colors[palette_idx]
		c_btn.set_custom_minimum_size(Vector2(65, 25))
		c_btn.color_changed.connect(func(new_color, pidx = palette_idx):
			terrain.palette_colors[pidx] = new_color
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
		)
		c_hbox.add_child(c_btn)
		
		# Only show weights once a slot has 2+ colors
		if slot_indices.size() > 1:
			terrain._ensure_palette_weights()
			var w_label := Label.new()
			w_label.text = str(int(round(terrain.palette_weights[palette_idx]))) + "%"
			w_label.set_custom_minimum_size(Vector2(32, 20))
			c_hbox.add_child(w_label)
			
			var w_slider := HSlider.new()
			w_slider.min_value = 0.0
			w_slider.max_value = 100.0
			w_slider.step = 1.0
			w_slider.value = clampf(float(terrain.palette_weights[palette_idx]), 0.0, 100.0)
			w_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			w_slider.set_custom_minimum_size(Vector2(90, 25))
			w_slider.value_changed.connect(func(val, s = slot, pidx = palette_idx):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
					return
				terrain._ensure_palette_weights()
				var indices: Array = terrain.slot_color_indices[s]
				if indices.size() <= 1:
					return
				
				var new_v := clampf(float(val), 0.0, 100.0)
				terrain.palette_weights[pidx] = new_v
				w_label.text = str(int(round(new_v))) + "%"
				
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
				
				terrain._rebuild_palette_uniforms()
			)
			w_slider.drag_ended.connect(func(_ended):
				if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
					return
				terrain.save_to_preset()
				add_texture_settings()
			)
			c_hbox.add_child(w_slider)
		
		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.set_custom_minimum_size(Vector2(25, 25))
		remove_btn.pressed.connect(func(s = slot, ci_idx = ci):
			if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
				return
			terrain.slot_color_indices[s].remove_at(ci_idx)
			terrain._ensure_palette_weights()
			var indices: Array = terrain.slot_color_indices[s]
			if indices.size() > 0:
				var each := 100.0 / float(indices.size())
				for idx in indices:
					terrain.palette_weights[idx] = each
			terrain._rebuild_palette_uniforms()
			terrain.save_to_preset()
			add_texture_settings()
		)
		c_hbox.add_child(remove_btn)
		vbox.add_child(c_hbox, true)
	
	# Add Color button
	var add_btn := Button.new()
	add_btn.text = "+ Add Color"
	add_btn.set_custom_minimum_size(Vector2(150, 25))
	add_btn.pressed.connect(func(s = slot):
		if not is_instance_valid(terrain) or not is_instance_valid(plugin.current_terrain_node) or plugin.current_terrain_node != terrain:
			return
		# Find first unused palette index
		var used : Array = []
		for si in range(15):
			for idx in terrain.slot_color_indices[si]:
				used.append(idx)
		var next_idx := 0
		while next_idx < 128 and next_idx in used:
			next_idx += 1
		if next_idx >= 128:
			push_error("[MST] Palette is full (128 colors max)")
			return
		terrain.palette_colors[next_idx] = Color("647851ff")
		terrain.slot_color_indices[s].append(next_idx)
		terrain._ensure_palette_weights()
		var indices: Array = terrain.slot_color_indices[s]
		var each := 100.0 / float(max(indices.size(), 1))
		for idx in indices:
			terrain.palette_weights[idx] = each
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
		add_texture_settings()
	)
	vbox.add_child(add_btn, true)

	# Outline settings
	terrain._ensure_outline_settings()
	var outline_cb := CheckBox.new()
	outline_cb.text = "Has Outline"
	outline_cb.set_flat(true)
	outline_cb.button_pressed = terrain.slot_has_outline[slot]
	outline_cb.set_custom_minimum_size(Vector2(150, 18))
	vbox.add_child(outline_cb, true)

	var outline_mode_hbox := HBoxContainer.new()
	outline_mode_hbox.set_custom_minimum_size(Vector2(150, 20))
	var outline_mode_label := Label.new()
	outline_mode_label.text = "Mode:"
	outline_mode_label.set_custom_minimum_size(Vector2(50, 20))
	outline_mode_hbox.add_child(outline_mode_label)

	var outline_mode_opt := OptionButton.new()
	outline_mode_opt.add_item("Darken C1", 0)
	outline_mode_opt.add_item("Use Last", 1)
	outline_mode_opt.selected = terrain.slot_outline_modes[slot]
	outline_mode_opt.set_custom_minimum_size(Vector2(95, 25))
	outline_mode_opt.item_selected.connect(func(idx):
		terrain.slot_outline_modes[slot] = idx
		terrain._push_slot_outline_settings()
		terrain.save_to_preset()
	)
	outline_mode_hbox.add_child(outline_mode_opt)
	outline_mode_hbox.visible = outline_cb.button_pressed
	vbox.add_child(outline_mode_hbox, true)

	outline_cb.toggled.connect(func(pressed):
		terrain.slot_has_outline[slot] = pressed
		terrain._push_slot_outline_settings()
		terrain.save_to_preset()
		outline_mode_hbox.visible = pressed
	)


func _on_slider_drag_ended(ended: bool) -> void:
	if plugin == null or plugin.current_terrain_node == null:
		return
	for chunk: MarchingSquaresTerrainChunk in plugin.current_terrain_node.chunks.values():
		chunk.grass_planter.regenerate_all_cells()
