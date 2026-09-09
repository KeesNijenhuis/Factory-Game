class_name CaveGenDebugView
extends Node2D
## Standalone Milestone 1 debug visualization: generates a CaveData from
## `config` and draws it directly with _draw(), entirely decoupled from any
## TileMap/TileSet. Run this scene directly (F6) to iterate on
## CaveGenerationConfig presets before CaveBuilder's real TileMap painting is
## involved at all -- kept in the repo permanently since it stays useful for
## fast config-tuning iteration well past Milestone 1.

const TILE_SIZE: int = 16
const COLORS := {
	CaveData.TileType.WALL: Color(0.15, 0.15, 0.17),
	CaveData.TileType.FLOOR: Color(0.65, 0.55, 0.4),
	CaveData.TileType.ORE_COPPER: Color(0.85, 0.45, 0.2),
	CaveData.TileType.ORE_IRON: Color(0.6, 0.6, 0.65),
	CaveData.TileType.ORE_GOLD: Color(0.95, 0.8, 0.2),
	CaveData.TileType.WATER: Color(0.2, 0.4, 0.9),
	CaveData.TileType.LAVA: Color(0.9, 0.25, 0.1),
}
const ORE_NODE_COLOR: Color = Color(1.0, 1.0, 1.0)
const ENTRANCE_COLOR: Color = Color(0.1, 1.0, 0.1)
const ROOM_CENTER_COLOR: Color = Color(0.1, 1.0, 1.0)

@export var config: CaveGenerationConfig

var _data: CaveData


func _ready() -> void:
	if config == null:
		push_warning("CaveGenDebugView: no config assigned.")
		return
	_data = CaveGenerator.generate(config)
	print("CaveGenDebugView: seed_used=%d room_centers=%d ore_node_placements=%d" % [
		_data.seed_used, _data.room_centers.size(), _data.ore_node_placements.size(),
	])
	queue_redraw()


func _draw() -> void:
	if _data == null:
		return
	for y in range(_data.height):
		for x in range(_data.width):
			var cell := Vector2i(x, y)
			var color: Color = COLORS.get(_data.get_tile(cell), Color.MAGENTA)
			draw_rect(Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE), color, true)

	for cell: Vector2i in _data.ore_node_placements:
		draw_circle(_cell_center(cell), TILE_SIZE * 0.25, ORE_NODE_COLOR)

	for center in _data.room_centers:
		draw_circle(_cell_center(center), TILE_SIZE * 0.3, ROOM_CENTER_COLOR)

	draw_circle(_cell_center(_data.entrance_position), TILE_SIZE * 0.45, ENTRANCE_COLOR)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) / 2.0
