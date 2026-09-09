extends PlayerStateAction
class_name PlayerStateDigging

## The ground cell this swing targets, frozen at enter_state() time -- see
## PlayerStateMining._locked_wall_cell for why the target must stay locked
## for the whole swing even if the mouse moves.
var _locked_ground_cell: Variant = null

func enter_state() -> void:
	player.interaction_controller.snap_player_facing()
	super.enter_state()
	player.play_direction_animation("shovel")
	# The weapon node carries the shovel hitbox for this action.
	position_tool()
	player.set_hit_area_active(true)

func exit_state() -> void:
	super.exit_state()
	player.set_hit_area_active(false)

func position_tool() -> void:
	_locked_ground_cell = player.interaction_controller.resolved_ground_cell
	var world_pos: Vector2 = player.interaction_controller.get_target_world_position()
	player.weapon.global_position = world_pos
	player.hit_area.global_position = world_pos

func _deal_damage() -> bool:
	if _locked_ground_cell == null:
		return false
	return _get_ground_layer().dig_cell(_locked_ground_cell)

func _get_ground_layer() -> CaveGroundLayer:
	var main_game := player.get_tree().current_scene as MainGame
	var level := main_game.get_current_level() if main_game else null
	var layer := level.get_ground_layer() if level else null
	return layer as CaveGroundLayer
