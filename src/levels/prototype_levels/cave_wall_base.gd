class_name CaveWallBase
extends RefCounted
## Shared rule for the Cave Wall / Cave Wall Base terrain pair: wherever a
## Cave Wall cell has open space below it, a Cave Wall Base cell belongs
## directly beneath it to cap the wall's bottom edge. Used by both
## ProceduralCaveLevel (paints from generated layout data) and the
## hand-painted cave_level.tscn Walls layer (paints live in the editor).

const TERRAIN_SET: int = 0
const WALL_TERRAIN: int = 0
const BASE_TERRAIN: int = 1

## Base strip atlas pieces, keyed by whether the wall cell above has a wall
## neighbor to its left/right -- deliberately keyed off the *wall* row's
## shape rather than the base row's own connectivity, so a stepped cave
## boundary still reads as one continuous base strip instead of fracturing
## into edge caps at every step.
const ATLAS_ISOLATED: Vector2i = Vector2i(0, 4) ## no wall neighbor either side
const ATLAS_LEFT_EDGE: Vector2i = Vector2i(1, 4) ## wall continues to the right only
const ATLAS_MIDDLE: Vector2i = Vector2i(2, 4) ## wall continues both sides
const ATLAS_RIGHT_EDGE: Vector2i = Vector2i(3, 4) ## wall continues to the left only

## Neighborhood positions are stored in a stable clockwise/top-left order;
## PEERING_BITS below maps that order to Godot's sparse CellNeighbor enum.
const PEERING_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]
## CellNeighbor is not a compact 0..7 enum: it also contains the four
## side/corner positions used by hexagonal and isometric TileSets.
const PEERING_BITS: Array[int] = [11, 12, 15, 8, 0, 7, 4, 3]


## wall_cells: Dictionary or Array of Vector2i wall cells (Dictionary keys
## are used if given a Dictionary, so callers can pass their lookup
## structure directly). Returns cell -> atlas coords for every base cell
## that should exist for this wall layout.
static func compute_base_tiles(wall_cells) -> Dictionary:
	var walls: Dictionary = wall_cells if wall_cells is Dictionary else _to_lookup(wall_cells)
	var base_tiles := {}
	for cell in walls:
		var wall_cell: Vector2i = cell
		if walls.has(wall_cell + Vector2i.DOWN):
			continue ## another wall cell below -- this isn't a bottom edge
		var has_left: bool = walls.has(wall_cell + Vector2i.LEFT)
		var has_right: bool = walls.has(wall_cell + Vector2i.RIGHT)
		var atlas_coords: Vector2i
		if has_left and has_right:
			atlas_coords = ATLAS_MIDDLE
		elif has_right:
			atlas_coords = ATLAS_LEFT_EDGE
		elif has_left:
			atlas_coords = ATLAS_RIGHT_EDGE
		else:
			atlas_coords = ATLAS_ISOLATED
		base_tiles[wall_cell + Vector2i.DOWN] = atlas_coords
	return base_tiles


static func _to_lookup(cells: Array) -> Dictionary:
	var lookup := {}
	for cell in cells:
		lookup[cell] = true
	return lookup


## Builds a direct set_cell lookup for a terrain's peering bits. The terrain
## solver normally does this work inside set_cells_terrain_connect(), but
## generated chunks can avoid that expensive bulk call by selecting the same
## atlas tile directly. Missing/partial terrain metadata is intentionally
## tolerated: callers can fall back to terrain_connect when this is empty.
static func build_terrain_tile_lookup(tile_set: TileSet, terrain_set: int, terrain: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for source_index in range(tile_set.get_source_count()):
		var source_id := tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id)
		if not source is TileSetAtlasSource:
			continue
		var atlas_source: TileSetAtlasSource = source
		for tile_index in range(atlas_source.get_tiles_count()):
			var atlas_coords := atlas_source.get_tile_id(tile_index)
			var alternative_count := atlas_source.get_alternative_tiles_count(atlas_coords)
			for alternative_index in range(alternative_count):
				var alternative_tile := atlas_source.get_alternative_tile_id(atlas_coords, alternative_index)
				var tile_data := atlas_source.get_tile_data(atlas_coords, alternative_tile)
				if tile_data == null \
						or tile_data.terrain_set != terrain_set \
						or tile_data.terrain != terrain:
					continue
				var required_mask := 0
				for peering_bit in range(PEERING_OFFSETS.size()):
					if tile_data.get_terrain_peering_bit(PEERING_BITS[peering_bit]) == terrain:
						required_mask |= 1 << peering_bit
				candidates.append({
					"required": required_mask,
					"source_id": source_id,
					"atlas_coords": atlas_coords,
					"alternative": alternative_tile,
				})

	if candidates.is_empty():
		return {}

	# A terrain atlas usually contains only the useful 48-blob shapes rather
	# than all 256 masks. For each possible neighborhood choose the candidate
	# with the most matching required bits that is still compatible with it.
	var lookup := {}
	for actual_mask in range(1 << PEERING_OFFSETS.size()):
		var best: Dictionary = {}
		var best_score := -1
		for candidate in candidates:
			var required: int = candidate["required"]
			if required & actual_mask != required:
				continue
			var score := _bit_count(required)
			if score > best_score:
				best = candidate
				best_score = score
		if not best.is_empty():
			lookup[actual_mask] = best
	return lookup


static func _bit_count(value: int) -> int:
	var count := 0
	while value != 0:
		count += value & 1
		value >>= 1
	return count
