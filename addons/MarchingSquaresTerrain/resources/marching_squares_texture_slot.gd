@tool
extends Resource
class_name MarchingSquaresTextureSlot

# Whether this slot is shown in the UI/selectors.
@export var active: bool = true

# Base terrain texture to sample (0..15).
# - 0..14 map to Terrain Texture 1..15
# - 15 is reserved VOID (transparent) and should generally not be used except for the void slot.
# This lets all 0..255 texture slots share the same 15 base textures without allocating 256 layers.
@export var terrain_texture_index: int = 0

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
