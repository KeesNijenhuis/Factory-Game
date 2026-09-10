class_name CaveGenerator
extends RefCounted
## Pure-data cave layout generator. Turns a CaveGenerationConfig into a
## CaveData grid: organic rooms connected by winding corridors, smoothed with
## cellular automata, validated for connectivity (retrying with a derived
## sub-seed if needed), then decorated with wall ore veins, water/lava pools,
## and pickable floor ore nodes. Has zero scene-tree/TileMap dependency --
## see CaveBuilder for painting the result onto a real level.
##
## Every stochastic step reads only from _rng, which is constructed fresh
## per generation attempt from a seed derived from config.seed -- never from
## Godot's global RNG. This is a real trap: Array.shuffle()/Array.pick_random()
## always draw from the global RNG regardless of context, so CaveGenMath's
## seeded equivalents are used everywhere instead. This is what makes the
## same config.seed reproduce an identical CaveData every time -- see
## generate() below and tools/cave_gen_reproducibility_check.gd.

## Momentum used when carving a corridor to reconnect an unreachable pocket
## -- deliberately higher than a normal room-to-room corridor's momentum so
## the connector reaches its target quickly instead of wandering.
const RECONNECT_MOMENTUM: float = 0.9
const MIN_POOL_SIZE: int = 3
const ORE_NODE_PLACEMENT_ATTEMPTS: int = 30

var _config: CaveGenerationConfig
var _rng: RandomNumberGenerator
var _data: CaveData
## Whether the core (room/corridor/connectivity) layout from
## _generate_core_layout() passed validation -- decoration (ore/water/nodes)
## only ever runs once, against whichever attempt ends up being used.
var is_valid: bool = false


## Single public entry point for a whole-map (non-chunked) grid -- kept for
## cave_gen_debug_view.tscn and any future large-single-cave preset use. See
## generate_chunk() for the per-chunk streaming entry point, which shares
## 100% of the retry/decorate logic via _generate_from_seed().
static func generate(config: CaveGenerationConfig) -> CaveData:
	var base_seed := config.seed if config.seed != 0 else randi()
	return _generate_from_seed(config, base_seed)


## Per-chunk entry point: derives metadata from world_seed + chunk_coord while
## the actual layout is sampled in shared world space. The same world_seed
## therefore produces the same chunk at the same coordinate regardless of
## generation order, and neighboring chunks agree across their shared seams.
static func generate_chunk(config: CaveGenerationConfig, chunk_coord: Vector2i, world_seed: int) -> CaveData:
	var chunk_seed := ("%d_%d_%d" % [world_seed, chunk_coord.x, chunk_coord.y]).hash()
	var data := _generate_world_space_chunk(config, chunk_coord, world_seed)
	data.seed_used = chunk_seed
	data.chunk_coord = chunk_coord
	return data


## Chunk generation deliberately samples a shared world-space field instead of
## seeding a fresh local map per chunk. Rooms and corridor endpoints live on a
## deterministic world lattice, while the background field and decoration
## noise are sampled with world coordinates. Consequently both sides of a
## chunk boundary make exactly the same decision for the same world cell and
## a room/corridor can cross any number of chunk edges.
static func _generate_world_space_chunk(config: CaveGenerationConfig, chunk_coord: Vector2i, world_seed: int) -> CaveData:
	var size := Vector2i(config.map_width, config.map_height)
	var data := CaveData.new(size.x, size.y)
	var origin := chunk_coord * size
	var field := FastNoiseLite.new()
	field.seed = _world_hash(world_seed, 17, 0, 0)
	field.frequency = 0.055
	field.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	for y in range(size.y):
		for x in range(size.x):
			var world_cell := origin + Vector2i(x, y)
			if field.get_noise_2d(world_cell.x, world_cell.y) < 0.08:
				data.set_tile(Vector2i(x, y), CaveData.TileType.FLOOR)

	var density_spacing := sqrt(float(config.map_width * config.map_height) / float(maxi(1, config.room_count)))
	var feature_spacing := (config.room_radius_max * 2.0 + config.corridor_width * 3.0) * 2.0
	var spacing := maxi(24, ceili(maxf(density_spacing, feature_spacing)))
	var min_lattice_x := floori(float(origin.x) / spacing) - 1
	var max_lattice_x := floori(float(origin.x + size.x) / spacing) + 1
	var min_lattice_y := floori(float(origin.y) / spacing) - 1
	var max_lattice_y := floori(float(origin.y + size.y) / spacing) + 1
	var rooms: Dictionary = {}
	for lattice_y in range(min_lattice_y, max_lattice_y + 1):
		for lattice_x in range(min_lattice_x, max_lattice_x + 1):
			var lattice := Vector2i(lattice_x, lattice_y)
			var descriptor := _world_room_descriptor(config, world_seed, lattice, spacing)
			rooms[lattice] = descriptor
			var center: Vector2i = descriptor["center"]
			if center.x >= origin.x - ceili(config.room_radius_max) and center.x < origin.x + size.x + ceili(config.room_radius_max) \
					and center.y >= origin.y - ceili(config.room_radius_max) and center.y < origin.y + size.y + ceili(config.room_radius_max):
				_stamp_world_room(data, origin, center, descriptor.radius, config.room_roughness)
				if center.x >= origin.x and center.x < origin.x + size.x and center.y >= origin.y and center.y < origin.y + size.y:
					data.room_centers.append(center - origin)

	for lattice_y in range(min_lattice_y, max_lattice_y + 1):
		for lattice_x in range(min_lattice_x, max_lattice_x + 1):
			var lattice := Vector2i(lattice_x, lattice_y)
			var from_room: Dictionary = rooms.get(lattice, {})
			if from_room.is_empty():
				continue
			for neighbor in [lattice + Vector2i.RIGHT, lattice + Vector2i.DOWN]:
				if not rooms.has(neighbor):
					continue
				var to_room: Dictionary = rooms[neighbor]
				_stamp_world_corridor(
					data,
					origin,
					from_room["center"],
					to_room["center"],
					config.corridor_width,
					config.corridor_max_turn_degrees,
					_world_hash(world_seed, lattice.x, lattice.y, neighbor.x * 31 + neighbor.y)
				)

	_set_world_entrance(data, origin)
	_decorate_world_space_chunk(data, config, origin, world_seed)
	return data


static func _world_room_descriptor(config: CaveGenerationConfig, world_seed: int, lattice: Vector2i, spacing: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _world_hash(world_seed, lattice.x, lattice.y, 101)
	var jitter := maxi(1, spacing / 5)
	var center := lattice * spacing + Vector2i(
		spacing / 2 + rng.randi_range(-jitter, jitter),
		spacing / 2 + rng.randi_range(-jitter, jitter)
	)
	var radius := rng.randf_range(config.room_radius_min, config.room_radius_max)
	return {"center": center, "radius": radius}


static func _stamp_world_room(data: CaveData, origin: Vector2i, center: Vector2i, radius: float, roughness: float) -> void:
	var bounds := ceili(radius) + 1
	for dy in range(-bounds, bounds + 1):
		for dx in range(-bounds, bounds + 1):
			var world_cell := center + Vector2i(dx, dy)
			var distance := Vector2(dx, dy).length()
			var edge_jitter := 1.0 + roughness * 0.12 * sin(float((world_cell.x * 13 + world_cell.y * 7) % 31))
			if distance <= radius * edge_jitter:
				var local_cell := world_cell - origin
				if data.is_in_bounds(local_cell):
					data.set_tile(local_cell, CaveData.TileType.FLOOR)


static func _stamp_world_corridor(
	data: CaveData,
	origin: Vector2i,
	from: Vector2i,
	to: Vector2i,
	width: int,
	max_turn_degrees: float,
	corridor_seed: int
) -> void:
	var distance := Vector2(from - to).length()
	var steps := maxi(1, ceili(distance * 1.5))
	var perpendicular := (Vector2(to - from).normalized().rotated(PI / 2.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var jitter := (sin(float(i * 17 + absi(corridor_seed % 97))) * 0.5 + 0.5)
		jitter = (jitter * 2.0 - 1.0) * minf(float(width) * 1.5, max_turn_degrees / 20.0)
		var point := Vector2(from).lerp(Vector2(to), t) + perpendicular * jitter
		var local_cell := Vector2i(point.round()) - origin
		CaveGenMath.stamp_disk(data, local_cell, maxf(0.5, width / 2.0), CaveData.TileType.FLOOR)


static func _set_world_entrance(data: CaveData, origin: Vector2i) -> void:
	var best := Vector2i.ZERO
	var best_distance := INF
	# The origin chunk is the player's permanent starting area. Keep its
	# entrance near world cell (0, 0); other chunks retain a local center
	# anchor for debug/streaming metadata.
	var target := Vector2i.ONE if origin == Vector2i.ZERO else origin + Vector2i(data.width / 2, data.height / 2)
	for y in range(data.height):
		for x in range(data.width):
			var cell := Vector2i(x, y)
			if data.get_tile(cell) != CaveData.TileType.FLOOR:
				continue
			var distance := Vector2(origin + cell - target).length_squared()
			if distance < best_distance:
				best_distance = distance
				best = cell
	if best_distance == INF:
		best = Vector2i.ONE if origin == Vector2i.ZERO else Vector2i(data.width / 2, data.height / 2)
		data.set_tile(best, CaveData.TileType.FLOOR)
	data.entrance_position = best


static func _decorate_world_space_chunk(data: CaveData, config: CaveGenerationConfig, origin: Vector2i, world_seed: int) -> void:
	for vein_config in config.ore_veins:
		if vein_config == null or vein_config.ore_type == null:
			continue
		var noise := FastNoiseLite.new()
		noise.seed = _world_hash(world_seed, vein_config.seed_offset, 211, 0)
		noise.frequency = vein_config.noise_frequency
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		var tile_type := CaveOreVeinConfig.slot_to_tile_type(vein_config.ore_slot)
		for y in range(data.height):
			for x in range(data.width):
				var cell := Vector2i(x, y)
				if data.get_tile(cell) != CaveData.TileType.WALL:
					continue
				var world_cell := origin + cell
				var value := (noise.get_noise_2d(world_cell.x, world_cell.y) + 1.0) / 2.0
				if value >= vein_config.vein_threshold and value <= vein_config.vein_threshold + vein_config.band_width:
					data.set_tile(cell, tile_type)

	var liquid_noise := FastNoiseLite.new()
	liquid_noise.seed = _world_hash(world_seed, 307, 0, 0)
	liquid_noise.frequency = 0.09
	liquid_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	for y in range(data.height):
		for x in range(data.width):
			var cell := Vector2i(x, y)
			if data.get_tile(cell) != CaveData.TileType.FLOOR:
				continue
			var world_cell := origin + cell
			var value := (liquid_noise.get_noise_2d(world_cell.x, world_cell.y) + 1.0) / 2.0
			if config.enable_water and config.water_pool_count > 0 and value > 0.88:
				data.set_tile(cell, CaveData.TileType.WATER)
			elif config.enable_lava and config.lava_pool_count > 0 and value > 0.96:
				data.set_tile(cell, CaveData.TileType.LAVA)

	_place_world_ore_nodes(data, config, origin, world_seed)


static func _place_world_ore_nodes(data: CaveData, config: CaveGenerationConfig, origin: Vector2i, world_seed: int) -> void:
	var rules: Array[CaveOreNodeConfig] = []
	var weights: Array[float] = []
	for rule in config.ore_node_rules:
		if rule != null and rule.node_type != null and rule.rarity_weight > 0.0:
			rules.append(rule)
			weights.append(rule.rarity_weight)
	if rules.is_empty():
		return
	var candidates: Array[Dictionary] = []
	for y in range(data.height):
		for x in range(data.width):
			var cell := Vector2i(x, y)
			if data.get_tile(cell) != CaveData.TileType.FLOOR or cell == data.entrance_position:
				continue
			var world_cell := origin + cell
			candidates.append({"cell": cell, "score": _world_unit_hash(world_seed, world_cell.x, world_cell.y, 401)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var placed: Array[Vector2i] = []
	var total_weight := 0.0
	for weight in weights:
		total_weight += weight
	for candidate in candidates:
		if placed.size() >= config.ore_node_total_count:
			break
		var cell: Vector2i = candidate["cell"]
		var far_enough := true
		for other in placed:
			if Vector2(cell - other).length() < config.ore_node_min_separation:
				far_enough = false
				break
		if not far_enough:
			continue
		var choice := int(floori(_world_unit_hash(world_seed, origin.x + cell.x, origin.y + cell.y, 409) * total_weight))
		var cumulative := 0.0
		var rule_index := 0
		for i in range(weights.size()):
			cumulative += weights[i]
			if choice < cumulative:
				rule_index = i
				break
		data.ore_node_placements[cell] = rules[rule_index].node_type
		placed.append(cell)


static func _world_unit_hash(world_seed: int, x: int, y: int, salt: int) -> float:
	var hashed := _world_hash(world_seed, x, y, salt)
	return float(posmod(hashed, 1000000)) / 1000000.0


static func _world_hash(world_seed: int, x: int, y: int, salt: int) -> int:
	return ("%d:%d:%d:%d" % [world_seed, x, y, salt]).hash()


## Retries with a deterministic derived sub-seed up to
## config.max_generation_retries times if a layout doesn't pass connectivity
## validation; returns the best attempt (never null) if every retry fails.
static func _generate_from_seed(config: CaveGenerationConfig, base_seed: int) -> CaveData:
	var last_generator: CaveGenerator = null
	var last_seed := base_seed
	for attempt in range(config.max_generation_retries + 1):
		var attempt_seed := base_seed if attempt == 0 else ("%d_%d" % [base_seed, attempt]).hash()
		var rng := RandomNumberGenerator.new()
		rng.seed = attempt_seed
		var generator := CaveGenerator.new()
		generator._generate_core_layout(rng, config)
		last_generator = generator
		last_seed = attempt_seed
		if generator.is_valid:
			generator._decorate()
			generator._data.seed_used = attempt_seed
			return generator._data
	push_warning("CaveGenerator: exhausted %d attempts without a fully connected layout -- using the best attempt anyway." % (config.max_generation_retries + 1))
	last_generator._decorate()
	last_generator._data.seed_used = last_seed
	return last_generator._data


func _generate_core_layout(rng: RandomNumberGenerator, config: CaveGenerationConfig) -> void:
	_rng = rng
	_config = config
	_data = CaveData.new(config.map_width, config.map_height)

	_carve_rooms_and_corridors()
	_smooth_with_cellular_automata()
	is_valid = _resolve_connectivity()


func _decorate() -> void:
	_generate_ore_veins()
	_generate_water_lava_pools()
	_generate_ore_nodes()


# ---------------------------------------------------------------------------
# Rooms & corridors
# ---------------------------------------------------------------------------

func _carve_rooms_and_corridors() -> void:
	var centers: Array[Vector2i] = []
	for _i in range(_config.room_count):
		var center = _try_place_room(centers)
		if center != null:
			centers.append(center)
	_data.room_centers = centers
	if centers.size() < 2:
		return
	var edges := _build_connection_edges(centers)
	for edge in edges:
		_carve_corridor(centers[edge.x], centers[edge.y], _config.corridor_momentum)


func _try_place_room(existing_centers: Array[Vector2i]) -> Variant:
	var margin := ceili(_config.room_radius_max) + 1
	var max_x := _config.map_width - margin - 1
	var max_y := _config.map_height - margin - 1
	if max_x < margin or max_y < margin:
		margin = 1
		max_x = _config.map_width - margin - 1
		max_y = _config.map_height - margin - 1
	if max_x < margin or max_y < margin:
		return null
	for _attempt in range(_config.room_placement_attempts):
		var center := Vector2i(_rng.randi_range(margin, max_x), _rng.randi_range(margin, max_y))
		var far_enough := true
		for other in existing_centers:
			if Vector2(center - other).length() < _config.room_min_separation:
				far_enough = false
				break
		if far_enough:
			_carve_room_blob(center)
			return center
	return null


func _carve_room_blob(center: Vector2i) -> void:
	var radius := _rng.randf_range(_config.room_radius_min, _config.room_radius_max)
	var boundary_radii: Array[float] = []
	for _i in range(_config.room_boundary_samples):
		var jitter := 1.0 + _config.room_roughness * (_rng.randf() * 2.0 - 1.0)
		boundary_radii.append(clampf(radius * jitter, radius * 0.5, radius * 1.5))

	var max_r := radius * 1.5
	var r := ceili(max_r) + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var offset := Vector2i(dx, dy)
			var v := Vector2(offset)
			var dist := v.length()
			if dist > max_r:
				continue
			var angle := v.angle()
			if angle < 0.0:
				angle += TAU
			if dist <= _interpolate_boundary(boundary_radii, angle):
				_data.set_tile(center + offset, CaveData.TileType.FLOOR)

	_roughen_room_edges(center, max_r)


func _interpolate_boundary(boundary_radii: Array[float], angle: float) -> float:
	var count := boundary_radii.size()
	var step := TAU / count
	var index_f := angle / step
	var i0 := int(floor(index_f)) % count
	var i1 := (i0 + 1) % count
	var t: float = index_f - floor(index_f)
	return lerpf(boundary_radii[i0], boundary_radii[i1], t)


func _roughen_room_edges(center: Vector2i, max_r: float) -> void:
	var r := ceili(max_r) + 1
	var boundary_cells: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := center + Vector2i(dx, dy)
			if _data.get_tile(cell) != CaveData.TileType.FLOOR:
				continue
			for offset in CaveGenMath.NEIGHBORS_4:
				if _data.get_tile(cell + offset) == CaveData.TileType.WALL:
					boundary_cells.append(cell)
					break

	for cell in boundary_cells:
		var roll := _rng.randf()
		if roll < _config.room_roughness * 0.5:
			var wall_neighbors: Array[Vector2i] = []
			for offset in CaveGenMath.NEIGHBORS_4:
				var neighbor := cell + offset
				if _data.get_tile(neighbor) == CaveData.TileType.WALL:
					wall_neighbors.append(neighbor)
			var bump = CaveGenMath.pick_random_with_rng(wall_neighbors, _rng)
			if bump != null:
				_data.set_tile(bump, CaveData.TileType.FLOOR)
		elif roll < _config.room_roughness * 0.75:
			_data.set_tile(cell, CaveData.TileType.WALL)


func _build_connection_edges(centers: Array[Vector2i]) -> Array[Vector2i]:
	var edges: Array[Vector2i]
	if _config.room_connection_strategy == CaveGenerationConfig.RoomConnectionStrategy.SEQUENTIAL_NEAREST_NEIGHBOR:
		edges = _sequential_nearest_neighbor_edges(centers)
	else:
		edges = _mst_edges(centers)
	_add_loop_connections(centers, edges)
	return edges


## Prim's algorithm over Euclidean distance between room centers. O(n^2),
## fine at the room counts this generator targets (a handful to a few dozen).
func _mst_edges(centers: Array[Vector2i]) -> Array[Vector2i]:
	var n := centers.size()
	var in_tree: Array[bool] = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var tree_edges: Array[Vector2i] = []

	for _i in range(n - 1):
		var best_dist := INF
		var best_a := -1
		var best_b := -1
		for a in range(n):
			if not in_tree[a]:
				continue
			for b in range(n):
				if in_tree[b]:
					continue
				var d := Vector2(centers[a] - centers[b]).length()
				if d < best_dist:
					best_dist = d
					best_a = a
					best_b = b
		if best_b == -1:
			break
		in_tree[best_b] = true
		tree_edges.append(Vector2i(best_a, best_b))
	return tree_edges


func _sequential_nearest_neighbor_edges(centers: Array[Vector2i]) -> Array[Vector2i]:
	var n := centers.size()
	var connected: Array[int] = [0]
	var edges: Array[Vector2i] = []
	for i in range(1, n):
		var best_dist := INF
		var best_j := connected[0]
		for j in connected:
			var d := Vector2(centers[i] - centers[j]).length()
			if d < best_dist:
				best_dist = d
				best_j = j
		edges.append(Vector2i(best_j, i))
		connected.append(i)
	return edges


## Adds each next-shortest non-tree edge with probability
## extra_loop_connection_chance, so the connection graph isn't a purely
## dead-end-heavy tree.
func _add_loop_connections(centers: Array[Vector2i], edges: Array[Vector2i]) -> void:
	var n := centers.size()
	var existing := {}
	for e in edges:
		existing[_edge_key(e.x, e.y)] = true
	var candidates: Array[Vector2i] = []
	for a in range(n):
		for b in range(a + 1, n):
			if not existing.has(_edge_key(a, b)):
				candidates.append(Vector2i(a, b))
	candidates.sort_custom(func(e1: Vector2i, e2: Vector2i) -> bool:
		var d1 := Vector2(centers[e1.x] - centers[e1.y]).length_squared()
		var d2 := Vector2(centers[e2.x] - centers[e2.y]).length_squared()
		return d1 < d2)
	for edge in candidates:
		if _rng.randf() < _config.extra_loop_connection_chance:
			edges.append(edge)


func _edge_key(a: int, b: int) -> String:
	return "%d_%d" % [min(a, b), max(a, b)]


## Momentum-biased winding walk from `from` toward `to`, stamping a
## corridor_width-diameter disk of FLOOR at each step. heading is blended
## between its previous value (weighted by momentum) and the direction to
## the target, then jittered -- this keeps the corridor winding locally while
## still reliably reaching its destination.
func _carve_corridor(from: Vector2i, to: Vector2i, momentum: float) -> void:
	var current := Vector2(from)
	var target := Vector2(to)
	var heading := (target - current).normalized()
	if heading == Vector2.ZERO:
		heading = Vector2.RIGHT
	var max_steps := int(Vector2(to - from).length()) * 4 + 8
	var steps := 0
	while Vector2(current - target).length() > _config.corridor_width and steps < max_steps:
		var desired := (target - current).normalized()
		if desired == Vector2.ZERO:
			desired = heading
		var blended := heading * momentum + desired * (1.0 - momentum)
		heading = blended.normalized() if blended.length() > 0.0001 else desired
		var turn := deg_to_rad(_rng.randf_range(-_config.corridor_max_turn_degrees, _config.corridor_max_turn_degrees))
		heading = heading.rotated(turn)
		var step := heading * _config.corridor_step_length
		if Vector2i(step.round()) == Vector2i.ZERO:
			step = desired * _config.corridor_step_length
		current += step
		var cell := Vector2i(current.round())
		cell.x = clampi(cell.x, 1, _config.map_width - 2)
		cell.y = clampi(cell.y, 1, _config.map_height - 2)
		CaveGenMath.stamp_disk(_data, cell, _config.corridor_width / 2.0, CaveData.TileType.FLOOR)
		steps += 1
	CaveGenMath.stamp_disk(_data, to, _config.corridor_width / 2.0, CaveData.TileType.FLOOR)


# ---------------------------------------------------------------------------
# Cellular automata smoothing
# ---------------------------------------------------------------------------

func _smooth_with_cellular_automata() -> void:
	for _i in range(_config.ca_smoothing_iterations):
		_smooth_pass()


func _smooth_pass() -> void:
	var new_data := CaveData.new(_data.width, _data.height)
	for y in range(_data.height):
		for x in range(_data.width):
			var cell := Vector2i(x, y)
			if _count_wall_neighbors(cell) >= _config.ca_wall_threshold:
				new_data.set_tile(cell, CaveData.TileType.WALL)
			else:
				new_data.set_tile(cell, CaveData.TileType.FLOOR)
	new_data.room_centers = _data.room_centers
	_data = new_data


func _count_wall_neighbors(cell: Vector2i) -> int:
	var count := 0
	for offset in CaveGenMath.NEIGHBORS_8:
		if _data.get_tile(cell + offset) == CaveData.TileType.WALL:
			count += 1
	return count


# ---------------------------------------------------------------------------
# Connectivity: flood fill, prune/reconnect pockets, validate
# ---------------------------------------------------------------------------

func _resolve_connectivity() -> bool:
	if _data.room_centers.size() < 2:
		return false
	_data.entrance_position = _data.room_centers[0]
	if _data.get_tile(_data.entrance_position) != CaveData.TileType.FLOOR:
		# Entrance got smoothed into a wall -- carve it back open so flood
		# fill has somewhere to start from.
		_data.set_tile(_data.entrance_position, CaveData.TileType.FLOOR)

	var is_floor := func(cell: Vector2i) -> bool:
		return _data.get_tile(cell) == CaveData.TileType.FLOOR
	var reachable := CaveGenMath.flood_fill(_data, _data.entrance_position, is_floor)

	var total_floor := 0
	var unreached: Array[Vector2i] = []
	for y in range(_data.height):
		for x in range(_data.width):
			var cell := Vector2i(x, y)
			if _data.get_tile(cell) == CaveData.TileType.FLOOR:
				total_floor += 1
				if not reachable.has(cell):
					unreached.append(cell)

	_resolve_pockets(unreached, reachable, is_floor)

	if total_floor == 0:
		return false
	var ratio := float(reachable.size()) / float(total_floor)
	return ratio >= _config.min_reachable_floor_ratio


func _resolve_pockets(unreached: Array[Vector2i], reachable: Dictionary, is_floor: Callable) -> void:
	var visited := {}
	for cell in unreached:
		if visited.has(cell):
			continue
		var pocket := CaveGenMath.flood_fill(_data, cell, is_floor)
		var pocket_cells: Array = pocket.keys()
		for pcell in pocket_cells:
			visited[pcell] = true
		if pocket_cells.size() < _config.prune_min_pocket_size:
			for pcell in pocket_cells:
				_data.set_tile(pcell, CaveData.TileType.WALL)
		elif _config.reconnect_larger_pockets:
			_reconnect_pocket(pocket_cells, reachable)
			for pcell in pocket_cells:
				reachable[pcell] = true
		else:
			for pcell in pocket_cells:
				_data.set_tile(pcell, CaveData.TileType.WALL)


## Carves a near-straight connector corridor between the closest pair of
## (pocket cell, already-reachable cell), by Euclidean distance.
func _reconnect_pocket(pocket_cells: Array, reachable: Dictionary) -> void:
	var reachable_cells: Array = reachable.keys()
	if reachable_cells.is_empty():
		return
	var best_dist := INF
	var best_pocket_cell: Vector2i = pocket_cells[0]
	var best_reachable_cell: Vector2i = reachable_cells[0]
	for pcell in pocket_cells:
		for rcell in reachable_cells:
			var d: float = Vector2(pcell - rcell).length_squared()
			if d < best_dist:
				best_dist = d
				best_pocket_cell = pcell
				best_reachable_cell = rcell
	_carve_corridor(best_pocket_cell, best_reachable_cell, RECONNECT_MOMENTUM)


# ---------------------------------------------------------------------------
# Ore veins
# ---------------------------------------------------------------------------

func _generate_ore_veins() -> void:
	var used_slots := {}
	for vein_config in _config.ore_veins:
		if vein_config == null or vein_config.ore_type == null:
			continue
		if used_slots.has(vein_config.ore_slot):
			push_warning("CaveGenerator: duplicate ore_slot in ore_veins config -- skipping.")
			continue
		used_slots[vein_config.ore_slot] = true
		_generate_single_ore_vein(vein_config)


## Deliberate, documented exception to "everything goes through _rng":
## FastNoiseLite is itself fully deterministic given its seed/params, so
## seeding it directly from the attempt seed doesn't break reproducibility.
func _generate_single_ore_vein(vein_config: CaveOreVeinConfig) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = int(_rng.seed) + vein_config.seed_offset
	noise.frequency = vein_config.noise_frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var tile_type := CaveOreVeinConfig.slot_to_tile_type(vein_config.ore_slot)
	var low := vein_config.vein_threshold
	var high := vein_config.vein_threshold + vein_config.band_width
	for y in range(_data.height):
		for x in range(_data.width):
			var cell := Vector2i(x, y)
			if _data.get_tile(cell) != CaveData.TileType.WALL:
				continue
			var n := (noise.get_noise_2d(x, y) + 1.0) / 2.0
			if n >= low and n <= high:
				_data.set_tile(cell, tile_type)


# ---------------------------------------------------------------------------
# Water & lava pools
# ---------------------------------------------------------------------------

func _generate_water_lava_pools() -> void:
	var pool_seeds: Array[Vector2i] = []
	if _config.enable_water:
		for _i in range(_config.water_pool_count):
			_try_grow_pool(CaveData.TileType.WATER, pool_seeds)
	if _config.enable_lava:
		for _i in range(_config.lava_pool_count):
			_try_grow_pool(CaveData.TileType.LAVA, pool_seeds)


func _try_grow_pool(tile_type: CaveData.TileType, pool_seeds: Array[Vector2i]) -> void:
	var seed_cell = _pick_pool_seed(pool_seeds)
	if seed_cell == null:
		push_warning("CaveGenerator: could not find a valid seed cell for a pool -- skipping.")
		return
	var pool_cells := _grow_pool_cells(seed_cell)
	if pool_cells.size() < MIN_POOL_SIZE:
		push_warning("CaveGenerator: pool grew too small -- discarding.")
		return
	for cell in pool_cells:
		_data.set_tile(cell, tile_type)
	if not _pool_preserves_connectivity():
		for cell in pool_cells:
			_data.set_tile(cell, CaveData.TileType.FLOOR)
		push_warning("CaveGenerator: pool broke connectivity -- rolled back.")
		return
	pool_seeds.append(seed_cell)


func _pick_pool_seed(pool_seeds: Array[Vector2i]) -> Variant:
	var candidates: Array[Vector2i] = []
	for y in range(_data.height):
		for x in range(_data.width):
			var cell := Vector2i(x, y)
			if _data.get_tile(cell) == CaveData.TileType.FLOOR:
				candidates.append(cell)
	CaveGenMath.shuffle_with_rng(candidates, _rng)
	for cell in candidates:
		if Vector2(cell - _data.entrance_position).length() < _config.min_distance_from_entrance:
			continue
		var far_enough := true
		for other_seed in pool_seeds:
			if Vector2(cell - other_seed).length() < _config.min_distance_between_pools:
				far_enough = false
				break
		if far_enough:
			return cell
	return null


## pool_walk_bias: 0 = snaking random-walk (always expand the most recently
## added frontier cell), 1 = rounder flood-fill-like growth (expand a
## uniformly-picked frontier cell) -- unifies both growth styles behind one
## knob.
func _grow_pool_cells(seed_cell: Vector2i) -> Array:
	var target_size := _rng.randi_range(_config.pool_size_min, _config.pool_size_max)
	var pool := {seed_cell: true}
	var frontier: Array[Vector2i] = [seed_cell]
	while pool.size() < target_size and not frontier.is_empty():
		var index := _rng.randi_range(0, frontier.size() - 1) if _rng.randf() < _config.pool_walk_bias else frontier.size() - 1
		var current: Vector2i = frontier[index]
		var candidates: Array[Vector2i] = []
		for offset in CaveGenMath.NEIGHBORS_4:
			var neighbor := current + offset
			if pool.has(neighbor):
				continue
			if _data.get_tile(neighbor) != CaveData.TileType.FLOOR:
				continue
			if Vector2(neighbor - _data.entrance_position).length() < _config.min_distance_from_entrance:
				continue
			candidates.append(neighbor)
		if candidates.is_empty():
			frontier.remove_at(index)
			continue
		var next_cell: Vector2i = CaveGenMath.pick_random_with_rng(candidates, _rng)
		pool[next_cell] = true
		frontier.append(next_cell)
	return pool.keys()


## WATER is passable, LAVA is impassable -- matches the Water tile having no
## collision shape in the tileset, and reads as the intuitive gameplay
## expectation for a lava hazard.
func _pool_preserves_connectivity() -> bool:
	var is_passable := func(cell: Vector2i) -> bool:
		var tile := _data.get_tile(cell)
		return tile == CaveData.TileType.FLOOR or tile == CaveData.TileType.WATER
	var reachable := CaveGenMath.flood_fill(_data, _data.entrance_position, is_passable)
	for center in _data.room_centers:
		if not reachable.has(center):
			return false
	return true


# ---------------------------------------------------------------------------
# Pickable ore nodes
# ---------------------------------------------------------------------------

func _generate_ore_nodes() -> void:
	var weights: Array[float] = []
	var rules: Array[CaveOreNodeConfig] = []
	for rule in _config.ore_node_rules:
		if rule == null or rule.node_type == null or rule.rarity_weight <= 0.0:
			continue
		rules.append(rule)
		weights.append(rule.rarity_weight)
	if rules.is_empty():
		return

	var placed: Array[Vector2i] = []
	for _i in range(_config.ore_node_total_count):
		var rule_index := CaveGenMath.weighted_pick_index_with_rng(weights, _rng)
		if rule_index < 0:
			continue
		var cell = _pick_ore_node_cell(placed)
		if cell == null:
			continue
		_data.ore_node_placements[cell] = rules[rule_index].node_type
		placed.append(cell)


func _pick_ore_node_cell(placed: Array[Vector2i]) -> Variant:
	for _attempt in range(ORE_NODE_PLACEMENT_ATTEMPTS):
		var cell := Vector2i(_rng.randi_range(0, _data.width - 1), _rng.randi_range(0, _data.height - 1))
		if _data.get_tile(cell) != CaveData.TileType.FLOOR:
			continue
		if cell == _data.entrance_position or _data.ore_node_placements.has(cell):
			continue
		var far_enough := true
		for other in placed:
			if Vector2(cell - other).length() < _config.ore_node_min_separation:
				far_enough = false
				break
		if far_enough:
			return cell
	return null
