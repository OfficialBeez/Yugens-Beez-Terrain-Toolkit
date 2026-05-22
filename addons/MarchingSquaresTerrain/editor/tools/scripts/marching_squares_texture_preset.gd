@tool
extends Resource
class_name MarchingSquaresTexturePreset


@export var preset_name : String = "New Preset"

@export var new_tex_names : MarchingSquaresTextureNames = MarchingSquaresTextureNames.new()

@export var new_textures : MarchingSquaresTextureList = MarchingSquaresTextureList.new()

@export var quick_paints : Array[MarchingSquaresQuickPaint] = []

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
