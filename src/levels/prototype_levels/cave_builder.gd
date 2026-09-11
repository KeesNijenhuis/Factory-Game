class_name CaveBuilder
extends Node
## Runtime consumer of CaveGenerator's output: paints a CaveData onto the
## real cave TileSet layers and scatters pickable ore node scenes. This is
## the second half of the two-phase pipeline -- CaveGenerator is pure data,
## this is what actually touches TileMapLayer.
##
## build_chunk()/build_chunk_async()/clear_chunk() are the streaming entry
## points CaveChunkStreamer drives, each operating on one chunk's cells at
## its world offset on the SAME shared layers every other chunk paints onto
## (confirmed correct over per-chunk layers: TileMapLayer cell storage is
## sparse, so there's no memory cost to a large logical world, and
## terrain-autoconnect only ever sees neighbors on the same layer instance --
## per-chunk layers would make cross-chunk wall shapes unreconcilable).
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
## Generated wall cells use CaveWallsLayer's direct terrain-peering lookup,
## avoiding the expensive bulk terrain solver. If a tileset has incomplete
## metadata the layer falls back to set_cells_terrain_connect(). All other
## paint passes are safe to budget across frames -- see build_chunk_async().

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
## Maximum number of generated tile writes per frame on the asynchronous
## streaming path. Wall terrain is selected directly from peering bits, so it
## can also be safely split when the lookup is available.
@export var async_paint_cells_per_frame: int = 256

var walls_layer: CaveWallsLayer
var ground_layer: CaveGroundLayer
var ore_overlay_layer: CaveOreOverlayLayer
var liquids_layer: TileMapLayer
var objects_layer: TileMapLayer

## chunk_coord -> Array[Node2D], ore node instances owned by each currently-
## built chunk -- lets clear_chunk() free exactly (and only) the ones this
## chunk placed, without scanning/filtering objects_layer's whole child list.
var _chunk_object_instances: Dictionary = {}
var _ore_types_by_tile: Dictionary = {}
## Cached, reusable pattern of a whole chunk's worth of the uniform plain-floor
## tile -- see _get_ground_pattern(). Rebuilt lazily whenever config's chunk
## size doesn't match the cached pattern's, so it stays correct across
## set_generation_config() (streaming).
var _ground_pattern: TileMapPattern
var _ground_pattern_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	walls_layer = get_node(walls_layer_path)
	ground_layer = get_node(ground_layer_path)
	ore_overlay_layer = get_node(ore_overlay_layer_path)
	liquids_layer = get_node(liquids_layer_path)
	objects_layer = get_node(objects_layer_path)
	_ore_types_by_tile = _build_ore_type_lookup()


## The streaming scene assigns its chunk config after this node's _ready()
## (the scene keeps a lightweight placeholder config for editor previews).
## Refreshing the derived lookup here is required for generated ore veins to
## reach CaveOreOverlayLayer in streamed chunks.
func set_generation_config(generation_config: CaveGenerationConfig) -> void:
	config = generation_config
	_ore_types_by_tile = _build_ore_type_lookup()


## Synchronous chunk build: generates + paints chunk_coord with no yields --
## required for the initial spawn-radius load, since ProceduralCaveLevel's
## _ready() must finish before MainGame reads the level's default player
## spawn (see CaveChunkStreamer.load_initial_chunks()).
##
## mutation_record (see CaveChunkStreamer for its shape) excludes previously
## mined/dug cells from the fresh paint and restores depleted/damaged ore
## nodes, so a rebuilt chunk shows exactly what the player left behind
## rather than pristine terrain.
func build_chunk(
	chunk_coord: Vector2i,
	world_seed: int,
	mutation_record: Dictionary = {},
	cached_data: CaveData = null
) -> CaveData:
	var total_start := Time.get_ticks_usec()
	var data: CaveData = cached_data
	if data == null:
		data = CaveGenerator.generate_chunk(config, chunk_coord, world_seed)
	var generation_done := Time.get_ticks_usec()
	var world_offset := _chunk_world_offset(chunk_coord)
	_paint_ground_pass(data, world_offset, mutation_record)
	var ground_done := Time.get_ticks_usec()
	var wall_start := Time.get_ticks_usec()
	var wall_cells := _paint_wall_and_base_pass(data, world_offset, mutation_record)
	var wall_done := Time.get_ticks_usec()
	var ore_start := Time.get_ticks_usec()
	_paint_ore_overlay_pass(data, world_offset, wall_cells)
	var ore_done := Time.get_ticks_usec()
	var liquid_start := Time.get_ticks_usec()
	_paint_liquids_pass(data, world_offset)
	var liquid_done := Time.get_ticks_usec()
	var node_start := Time.get_ticks_usec()
	_chunk_object_instances[chunk_coord] = _instance_ore_nodes(data, world_offset, mutation_record.get("ore_nodes", {}))
	var node_done := Time.get_ticks_usec()
	var boundary_start := Time.get_ticks_usec()
	_refresh_chunk_boundary(chunk_coord)
	if DebugSettings.profile_cave_generation:
		print("CaveChunkProfile phase=complete chunk=(%d,%d) generation_ms=%.1f ground_ms=%.1f wall_ms=%.1f ore_ms=%.1f liquids_ms=%.1f nodes_ms=%.1f boundary_ms=%.1f total_ms=%.1f" % [
			chunk_coord.x, chunk_coord.y, (generation_done - total_start) / 1000.0,
			(ground_done - generation_done) / 1000.0, (wall_done - wall_start) / 1000.0,
			(ore_done - ore_start) / 1000.0, (liquid_done - liquid_start) / 1000.0,
			(node_done - node_start) / 1000.0, _elapsed_ms(boundary_start), _elapsed_ms(total_start),
		])
	return data


## Steady-state chunk build: same result as build_chunk(), but yields after
## bounded paint batches so a chunk load never costs more than one small
## uninterrupted frame at a time. Pure CaveData generation stays on the main
## thread; only scene-safe painting is spread across frames.
func build_chunk_async(
	chunk_coord: Vector2i,
	world_seed: int,
	mutation_record: Dictionary = {},
	should_continue: Callable = Callable(),
	cached_data: CaveData = null
) -> CaveData:
	var total_start := Time.get_ticks_usec()
	var data: CaveData = cached_data
	if data == null:
		data = CaveGenerator.generate_chunk(config, chunk_coord, world_seed)
	var world_offset := _chunk_world_offset(chunk_coord)
	var generation_done := Time.get_ticks_usec()
	await get_tree().process_frame
	if _load_cancelled(should_continue):
		clear_chunk(chunk_coord, data)
		return null
	var ground_start := Time.get_ticks_usec()
	_paint_ground_pass(data, world_offset, mutation_record)
	var ground_done := Time.get_ticks_usec()
	await get_tree().process_frame
	if _load_cancelled(should_continue):
		clear_chunk(chunk_coord, data)
		return null
	var wall_start := Time.get_ticks_usec()
	var wall_cells := await _paint_wall_and_base_pass_async(data, world_offset, mutation_record)
	var wall_done := Time.get_ticks_usec()
	await get_tree().process_frame
	if _load_cancelled(should_continue):
		clear_chunk(chunk_coord, data)
		return null
	var ore_start := Time.get_ticks_usec()
	await _paint_ore_overlay_pass_async(data, world_offset, wall_cells)
	var ore_done := Time.get_ticks_usec()
	await get_tree().process_frame
	if _load_cancelled(should_continue):
		clear_chunk(chunk_coord, data)
		return null
	var liquid_start := Time.get_ticks_usec()
	await _paint_liquids_pass_async(data, world_offset)
	var liquid_done := Time.get_ticks_usec()
	await get_tree().process_frame
	if _load_cancelled(should_continue):
		clear_chunk(chunk_coord, data)
		return null
	var node_start := Time.get_ticks_usec()
	_chunk_object_instances[chunk_coord] = _instance_ore_nodes(data, world_offset, mutation_record.get("ore_nodes", {}))
	var node_done := Time.get_ticks_usec()
	var boundary_start := Time.get_ticks_usec()
	_refresh_chunk_boundary(chunk_coord)
	if DebugSettings.profile_cave_generation:
		print("CaveChunkProfile phase=complete chunk=(%d,%d) generation_ms=%.1f ground_ms=%.1f wall_ms=%.1f ore_ms=%.1f liquids_ms=%.1f nodes_ms=%.1f boundary_ms=%.1f total_ms=%.1f" % [
			chunk_coord.x, chunk_coord.y, (generation_done - total_start) / 1000.0,
			(ground_done - generation_done) / 1000.0, (wall_done - wall_start) / 1000.0,
			(ore_done - ore_start) / 1000.0, (liquid_done - liquid_start) / 1000.0,
			(node_done - node_start) / 1000.0, _elapsed_ms(boundary_start), _elapsed_ms(total_start),
		])
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

	var ore_node_records := get_chunk_ore_node_records(chunk_coord)
	for instance in _chunk_object_instances.get(chunk_coord, []):
		if not is_instance_valid(instance):
			continue
		instance.queue_free()
	_chunk_object_instances.erase(chunk_coord)

	_refresh_chunk_boundary(chunk_coord)
	return ore_node_records


## Captures live ore-node state without removing the instances. SaveManager
## can call this while a chunk is still loaded, so mining/damage remains
## persistent even when the player saves before crossing the unload radius.
func get_chunk_ore_node_records(chunk_coord: Vector2i) -> Dictionary:
	var records := {}
	for instance in _chunk_object_instances.get(chunk_coord, []):
		if not is_instance_valid(instance) or not instance.has_method("get_save_data"):
			continue
		var world_cell: Vector2i = objects_layer.local_to_map(instance.position)
		records["%d,%d" % [world_cell.x, world_cell.y]] = instance.get_save_data()
	return records


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
	var strips: Array[Rect2i] = []
	if _edge_has_wall(world_offset, Vector2i(0, -1), chunk_size.x):
		strips.append(Rect2i(world_offset.x, world_offset.y - 1, chunk_size.x, 2))
	if _edge_has_wall(world_offset + Vector2i(0, chunk_size.y - 1), Vector2i(0, 1), chunk_size.x):
		strips.append(Rect2i(world_offset.x, world_offset.y + chunk_size.y - 1, chunk_size.x, 2))
	if _edge_has_wall(world_offset, Vector2i(-1, 0), chunk_size.y, false):
		strips.append(Rect2i(world_offset.x - 1, world_offset.y, 2, chunk_size.y))
	if _edge_has_wall(world_offset + Vector2i(chunk_size.x - 1, 0), Vector2i(1, 0), chunk_size.y, false):
		strips.append(Rect2i(world_offset.x + chunk_size.x - 1, world_offset.y, 2, chunk_size.y))

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
	if not walls_layer.refresh_wall_cells_direct(cells):
		# Erase first -- terrain_connect is otherwise a no-op for an already
		# painted cell and would leave a stale seam shape.
		for cell in cells:
			walls_layer.erase_cell(cell)
		walls_layer.set_cells_terrain_connect(cells, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN)
	# Base caps are decorative atlas tiles rather than terrain-connected tiles,
	# so derive their shape from the complete live layer. The old
	# boundary_wall_cells-only lookup missed horizontal neighbors on the
	# left/right strips and left the south edge with a stale cap when a
	# neighboring chunk loaded or unloaded.
	walls_layer.refresh_base_tiles_around(cells)
	ore_overlay_layer.resync_around(cells)


func _edge_has_wall(edge_start: Vector2i, outside_step: Vector2i, length: int, horizontal: bool = true) -> bool:
	for index in range(length):
		var edge_cell := edge_start + (Vector2i(index, 0) if horizontal else Vector2i(0, index))
		if walls_layer.is_wall_cell(edge_cell + outside_step):
			return true
	return false


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
func _paint_ground_pass(_data: CaveData, world_offset: Vector2i, mutation_record: Dictionary) -> void:
	ground_layer.set_pattern(world_offset, _get_ground_pattern())
	var dug_cells: Array = mutation_record.get("dug_ground_cells", [])
	if not dug_cells.is_empty():
		var to_dig := _world_cell_set(dug_cells).keys()
		ground_layer.set_cells_terrain_connect(Array(to_dig, TYPE_VECTOR2I, "", null), CaveGroundLayer.TERRAIN_SET, CaveGroundLayer.DUG_TERRAIN)


## Cached whole-chunk pattern of the uniform plain-floor tile, rebuilt
## whenever config's chunk size doesn't match what's cached.
func _get_ground_pattern() -> TileMapPattern:
	var size := Vector2i(config.map_width, config.map_height)
	if _ground_pattern == null or _ground_pattern_size != size:
		var pattern := TileMapPattern.new()
		for y in range(size.y):
			for x in range(size.x):
				# TileMapPattern.set_cell()'s alternative_tile parameter
				# defaults to -1 (an empty/invalid cell), unlike
				# TileMapLayer.set_cell()'s default of 0 -- must be passed
				# explicitly or set_pattern() pastes nothing.
				pattern.set_cell(Vector2i(x, y), PLAIN_FLOOR_SOURCE_ID, PLAIN_FLOOR_ATLAS_COORDS, 0)
		_ground_pattern = pattern
		_ground_pattern_size = size
	return _ground_pattern


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

	if not walls_layer.set_wall_cells_direct(wall_cells, wall_cells):
		walls_layer.set_cells_terrain_connect(wall_cells, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN)

	# CaveWallsLayer's own `changed`-signal auto-sync isn't guaranteed
	# synchronous -- call compute_base_tiles() explicitly so the result is
	# correct the instant this function returns.
	var base_tiles := CaveWallBase.compute_base_tiles(wall_cells)
	walls_layer.set_base_tiles_direct(base_tiles, false)
	for cell: Vector2i in base_tiles:
		# Base cap cells sit one row below their wall cell, which can fall
		# just past this chunk's own bottom edge (a wall cell at the last
		# row has no listed wall below it, so it still gets a cap) -- the
		# ground pass never reaches that row, so patch it in here too.
		if ground_layer.get_cell_source_id(cell) == -1:
			ground_layer.set_cell(cell, PLAIN_FLOOR_SOURCE_ID, PLAIN_FLOOR_ATLAS_COORDS)
	return wall_cells


func _paint_wall_and_base_pass_async(
	data: CaveData, world_offset: Vector2i, mutation_record: Dictionary = {}
) -> Array[Vector2i]:
	var removed := _world_cell_set(mutation_record.get("removed_wall_cells", []))
	var wall_cells: Array[Vector2i] = []
	for cell in _wall_cells_for(data, world_offset):
		if not removed.has(cell):
			wall_cells.append(cell)

	if walls_layer.has_direct_wall_lookup():
		var batch: Array[Vector2i] = []
		var painted := 0
		for cell in wall_cells:
			batch.append(cell)
			painted += 1
			if painted >= maxi(1, async_paint_cells_per_frame):
				walls_layer.set_wall_cells_direct(batch, wall_cells)
				batch.clear()
				painted = 0
				await get_tree().process_frame
		if not batch.is_empty():
			walls_layer.set_wall_cells_direct(batch, wall_cells)
	else:
		walls_layer.set_cells_terrain_connect(wall_cells, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN)

	var base_tiles := CaveWallBase.compute_base_tiles(wall_cells)
	for cell: Vector2i in base_tiles:
		walls_layer.set_cell(cell, CaveWallsLayer.TILESET_SOURCE_ID, base_tiles[cell])
		if ground_layer.get_cell_source_id(cell) == -1:
			ground_layer.set_cell(cell, PLAIN_FLOOR_SOURCE_ID, PLAIN_FLOOR_ATLAS_COORDS)
	return wall_cells


## Must run after the wall pass, since mark_ore_cell() checks is_wall_cell().
func _paint_ore_overlay_pass(data: CaveData, world_offset: Vector2i, wall_cells: Array[Vector2i]) -> void:
	var ore_types_by_tile := _ore_types_by_tile
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


func _paint_ore_overlay_pass_async(data: CaveData, world_offset: Vector2i, wall_cells: Array[Vector2i]) -> void:
	var ore_types_by_tile := _ore_types_by_tile
	if ore_types_by_tile.is_empty():
		return
	var wall_cell_set := {}
	for cell in wall_cells:
		wall_cell_set[cell] = true
	var painted := 0
	for y in range(data.height):
		for x in range(data.width):
			var local_cell := Vector2i(x, y)
			var tile_type := data.get_tile(local_cell)
			if ore_types_by_tile.has(tile_type):
				var world_cell := world_offset + local_cell
				if wall_cell_set.has(world_cell):
					ore_overlay_layer.mark_ore_cell(world_cell, ore_types_by_tile[tile_type])
			painted += 1
			if painted >= maxi(1, async_paint_cells_per_frame):
				painted = 0
				await get_tree().process_frame


## Lava is deliberately not painted here (see class doc) -- no tile art
## exists for it yet.
func _paint_liquids_pass(data: CaveData, world_offset: Vector2i) -> void:
	for cell in _water_cells_for(data, world_offset):
		liquids_layer.set_cell(cell, WATER_SOURCE_ID, WATER_ATLAS_COORDS)


func _paint_liquids_pass_async(data: CaveData, world_offset: Vector2i) -> void:
	var painted := 0
	for cell in _water_cells_for(data, world_offset):
		liquids_layer.set_cell(cell, WATER_SOURCE_ID, WATER_ATLAS_COORDS)
		painted += 1
		if painted >= maxi(1, async_paint_cells_per_frame):
			painted = 0
			await get_tree().process_frame


## Mirrors OreNodeGenerator._spawn_node()'s scene-instancing exactly; only
## the placement logic (seeded + rarity-weighted, computed in CaveGenerator)
## is new, not the object identity or rendering. ore_node_records (world-cell
## keyed, see CaveChunkStreamer) re-applies a previously depleted/damaged
## node's saved state via apply_save_data() rather than spawning it fresh.
## Opts the instance out of self-registering into "saveable" -- CaveChunkStreamer
## owns capturing/restoring this state itself instead (see clear_chunk()).
func _instance_ore_nodes(data: CaveData, world_offset: Vector2i, ore_node_records: Dictionary) -> Array[Node2D]:
	var instances: Array[Node2D] = []
	for local_cell: Vector2i in data.ore_node_placements:
		var node_type: OreNodeType = data.ore_node_placements[local_cell]
		var world_cell := world_offset + local_cell
		var instance: Node2D = node_type.scene.instantiate()
		instance.position = objects_layer.map_to_local(world_cell)
		if "self_register_saveable" in instance:
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


func _load_cancelled(should_continue: Callable) -> bool:
	return should_continue.is_valid() and not should_continue.call()


func _world_cell_set(entries: Array) -> Dictionary:
	var cell_set := {}
	for entry in entries:
		cell_set[Vector2i(entry.get("x", 0), entry.get("y", 0))] = true
	return cell_set
