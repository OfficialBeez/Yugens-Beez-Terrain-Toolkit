extends Node3D
class_name LodChunk

var coords: Vector2i = Vector2i.ZERO
var lod: int = 0
var key: String = ""

var mesh_instance: MeshInstance3D

func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)


func reset() -> void:
	coords = Vector2i.ZERO
	lod = 0
	key = ""
	visible = false
	mesh_instance.mesh = null


func apply_mesh(mesh: ArrayMesh, material: Material) -> void:
	mesh_instance.mesh = mesh
	# Don't mutate the shared cached mesh resource; use instance overrides instead.
	if material:
		mesh_instance.material_override = material
	visible = true
