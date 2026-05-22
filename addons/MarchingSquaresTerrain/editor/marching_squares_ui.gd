@tool
extends Node
class_name MarchingSquaresUI


const TOOLBAR : Script = preload("uid://3d77dnetkeik")
const TOOL_ATTRIBUTES : Script = preload("uid://buxevb44hutjm")
const TEXTURE_SETTINGS : Script = preload("uid://blvx0jk6wxk5p")
const PRESET_SAVE_DEBOUNCE_SECONDS := 0.2

#region texture setting property maps
# Property names that map directly to terrain properties with same name
const TEXTURE_PROPERTIES := [
	"texture_1", "texture_2", "texture_3", "texture_4", "texture_5",
	"texture_6", "texture_7", "texture_8", "texture_9", "texture_10",
	"texture_11", "texture_12", "texture_13", "texture_14", "texture_15"
]

const GRASS_SPRITE_PROPERTIES := [
	"grass_sprite_tex_1", "grass_sprite_tex_2", "grass_sprite_tex_3",
	"grass_sprite_tex_4", "grass_sprite_tex_5", "grass_sprite_tex_6"
]



const HAS_GRASS_PROPERTIES := [
	"tex2_has_grass", "tex3_has_grass", "tex4_has_grass",
	"tex5_has_grass", "tex6_has_grass"
]

const TEXTURE_SCALE_PROPERTIES := [
	"texture_scale_1", "texture_scale_2", "texture_scale_3", "texture_scale_4", "texture_scale_5",
	"texture_scale_6", "texture_scale_7", "texture_scale_8", "texture_scale_9", "texture_scale_10",
	"texture_scale_11", "texture_scale_12", "texture_scale_13", "texture_scale_14", "texture_scale_15"
]
#endregion

var plugin : MarchingSquaresTerrainPlugin
var _terrain_snapshot : MarchingSquaresTexturePreset = null
var _preset_save_timer : Timer = null
var toolbar : TOOLBAR
var tool_attributes : TOOL_ATTRIBUTES
var texture_settings : TEXTURE_SETTINGS
var active_tool : int
var visible : bool = false


func _enter_tree() -> void:
	call_deferred("_deferred_enter_tree")


func _deferred_enter_tree() -> void:
	if not EngineWrapper.instance.is_editor():
		push_error("Attempt to load during runtime (NOT SUPPORTED IN CURRENT BUILD)")
		return
	
	if not plugin:
		push_error("Plugin not ready")
		return
	
	toolbar = TOOLBAR.new()
	toolbar.tool_changed.connect(_on_tool_changed)
	toolbar.hide()
	
	tool_attributes = TOOL_ATTRIBUTES.new()
	tool_attributes.setting_changed.connect(_on_setting_changed)
	tool_attributes.terrain_setting_changed.connect(_on_terrain_setting_changed)
	tool_attributes.plugin = plugin
	tool_attributes.attribute_list = MarchingSquaresToolAttributesList.new()
	tool_attributes.hide()
	
	texture_settings = TEXTURE_SETTINGS.new()
	texture_settings.texture_setting_changed.connect(_on_texture_setting_changed)
	texture_settings.plugin = plugin
	texture_settings.hide()

	_preset_save_timer = Timer.new()
	_preset_save_timer.one_shot = true
	# Debounce rapid UI updates (sliders/color dragging) into a single preset disk save.
	_preset_save_timer.wait_time = PRESET_SAVE_DEBOUNCE_SECONDS
	_preset_save_timer.timeout.connect(_flush_preset_save)
	add_child(_preset_save_timer)
	
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, toolbar)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, tool_attributes)
	plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, texture_settings)


func _exit_tree() -> void:
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, toolbar)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, tool_attributes)
	plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_RIGHT, texture_settings)
	
	toolbar.queue_free()
	tool_attributes.queue_free()
	texture_settings.queue_free()


func set_visible(is_visible: bool) -> void:
	visible = is_visible
	toolbar.set_visible(is_visible)
	tool_attributes.set_visible(is_visible)
	texture_settings.set_visible(is_visible)
	
	if is_visible:
		await get_tree().create_timer(.01).timeout
		
		if active_tool == null:
			active_tool = 0
		
		if toolbar and toolbar.tool_buttons.has(active_tool):
			toolbar.tool_buttons[active_tool].set_pressed(true)
		
		tool_attributes.show()
		_on_tool_changed(active_tool)

#region on-signal functions

func _on_tool_changed(tool_index: int) -> void:
	active_tool = tool_index
	
	if tool_index == 5: # Vertex Painting
		tool_attributes.attribute_list = MarchingSquaresToolAttributesList.new()
		texture_settings.show()
		texture_settings.add_texture_settings()
	else:
		texture_settings.hide()
	
	if tool_index == 3: # Bridge tool
		plugin.falloff = false
		plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", false)
	
	plugin.active_tool = tool_index
	plugin.mode = tool_index
	plugin.vertex_color_idx = 0 # Set to the first material on start # Working around a UI sync bug. #TODO: This is temp workaround - Possible refactor.
	tool_attributes.show_tool_attributes(active_tool)


func _on_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	match p_setting_name:
		"brush_type":
			if p_value is int:
				plugin.current_brush_index = p_value
				plugin.BRUSH_RADIUS_VISUAL = plugin.BrushMode.get(str(p_value))
				plugin.BRUSH_RADIUS_MATERIAL = plugin.BrushMat.get(str(p_value))
				plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", plugin.falloff)
		"size":
			if p_value is float or p_value is int:
				plugin.brush_size = float(p_value)
		"ease_value":
			if p_value is float:
				plugin.ease_value = p_value
		"flatten":
			if p_value is bool:
				plugin.flatten = p_value
		"falloff":
			if p_value is bool:
				plugin.falloff = p_value
				if plugin.BRUSH_RADIUS_MATERIAL:
					plugin.BRUSH_RADIUS_MATERIAL.set_shader_parameter("falloff_visible", p_value)
		"strength":
			if p_value is float or p_value is int:
				plugin.strength = float(p_value)
		"height":
			if p_value is float or p_value is int:
				plugin.height = float(p_value)
		"mask_mode": # Grass mask mode
			if p_value is bool:
				plugin.should_mask_grass = p_value
		"material": # Vertex paint setting
			if p_value is int:
				plugin.vertex_color_idx = p_value
		"texture_name":
			if p_value is String and p_value != "":
				var idx := plugin.vertex_color_idx
				if idx == 0 or idx == 15:
					return
				var terrain := plugin.current_terrain_node
				if terrain.texture_names.size() > idx:
					terrain.texture_names[idx] = p_value
					if terrain.current_texture_preset != null and not terrain.current_texture_preset.resource_path.is_empty():
						terrain.save_to_preset()
					elif _terrain_snapshot != null:
						terrain.save_to_preset_target(_terrain_snapshot)
		"texture_preset":
			if plugin.current_terrain_node.current_texture_preset == null:
				_terrain_snapshot = MarchingSquaresTexturePreset.new()
				_terrain_snapshot.new_textures = MarchingSquaresTextureList.new()
				_terrain_snapshot.new_textures.grass_colors.resize(128)
				plugin.current_terrain_node.save_to_preset_target(_terrain_snapshot)
			
			if p_value is MarchingSquaresTexturePreset:
				plugin.current_texture_preset = p_value
			else:
				if _terrain_snapshot != null:
					plugin.current_texture_preset = _terrain_snapshot
				else:
					plugin.current_texture_preset = null
			
			tool_attributes.show_tool_attributes.call_deferred(active_tool)
		"quick_paint_selection":
					if p_value is MarchingSquaresQuickPaint:
						plugin.current_quick_paint = p_value
					else:
						plugin.current_quick_paint = null
		"paint_walls":
			if p_value is bool:
				plugin.paint_walls_mode = p_value


func _apply_preset_to_terrain(preset: MarchingSquaresTexturePreset, terrain: MarchingSquaresTerrain) -> void:
	var t := preset.new_textures

	# Terrain textures
	terrain.texture_1  = t.terrain_textures[0]
	terrain.texture_2  = t.terrain_textures[1]
	terrain.texture_3  = t.terrain_textures[2]
	terrain.texture_4  = t.terrain_textures[3]
	terrain.texture_5  = t.terrain_textures[4]
	terrain.texture_6  = t.terrain_textures[5]
	terrain.texture_7  = t.terrain_textures[6]
	terrain.texture_8  = t.terrain_textures[7]
	terrain.texture_9  = t.terrain_textures[8]
	terrain.texture_10 = t.terrain_textures[9]
	terrain.texture_11 = t.terrain_textures[10]
	terrain.texture_12 = t.terrain_textures[11]
	terrain.texture_13 = t.terrain_textures[12]
	terrain.texture_14 = t.terrain_textures[13]
	terrain.texture_15 = t.terrain_textures[14]
	# Texture scales
	terrain.texture_scale_1  = t.texture_scales[0]
	terrain.texture_scale_2  = t.texture_scales[1]
	terrain.texture_scale_3  = t.texture_scales[2]
	terrain.texture_scale_4  = t.texture_scales[3]
	terrain.texture_scale_5  = t.texture_scales[4]
	terrain.texture_scale_6  = t.texture_scales[5]
	terrain.texture_scale_7  = t.texture_scales[6]
	terrain.texture_scale_8  = t.texture_scales[7]
	terrain.texture_scale_9  = t.texture_scales[8]
	terrain.texture_scale_10 = t.texture_scales[9]
	terrain.texture_scale_11 = t.texture_scales[10]
	terrain.texture_scale_12 = t.texture_scales[11]
	terrain.texture_scale_13 = t.texture_scales[12]
	terrain.texture_scale_14 = t.texture_scales[13]
	terrain.texture_scale_15 = t.texture_scales[14]
	# Grass sprites
	terrain.grass_sprite_tex_1 = t.grass_sprites[0]
	terrain.grass_sprite_tex_2 = t.grass_sprites[1]
	terrain.grass_sprite_tex_3 = t.grass_sprites[2]
	terrain.grass_sprite_tex_4 = t.grass_sprites[3]
	terrain.grass_sprite_tex_5 = t.grass_sprites[4]
	terrain.grass_sprite_tex_6 = t.grass_sprites[5]
	# Palette system
	terrain.load_from_preset(preset)
	# Has grass flags
	terrain.tex2_has_grass = t.has_grass[0]
	terrain.tex3_has_grass = t.has_grass[1]
	terrain.tex4_has_grass = t.has_grass[2]
	terrain.tex5_has_grass = t.has_grass[3]
	terrain.tex6_has_grass = t.has_grass[4]
	# Texture names
	if preset.new_tex_names and preset.new_tex_names.texture_names.size() > 0:
		terrain.texture_names = preset.new_tex_names.texture_names.duplicate()		


func _on_terrain_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	var terrain := plugin.current_terrain_node
	match p_setting_name:
		"dimensions":
			if p_value is Vector3i:
				terrain.dimensions = p_value
		"cell_size":
			if p_value is Vector2:
				terrain.cell_size = p_value
		"collision_depth":
			if p_value is float:
				terrain.collision_depth = p_value
		"blend_mode":
			if p_value is int:
				terrain.blend_mode = p_value
		"wall_threshold":
			if p_value is float:
				terrain.wall_threshold = p_value
		"noise_hmap":
			if p_value is Noise or p_value == null:
				terrain.noise_hmap = p_value
		"wall_texture":
			if p_value is Texture2D or p_value == null:
				terrain.wall_texture = p_value
		"wall_color":
			if p_value is Color:
				terrain.wall_color = p_value
		"animation_fps":
			if p_value is int or p_value is float:
				terrain.animation_fps = p_value
		"grass_subdivisions":
			if p_value is int or p_value is float:
				terrain.grass_subdivisions = p_value
		"grass_size":
			if p_value is Vector2:
				terrain.grass_size = p_value
		"grass_size_variation":
			if p_value is float or p_value is int:
				terrain.grass_size_variation = float(p_value)
		"grass_size_variation_commit":
			if p_value is bool and p_value:
				terrain.rebuild_grass_now = true
		"use_flat_normals":
			if p_value is bool:
				terrain.use_flat_normals = p_value
		"use_cell_shading":
			if p_value is bool:
				terrain.use_cell_shading = p_value
		"ridge_threshold":
			if p_value is float:
				terrain.ridge_threshold = p_value
		"ledge_threshold":
			if p_value is float:
				terrain.ledge_threshold = p_value
		"use_ridge_texture":
			if p_value is bool:
				terrain.use_ridge_texture = p_value
		"use_ledge_texture":
			if p_value is bool:
				terrain.use_ledge_texture = p_value
		"default_wall_texture":
			if p_value is int:
				terrain.default_wall_texture = p_value
		"extra_collision_layer":
			if p_value is int:
				# +1 because collision layers don't start from 0 like indexed items
				# +8 because the selectable collision layers range from 9 to 32
				terrain.extra_collision_layer = p_value + 9
		"global_noise_strength":
			if p_value is float:
				terrain.global_noise_strength = p_value
		"global_noise_scale":
			if p_value is float:
				terrain.global_noise_scale = p_value
		"wind_mode":
			if p_value is int:
				terrain.wind_mode = p_value
		"wind_intensity":
			if p_value is float:
				terrain.wind_intensity = p_value
		"wind_tip_color":
			if p_value is Color:
				terrain.wind_tip_color = p_value
		"wind_tip_strength":
			if p_value is float:
				terrain.wind_tip_strength = p_value


func _on_texture_setting_changed(p_setting_name: String, p_value: Variant) -> void:
	var terrain := plugin.current_terrain_node
	if not terrain:
		push_error("No current terrain node to apply texture settings to")
		return
	
	# Texture properties (Texture2D or null)
	if p_setting_name in TEXTURE_PROPERTIES:
		if p_value is Texture2D or p_value == null:
			terrain.set(p_setting_name, p_value)
	# Grass sprite properties (CompressedTexture2D or null)
	elif p_setting_name in GRASS_SPRITE_PROPERTIES:
		if p_value is CompressedTexture2D or p_value == null:
			terrain.set(p_setting_name, p_value)
	# Has grass flags (bool)
	elif p_setting_name in HAS_GRASS_PROPERTIES:
		if p_value is bool:
			terrain.set(p_setting_name, p_value)
	# Texture scale properties (float)
	elif p_setting_name in TEXTURE_SCALE_PROPERTIES:
		if p_value is float or p_value is int:
			terrain.set(p_setting_name, float(p_value))
	
	_queue_preset_save()


func _queue_preset_save() -> void:
	if _preset_save_timer == null:
		return
	_preset_save_timer.start()


func _flush_preset_save() -> void:
	if not plugin or not plugin.current_terrain_node:
		return
	plugin.current_terrain_node.save_to_preset()


#endregion
