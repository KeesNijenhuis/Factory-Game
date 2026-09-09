@abstract
class_name BaseLevel
extends Node2D

## Abstract class for levels

## Provides default global position for player to be placed in level
@abstract func get_default_player_spawn() -> Vector2

## Provides the camera used in the level
@abstract func get_player_camera() -> Camera2D  # FUTURE (camera): This should be moved out of level into camera system/manager

## Provides the TileMapLayer that holds design-time and runtime-placed world
## objects (chests, furnaces, ladders, etc.), keyed by tile cell.
@abstract func get_objects_layer() -> TileMapLayer

## Provides the TileMapLayer that holds solid wall tiles, used to block
## placement of world objects onto occupied wall cells.
@abstract func get_walls_layer() -> TileMapLayer

## Provides the TileMapLayer that holds the diggable ground floor.
@abstract func get_ground_layer() -> TileMapLayer
