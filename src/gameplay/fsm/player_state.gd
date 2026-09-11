extends State
class_name PlayerState

var player: Player

func _ready() -> void:
	await owner.ready
	player = owner as Player


## Shared by every locomotion state (Idle, Walk) so a held tool_target_click
## starts whichever action state the equipped tool wants, the same way
## regardless of which locomotion state the player is currently in -- a new
## action state only needs its dispatch case added here once, rather than
## copied into every locomotion state's own process_state(). Each tool's
## eligibility/requirement checks stay tool-specific (different tools target
## different things -- a wall, an object, a ground cell, nothing at all), but
## where that dispatch lives, and which locomotion states offer it, doesn't
## vary per tool. Returns whether a transition happened, so callers can bail
## out of the rest of their own per-frame logic exactly like a successful
## transition already required them to.
func try_start_tool_action() -> bool:
	if not Input.is_action_pressed("tool_target_click") or player.interaction_consumed or player.is_mouse_over_inventory_panel():
		return false
	var ic := player.interaction_controller
	match player.current_tool_type:
		Item.ToolTypes.Sword:
			fsm.transition_to("Attack")
			return true
		Item.ToolTypes.Pickaxe:
			if not ic.has_wall_target() and not ic.has_object_target_for(Item.ToolTypes.Pickaxe):
				return false
			if not player.skills_manager.check_tool_requirement(player.current_tool_item):
				player.interaction_consumed = true
				player.show_tool_denied_indicator()
				return false
			# A wall target might be occluded by a nearer wall -- try_mine()
			# still turns the player to face it, it just doesn't swing.
			if ic.has_wall_target() and not ic.try_mine():
				return false
			fsm.transition_to("Mining")
			return true
		Item.ToolTypes.Axe:
			if not ic.has_object_target_for(Item.ToolTypes.Axe):
				return false
			if not player.skills_manager.check_tool_requirement(player.current_tool_item):
				player.interaction_consumed = true
				player.show_tool_denied_indicator()
				return false
			fsm.transition_to("Woodcutting")
			return true
		Item.ToolTypes.Shovel:
			if not ic.has_ground_target():
				return false
			if not player.skills_manager.check_tool_requirement(player.current_tool_item):
				player.interaction_consumed = true
				player.show_tool_denied_indicator()
				return false
			# The tile the player is standing on is a selectable target (so
			# it still shows the dim hover highlight) but never a valid one.
			if not ic.is_hovered_ground_target_diggable():
				return false
			fsm.transition_to("Digging")
			return true
		Item.ToolTypes.Hoe:
			fsm.transition_to("Tilling")
			return true
	return false


