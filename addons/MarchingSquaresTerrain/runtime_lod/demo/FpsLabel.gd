extends Label

@export var update_hz: float = 4.0
@export var show_ms: bool = true

var _accum: float = 0.0


func _ready() -> void:
	# Small, always-on overlay label (used by demo scenes).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = "FPS: --"


func _process(delta: float) -> void:
	_accum += delta
	var interval: float = 1.0 / maxf(0.1, update_hz)
	if _accum < interval:
		return
	_accum = 0.0

	var fps := float(Engine.get_frames_per_second())
	if fps <= 0.0:
		text = "FPS: --"
		return
	if show_ms:
		text = "FPS: %d (%.1f ms)" % [int(fps), 1000.0 / fps]
	else:
		text = "FPS: %d" % int(fps)
