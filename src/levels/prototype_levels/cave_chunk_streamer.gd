class_name CaveChunkStreamer
extends Node
## Loads/unloads cave chunks around the player as they move, driving
## CaveBuilder's chunk API. Not under src/core/generation/ -- that folder is
## explicitly pure-data/zero-scene-tree-dependency, and this owns a
## _process() and talks to the live player/CaveBuilder throughout.
##
## Two load paths:
## - load_initial_chunks() -- fully synchronous, no yields anywhere. Called
##   once by ProceduralCaveLevel._ready(), which must finish before
##   MainGame reads the level's default player spawn.
## - Steady-state _process() -- budgeted. At most
##   streaming_config.max_chunk_loads_in_flight chunk builds run at once,
##   each via CaveBuilder.build_chunk_async() (which yields between every
##   paint pass except the one atomic wall-terrain-connect call -- see
##   CaveBuilder's class doc for why that one is never split). A
##   preload_margin_chunks ring is queued proactively, before the player is
##   near the load radius's edge, so a chunk's cost is paid off-screen
##   rather than at the exact moment it should already be visible.
##
## Chunk unload uses hysteresis (keep_radius_chunks > load_radius_chunks +
## preload_margin_chunks) so a player oscillating right at a boundary
## doesn't repeatedly load/unload the same chunk.

@export var streaming_config: CaveWorldStreamingConfig
@export var cave_builder_path: NodePath

var cave_builder: CaveBuilder
## Not a scene-relative NodePath -- Player lives under MainGame's
## entity_root, not under this level, so it's resolved the same way
## PlayerStateDigging._get_ground_layer() looks up the current level: via
## MainGame, which is always the current_scene (see project.godot's
## run/main_scene). Safe to resolve in _ready(): MainGame._init_player()
## runs synchronously before load_level() is even called, well before this
## level's _ready() fires.
var player: Node2D

var _world_seed: int
var _loaded_chunks: Dictionary = {} ## Vector2i chunk_coord -> CaveData
## chunk_coord -> mutation record (see CaveBuilder.build_chunk); populated
## starting Milestone 4 -- an empty/missing entry just means "no mutations
## recorded for this chunk yet," which build_chunk()/build_chunk_async()
## already treat as a no-op exclusion set.
var _mutations: Dictionary = {}

var _pending_loads: Array[Vector2i] = []
var _pending_load_set: Dictionary = {} ## Vector2i -> true, O(1) "already queued" checks
var _in_flight_count: int = 0
## Sentinel far outside any real chunk coordinate, so the first _process()
## tick always recomputes the active set even if the player happens to be
## sitting exactly on Vector2i.ZERO.
var _current_center_chunk: Vector2i = Vector2i(1 << 30, 1 << 30)


func _ready() -> void:
	# The single "saveable" node for a chunk-streamed level -- see
	# CaveWallsLayer.self_register_saveable's doc comment for why the
	# per-layer/per-object self-registration this supersedes doesn't work
	# once only nearby chunks are loaded.
	add_to_group("saveable")
	cave_builder = get_node(cave_builder_path)
	var main_game := get_tree().current_scene as MainGame
	if main_game == null or main_game.player == null:
		push_error("CaveChunkStreamer: could not resolve the player via MainGame.")
	else:
		player = main_game.player
	# Forwarded programmatically (not relied on via scene-file wiring) so
	# CaveBuilder can never end up painting with a different chunk size than
	# the streamer is doing coordinate math against.
	cave_builder.config = streaming_config.chunk_config
	_world_seed = streaming_config.seed if streaming_config.seed != 0 else randi()
	cave_builder.walls_layer.cell_removed.connect(_on_wall_cell_removed)
	cave_builder.ground_layer.cell_dug.connect(_on_ground_cell_dug)


func chunk_size() -> Vector2i:
	return Vector2i(streaming_config.chunk_config.map_width, streaming_config.chunk_config.map_height)


## Builds every chunk within initial_load_radius_chunks of spawn_chunk_coord
## synchronously (no yields anywhere -- see class doc), then queues the
## wider preload ring for steady-state pickup. Returns the spawn chunk's
## entrance translated to world/global coordinates.
func load_initial_chunks(spawn_chunk_coord: Vector2i) -> Vector2:
	var radius := streaming_config.initial_load_radius_chunks
	var spawn_data: CaveData = null
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var coord := spawn_chunk_coord + Vector2i(x, y)
			var data := cave_builder.build_chunk(coord, _world_seed, _mutations.get(coord, {}))
			_loaded_chunks[coord] = data
			if coord == spawn_chunk_coord:
				spawn_data = data

	_current_center_chunk = spawn_chunk_coord
	_recompute_active_set(spawn_chunk_coord)

	var world_offset := spawn_chunk_coord * chunk_size()
	var entrance_cell := world_offset + spawn_data.entrance_position
	return cave_builder.ground_layer.to_global(cave_builder.ground_layer.map_to_local(entrance_cell))


func _process(_delta: float) -> void:
	if player == null or cave_builder == null:
		return

	var player_cell: Vector2i = cave_builder.ground_layer.local_to_map(cave_builder.ground_layer.to_local(player.global_position))
	var player_chunk := _cell_to_chunk_coord(player_cell)
	if player_chunk != _current_center_chunk:
		_current_center_chunk = player_chunk
		_recompute_active_set(player_chunk)

	while _in_flight_count < streaming_config.max_chunk_loads_in_flight and not _pending_loads.is_empty():
		var coord: Vector2i = _pending_loads.pop_front()
		_pending_load_set.erase(coord)
		if _loaded_chunks.has(coord):
			continue
		_in_flight_count += 1
		_load_chunk_async(coord)


func _cell_to_chunk_coord(cell: Vector2i) -> Vector2i:
	var size := chunk_size()
	return Vector2i(floori(float(cell.x) / size.x), floori(float(cell.y) / size.y))


func _recompute_active_set(center: Vector2i) -> void:
	var want_radius := streaming_config.load_radius_chunks + streaming_config.preload_margin_chunks
	for y in range(-want_radius, want_radius + 1):
		for x in range(-want_radius, want_radius + 1):
			var coord := center + Vector2i(x, y)
			if _loaded_chunks.has(coord) or _pending_load_set.has(coord):
				continue
			_pending_loads.append(coord)
			_pending_load_set[coord] = true
	_pending_loads.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, center) < _chebyshev(b, center))

	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks:
		if _chebyshev(coord, center) > streaming_config.keep_radius_chunks:
			to_unload.append(coord)
	for coord in to_unload:
		var data: CaveData = _loaded_chunks[coord]
		var ore_node_records: Dictionary = cave_builder.clear_chunk(coord, data)
		if not ore_node_records.is_empty():
			var record: Dictionary = _mutations.get(coord, {})
			var existing_ore: Dictionary = record.get("ore_nodes", {})
			for key in ore_node_records:
				existing_ore[key] = ore_node_records[key]
			record["ore_nodes"] = existing_ore
			_mutations[coord] = record
		_loaded_chunks.erase(coord)

	# Drop any now-out-of-range pending loads so we never load something
	# we'd immediately turn around and unload.
	var still_pending: Array[Vector2i] = []
	for coord in _pending_loads:
		if _chebyshev(coord, center) <= want_radius:
			still_pending.append(coord)
		else:
			_pending_load_set.erase(coord)
	_pending_loads = still_pending


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _load_chunk_async(coord: Vector2i) -> void:
	var data: CaveData = await cave_builder.build_chunk_async(coord, _world_seed, _mutations.get(coord, {}))
	_loaded_chunks[coord] = data
	_in_flight_count -= 1


func _on_wall_cell_removed(cell: Vector2i) -> void:
	_record_mutation(cell, "removed_wall_cells")


func _on_ground_cell_dug(cell: Vector2i) -> void:
	_record_mutation(cell, "dug_ground_cells")


## The Walls/Ground TileMapLayers' signals are shared across every chunk
## (one instance for the whole level), so this is the one place that
## buckets a raw world-cell event into its owning chunk's mutation record.
func _record_mutation(cell: Vector2i, key: String) -> void:
	var coord := _cell_to_chunk_coord(cell)
	var record: Dictionary = _mutations.get(coord, {})
	var cells: Array = record.get(key, [])
	cells.append({"x": cell.x, "y": cell.y})
	record[key] = cells
	_mutations[coord] = record


func get_save_id() -> String:
	return "cave_chunk_streamer"


## Every chunk ever touched gets saved, not just currently-loaded ones --
## mutations for a chunk the player wandered away from must survive too.
func get_save_data() -> Dictionary:
	var chunks := {}
	for coord: Vector2i in _mutations:
		chunks["%d,%d" % [coord.x, coord.y]] = _mutations[coord]
	return {"world_seed": _world_seed, "chunks": chunks}


## Restores world_seed and every chunk's mutation record. Chunks already
## built by the time this runs (the synchronous initial-load radius from
## load_initial_chunks(), which fires during level load -- before
## SaveManager gets around to applying saved data, see the class doc) were
## necessarily built against an empty mutation record and, if world_seed
## was randomized, possibly even a different seed than the save's -- so
## they're force-rebuilt here against the now-correct data. This only
## affects the small initial-radius set; player position itself restores
## independently from the save's own recorded global_position, not from any
## chunk's entrance, so spawn correctness doesn't depend on this ordering.
func apply_save_data(data: Dictionary) -> void:
	_world_seed = data.get("world_seed", _world_seed)
	var chunks: Dictionary = data.get("chunks", {})
	_mutations.clear()
	for key: String in chunks:
		var parts := key.split(",")
		_mutations[Vector2i(int(parts[0]), int(parts[1]))] = chunks[key]

	for coord: Vector2i in _loaded_chunks.keys():
		var stale_data: CaveData = _loaded_chunks[coord]
		cave_builder.clear_chunk(coord, stale_data)
		_loaded_chunks[coord] = cave_builder.build_chunk(coord, _world_seed, _mutations.get(coord, {}))
