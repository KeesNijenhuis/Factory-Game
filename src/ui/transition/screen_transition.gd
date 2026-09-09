extends Control
class_name ScreenTransition
## Full-screen fade used to hide level-load work (level swap, camera
## snapping, save-data replay) so the player never sees an in-between state.

@onready var overlay: ColorRect = %Overlay


## Fades the overlay to fully opaque, hiding the screen.
func fade_out(duration: float = 0.15) -> void:
	visible = true
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 1.0, duration)
	await tween.finished


## Fades the overlay back to fully transparent, revealing the screen.
func fade_in(duration: float = 0.25) -> void:
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, duration)
	await tween.finished
	visible = false
