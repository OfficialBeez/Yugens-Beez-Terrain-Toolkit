@tool
extends ScrollContainer
class_name MarchingSquaresTextureSettings


signal texture_setting_changed(setting: String, value: Variant)

var plugin : MarchingSquaresTerrainPlugin
var vp_tex_names : MarchingSquaresTextureNames = preload("uid://dd7fens03aosa")

const MAX_TEXTURE_SLOTS := 256

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
	# Slightly wider by default so controls on the right edge are easier to click.
	set_custom_minimum_size(Vector2(260, 0))
	add_theme_constant_override("separation", 5)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _ensure_terrain_arrays(terrain: Object) -> bool:
	if terrain == null:
		return false
	
	# Avoid calling into the terrain script from the editor UI.
	# In editor reload/order edge-cases the selected node can be a plain Node3D or a placeholder script,
	# which makes method calls like _ensure_texture_slots() fail even though exported properties exist.
	var slots_var := terrain.get("texture_slots")
	if not (slots_var is Array):
		push_error("[MST] Selected node doesn't expose texture_slots. Select the MarchingSquaresTerrain node (with script attached).")
		return false
	if slots_var.size() != MAX_TEXTURE_SLOTS:
		slots_var.resize(MAX_TEXTURE_SLOTS)
	for i in range(MAX_TEXTURE_SLOTS):
		if slots_var[i] == null:
			slots_var[i] = MarchingSquaresTextureSlot.new()
		# Default any missing 'active' to true (older saves won't have it).
		if slots_var[i] != null and slots_var[i].get("active") == null:
			slots_var[i].active = true
		# Default slot->base-texture mapping for older slot resources.
		if slots_var[i] != null and slots_var[i].get("terrain_texture_index") == null:
			if i == 15:
				slots_var[i].terrain_texture_index = 15
			elif i < 15:
				slots_var[i].terrain_texture_index = i
			else:
				slots_var[i].terrain_texture_index = 0
		elif slots_var[i] != null:
			slots_var[i].terrain_texture_index = clampi(int(slots_var[i].terrain_texture_index), 0, 15)
		# Default grass fields for older slot resources.
		if slots_var[i] != null and slots_var[i].get("has_grass") == null:
			slots_var[i].has_grass = (i == 0)
		if slots_var[i] != null and slots_var[i].get("grass_texture") == null:
			slots_var[i].grass_texture = null
	
	# Palette-per-slot arrays (all optional, but expected for the UI).
	var slot_color_indices := terrain.get("slot_color_indices")
	if slot_color_indices is Array:
		if slot_color_indices.size() != MAX_TEXTURE_SLOTS:
			slot_color_indices.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_color_indices[i] == null:
				slot_color_indices[i] = []
	
	var slot_blend_modes := terrain.get("slot_blend_modes")
	if slot_blend_modes is Array:
		if slot_blend_modes.size() != MAX_TEXTURE_SLOTS:
			slot_blend_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_blend_modes[i] == null:
				slot_blend_modes[i] = 3
	
	var slot_has_outline := terrain.get("slot_has_outline")
	if slot_has_outline is Array:
		if slot_has_outline.size() != MAX_TEXTURE_SLOTS:
			slot_has_outline.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_has_outline[i] == null:
				slot_has_outline[i] = false
	
	var slot_outline_modes := terrain.get("slot_outline_modes")
	if slot_outline_modes is Array:
		if slot_outline_modes.size() != MAX_TEXTURE_SLOTS:
			slot_outline_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_outline_modes[i] == null:
				slot_outline_modes[i] = 0
			slot_outline_modes[i] = clampi(int(slot_outline_modes[i]), 0, 1)
	
	var slot_outline_widths := terrain.get("slot_outline_widths")
	if slot_outline_widths is Array:
		if slot_outline_widths.size() != MAX_TEXTURE_SLOTS:
			slot_outline_widths.resize(MAX_TEXTURE_SLOTS)
		var default_w := 6.0
		var ow := terrain.get("outline_width")
		if ow is float or ow is int:
			default_w = float(ow)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_outline_widths[i] == null:
				slot_outline_widths[i] = default_w
			slot_outline_widths[i] = clampf(float(slot_outline_widths[i]), 0.25, 32.0)
	
	var slot_wet_enabled := terrain.get("slot_wet_enabled")
	if slot_wet_enabled is Array:
		if slot_wet_enabled.size() != MAX_TEXTURE_SLOTS:
			slot_wet_enabled.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_enabled[i] == null:
				slot_wet_enabled[i] = false

	var slot_wet_modes := terrain.get("slot_wet_modes")
	if slot_wet_modes is Array:
		if slot_wet_modes.size() != MAX_TEXTURE_SLOTS:
			slot_wet_modes.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_wet_modes[i] == null:
				slot_wet_modes[i] = 0
			slot_wet_modes[i] = clampi(int(slot_wet_modes[i]), 0, 1)

	var slot_roughnesses := terrain.get("slot_roughnesses")
	if slot_roughnesses is Array:
		if slot_roughnesses.size() != MAX_TEXTURE_SLOTS:
			slot_roughnesses.resize(MAX_TEXTURE_SLOTS)
		for i in range(MAX_TEXTURE_SLOTS):
			if slot_roughnesses[i] == null:
				slot_roughnesses[i] = 1.0
			slot_roughnesses[i] = clampf(float(slot_roughnesses[i]), 0.0, 1.0)
	
	return true


func add_texture_settings() -> void:
	for child in get_children():
		child.queue_free()
	
	var terrain := plugin.current_terrain_node
	if terrain == null:
		return
	
	# Ensure slot/palette arrays are initialized before we build UI.
	if not _ensure_terrain_arrays(terrain):
		return
	
	var vbox := VBoxContainer.new()
	# Wider panel so palette weight sliders fit without being clipped.
	vbox.set_custom_minimum_size(Vector2(300, 0))
	
	var preset := terrain.current_texture_preset
	var names : Array[String] = []
	if preset and preset.new_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
		names = preset.new_tex_names.get("texture_names")
	elif vp_tex_names:
		MarchingSquaresTerrainPlugin._ensure_texture_names_resource(vp_tex_names)
		names = vp_tex_names.get("texture_names")
	
	var visible_count := clampi(int(terrain.visible_texture_slot_count), 1, 256)
	
	for i in range(visible_count):
		var slot_idx := i
		var slot_obj := terrain.texture_slots[slot_idx] if slot_idx < terrain.texture_slots.size() else null
		# Hide inactive slots (except reserved ones).
		if slot_idx != 0 and slot_idx != 15 and slot_obj != null and bool(slot_obj.get("active")) == false:
			continue
		
		# Slot display name (saved in preset.new_tex_names when a preset is active)
		var name_row := HBoxContainer.new()
		# Negative separation makes the X "push into" the name field visually.
		name_row.add_theme_constant_override("separation", -16)
		
		var name_edit := LineEdit.new()
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.text = names[slot_idx] if slot_idx < names.size() else ("Texture " + str(slot_idx + 1))
		name_edit.placeholder_text = "Texture %d" % (slot_idx + 1)
		name_edit.set_custom_minimum_size(Vector2(220, 25))
		name_edit.tooltip_text = "Rename this texture slot (saved in the active preset)"
		
		var remove_btn := Button.new()
		remove_btn.text = "X"
		remove_btn.flat = true
		remove_btn.focus_mode = Control.FOCUS_NONE
		remove_btn.set_custom_minimum_size(Vector2(22, 25))
		remove_btn.tooltip_text = "Deactivate (clear) this texture slot"
		
		# Texture 1 and Void are reserved.
		if slot_idx == 0:
			remove_btn.disabled = true
			remove_btn.tooltip_text = "Texture 1 is reserved"
		if slot_idx == 15:
			name_edit.text = "Void"
			name_edit.editable = false
			name_edit.tooltip_text = "Void (reserved)"
			remove_btn.disabled = true
			remove_btn.tooltip_text = "Void is reserved"
		
		# Only persist names into a real preset resource.
		var persist_name := func(p_idx: int):
			if preset == null or preset.new_tex_names == null:
				return
			MarchingSquaresTerrainPlugin._ensure_texture_names_resource(preset.new_tex_names)
			var n := preset.new_tex_names.get("texture_names")
			if n is Array and p_idx < n.size():
				n[p_idx] = name_edit.text
				preset.new_tex_names.set("texture_names", n)
			# Refresh dropdowns (Material + Default Wall)
			if plugin and plugin.ui and plugin.ui.tool_attributes:
				plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
			if preset.resource_path != null and not str(preset.resource_path).is_empty():
				ResourceSaver.save(preset)
		
		var deactivate_slot := func(p_idx: int):
			if terrain == null:
				return
			if p_idx == 15:
				return
			
			if not _ensure_terrain_arrays(terrain):
				return
			
			if terrain.texture_slots[p_idx] == null:
				terrain.texture_slots[p_idx] = MarchingSquaresTextureSlot.new()
			terrain.texture_slots[p_idx].active = false
			terrain.texture_slots[p_idx].texture = null
			terrain.texture_slots[p_idx].scale = 1.0
			terrain.texture_slots[p_idx].terrain_texture_index = (p_idx if p_idx < 15 else 0)
			
			# Reset per-slot palette/outline settings too (so the slot truly clears).
			if p_idx >= 0 and p_idx < terrain.slot_color_indices.size():
				terrain.slot_color_indices[p_idx] = []
			if p_idx >= 0 and p_idx < terrain.slot_blend_modes.size():
				terrain.slot_blend_modes[p_idx] = 3
			if p_idx >= 0 and p_idx < terrain.slot_has_outline.size():
				terrain.slot_has_outline[p_idx] = false
			if p_idx >= 0 and p_idx < terrain.slot_outline_modes.size():
				terrain.slot_outline_modes[p_idx] = 0
			if p_idx >= 0 and p_idx < terrain.slot_outline_widths.size():
				var ow := terrain.get("outline_width")
				terrain.slot_outline_widths[p_idx] = float(ow) if (ow is float or ow is int) else 6.0
			if terrain.get("slot_wet_enabled") is Array and p_idx >= 0 and p_idx < terrain.slot_wet_enabled.size():
				terrain.slot_wet_enabled[p_idx] = false
			if terrain.get("slot_wet_modes") is Array and p_idx >= 0 and p_idx < terrain.slot_wet_modes.size():
				terrain.slot_wet_modes[p_idx] = 0
			if terrain.get("slot_roughnesses") is Array and p_idx >= 0 and p_idx < terrain.slot_roughnesses.size():
				terrain.slot_roughnesses[p_idx] = 1.0
			
			# Keep legacy properties in sync for slots 1..15 so presets save correctly.
			if p_idx >= 0 and p_idx < 15:
				terrain.set("texture_%d" % (p_idx + 1), null)
				terrain.set("texture_scale_%d" % (p_idx + 1), 1.0)
				# Clear legacy grass toggle for slots 2..6 (indices 1..5)
				if p_idx >= 1 and p_idx <= 5:
					terrain.set("tex%d_has_grass" % (p_idx + 1), false)
			else:
				# Non-base slots do not require rebuilding the terrain Texture2DArray anymore.
				terrain._push_tex_scales()
			
			# Push palette lookup textures to materials.
			terrain._rebuild_palette_uniforms()
			
			if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
				terrain.save_to_preset()
			
			# Refresh UI + dropdowns.
			if plugin and plugin.ui and plugin.ui.tool_attributes:
				plugin.ui.tool_attributes.show_tool_attributes(plugin.ui.active_tool)
			call_deferred("add_texture_settings")
		
		name_edit.text_submitted.connect(func(_t, p_idx := slot_idx): persist_name.call(p_idx))
		name_edit.focus_exited.connect(func(p_idx := slot_idx): persist_name.call(p_idx))
		remove_btn.pressed.connect(func(p_idx := slot_idx): deactivate_slot.call(p_idx))
		
		name_row.add_child(name_edit, true)
		name_row.add_child(remove_btn, false)
		vbox.add_child(name_row, true)
		
		# Terrain texture picker (slot-based)
		var slot := terrain.texture_slots[i]
		var tex_var : Texture2D = slot.texture if slot != null else null
		if tex_var != null and not (tex_var is Texture2D):
			tex_var = null
		
		# For the reserved Void slot, don't allow editing the texture.
		if slot_idx == 15:
			var void_tex_label := Label.new()
			void_tex_label.text = "(Void texture is reserved)"
			vbox.add_child(void_tex_label, true)
		elif slot_idx < 15:
			# Base textures 1..15 are edited here.
			var editor_r_picker := EditorResourcePicker.new()
			editor_r_picker.set_base_type("Texture2D")
			editor_r_picker.edited_resource = tex_var
			editor_r_picker.resource_changed.connect(func(resource, p_idx := slot_idx):
				if resource != null and not (resource is Texture2D):
					resource = null
				if not _ensure_terrain_arrays(terrain):
					return
				if terrain.texture_slots[p_idx] == null:
					terrain.texture_slots[p_idx] = MarchingSquaresTextureSlot.new()
				terrain.texture_slots[p_idx].texture = resource
				# Keep base mapping identity.
				terrain.texture_slots[p_idx].terrain_texture_index = p_idx
				
				# Keep legacy properties in sync for slots 1..15 so presets save correctly.
				terrain.set("texture_%d" % (p_idx + 1), resource)
				
				terrain.rebuild_texture_array()
				
				if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
					terrain.save_to_preset()
			)
			editor_r_picker.set_custom_minimum_size(Vector2(100, 25))
			vbox.add_child(editor_r_picker, true)
		else:
			# For slots 16..255, select which base terrain texture to sample.
			var map_hbox := HBoxContainer.new()
			map_hbox.set_custom_minimum_size(Vector2(150, 20))
			var map_label := Label.new()
			map_label.text = "Terrain Texture:"
			map_label.set_custom_minimum_size(Vector2(95, 20))
			map_hbox.add_child(map_label)
			var map_opt := OptionButton.new()
			map_opt.set_custom_minimum_size(Vector2(140, 25))
			for ti in range(15):
				var nm := (names[ti] if names.size() > ti else ("Texture %d" % (ti + 1)))
				map_opt.add_item("%d: %s" % [ti + 1, nm], ti)
			map_opt.add_item("VOID", 15)
			var cur_idx := int(slot.terrain_texture_index) if slot != null and slot.get("terrain_texture_index") != null else 0
			map_opt.select(map_opt.get_item_index(clampi(cur_idx, 0, 15)))
			map_opt.item_selected.connect(func(id, p_idx := slot_idx):
				if not _ensure_terrain_arrays(terrain):
					return
				if terrain.texture_slots[p_idx] == null:
					terrain.texture_slots[p_idx] = MarchingSquaresTextureSlot.new()
				terrain.texture_slots[p_idx].terrain_texture_index = clampi(int(id), 0, 15)
				# Update shader lookup textures.
				terrain._rebuild_palette_uniforms()
				if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
					terrain.save_to_preset()
			)
			map_hbox.add_child(map_opt, true)
			vbox.add_child(map_hbox, true)
		
		# Grass settings are built next to outline settings in _build_palette_ui() for each slot.
		
		# Scale slider (slot-based)
		var scale_value : float = float(slot.scale) if slot != null else 1.0
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
		scale_slider.value_changed.connect(func(val, p_idx := slot_idx):
			if not _ensure_terrain_arrays(terrain):
				return
			if terrain.texture_slots[p_idx] == null:
				terrain.texture_slots[p_idx] = MarchingSquaresTextureSlot.new()
			terrain.texture_slots[p_idx].scale = float(val)
			
			# Keep legacy properties in sync for slots 1..15 so presets save correctly.
			if p_idx >= 0 and p_idx < 15:
				terrain.set("texture_scale_%d" % (p_idx + 1), float(val))
			else:
				terrain._push_tex_scales()
			
			if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
				terrain.save_to_preset()
		)
		scale_hbox.add_child(c_cont_2, true)
		
		var scale_value_label := Label.new()
		scale_value_label.text = str(scale_value)
		scale_value_label.set_custom_minimum_size(Vector2(25, 20))
		scale_slider.value_changed.connect(func(val): scale_value_label.text = str(snapped(val, 0.1)))
		scale_hbox.add_child(scale_value_label)
		
		vbox.add_child(scale_hbox, true)
		
		# Palette UI for ALL visible slots
		_build_palette_ui(vbox, terrain, i)
		
		vbox.add_child(HSeparator.new())
	
	# Reveal more slots without rendering all 256 controls by default.
	var add_button := Button.new()
	add_button.text = "+ Add Texture"
	add_button.pressed.connect(func():
		if not _ensure_terrain_arrays(terrain):
			return
		
		# Prefer re-enabling the first inactive slot that is already in-range.
		var made_active := false
		for idx in range(clampi(int(terrain.visible_texture_slot_count), 1, 256)):
			if idx == 0 or idx == 15:
				continue
			var s := terrain.texture_slots[idx]
			if s != null and bool(s.get("active")) == false:
				s.active = true
				made_active = true
				break
		
		# Otherwise, extend the visible range by one.
		if not made_active:
			terrain.visible_texture_slot_count = mini(int(terrain.visible_texture_slot_count) + 1, 256)
		
		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
		call_deferred("add_texture_settings")
	)
	vbox.add_child(add_button, true)
	
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
		terrain._rebuild_palette_uniforms()
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

	# Grass settings (slot-based)
	var slot_res := terrain.texture_slots[slot]
	var has_grass_var := bool(slot_res.has_grass) if slot_res != null else (slot == 0)
	var grass_cb := CheckBox.new()
	grass_cb.text = "Has Grass"
	grass_cb.set_flat(true)
	grass_cb.button_pressed = has_grass_var
	grass_cb.set_custom_minimum_size(Vector2(25, 15))

	var grass_center := CenterContainer.new()
	grass_center.set_custom_minimum_size(Vector2(25, 25))
	grass_center.add_child(grass_cb, true)
	vbox.add_child(grass_center, true)

	var grass_picker := EditorResourcePicker.new()
	grass_picker.set_base_type("Texture2D")
	var grass_tex_var : Texture2D = slot_res.grass_texture if slot_res != null else null
	if grass_tex_var != null and not (grass_tex_var is Texture2D):
		grass_tex_var = null
	grass_picker.edited_resource = grass_tex_var
	grass_picker.visible = grass_cb.button_pressed
	grass_picker.set_custom_minimum_size(Vector2(100, 25))
	vbox.add_child(grass_picker, true)

	grass_cb.toggled.connect(func(pressed: bool, p_idx := slot):
		grass_picker.visible = pressed
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[p_idx] == null:
			terrain.texture_slots[p_idx] = MarchingSquaresTextureSlot.new()
		terrain.texture_slots[p_idx].has_grass = pressed

		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if p_idx >= 0 and p_idx < 6:
			terrain.set("tex%d_has_grass" % (p_idx + 1), pressed)
		else:
			if terrain.has_method("_request_grass_regen"):
				terrain._request_grass_regen()

		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)

	grass_picker.resource_changed.connect(func(resource, p_idx := slot):
		if resource != null and not (resource is Texture2D):
			resource = null
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.texture_slots[p_idx] == null:
			terrain.texture_slots[p_idx] = MarchingSquaresTextureSlot.new()
		terrain.texture_slots[p_idx].grass_texture = resource

		# Keep legacy properties in sync for slots 1..6 so presets/UI stay compatible.
		if p_idx >= 0 and p_idx < 6:
			terrain.set("grass_sprite_tex_%d" % (p_idx + 1), resource)
		else:
			if terrain.has_method("rebuild_grass_texture_array"):
				terrain.rebuild_grass_texture_array()
			if terrain.has_method("_request_grass_regen"):
				terrain._request_grass_regen()

		if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
			terrain.save_to_preset()
	)

	# Wetness (per slot)
	var wet_cb := CheckBox.new()
	wet_cb.text = "Wetness"
	wet_cb.set_flat(true)
	wet_cb.button_pressed = bool(terrain.slot_wet_enabled[slot]) if (terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size()) else false
	wet_cb.set_custom_minimum_size(Vector2(25, 15))
	var wet_center := CenterContainer.new()
	wet_center.set_custom_minimum_size(Vector2(25, 25))
	wet_center.add_child(wet_cb, true)
	vbox.add_child(wet_center, true)

	var wet_mode_hbox := HBoxContainer.new()
	wet_mode_hbox.set_custom_minimum_size(Vector2(150, 20))
	var wet_mode_label := Label.new()
	wet_mode_label.text = "Mode:"
	wet_mode_label.set_custom_minimum_size(Vector2(50, 20))
	wet_mode_hbox.add_child(wet_mode_label)
	var wet_mode_opt := OptionButton.new()
	wet_mode_opt.add_item("Wet", 0)
	wet_mode_opt.add_item("Glossy Puddles", 1)
	wet_mode_opt.selected = int(terrain.slot_wet_modes[slot]) if (terrain.get("slot_wet_modes") is Array and slot >= 0 and slot < terrain.slot_wet_modes.size()) else 0
	wet_mode_opt.set_custom_minimum_size(Vector2(95, 25))
	wet_mode_hbox.add_child(wet_mode_opt)
	wet_mode_hbox.visible = wet_cb.button_pressed
	vbox.add_child(wet_mode_hbox, true)

	var wetness_hbox := HBoxContainer.new()
	wetness_hbox.set_custom_minimum_size(Vector2(150, 20))
	var wetness_label := Label.new()
	wetness_label.text = "Wetness:"
	wetness_label.set_custom_minimum_size(Vector2(70, 20))
	wetness_hbox.add_child(wetness_label)
	var wetness_slider := EditorSpinSlider.new()
	wetness_slider.set_flat(true)
	wetness_slider.set_min(0.0)
	wetness_slider.set_max(1.0)
	wetness_slider.set_step(0.05)
	# Stored as roughness: roughness = 1 - wetness.
	if terrain.get("slot_roughnesses") is Array and slot >= 0 and slot < terrain.slot_roughnesses.size():
		wetness_slider.set_value(1.0 - float(terrain.slot_roughnesses[slot]))
	else:
		wetness_slider.set_value(0.0)
	wetness_slider.set_custom_minimum_size(Vector2(95, 25))
	wetness_hbox.add_child(wetness_slider)
	wetness_hbox.visible = wet_cb.button_pressed
	vbox.add_child(wetness_hbox, true)

	wet_cb.toggled.connect(func(pressed: bool):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_enabled") is Array and slot >= 0 and slot < terrain.slot_wet_enabled.size():
			terrain.slot_wet_enabled[slot] = pressed
		wet_mode_hbox.visible = pressed
		wetness_hbox.visible = pressed
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	wet_mode_opt.item_selected.connect(func(idx: int):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_wet_modes") is Array and slot >= 0 and slot < terrain.slot_wet_modes.size():
			terrain.slot_wet_modes[slot] = idx
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	wetness_slider.value_changed.connect(func(value: float):
		if not _ensure_terrain_arrays(terrain):
			return
		if terrain.get("slot_roughnesses") is Array and slot >= 0 and slot < terrain.slot_roughnesses.size():
			terrain.slot_roughnesses[slot] = clampf(1.0 - float(value), 0.0, 1.0)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)

	# Outline settings
	terrain._ensure_outline_settings()
	var outline_cb := CheckBox.new()
	outline_cb.text = "Has Outline"
	outline_cb.set_flat(true)
	outline_cb.button_pressed = terrain.slot_has_outline[slot]
	outline_cb.set_custom_minimum_size(Vector2(25, 15))

	var outline_center := CenterContainer.new()
	outline_center.set_custom_minimum_size(Vector2(25, 25))
	outline_center.add_child(outline_cb, true)
	vbox.add_child(outline_center, true)

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
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	outline_mode_hbox.add_child(outline_mode_opt)
	outline_mode_hbox.visible = outline_cb.button_pressed
	vbox.add_child(outline_mode_hbox, true)

	var outline_width_hbox := HBoxContainer.new()
	outline_width_hbox.set_custom_minimum_size(Vector2(150, 20))
	var outline_width_label := Label.new()
	outline_width_label.text = "Width:"
	outline_width_label.set_custom_minimum_size(Vector2(50, 20))
	outline_width_hbox.add_child(outline_width_label)

	var outline_width_slider := EditorSpinSlider.new()
	outline_width_slider.set_flat(true)
	outline_width_slider.set_min(0.25)
	outline_width_slider.set_max(32.0)
	outline_width_slider.set_step(0.25)
	outline_width_slider.set_value(float(terrain.slot_outline_widths[slot]))
	outline_width_slider.value_changed.connect(func(value):
		terrain.slot_outline_widths[slot] = float(value)
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
	)
	outline_width_slider.set_custom_minimum_size(Vector2(95, 25))
	outline_width_hbox.add_child(outline_width_slider)
	outline_width_hbox.visible = outline_cb.button_pressed
	vbox.add_child(outline_width_hbox, true)

	outline_cb.toggled.connect(func(pressed):
		terrain.slot_has_outline[slot] = pressed
		terrain._rebuild_palette_uniforms()
		terrain.save_to_preset()
		outline_mode_hbox.visible = pressed
		outline_width_hbox.visible = pressed
	)


func _on_slider_drag_ended(ended: bool) -> void:
	if plugin == null or plugin.current_terrain_node == null:
		return
	for chunk: MarchingSquaresTerrainChunk in plugin.current_terrain_node.chunks.values():
		chunk.grass_planter.regenerate_all_cells()
