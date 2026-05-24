@tool
extends Resource
class_name MarchingSquaresTextureSlot

@export var texture: Texture2D
@export var scale: float = 1.0
@export var albedo: Color = Color(1, 1, 1, 1)

# Grass system (only used by first few slots currently)
@export var grass_texture: Texture2D
@export var has_grass: bool = false

# Outline settings (optional)
@export var has_outline: bool = false
# 0 = darken albedo, 1 = use albedo as outline color
@export var outline_mode: int = 0
