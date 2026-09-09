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

	if Input.is_action_pressed("tool_target_click") and not player.interaction_consumed and not player.is_mouse_over_inventory_panel():
		# Tool interactions replace movement for this frame and enter an animation state.
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
		else:
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
