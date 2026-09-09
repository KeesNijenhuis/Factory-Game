extends BaseLevel
class_name CaveLevel
## PLACEHOLDER: This script and corresponding scenes exist only to provide levels for demonstrating the project foundation.
## It is not intended as an example of a completed level scene or script.

## FUTURE (level): Replace with the actual level implementation.

@onready var player_spawn_marker : Marker2D = $LevelObjects/PlayerSpawn
# FUTURE (camera): This will be moved to camera system/manager
@onready var player_camera : Camera2D = $LevelObjects/PlayerCamera
@onready var objects_layer: TileMapLayer = $Tilemaps/Objects
@onready var walls_layer: TileMapLayer = $Tilemaps/Walls
@onready var ground_layer: TileMapLayer = $Tilemaps/Ground


func get_default_player_spawn() -> Vector2:
	return player_spawn_marker.global_position

func get_player_camera() -> Camera2D:
	return player_camera

func get_objects_layer() -> TileMapLayer:
	return objects_layer

func get_walls_layer() -> TileMapLayer:
	return walls_layer

func get_ground_layer() -> TileMapLayer:
	return ground_layer
