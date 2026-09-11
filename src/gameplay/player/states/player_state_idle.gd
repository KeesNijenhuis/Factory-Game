extends PlayerState
class_name PlayerStateIdle

func enter_state() -> void:
	player.play_direction_animation("idle")

func process_state(_delta: float) -> void:
	if try_start_tool_action():
		return

	# Do not interrupt an attack or tool animation just because movement is held.
	if player.is_moving() and fsm.curr_state is not PlayerStateAttack and fsm.curr_state is not PlayerStateWalk:
		fsm.transition_to("Walk")
		return
