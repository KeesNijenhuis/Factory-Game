class_name ActionDeniedIndicator
extends Sprite2D
## Brief blinking "not allowed" flash. Instanced as a child of the target object
## by ObjectResource.show_action_denied() and frees itself when the flash ends.

@export var flash_duration: float = 0.4
@export var blink_interval: float = 0.1

func _ready() -> void:
	_flash()

func _flash() -> void:
	var elapsed := 0.0
	while elapsed < flash_duration:
		visible = not visible
		await get_tree().create_timer(blink_interval).timeout
		elapsed += blink_interval
	queue_free()
