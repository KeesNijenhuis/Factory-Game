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
## is chunk-local (0..width-1, 0..height-1) -- it's just _resolve_connectivity()'s
## internal validation anchor (room_centers[0]) for every chunk except the
## player's actual spawn chunk, not a literal level entrance. See CaveBuilder/
## CaveChunkStreamer for how chunk-local coordinates become world coordinates.
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
## reproducibility check (see tools/cave_gen_reproducibility_check.gd).
func grid_equals(other: CaveData) -> bool:
	if other == null or other.width != width or other.height != height:
		return false
	return _grid == other._grid
