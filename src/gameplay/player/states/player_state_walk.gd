extends PlayerState
class_name PlayerStateWalk


func enter_state() -> void:
	player.play_direction_animation("walk")

func process_state(_delta: float) -> void:
	var input_vector = Input.get_vector("move_left","move_right","move_up","move_down")

	if input_vector != Vector2.ZERO and Input.is_action_just_pressed("dash"):
		# Dash away in whatever direction the player is currently moving.
		player.dash_direction = input_vector.normalized()
		fsm.transition_to("Dash")
		return

	if try_start_tool_action():
		return

	if input_vector == Vector2.ZERO:
		fsm.transition_to("Idle")
		return
	player.update_direction(input_vector)


	if Input.is_action_pressed("sprint"):
		# Movement speed and animation must stay in sync when sprinting is held.
		player.play_direction_animation("sprint")
	else:
		player.play_direction_animation("walk")

func process_physics_state(_delta: float) -> void:
	var input_vector = Input.get_vector("move_left","move_right","move_up","move_down")
	if input_vector == Vector2.ZERO:
		return
	if Input.is_action_pressed("sprint"):
		player.velocity = input_vector * player.move_speed_sprinting
	else:
		player.velocity = input_vector * player.move_speed
	player.move_and_slide()
