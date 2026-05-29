@tool
extends Resource
class_name MarchingSquaresTexturePreset


@export var preset_name : String = "New Preset"

@export var new_tex_names : MarchingSquaresTextureNames = MarchingSquaresTextureNames.new()

@export var new_textures : MarchingSquaresTextureList = MarchingSquaresTextureList.new()

@export var quick_paints : Array[MarchingSquaresQuickPaint] = []

# If enabled, the preset also stores/applies selected global terrain settings (beyond just colors/textures).
@export_group("Global Settings")
@export var apply_terrain_settings: bool = false
@export var apply_chunk_settings: bool = false # Recommended off (can trigger heavy rebuilds).
@export var apply_vertex_painter_settings: bool = true
@export var apply_grass_settings: bool = true
@export var terrain_settings: Dictionary = {}

@export_group("")
@export var slot_color_indices: Array = [[], [], [], [], [], [], [], [], [], [], [], [], [], [], []]

@export var slot_blend_modes: Array[int] = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]

# Palette weights (per palette index 0-127). Used to control distribution of each palette color.
# Values are normalized per-slot in the shader (so they behave like percentages).
@export var palette_weights: Array[float] = []

# Outline settings (per texture slot)
# slot_has_outline[slot] == true enables an edge/foam-like outline when that texture meets another.
# slot_outline_modes[slot]: 0 = darken Color 1, 1 = use last palette color
@export var slot_has_outline: Array[bool] = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]
@export var slot_outline_modes: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
@export var slot_outline_widths: Array[float] = [6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0]

# Wetness controls (per texture slot)
# slot_wet_enabled[slot] toggles wetness effects on/off for that slot.
# slot_wet_modes[slot]: 0 = Wet (darken only), 1 = Glossy puddles (noise-masked).
@export var slot_wet_enabled: Array[bool] = [false, false, false, false, false, false, false, false, false, false, false, false, false, false, false]
@export var slot_wet_modes: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

# Roughness per texture slot (0 = shiny/wet, 1 = matte/dry)
@export var slot_roughnesses: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
