class_name CaveGenMath
extends RefCounted
## Small pure-math helpers shared by CaveGenerator's stochastic steps. Exists
## so every random choice in cave generation goes through an explicitly
## passed RandomNumberGenerator -- Array.shuffle()/pick_random() always draw
## from Godot's global RNG regardless of context, which would silently break
## CaveGenerator's seed reproducibility if used instead of these.

const NEIGHBORS_4: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]


## Fisher-Yates shuffle using rng, in place. Returns the same array back for
## chaining.
static func shuffle_with_rng(array: Array, rng: RandomNumberGenerator) -> Array:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp
	return array


static func pick_random_with_rng(array: Array, rng: RandomNumberGenerator) -> Variant:
	if array.is_empty():
		return null
	return array[rng.randi_range(0, array.size() - 1)]


## Weighted pick over parallel weights, using rng. Returns -1 if weights is
## empty or every weight is <= 0 -- callers treat that as "nothing to pick."
static func weighted_pick_index_with_rng(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		if w > 0.0:
			total += w
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	var cumulative := 0.0
	for i in range(weights.size()):
		if weights[i] <= 0.0:
			continue
		cumulative += weights[i]
		if roll < cumulative:
			return i
	return weights.size() - 1


## Stamps a filled disk of tile_type onto data, centered at center with the
## given radius (cells within radius, inclusive).
static func stamp_disk(data: CaveData, center: Vector2i, radius: float, tile_type: CaveData.TileType) -> void:
	var r := ceili(radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var offset := Vector2i(dx, dy)
			if Vector2(offset).length() <= radius:
				data.set_tile(center + offset, tile_type)


## Iterative BFS flood fill from start over cells where passable_predicate
## returns true. Returns every reached cell (including start, if passable)
## as the keys of a Dictionary[Vector2i, bool].
static func flood_fill(data: CaveData, start: Vector2i, passable_predicate: Callable) -> Dictionary:
	var reached := {}
	if not data.is_in_bounds(start) or not passable_predicate.call(start):
		return reached
	var frontier: Array[Vector2i] = [start]
	reached[start] = true
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for offset in NEIGHBORS_4:
			var neighbor := cell + offset
			if reached.has(neighbor) or not data.is_in_bounds(neighbor):
				continue
			if not passable_predicate.call(neighbor):
				continue
			reached[neighbor] = true
			frontier.append(neighbor)
	return reached
