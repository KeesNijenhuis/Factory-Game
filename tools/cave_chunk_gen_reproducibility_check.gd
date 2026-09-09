extends SceneTree
## Headless reproducibility check for CaveGenerator.generate_chunk(): confirms
## (a) the same world_seed + chunk_coord reproduces an identical CaveData,
## (b) different chunk_coords under the same world_seed produce different
## layouts (chunks aren't accidentally sharing state), and (c) per-chunk
## generation time stays flat across many chunks (no accidental growth). Run:
##   godot --headless --script res://tools/cave_chunk_gen_reproducibility_check.gd

const FIXED_WORLD_SEED: int = 424242
const FLAT_TIMING_CHUNK_COUNT: int = 200
## Generous slack over the per-chunk average -- this check only wants to
## catch real O(n)-in-chunk-count growth, not normal timing jitter.
const FLAT_TIMING_MAX_RATIO: float = 3.0


func _init() -> void:
	var config: CaveGenerationConfig = load("res://src/resources/cave_generation/presets/chunk_cave.tres")
	var failures: Array[String] = []

	# (a) determinism
	var a := CaveGenerator.generate_chunk(config, Vector2i(3, -2), FIXED_WORLD_SEED)
	var b := CaveGenerator.generate_chunk(config, Vector2i(3, -2), FIXED_WORLD_SEED)
	if a.seed_used != b.seed_used:
		failures.append("same chunk_coord: seed_used differs (%d vs %d)" % [a.seed_used, b.seed_used])
	if not a.grid_equals(b):
		failures.append("same chunk_coord: tile grid differs")
	if a.entrance_position != b.entrance_position or a.room_centers != b.room_centers:
		failures.append("same chunk_coord: entrance/room_centers differ")
	if a.chunk_coord != Vector2i(3, -2) or b.chunk_coord != Vector2i(3, -2):
		failures.append("chunk_coord not recorded correctly on CaveData")

	# (b) different coords -> different layouts (not sharing state)
	var c := CaveGenerator.generate_chunk(config, Vector2i(3, -1), FIXED_WORLD_SEED)
	if a.grid_equals(c):
		failures.append("adjacent chunk_coord produced an identical grid -- suspicious state sharing")
	if a.seed_used == c.seed_used:
		failures.append("adjacent chunk_coord produced the same seed_used")

	# (b2) order independence: generating in a different order shouldn't change results
	var c_first := CaveGenerator.generate_chunk(config, Vector2i(3, -1), FIXED_WORLD_SEED)
	var a_second := CaveGenerator.generate_chunk(config, Vector2i(3, -2), FIXED_WORLD_SEED)
	if not c_first.grid_equals(c) or not a_second.grid_equals(a):
		failures.append("generation order affected chunk output -- chunks are not independent")

	# (c) flat timing across many chunks
	var timings: Array[float] = []
	for i in range(FLAT_TIMING_CHUNK_COUNT):
		var t := Time.get_ticks_usec()
		CaveGenerator.generate_chunk(config, Vector2i(i, 0), FIXED_WORLD_SEED)
		timings.append((Time.get_ticks_usec() - t) / 1000.0)
	var first_half_avg := _average(timings.slice(0, FLAT_TIMING_CHUNK_COUNT / 2))
	var second_half_avg := _average(timings.slice(FLAT_TIMING_CHUNK_COUNT / 2, FLAT_TIMING_CHUNK_COUNT))
	print("CaveChunkReproCheck: first-half avg %.2f ms, second-half avg %.2f ms (%d chunks)" % [
		first_half_avg, second_half_avg, FLAT_TIMING_CHUNK_COUNT,
	])
	if second_half_avg > first_half_avg * FLAT_TIMING_MAX_RATIO and second_half_avg > 5.0:
		failures.append("per-chunk generation time grew across the run (%.2f ms -> %.2f ms) -- possible O(n)-in-chunk-count regression" % [first_half_avg, second_half_avg])

	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL:")
		for f in failures:
			print("  - " + f)
		quit(1)


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
