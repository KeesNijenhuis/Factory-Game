extends PlayerStateAction
class_name PlayerStateAttack

func enter_state() -> void:
	super.enter_state()
	player.play_direction_animation("attack")
	# The weapon stays active only for the attack animation's duration.
	position_weapon()

func position_weapon() -> void:
	var direction_key: String = player.last_direction
	var marker: Marker2D = player.attack_positions[direction_key]
	player.weapon.global_position = marker.global_position
