extends Camera2D

@export_group("Follow Smoothing")
@export var smoothing_enabled: bool = true
## How quickly the camera catches up to the target. Lower values lag behind more.
@export_range(0.0, 20.0, 0.1) var smoothing_speed: float = 8.0

const DEBUG_ZOOM_MIN: float = 0.5
const DEBUG_ZOOM_MAX: float = 2.0
const DEBUG_ZOOM_STEP: float = 0.5

var target : Node2D = null
var _debug_zoom_level: float


func _ready() -> void:
	_debug_zoom_level = zoom.x


func _unhandled_input(event : InputEvent) -> void:
	if not OS.is_debug_build() or not DebugSettings.enable_camera_zoom:
		return

	if event.is_action_pressed(&"debug_zoom_in"):
		_debug_zoom_level = clampf(_debug_zoom_level + DEBUG_ZOOM_STEP, DEBUG_ZOOM_MIN, DEBUG_ZOOM_MAX)
		zoom = Vector2(_debug_zoom_level, _debug_zoom_level)
	elif event.is_action_pressed(&"debug_zoom_out"):
		_debug_zoom_level = clampf(_debug_zoom_level - DEBUG_ZOOM_STEP, DEBUG_ZOOM_MIN, DEBUG_ZOOM_MAX)
		zoom = Vector2(_debug_zoom_level, _debug_zoom_level)


func _process(delta : float) -> void:
	_follow_camera_target(delta)


## Instantly moves the camera onto its target, bypassing follow smoothing.
func snap_to_target() -> void:
	if target:
		global_position = target.global_position


func _follow_camera_target(delta : float) -> void:
	if not target:
		return
	if smoothing_enabled:
		global_position = global_position.lerp(target.global_position, clampf(smoothing_speed * delta, 0.0, 1.0))
	else:
		global_position = target.global_position
#
