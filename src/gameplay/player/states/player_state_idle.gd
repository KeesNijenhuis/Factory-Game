extends PlayerState
class_name PlayerStateIdle

func enter_state() -> void:
	player.play_direction_animation("idle")

func process_state(_delta: float) -> void:
	if Input.is_action_pressed("tool_target_click") and not player.interaction_consumed and not player.is_mouse_over_inventory_panel():
		# Each tool has a dedicated animation state; empty hands remove world objects.
		if player.current_tool_type == Item.ToolTypes.Sword:
			fsm.transition_to("Attack")
			return
		elif player.current_tool_type == Item.ToolTypes.Pickaxe:
			var ic := player.interaction_controller
			if not ic.has_wall_target() and not ic.has_object_target_for(Item.ToolTypes.Pickaxe):
				return
			if not player.skills_manager.check_tool_requirement(player.current_tool_item):
				player.interaction_consumed = true
				player.show_tool_denied_indicator()
				return
			# A wall target might be occluded by a nearer wall -- try_mine()
			# still turns the player to face it, it just doesn't swing.
			if ic.has_wall_target() and not ic.try_mine():
				return
			fsm.transition_to("Mining")
			return
		elif player.current_tool_type == Item.ToolTypes.Axe:
			if not player.interaction_controller.has_object_target_for(Item.ToolTypes.Axe):
				return
			if not player.skills_manager.check_tool_requirement(player.current_tool_item):
				player.interaction_consumed = true
				player.show_tool_denied_indicator()
				return
			fsm.transition_to("Woodcutting")
			return
		elif player.current_tool_type == Item.ToolTypes.Shovel:
			var ic := player.interaction_controller
			if not ic.has_ground_target():
				return
			if not player.skills_manager.check_tool_requirement(player.current_tool_item):
				player.interaction_consumed = true
				player.show_tool_denied_indicator()
				return
			# The tile the player is standing on is a selectable target (so
			# it still shows the dim hover highlight) but never a valid one.
			if not ic.is_hovered_ground_target_diggable():
				return
			fsm.transition_to("Digging")
			return
		elif player.current_tool_type == Item.ToolTypes.Hoe:
			fsm.transition_to("Tilling")
			return
		# else:
		# 	return
		# 	#player.remove_object_tile()
			
	# Do not interrupt an attack or tool animation just because movement is held.
	if player.is_moving() and fsm.curr_state is not PlayerStateAttack and fsm.curr_state is not PlayerStateWalk:
		fsm.transition_to("Walk")
		return
