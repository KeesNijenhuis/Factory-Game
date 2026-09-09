extends PlayerStateAction
class_name PlayerStateTilling

func enter_state() -> void:
	player.interaction_controller.snap_player_facing()
	player.set_hit_area_active(true)
	super.enter_state()
	player.play_direction_animation("hoe")
	# Position the tool before the animation emits any hit events.
	position_tool()

func exit_state() -> void:
	super.exit_state()
	player.set_hit_area_active(false)

func position_tool() -> void:
	var world_pos: Vector2 = player.interaction_controller.get_target_world_position()
	player.weapon.global_position = world_pos
	player.hit_area.global_position = world_pos
