extends PlayerStateAction
class_name PlayerStateMining

## The wall cell this swing targets, frozen at enter_state() time -- the mouse
## can move during the swing, but the base class's own contract ("facing stays
## locked to whatever direction it was on entry, since the tool's hit-check
## position is fixed then too") means the target must stay locked too. Null
## when the swing is actually targeting a placed object (e.g. a belt) rather
## than a wall -- the inherited physics-based super._deal_damage() already
## handles that case, so the wall-specific calls below just no-op on null.
var _locked_wall_cell: Variant = null

func enter_state() -> void:
	player.interaction_controller.snap_player_facing()
	super.enter_state()
	player.play_direction_animation("mine")
	position_tool()

## Locks the swing's target. PlayerStateIdle already ran the mineability
## check (InteractionController.try_mine()) before transitioning here for a
## wall target -- an occluded candidate never gets this far, so this just
## grabs whatever resolved (a wall cell, or null for an object target).
func position_tool() -> void:
	_locked_wall_cell = player.interaction_controller.resolved_wall_cell
	player.hit_area.global_position = player.interaction_controller.get_target_world_position()
	# super.enter_state() already telegraphed at the (now stale) marker
	# position -- re-telegraph here at the actual mouse-resolved target.
	player.hit_area.telegraph_hit()

func _on_flash_frame() -> void:
	if _locked_wall_cell != null:
		_get_walls_layer().flash_minable_cell(_locked_wall_cell)
	super._on_flash_frame()

func _deal_damage() -> bool:
	var hit_something := super._deal_damage()
	if _locked_wall_cell != null and _get_walls_layer().damage_wall_cell(_locked_wall_cell):
		hit_something = true
	return hit_something

func _get_walls_layer() -> CaveWallsLayer:
	var main_game := player.get_tree().current_scene as MainGame
	var level := main_game.get_current_level() if main_game else null
	var layer := level.get_walls_layer() if level else null
	return layer as CaveWallsLayer
