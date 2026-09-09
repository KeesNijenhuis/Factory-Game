extends PlayerStateAction
class_name PlayerStateWoodcutting

func enter_state() -> void:
	player.interaction_controller.snap_player_facing()
	super.enter_state()
	player.play_direction_animation("axe")
	position_tool()

func position_tool() -> void:
	player.hit_area.global_position = player.interaction_controller.get_target_world_position()
	# super.enter_state() already telegraphed at the (now stale) marker
	# position -- re-telegraph here at the actual mouse-resolved target.
	player.hit_area.telegraph_hit()
