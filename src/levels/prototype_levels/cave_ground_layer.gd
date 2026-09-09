class_name CaveGroundLayer
extends TileMapLayer
## Attach to the hand-painted Ground layer. Lets a shovel turn a plain ground
## cell into a Ground_Dug cell (simulating a dug-out hole), one swing at a
## time -- see PlayerStateDigging._deal_damage().

const TERRAIN_SET: int = 0
const DUG_TERRAIN: int = 2

## Whether this layer registers itself into the "saveable" group for
## SaveManager's whole-level scan. Default true preserves today's behavior
## for hand-authored levels. A chunk-streamed level sets this false --
## CaveChunkStreamer becomes the single "saveable" node instead (see
## cell_dug) -- see CaveWallsLayer.self_register_saveable for the full
## reasoning.
@export var self_register_saveable: bool = true

## Emitted whenever a cell is actually dug (not when CaveBuilder paints dug
## terrain directly while rebuilding a chunk from saved mutation data, which
## calls set_cells_terrain_connect() itself rather than through dig_cell()).
## CaveChunkStreamer listens to this to record which cells were dug per chunk.
signal cell_dug(cell: Vector2i)

## Cells dug so far, keyed by cell. This is the persisted record of what's
## been dug out -- the tile data itself only shows a cell's current state,
## not that it used to be plain ground, so this is what
## get_save_data()/apply_save_data() round-trip.
var _dug_cells: Dictionary = {}


func _ready() -> void:
	if not Engine.is_editor_hint() and self_register_saveable:
		add_to_group("saveable")


func get_save_id() -> String:
	return "cave_ground_layer"


func get_save_data() -> Dictionary:
	var cells := []
	for cell in _dug_cells:
		cells.append({"x": cell.x, "y": cell.y})
	return {"dug_cells": cells}


func apply_save_data(data: Dictionary) -> void:
	var entries: Array = data.get("dug_cells", [])
	var cells: Array[Vector2i] = []
	for entry in entries:
		var cell := Vector2i(entry.get("x", 0), entry.get("y", 0))
		if is_diggable(cell):
			cells.append(cell)
	if cells.is_empty():
		return
	set_cells_terrain_connect(cells, TERRAIN_SET, DUG_TERRAIN)
	for cell in cells:
		_dug_cells[cell] = true


func is_dug(cell: Vector2i) -> bool:
	var tile_data := get_cell_tile_data(cell)
	return tile_data != null \
		and tile_data.terrain_set == TERRAIN_SET \
		and tile_data.terrain == DUG_TERRAIN


func is_diggable(cell: Vector2i) -> bool:
	return get_cell_tile_data(cell) != null and not is_dug(cell)


## Registers one shovel swing against `cell`. Returns whether it actually dug
## a plain ground cell -- false if `cell` isn't diggable (no ground tile
## there, or already dug).
func dig_cell(cell: Vector2i) -> bool:
	if not is_diggable(cell):
		return false
	set_cells_terrain_connect([cell], TERRAIN_SET, DUG_TERRAIN)
	_dug_cells[cell] = true
	cell_dug.emit(cell)
	return true
