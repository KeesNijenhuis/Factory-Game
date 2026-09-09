class_name CaveChunkDebugView
extends Node2D
## Chunk-grid sibling to CaveGenDebugView: renders a small grid of
## independently generated chunks side by side (with boundary lines), so
## chunk size/room density and cross-chunk visual character can be judged
## directly, entirely decoupled from any TileMap/TileSet. Run standalone via
## F6. Each chunk is generated via CaveGenerator.generate_chunk() exactly as
## CaveChunkStreamer would at runtime, just all at once instead of streamed.

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
const BOUNDARY_COLOR: Color = Color(1.0, 1.0, 1.0, 0.5)

@export var chunk_config: CaveGenerationConfig
@export var world_seed: int = 12345
## Renders a (2*grid_radius_chunks+1)^2 grid of chunks centered on (0,0).
@export var grid_radius_chunks: int = 2

var _chunks: Dictionary = {} ## Vector2i chunk_coord -> CaveData


func _ready() -> void:
	if chunk_config == null:
		push_warning("CaveChunkDebugView: no chunk_config assigned.")
		return
	var chunk_size := Vector2i(chunk_config.map_width, chunk_config.map_height)
	for y in range(-grid_radius_chunks, grid_radius_chunks + 1):
		for x in range(-grid_radius_chunks, grid_radius_chunks + 1):
			var coord := Vector2i(x, y)
			_chunks[coord] = CaveGenerator.generate_chunk(chunk_config, coord, world_seed)
	print("CaveChunkDebugView: generated %d chunks (%dx%d cells each)" % [_chunks.size(), chunk_size.x, chunk_size.y])
	queue_redraw()


func _draw() -> void:
	var chunk_size := Vector2i(chunk_config.map_width, chunk_config.map_height)
	for coord: Vector2i in _chunks:
		var data: CaveData = _chunks[coord]
		var chunk_offset := coord * chunk_size

		for y in range(data.height):
			for x in range(data.width):
				var cell := Vector2i(x, y)
				var color: Color = COLORS.get(data.get_tile(cell), Color.MAGENTA)
				var world_cell := chunk_offset + cell
				draw_rect(Rect2(world_cell.x * TILE_SIZE, world_cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), color, true)

		for cell: Vector2i in data.ore_node_placements:
			draw_circle(_cell_center(chunk_offset + cell), TILE_SIZE * 0.25, ORE_NODE_COLOR)
		for center in data.room_centers:
			draw_circle(_cell_center(chunk_offset + center), TILE_SIZE * 0.3, ROOM_CENTER_COLOR)
		draw_circle(_cell_center(chunk_offset + data.entrance_position), TILE_SIZE * 0.45, ENTRANCE_COLOR)

		var boundary_pos := Vector2(chunk_offset) * TILE_SIZE
		var boundary_size := Vector2(data.width, data.height) * TILE_SIZE
		draw_rect(Rect2(boundary_pos, boundary_size), BOUNDARY_COLOR, false, 2.0)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) / 2.0
