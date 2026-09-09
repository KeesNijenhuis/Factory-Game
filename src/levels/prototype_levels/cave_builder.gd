class_name CaveBuilder
extends Node
## Runtime consumer of CaveGenerator's output: paints a CaveData onto the
## real cave TileSet layers and scatters pickable ore node scenes. This is
## the second half of the two-phase pipeline -- CaveGenerator is pure data,
## this is what actually touches TileMapLayer.
##
## Two families of entry points share the same painting logic:
## - generate_and_build() -- legacy whole-map path, clears every layer and
##   paints one CaveData in full. Kept for any standalone/debug use.
## - build_chunk()/build_chunk_async()/clear_chunk() -- the streaming entry
##   points CaveChunkStreamer drives, each operating on one chunk's cells at
##   its world offset on the SAME shared layers every other chunk paints
##   onto (confirmed correct over per-chunk layers: TileMapLayer cell storage
##   is sparse, so there's no memory cost to a large logical world, and
##   terrain-autoconnect only ever sees neighbors on the same layer instance
##   -- per-chunk layers would make cross-chunk wall shapes unreconcilable).
##
## Generated floor is painted as a PLAIN floor tile, NOT the Ground_Dug
## terrain -- Ground_Dug is a distinct, player-driven shovel-digging
## mechanic (see PlayerStateDigging/CaveGroundLayer.dig_cell()), and dug
## cells are treated as obstacles elsewhere (PlacementController refuses to
## place objects on them, and the dug-ground atlas carries its own physics
## collision layer). Painting generated floor as "dug" would make the whole
## cave read as a field of pits. PLAIN_FLOOR_SOURCE_ID/ATLAS_COORDS matches
## the tile the hand-authored cave_level.tscn's Ground layer already uses
## wherever it hasn't been shovel-dug (verified directly against that
## scene's tile data).
##
## The wall pass (set_cells_terrain_connect()) is the one atomic, never-
## sub-batched step in the whole pipeline -- measured at ~0.22-0.25ms per
## wall cell, essentially flat regardless of batch size. Splitting it across
## multiple calls (e.g. to spread a chunk's load across frames) would leave
## cells on a sub-batch seam reading a wrong autotile shape until a later
## batch touches them: a visible glitch, worse than a bounded, one-shot
## hitch. Every OTHER pass (ground fill, base caps, ore overlay, liquids,
## ore-node instancing) has no neighbor-shape dependency and is safe to
## yield between -- see build_chunk_async().

const PLAIN_FLOOR_SOURCE_ID: int = 0
const PLAIN_FLOOR_ATLAS_COORDS: Vector2i = Vector2i(4, 4)

const WATER_SOURCE_ID: int = 5
const WATER_ATLAS_COORDS: Vector2i = Vector2i(0, 0)

@export var config: CaveGenerationConfig
@export var walls_layer_path: NodePath
@export var ground_layer_path: NodePath
@export var ore_overlay_layer_path: NodePath
@export var liquids_layer_path: NodePath
@export var objects_layer_path: NodePath

var walls_layer: CaveWallsLayer
var ground_layer: CaveGroundLayer
var ore_overlay_layer: CaveOreOverlayLayer
var liquids_layer: TileMapLayer
var objects_layer: TileMapLayer

## chunk_coord -> Array[Node2D], ore node instances owned by each currently-
## built chunk -- lets clear_chunk() free exactly (and only) the ones this
## chunk placed, without scanning/filtering objects_layer's whole child list.
var _chunk_object_instances: Dictionary = {}


func _ready() -> void:
	walls_layer = get_node(walls_layer_path)
	ground_layer = get_node(ground_layer_path)
	ore_overlay_layer = get_node(ore_overlay_layer_path)
	liquids_layer = get_node(liquids_layer_path)
	objects_layer = get_node(objects_layer_path)


## Legacy whole-map entry point: generates via CaveGenerator.generate() and
## paints the whole grid in one call, clearing every layer first.
func generate_and_build() -> CaveData:
	var total_start := Time.get_ticks_usec()
	var data := CaveGenerator.generate(config)
	print("CaveBuilder: generation %.1f ms" % _elapsed_ms(total_start))

	var paint_start := Time.get_ticks_usec()
	walls_layer.clear()
	ground_layer.clear()
	liquids_layer.clear()
	_paint_ground_pass(data, Vector2i.ZERO, {})
	var wall_cells := _paint_wall_and_base_pass(data, Vector2i.ZERO)
	_paint_ore_overlay_pass(data, Vector2i.ZERO, wall_cells)
	_paint_liquids_pass(data, Vector2i.ZERO)
	_instance_ore_nodes(data, Vector2i.ZERO, {}, false)
	print("CaveBuilder: painting %.1f ms" % _elapsed_ms(paint_start))
	print("CaveBuilder: generate_and_build() total %.1f ms" % _elapsed_ms(total_start))
	return data


## Synchronous chunk build: generates + paints chunk_coord with no yields --
## required for the initial spawn-radius load, since ProceduralCaveLevel's
## _ready() must finish before MainGame reads the level's default player
## spawn (see CaveChunkStreamer.load_initial_chunks()).
##
## mutation_record (see CaveChunkStreamer for its shape) excludes previously
## mined/dug cells from the fresh paint and restores depleted/damaged ore
## nodes, so a rebuilt chunk shows exactly what the player left behind
## rather than pristine terrain.
func build_chunk(chunk_coord: Vector2i, world_seed: int, mutation_record: Dictionary = {}) -> CaveData:
	var data := CaveGenerator.generate_chunk(config, chunk_coord, world_seed)
	var world_offset := _chunk_world_offset(chunk_coord)
	_paint_ground_pass(data, world_offset, mutation_record)
	var wall_cells := _paint_wall_and_base_pass(data, world_offset, mutation_record)
	_paint_ore_overlay_pass(data, world_offset, wall_cells)
	_paint_liquids_pass(data, world_offset)
	_chunk_object_instances[chunk_coord] = _instance_ore_nodes(data, world_offset, mutation_record.get("ore_nodes", {}), true)
	_refresh_chunk_boundary(chunk_coord)
	return data


## Steady-state chunk build: same result as build_chunk(), but yields a
## frame between every pass that has no neighbor-shape dependency, so a
## chunk load never costs more than one uninterrupted frame at a time. The
## wall pass itself is never yielded around -- see class doc.
func build_chunk_async(chunk_coord: Vector2i, world_seed: int, mutation_record: Dictionary = {}) -> CaveData:
	var data := CaveGenerator.generate_chunk(config, chunk_coord, world_seed)
	var world_offset := _chunk_world_offset(chunk_coord)
	await get_tree().process_frame
	_paint_ground_pass(data, world_offset, mutation_record)
	await get_tree().process_frame
	var wall_cells := _paint_wall_and_base_pass(data, world_offset, mutation_record)
	await get_tree().process_frame
	_paint_ore_overlay_pass(data, world_offset, wall_cells)
	await get_tree().process_frame
	_paint_liquids_pass(data, world_offset)
	await get_tree().process_frame
	_chunk_object_instances[chunk_coord] = _instance_ore_nodes(data, world_offset, mutation_record.get("ore_nodes", {}), true)
	_refresh_chunk_boundary(chunk_coord)
	return data


## Erases exactly the cells `data` painted at chunk_coord's world offset
## (recomputed from the already-in-memory `data` -- no regeneration needed)
## and frees this chunk's ore-node instances. Cheap: erase_cell() has no
## neighbor-shape recompute cost, unlike painting. Returns each freed ore
## node's save-data, keyed "world_x,world_y" (matching the ore_nodes shape
## in CaveBuilder.build_chunk()'s mutation_record), so the caller
## (CaveChunkStreamer) can remember it for the next time this chunk builds.
func clear_chunk(chunk_coord: Vector2i, data: CaveData) -> Dictionary:
	var world_offset := _chunk_world_offset(chunk_coord)
	var wall_cells := _wall_cells_for(data, world_offset)

	for cell in wall_cells:
		walls_layer.erase_cell(cell)
	var base_tiles := CaveWallBase.compute_base_tiles(wall_cells)
	for cell: Vector2i in base_tiles:
		walls_layer.erase_cell(cell)
	for y in range(data.height):
		for x in range(data.width):
			ground_layer.erase_cell(world_offset + Vector2i(x, y))
	# Base cap cells can land one row past this chunk's own bottom edge (see
	# _paint_wall_and_base_pass's matching ground patch-in) -- the main loop
	# above only covers the chunk's own bounds, so also erase any such cell's
	# ground patch that falls outside it (x is always in-bounds -- DOWN only
	# ever pushes y one row past, never x).
	for cell: Vector2i in base_tiles:
		if cell.y >= world_offset.y + data.height:
			ground_layer.erase_cell(cell)
	for cell in _water_cells_for(data, world_offset):
		liquids_layer.erase_cell(cell)
	# Ore overlay self-cleans: resync() re-derives every currently-marked
	# cell's art from the Walls layer's live state, and _apply_cell() erases
	# + un-tracks any cell that's no longer a wall (the ones just erased
	# above) -- see CaveOreOverlayLayer._apply_cell().
	ore_overlay_layer.resync()

	var ore_node_records := {}
	for instance in _chunk_object_instances.get(chunk_coord, []):
		if not is_instance_valid(instance):
			continue
		if instance.has_method("get_save_data"):
			var world_cell: Vector2i = objects_layer.local_to_map(instance.position)
			ore_node_records["%d,%d" % [world_cell.x, world_cell.y]] = instance.get_save_data()
		instance.queue_free()
	_chunk_object_instances.erase(chunk_coord)

	_refresh_chunk_boundary(chunk_coord)
	return ore_node_records


func _chunk_world_offset(chunk_coord: Vector2i) -> Vector2i:
	return chunk_coord * Vector2i(config.map_width, config.map_height)


static func _elapsed_ms(start_usec: int) -> float:
	return (Time.get_ticks_usec() - start_usec) / 1000.0


# ---------------------------------------------------------------------------
# Boundary seam fix
# ---------------------------------------------------------------------------

## A chunk painted before its neighbor exists shapes its boundary wall cells
## as if the far side were empty (an outer-edge autotile shape). When the
## neighbor loads (or unloads), cells on ITS side of the shared edge connect
## correctly, but this chunk's already-painted boundary is never told to
## recompute -- a visible stale-shape seam. Fix: force-recompute every wall
## cell in a 2-cell-wide band straddling each of chunk_coord's 4 edges (this
## chunk's own edge row/column plus its neighbor's), the same erase-then-
## set_cells_terrain_connect() trick CaveWallsLayer._refresh_wall_terrain_around()
## already uses for mining, just widened from "8 neighbors of one cell" to
## "one shared edge's worth of cells." Cells belonging to a currently-
## unloaded neighbor simply aren't wall cells on the layer yet, so they
## contribute nothing -- no explicit "is neighbor loaded" bookkeeping needed.
func _refresh_chunk_boundary(chunk_coord: Vector2i) -> void:
	var chunk_size := Vector2i(config.map_width, config.map_height)
	var world_offset := _chunk_world_offset(chunk_coord)
	var strips: Array[Rect2i] = [
		Rect2i(world_offset.x, world_offset.y - 1, chunk_size.x, 2), # top edge
		Rect2i(world_offset.x, world_offset.y + chunk_size.y - 1, chunk_size.x, 2), # bottom edge
		Rect2i(world_offset.x - 1, world_offset.y, 2, chunk_size.y), # left edge
		Rect2i(world_offset.x + chunk_size.x - 1, world_offset.y, 2, chunk_size.y), # right edge
	]

	var boundary_wall_cells: Dictionary = {}
	for strip in strips:
		for y in range(strip.position.y, strip.position.y + strip.size.y):
			for x in range(strip.position.x, strip.position.x + strip.size.x):
				var cell := Vector2i(x, y)
				if walls_layer.is_wall_cell(cell):
					boundary_wall_cells[cell] = true

	if boundary_wall_cells.is_empty():
		return
	var cells: Array[Vector2i] = Array(boundary_wall_cells.keys(), TYPE_VECTOR2I, "", null)
	# erase first -- set_cells_terrain_connect() only recomputes a cell's
	# shape when it's newly transitioning onto the terrain, a no-op on cells
	# that already have it assigned (same reasoning as
	# CaveWallsLayer._refresh_wall_terrain_around()).
	for cell in cells:
		walls_layer.erase_cell(cell)
	walls_layer.set_cells_terrain_connect(cells, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN)
	var base_tiles := CaveWallBase.compute_base_tiles(boundary_wall_cells)
	for cell: Vector2i in base_tiles:
		walls_layer.set_cell(cell, CaveWallsLayer.TILESET_SOURCE_ID, base_tiles[cell])
	ore_overlay_layer.resync()


# ---------------------------------------------------------------------------
# Classification helpers (shared by paint and clear paths)
# ---------------------------------------------------------------------------

func _wall_cells_for(data: CaveData, world_offset: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(data.height):
		for x in range(data.width):
			match data.get_tile(Vector2i(x, y)):
				CaveData.TileType.WALL, CaveData.TileType.ORE_COPPER, CaveData.TileType.ORE_IRON, CaveData.TileType.ORE_GOLD:
					cells.append(world_offset + Vector2i(x, y))
	return cells


func _water_cells_for(data: CaveData, world_offset: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(data.height):
		for x in range(data.width):
			if data.get_tile(Vector2i(x, y)) == CaveData.TileType.WATER:
				cells.append(world_offset + Vector2i(x, y))
	return cells


# ---------------------------------------------------------------------------
# Paint passes
# ---------------------------------------------------------------------------

## Painted under the ENTIRE chunk, not just currently-open floor. Walls (and
## ore veins) are destructible -- if the Ground layer were only painted
## under FLOOR/WATER/LAVA, mining a wall away would reveal empty space
## instead of ground. A single uniform plain-floor tile, not a terrain call
## -- no autotile variants exist for plain (undug) ground. dug_ground_cells
## in mutation_record (world cells) get the Ground_Dug terrain instead,
## reusing CaveGroundLayer's own terrain constants, so a chunk rebuild shows
## previously shovel-dug cells as still dug.
func _paint_ground_pass(data: CaveData, world_offset: Vector2i, mutation_record: Dictionary) -> void:
	var dug_cells := _world_cell_set(mutation_record.get("dug_ground_cells", []))
	var to_dig: Array[Vector2i] = []
	for y in range(data.height):
		for x in range(data.width):
			var world_cell := world_offset + Vector2i(x, y)
			if dug_cells.has(world_cell):
				to_dig.append(world_cell)
			else:
				ground_layer.set_cell(world_cell, PLAIN_FLOOR_SOURCE_ID, PLAIN_FLOOR_ATLAS_COORDS)
	if not to_dig.is_empty():
		ground_layer.set_cells_terrain_connect(to_dig, CaveGroundLayer.TERRAIN_SET, CaveGroundLayer.DUG_TERRAIN)


## Wall pass (one batched terrain-connect call -- see class doc for why it's
## never split) + base cap pass. removed_wall_cells in mutation_record (world
## cells) are excluded entirely, so a previously-mined cell paints as open
## floor from the start rather than flashing wall-then-erased. Returns the
## painted wall cells (world coords) for the ore overlay pass.
func _paint_wall_and_base_pass(data: CaveData, world_offset: Vector2i, mutation_record: Dictionary = {}) -> Array[Vector2i]:
	var removed := _world_cell_set(mutation_record.get("removed_wall_cells", []))
	var wall_cells: Array[Vector2i] = []
	for cell in _wall_cells_for(data, world_offset):
		if not removed.has(cell):
			wall_cells.append(cell)

	walls_layer.set_cells_terrain_connect(wall_cells, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN)

	# CaveWallsLayer's own `changed`-signal auto-sync isn't guaranteed
	# synchronous -- call compute_base_tiles() explicitly so the result is
	# correct the instant this function returns.
	var base_tiles := CaveWallBase.compute_base_tiles(wall_cells)
	for cell: Vector2i in base_tiles:
		walls_layer.set_cell(cell, CaveWallsLayer.TILESET_SOURCE_ID, base_tiles[cell])
		# Base cap cells sit one row below their wall cell, which can fall
		# just past this chunk's own bottom edge (a wall cell at the last
		# row has no listed wall below it, so it still gets a cap) -- the
		# ground pass never reaches that row, so patch it in here too.
		if ground_layer.get_cell_source_id(cell) == -1:
			ground_layer.set_cell(cell, PLAIN_FLOOR_SOURCE_ID, PLAIN_FLOOR_ATLAS_COORDS)
	return wall_cells


## Must run after the wall pass, since mark_ore_cell() checks is_wall_cell().
func _paint_ore_overlay_pass(data: CaveData, world_offset: Vector2i, wall_cells: Array[Vector2i]) -> void:
	var ore_types_by_tile := _build_ore_type_lookup()
	if ore_types_by_tile.is_empty():
		return
	var wall_cell_set := {}
	for cell in wall_cells:
		wall_cell_set[cell] = true
	for y in range(data.height):
		for x in range(data.width):
			var local_cell := Vector2i(x, y)
			var tile_type := data.get_tile(local_cell)
			if not ore_types_by_tile.has(tile_type):
				continue
			var world_cell := world_offset + local_cell
			if wall_cell_set.has(world_cell):
				ore_overlay_layer.mark_ore_cell(world_cell, ore_types_by_tile[tile_type])


## Lava is deliberately not painted here (see class doc) -- no tile art
## exists for it yet.
func _paint_liquids_pass(data: CaveData, world_offset: Vector2i) -> void:
	for cell in _water_cells_for(data, world_offset):
		liquids_layer.set_cell(cell, WATER_SOURCE_ID, WATER_ATLAS_COORDS)


## Mirrors OreNodeGenerator._spawn_node()'s scene-instancing exactly; only
## the placement logic (seeded + rarity-weighted, computed in CaveGenerator)
## is new, not the object identity or rendering. ore_node_records (world-cell
## keyed, see CaveChunkStreamer) re-applies a previously depleted/damaged
## node's saved state via apply_save_data() rather than spawning it fresh.
## is_chunked opts the instance out of self-registering into "saveable" --
## only correct for the chunk-streaming path, where CaveChunkStreamer owns
## capturing/restoring this state itself (see clear_chunk()); the legacy
## whole-map generate_and_build() path has no streamer, so it must keep the
## normal self-registration behavior.
func _instance_ore_nodes(data: CaveData, world_offset: Vector2i, ore_node_records: Dictionary, is_chunked: bool) -> Array[Node2D]:
	var instances: Array[Node2D] = []
	for local_cell: Vector2i in data.ore_node_placements:
		var node_type: OreNodeType = data.ore_node_placements[local_cell]
		var world_cell := world_offset + local_cell
		var instance: Node2D = node_type.scene.instantiate()
		instance.position = objects_layer.map_to_local(world_cell)
		if is_chunked and "self_register_saveable" in instance:
			instance.self_register_saveable = false
		objects_layer.add_child(instance)
		var record_key := "%d,%d" % [world_cell.x, world_cell.y]
		if ore_node_records.has(record_key) and instance.has_method("apply_save_data"):
			instance.apply_save_data(ore_node_records[record_key])
		instances.append(instance)
	return instances


func _build_ore_type_lookup() -> Dictionary:
	var lookup := {}
	for vein_config in config.ore_veins:
		if vein_config == null or vein_config.ore_type == null:
			continue
		lookup[CaveOreVeinConfig.slot_to_tile_type(vein_config.ore_slot)] = vein_config.ore_type
	return lookup


func _world_cell_set(entries: Array) -> Dictionary:
	var cell_set := {}
	for entry in entries:
		cell_set[Vector2i(entry.get("x", 0), entry.get("y", 0))] = true
	return cell_set
