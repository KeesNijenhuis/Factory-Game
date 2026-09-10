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
## Chunk unload uses hysteresis plus a bounded grace-period/LRU cache, so a
## player oscillating right at a boundary keeps the painted chunk alive briefly
## and then reuses pure CaveData instead of regenerating it.

@export var streaming_config: CaveWorldStreamingConfig
@export var cave_builder_path: NodePath

const CACHE_VERSION: int = 1
const CACHE_ROOT: String = "user://cave_chunk_cache/"

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
## Complete generated chunk data belonging to this world/save. Unlike the
## bounded painted-data caches below, this is never evicted.
var _generated_chunks: Dictionary = {} ## Vector2i chunk_coord -> CaveData
var _retained_chunks: Dictionary = {} ## bounded LRU: Vector2i -> CaveData
var _retained_lru: Array[Vector2i] = []
var _unload_deadlines: Dictionary = {} ## Vector2i -> monotonic deadline (msec)
var _unload_order: Array[Vector2i] = []
## chunk_coord -> mutation record (see CaveBuilder.build_chunk); populated
## starting Milestone 4 -- an empty/missing entry just means "no mutations
## recorded for this chunk yet," which build_chunk()/build_chunk_async()
## already treat as a no-op exclusion set.
var _mutations: Dictionary = {}

var _pending_loads: Array[Vector2i] = []
var _pending_load_set: Dictionary = {} ## Vector2i -> true, O(1) "already queued" checks
var _in_flight: Dictionary = {} ## Vector2i -> request token
var _next_request_token: int = 0
var _desired_load_set: Dictionary = {}
var _stream_revision: int = 0
## Sentinel far outside any real chunk coordinate, so the first _process()
## tick always recomputes the active set even if the player happens to be
## sitting exactly on Vector2i.ZERO.
var _current_center_chunk: Vector2i = Vector2i(1 << 30, 1 << 30)
var _cache_namespace: String = ""


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
	cave_builder.set_generation_config(streaming_config.chunk_config)
	_world_seed = streaming_config.seed if streaming_config.seed != 0 else randi()
	prepare_startup_world_data(SaveManager.consume_startup_world_data())
	_cache_namespace = _build_cache_namespace()
	cave_builder.walls_layer.cell_removed.connect(_on_wall_cell_removed)
	cave_builder.ground_layer.cell_dug.connect(_on_ground_cell_dug)


func prepare_startup_world_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	_world_seed = int(data.get("world_seed", _world_seed))
	_mutations.clear()
	for key: String in data.get("chunks", {}):
		var parts := key.split(",")
		if parts.size() == 2:
			_mutations[Vector2i(int(parts[0]), int(parts[1]))] = data["chunks"][key]
	_generated_chunks.clear()
	_restore_generated_chunks(data.get("generated_chunks", {}))


func chunk_size() -> Vector2i:
	return Vector2i(streaming_config.chunk_config.map_width, streaming_config.chunk_config.map_height)


func get_initial_grid_rect() -> Rect2:
	var radius := streaming_config.initial_load_radius_chunks
	var size := chunk_size()
	var top_left := Vector2i(-radius, -radius) * size
	var grid_size := Vector2i(radius * 2 + 1, radius * 2 + 1) * size
	var local_top_left := cave_builder.ground_layer.map_to_local(top_left)
	var local_bottom_right := cave_builder.ground_layer.map_to_local(top_left + grid_size)
	var world_top_left := cave_builder.ground_layer.to_global(local_top_left)
	var world_bottom_right := cave_builder.ground_layer.to_global(local_bottom_right)
	return Rect2(world_top_left, world_bottom_right - world_top_left)


## Builds every chunk within initial_load_radius_chunks of spawn_chunk_coord
## synchronously (no yields anywhere -- see class doc), then queues the
## wider preload ring for steady-state pickup. Returns the spawn chunk's
## entrance translated to world/global coordinates.
func load_initial_chunks(spawn_chunk_coord: Vector2i) -> Vector2:
	var total_start := Time.get_ticks_usec()
	var radius := streaming_config.initial_load_radius_chunks
	var spawn_data: CaveData = null
	var chunk_count := 0
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var coord := spawn_chunk_coord + Vector2i(x, y)
			var cached_data: CaveData = _generated_chunks.get(coord, _read_cached_chunk(coord))
			var data := cave_builder.build_chunk(coord, _world_seed, _mutations.get(coord, {}), cached_data)
			if cached_data == null:
				_write_cached_chunk(coord, data)
			_generated_chunks[coord] = data
			_loaded_chunks[coord] = data
			chunk_count += 1
			if coord == spawn_chunk_coord:
				spawn_data = data

	_current_center_chunk = spawn_chunk_coord
	_recompute_active_set(spawn_chunk_coord)
	print("CaveChunkStreamer: initial grid generated %d chunks in %.1f ms" % [
		chunk_count,
		(Time.get_ticks_usec() - total_start) / 1000.0,
	])

	var world_offset := spawn_chunk_coord * chunk_size()
	var entrance_cell := world_offset + spawn_data.entrance_position
	return cave_builder.ground_layer.to_global(cave_builder.ground_layer.map_to_local(entrance_cell))


func _process(_delta: float) -> void:
	if player == null or cave_builder == null:
		return

	_expire_chunk_grace_periods()
	var player_cell: Vector2i = cave_builder.ground_layer.local_to_map(cave_builder.ground_layer.to_local(player.global_position))
	var player_chunk := _cell_to_chunk_coord(player_cell)
	if player_chunk != _current_center_chunk:
		_current_center_chunk = player_chunk
		_recompute_active_set(player_chunk)

	while _in_flight.size() < maxi(1, streaming_config.max_chunk_loads_in_flight) and not _pending_loads.is_empty():
		var coord: Vector2i = _pending_loads.pop_front()
		_pending_load_set.erase(coord)
		if _loaded_chunks.has(coord) or not _desired_load_set.has(coord):
			continue
		_next_request_token += 1
		var request_token := _next_request_token
		_in_flight[coord] = request_token
		_load_chunk_async(coord, request_token, _stream_revision)


func _cell_to_chunk_coord(cell: Vector2i) -> Vector2i:
	var size := chunk_size()
	return Vector2i(floori(float(cell.x) / size.x), floori(float(cell.y) / size.y))


func _recompute_active_set(center: Vector2i) -> void:
	var want_radius := streaming_config.load_radius_chunks + streaming_config.preload_margin_chunks
	_desired_load_set.clear()
	for y in range(-want_radius, want_radius + 1):
		for x in range(-want_radius, want_radius + 1):
			var coord := center + Vector2i(x, y)
			_desired_load_set[coord] = true
			_cancel_grace_period(coord)
			if _loaded_chunks.has(coord) or _pending_load_set.has(coord):
				continue
			_pending_loads.append(coord)
			_pending_load_set[coord] = true
	_pending_loads.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chebyshev(a, center) < _chebyshev(b, center))

	for coord: Vector2i in _loaded_chunks:
		if _chebyshev(coord, center) > streaming_config.keep_radius_chunks:
			_schedule_grace_period(coord)
		else:
			_cancel_grace_period(coord)

	# Drop any now-out-of-range pending loads so we never load something
	# we'd immediately turn around and unload.
	var still_pending: Array[Vector2i] = []
	for coord in _pending_loads:
		if _chebyshev(coord, center) <= want_radius:
			still_pending.append(coord)
		else:
			_pending_load_set.erase(coord)
	_pending_loads = still_pending
	_stream_revision += 1


func _schedule_grace_period(coord: Vector2i) -> void:
	if _unload_deadlines.has(coord):
		return
	var grace_msec := maxi(0, roundi(streaming_config.unload_grace_seconds * 1000.0))
	if grace_msec == 0:
		_release_chunk(coord)
		return
	_unload_deadlines[coord] = Time.get_ticks_msec() + grace_msec
	_unload_order.append(coord)
	_trim_grace_periods()


func _cancel_grace_period(coord: Vector2i) -> void:
	if not _unload_deadlines.has(coord):
		return
	_unload_deadlines.erase(coord)
	_unload_order.erase(coord)


func _expire_chunk_grace_periods() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array[Vector2i] = []
	for coord: Vector2i in _unload_order:
		if int(_unload_deadlines.get(coord, now + 1)) <= now:
			expired.append(coord)
	for coord in expired:
		_release_chunk(coord)


func _trim_grace_periods() -> void:
	var capacity := maxi(0, streaming_config.retained_chunk_capacity)
	while _unload_order.size() > capacity:
		_release_chunk(_unload_order[0])


func _release_chunk(coord: Vector2i) -> void:
	if not _loaded_chunks.has(coord):
		_cancel_grace_period(coord)
		return
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
	_cancel_grace_period(coord)
	_retained_chunks[coord] = data
	_retained_lru.erase(coord)
	_retained_lru.append(coord)
	_trim_retained_chunks()


func _trim_retained_chunks() -> void:
	var capacity := maxi(0, streaming_config.retained_chunk_capacity)
	while _retained_lru.size() > capacity:
		var coord: Vector2i = _retained_lru.pop_front()
		_retained_chunks.erase(coord)


func _remember_retained(coord: Vector2i, data: CaveData) -> void:
	_retained_chunks[coord] = data
	_retained_lru.erase(coord)
	_retained_lru.append(coord)
	_trim_retained_chunks()


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _load_chunk_async(coord: Vector2i, request_token: int, request_revision: int) -> void:
	var retained_data: CaveData = _retained_chunks.get(coord)
	if retained_data != null:
		_retained_chunks.erase(coord)
		_retained_lru.erase(coord)
	var should_continue := func() -> bool:
		return request_revision == _stream_revision and _desired_load_set.has(coord) and _in_flight.get(coord, -1) == request_token
	if retained_data == null:
		retained_data = _generated_chunks.get(coord, _read_cached_chunk(coord))
	var used_cached_data := retained_data != null
	var data: CaveData = await cave_builder.build_chunk_async(
		coord,
		_world_seed,
		_mutations.get(coord, {}),
		should_continue,
		retained_data,
	)
	var owns_request: bool = _in_flight.get(coord, -1) == request_token
	if owns_request:
		_in_flight.erase(coord)
	if data != null and request_revision == _stream_revision and _desired_load_set.has(coord) and not _loaded_chunks.has(coord):
		_loaded_chunks[coord] = data
		_generated_chunks[coord] = data
		if not used_cached_data:
			_write_cached_chunk(coord, data)
		_cancel_grace_period(coord)
		_trim_retained_chunks()
	elif data != null:
		cave_builder.clear_chunk(coord, data)
		if retained_data != null:
			_remember_retained(coord, retained_data)
	elif owns_request and _desired_load_set.has(coord) and not _loaded_chunks.has(coord) and not _pending_load_set.has(coord):
		_pending_loads.append(coord)
		_pending_load_set[coord] = true
		if retained_data != null:
			_remember_retained(coord, retained_data)


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
	var entry := {"x": cell.x, "y": cell.y}
	if entry not in cells:
		cells.append(entry)
	record[key] = cells
	_mutations[coord] = record


func get_save_id() -> String:
	return "cave_chunk_streamer"


## Every chunk ever touched gets saved, not just currently-loaded ones --
## mutations for a chunk the player wandered away from must survive too.
func get_save_data() -> Dictionary:
	var chunks := {}
	var generated_chunks := {}
	for coord: Vector2i in _mutations:
		chunks["%d,%d" % [coord.x, coord.y]] = _mutations[coord]
	for coord: Vector2i in _loaded_chunks:
		var live_ore_nodes := cave_builder.get_chunk_ore_node_records(coord)
		if live_ore_nodes.is_empty():
			continue
		var record: Dictionary = _mutations.get(coord, {}).duplicate(true)
		var saved_ore: Dictionary = record.get("ore_nodes", {})
		for key in live_ore_nodes:
			saved_ore[key] = live_ore_nodes[key]
		record["ore_nodes"] = saved_ore
		chunks["%d,%d" % [coord.x, coord.y]] = record
	for coord: Vector2i in _generated_chunks:
		generated_chunks["%d,%d" % [coord.x, coord.y]] = _generated_chunks[coord].to_cache_dict()
	return {
		"world_seed": _world_seed,
		"chunks": chunks,
		"generated_chunks": generated_chunks,
	}


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
	_generated_chunks.clear()
	_restore_generated_chunks(data.get("generated_chunks", {}))

	# Invalidate pending and in-flight requests before replacing live chunks.
	_desired_load_set.clear()
	_pending_loads.clear()
	_pending_load_set.clear()
	_retained_chunks.clear()
	_retained_lru.clear()
	_unload_deadlines.clear()
	_unload_order.clear()
	_stream_revision += 1
	for coord: Vector2i in _loaded_chunks.keys():
		var stale_data: CaveData = _loaded_chunks[coord]
		cave_builder.clear_chunk(coord, stale_data)
		_loaded_chunks[coord] = cave_builder.build_chunk(coord, _world_seed, _mutations.get(coord, {}))
	_recompute_active_set(_current_center_chunk)


func _restore_generated_chunks(serialized_chunks: Dictionary) -> void:
	for key: String in serialized_chunks:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var data = CaveData.from_cache_dict(serialized_chunks[key]) as CaveData
		if data != null:
			_generated_chunks[Vector2i(int(parts[0]), int(parts[1]))] = data


func _build_cache_namespace() -> String:
	var signature := "v%d|seed=%d|path=%s" % [
		CACHE_VERSION,
		_world_seed,
		streaming_config.chunk_config.resource_path,
	]
	for property in streaming_config.chunk_config.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE:
			signature += "|%s=%s" % [
				property.name,
				_cache_value_signature(streaming_config.chunk_config.get(property.name)),
			]
	return str(abs(signature.hash()))


func _cache_value_signature(value: Variant) -> String:
	if value is Resource:
		var resource := value as Resource
		var result := resource.resource_path
		for property in resource.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE:
				result += "|%s=%s" % [property.name, _cache_value_signature(resource.get(property.name))]
		return result
	if value is Array:
		var entries: Array[String] = []
		for entry in value:
			entries.append(_cache_value_signature(entry))
		return "[%s]" % ",".join(entries)
	if value is Dictionary:
		var entries: Array[String] = []
		for key in value:
			entries.append("%s:%s" % [key, _cache_value_signature(value[key])])
		entries.sort()
		return "{%s}" % ",".join(entries)
	return str(value)


func _cache_path(coord: Vector2i) -> String:
	return CACHE_ROOT + _cache_namespace + "/%d_%d.json" % [coord.x, coord.y]


func _read_cached_chunk(coord: Vector2i) -> CaveData:
	var path := _cache_path(coord)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return null
	var data = CaveData.from_cache_dict(parsed) as CaveData
	if data == null or data.chunk_coord != coord:
		return null
	return data


func _write_cached_chunk(coord: Vector2i, data: CaveData) -> void:
	if data == null:
		return
	var directory := CACHE_ROOT + _cache_namespace
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(_cache_path(coord), FileAccess.WRITE)
	if file == null:
		push_warning("CaveChunkStreamer: could not write cache for chunk %s" % coord)
		return
	file.store_string(JSON.stringify(data.to_cache_dict()))
