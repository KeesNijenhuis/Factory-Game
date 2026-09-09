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
