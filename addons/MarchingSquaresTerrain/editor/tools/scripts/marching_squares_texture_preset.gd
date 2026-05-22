@tool
extends Resource
class_name MarchingSquaresTexturePreset


@export var preset_name : String = "New Preset"

@export var new_tex_names : MarchingSquaresTextureNames = MarchingSquaresTextureNames.new()

@export var new_textures : MarchingSquaresTextureList = MarchingSquaresTextureList.new()

@export var quick_paints : Array[MarchingSquaresQuickPaint] = []

@export var slot_color_indices: Array = [[], [], [], [], [], [], [], [], [], [], [], [], [], [], []]

@export var slot_blend_modes: Array[int] = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]
