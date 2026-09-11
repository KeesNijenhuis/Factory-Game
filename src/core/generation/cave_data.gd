class_name CaveData
extends RefCounted
## Pure-data output of CaveGenerator: a 2D grid of TileType values plus the
## generation metadata (entrance, room centers, seed) needed to build a level
## from it. Holds no scene-tree/TileMap references -- see CaveBuilder for
## the side of the pipeline that paints this onto a real level.

enum TileType { WALL, FLOOR, ORE_COPPER, ORE_IRON, ORE_GOLD, WATER, LAVA }

var width: int
var height: int
## For a chunk generated via CaveGenerator.generate_chunk(), entrance_position
## is a deterministic chunk-local floor cell (0..width-1, 0..height-1) used
## as the spawn/loading anchor. See CaveBuilder/CaveChunkStreamer for how
## chunk-local coordinates become world coordinates.
var entrance_position: Vector2i
var room_centers: Array[Vector2i] = []
## The seed actually used to produce this grid -- may differ from the
## originating CaveGenerationConfig.seed if config.seed was 0 (randomize) or
## if CaveGenerator had to retry with a derived sub-seed.
var seed_used: int
## Which chunk this grid belongs to, in chunk coordinates (not cells) --
## Vector2i.ZERO and otherwise meaningless for CaveData produced by the
## whole-map generate() path. World-space offset for this chunk's cells is
## chunk_coord * Vector2i(width, height), computed by callers that already
## have the generating config in scope rather than stored here separately.
var chunk_coord: Vector2i = Vector2i.ZERO

## Pickable floor ore objects scattered by CaveGenerator, keyed by cell.
## Kept separate from the tile grid (rather than as a TileType) since a node
## sits on top of a FLOOR cell instead of replacing it -- mirroring how
## CaveOreOverlayLayer keeps its ore-overlay state separate from the base
## wall tile.
var ore_node_placements: Dictionary = {} ## Vector2i -> OreNodeType

var _grid: Array[int] = []


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	_grid.resize(width * height)
	_grid.fill(TileType.WALL)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Out-of-bounds cells read as WALL, so map-edge logic (CA smoothing,
## connectivity flood fill) never needs a separate bounds check.
func get_tile(cell: Vector2i) -> TileType:
	if not is_in_bounds(cell):
		return TileType.WALL
	return _grid[cell.y * width + cell.x] as TileType


func set_tile(cell: Vector2i, tile_type: TileType) -> void:
	if not is_in_bounds(cell):
		return
	_grid[cell.y * width + cell.x] = tile_type


func get_size() -> Vector2i:
	return Vector2i(width, height)


## Value-equality check against another CaveData's tile grid -- used by the
## reproducibility check (see tools/cave_chunk_gen_reproducibility_check.gd).
func grid_equals(other: CaveData) -> bool:
	if other == null or other.width != width or other.height != height:
		return false
	return _grid == other._grid


func to_cache_dict() -> Dictionary:
	var ore_nodes := []
	var serialized_centers := []
	for cell: Vector2i in ore_node_placements:
		var node_type: OreNodeType = ore_node_placements[cell]
		if node_type == null or node_type.scene == null:
			continue
		ore_nodes.append({
			"x": cell.x,
			"y": cell.y,
			"scene_path": node_type.scene.resource_path,
		})
	for cell: Vector2i in room_centers:
		serialized_centers.append({"x": cell.x, "y": cell.y})
	return {
		"width": width,
		"height": height,
		"grid": _grid,
		"entrance": {"x": entrance_position.x, "y": entrance_position.y},
		"room_centers": serialized_centers,
		"seed_used": seed_used,
		"chunk_coord": {"x": chunk_coord.x, "y": chunk_coord.y},
		"ore_nodes": ore_nodes,
	}


static func from_cache_dict(cached: Dictionary) -> CaveData:
	var data := CaveData.new(int(cached.get("width", 0)), int(cached.get("height", 0)))
	if data.width <= 0 or data.height <= 0:
		return null
	var grid: Array = cached.get("grid", [])
	if grid.size() != data.width * data.height:
		return null
	for index in range(grid.size()):
		data._grid[index] = int(grid[index])
	var entrance: Dictionary = cached.get("entrance", {})
	data.entrance_position = Vector2i(int(entrance.get("x", 0)), int(entrance.get("y", 0)))
	for center_data: Dictionary in cached.get("room_centers", []):
		data.room_centers.append(Vector2i(int(center_data.get("x", 0)), int(center_data.get("y", 0))))
	data.seed_used = int(cached.get("seed_used", 0))
	var coord: Dictionary = cached.get("chunk_coord", {})
	data.chunk_coord = Vector2i(int(coord.get("x", 0)), int(coord.get("y", 0)))
	for node_data: Dictionary in cached.get("ore_nodes", []):
		var scene := load(node_data.get("scene_path", "")) as PackedScene
		if scene == null:
			return null
		var node_type := OreNodeType.new()
		node_type.scene = scene
		data.ore_node_placements[Vector2i(int(node_data.get("x", 0)), int(node_data.get("y", 0)))] = node_type
	return data
