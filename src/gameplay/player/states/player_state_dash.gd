extends PlayerState
class_name PlayerStateDash

## Collision bit used by solid-but-not-wall objects (ores, trees, chests). Walls use
## a different bit, so clearing only this one lets the dash pass through obstacles
## while still stopping at walls.
const SOLID_OBJECT_COLLISION_BIT: int = 1
## Collision bit used by dug-out ground pits. Walls use a different bit, so clearing
## this lets a dash carry the player across a pit (if it's within dash_distance)
## while still stopping the dash at walls.
const DUG_GROUND_COLLISION_BIT: int = 32

var current_speed: float = 0.0
var accelerating: bool = true
var target_speed: float = 0.0
var dash_start_position: Vector2 = Vector2.ZERO
var original_collision_mask: int = 0

func enter_state() -> void:
	current_speed = player.move_speed
	accelerating = true
	# Settle back into whatever speed the player was already moving at (walk or sprint).
	target_speed = player.move_speed_sprinting if Input.is_action_pressed("sprint") else player.move_speed
	dash_start_position = player.global_position
	original_collision_mask = player.collision_mask
	player.collision_mask &= ~(SOLID_OBJECT_COLLISION_BIT | DUG_GROUND_COLLISION_BIT)
	player.play_direction_animation("sprint")

func exit_state() -> void:
	player.collision_mask = original_collision_mask

func process_physics_state(delta: float) -> void:
	if accelerating:
		current_speed += player.dash_acceleration * delta
		if current_speed >= player.dash_top_speed:
			current_speed = player.dash_top_speed
			accelerating = false
	else:
		current_speed -= player.dash_deceleration * delta

	var traveled_distance: float = player.global_position.distance_to(dash_start_position)
	var decayed_to_target: bool = not accelerating and current_speed <= target_speed
	var reached_dash_distance: bool = traveled_distance >= player.dash_distance

	if decayed_to_target or reached_dash_distance:
		current_speed = target_speed
		player.velocity = player.dash_direction * current_speed
		player.move_and_slide()
		if player.is_moving():
			fsm.transition_to("Walk")
		else:
			fsm.transition_to("Idle")
		return

	player.velocity = player.dash_direction * current_speed
	player.move_and_slide()
