class_name Ladder
extends Area2D
## Reusable level-transition trigger. Interacting with it loads destination_level
## and lets MainGame place the player via that level's own BaseLevel spawn/camera
## getters, so this works with any BaseLevel scene -- hand-authored or freshly
## procedurally generated -- without knowing anything about its layout.

## Level scene to travel to. Its root must extend BaseLevel. Set per-instance in
## the editor so the same Ladder scene can link any two levels.
@export var destination_level: PackedScene

## How close the player's active attack/interact point needs to be before an
## interact press triggers travel. Mirrors Chest's swing-reach check so ladders
## participate in the same interact system as other world objects.
@export var interaction_reach: float = 8.0

func _ready() -> void:
	add_to_group("ladders")
	area_entered.connect(_on_area_entered)

func can_interact_with(player: Player) -> bool:
	var direction_marker: Marker2D = player.attack_positions.get(player.last_direction)
	if direction_marker == null:
		return false
	return global_position.distance_to(direction_marker.global_position) <= interaction_reach

func _on_area_entered(area: Area2D) -> void:
	if area is HitArea and Input.is_action_pressed(&"interact"):
		var player := area.get_parent() as Player
		if player and can_interact_with(player):
			player.interaction_consumed = true
			_travel(player)

func _travel(_player: Player) -> void:
	if destination_level == null:
		push_warning("Ladder '%s' has no destination_level assigned" % name)
		return
	var main_game := get_tree().current_scene as MainGame
	if main_game == null:
		push_error("Ladder could not find MainGame to load destination_level")
		return
	main_game.load_level(destination_level.resource_path)
