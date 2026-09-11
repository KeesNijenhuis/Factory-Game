class_name CaveGenerator
extends RefCounted
## Pure-data cave layout generator. Samples a deterministic world-space field
## (rooms on a jittered lattice, corridors between neighbors, noise-driven ore
## veins/pools) into a CaveData grid for one chunk at a time. Has zero
## scene-tree/TileMap dependency -- see CaveBuilder for painting the result
## onto a real level.
##
## Every stochastic decision derives from world_seed + world-cell coordinates
## via _world_hash()/_world_unit_hash(), never Godot's global RNG -- this is
## what makes the same world_seed reproduce an identical chunk at a given
## coordinate regardless of generation order, and what lets neighboring
## chunks agree across their shared seams (see generate_chunk() below).

## Tile types that read as solid wall mass for ore-node placement purposes --
## includes wall-vein tiles (ORE_COPPER/IRON/GOLD), which are still WALL
## underneath until mined. Matches CaveBuilder._wall_cells_for()'s notion of
## "wall" so a node never spawns beside a cell that will paint as a wall or
## get a wall-base cap.
const _WALL_LIKE_TILE_TYPES: Array[CaveData.TileType] = [
	CaveData.TileType.WALL, CaveData.TileType.ORE_COPPER,
	CaveData.TileType.ORE_IRON, CaveData.TileType.ORE_GOLD,
]

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
	@warning_ignore("integer_division")
	var jitter := maxi(1, spacing / 5)
	@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
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
		@warning_ignore("integer_division")
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
			if _has_adjacent_wall(data, cell):
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
		# Salt kept far from the candidate-score salt (401) -- a nearby salt here
		# correlated with it and made every node the same type (verified empirically).
		var choice := int(floori(_world_unit_hash(world_seed, origin.x + cell.x, origin.y + cell.y, 87911) * total_weight))
		var cumulative := 0.0
		var rule_index := 0
		for i in range(weights.size()):
			cumulative += weights[i]
			if choice < cumulative:
				rule_index = i
				break
		data.ore_node_placements[cell] = rules[rule_index].node_type
		placed.append(cell)


## Ore nodes must sit at least one tile away from every wall (and, by
## extension, every wall-base cap, which always paints directly under a wall
## cell) -- checks all 8 neighbors, not just the 4 orthogonal ones, so a node
## can't spawn diagonally against a wall corner either. Out-of-bounds
## neighbors read as WALL (see CaveData.get_tile()), which correctly keeps
## nodes off the edge of a chunk that borders an unwritten neighbor.
static func _has_adjacent_wall(data: CaveData, cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if _WALL_LIKE_TILE_TYPES.has(data.get_tile(cell + Vector2i(dx, dy))):
				return true
	return false


static func _world_unit_hash(world_seed: int, x: int, y: int, salt: int) -> float:
	var hashed := _world_hash(world_seed, x, y, salt)
	return float(posmod(hashed, 1000000)) / 1000000.0


static func _world_hash(world_seed: int, x: int, y: int, salt: int) -> int:
	return ("%d:%d:%d:%d" % [world_seed, x, y, salt]).hash()
