@tool
extends Resource
class_name MarchingSquaresTextureList


const GRASS_SPRITE : Texture2D = preload("uid://cxvnfgy865wsk")

@export var terrain_textures : Array[Texture2D] = [
	null, null, null, null,
	null, null, null, null,
	null, null, null, null,
	null, null, null,
]

@export var texture_scales : Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0,
]

@export var grass_sprites : Array[Texture2D] = [
	GRASS_SPRITE, GRASS_SPRITE, GRASS_SPRITE,
	GRASS_SPRITE, GRASS_SPRITE, GRASS_SPRITE,
]

@export var grass_colors : Array[Color] = [
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex1
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex2
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex3
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex4
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex5
	Color("647851ff"), Color("527b62ff"), Color("5f6c4bff"), Color("647941ff"),  # tex6
]

@export var has_grass : Array[bool] = [
	true, true, true, true, true,
]
