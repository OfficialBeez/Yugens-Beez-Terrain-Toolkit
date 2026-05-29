extends Camera3D

@export var move_speed: float = 30.0
@export var vertical_speed: float = 20.0

func _process(delta: float) -> void:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# v.y comes from ui_up/ui_down; treat ui_up as forward.
	var dir := (global_transform.basis.x * v.x) + (-global_transform.basis.z * v.y)
	if dir.length() > 0.0:
		dir = dir.normalized()

	# Use keys directly to avoid missing InputMap actions spamming errors.
	var up_down := 0.0
	if Input.is_key_pressed(KEY_E):
		up_down += 1.0
	if Input.is_key_pressed(KEY_Q):
		up_down -= 1.0

	global_position += (dir * move_speed + Vector3.UP * up_down * vertical_speed) * delta
