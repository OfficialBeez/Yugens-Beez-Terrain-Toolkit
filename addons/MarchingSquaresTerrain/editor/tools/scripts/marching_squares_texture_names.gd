@tool
extends Resource
class_name MarchingSquaresTextureNames


const MAX_TEXTURE_SLOTS := 256

# Vertex painting texture display names (unified for both floor and wall painting)
@export var texture_names : Array[String] = []


func ensure_initialized() -> void:
	# NOTE: For Resources loaded from .tres, _init() may not run, so callers should
	# defensively call this before reading texture_names.
	if texture_names.is_empty():
		texture_names = [
			"Base Grass", "Texture 2 (g)", "Texture 3 (g)", "Texture 4 (g)",
			"Texture 5 (g)", "Texture 6 (g)", "Texture 7", "Texture 8",
			"Texture 9", "Texture 10", "Texture 11", "Texture 12",
			"Texture 13", "Texture 14", "Texture 15", "Void",
		]
	# Extend (do not overwrite existing custom names coming from presets/resources)
	if texture_names.size() < MAX_TEXTURE_SLOTS:
		for i in range(texture_names.size(), MAX_TEXTURE_SLOTS):
			texture_names.append("Texture %d" % (i + 1))
	elif texture_names.size() > MAX_TEXTURE_SLOTS:
		texture_names.resize(MAX_TEXTURE_SLOTS)

	# Keep the legacy void slot name stable/obvious.
	var VOID_SLOT := 15
	if texture_names.size() > VOID_SLOT:
		texture_names[VOID_SLOT] = "Void"


func _init() -> void:
	ensure_initialized()
