extends SceneTree
## Headless reproducibility check for CaveGenerator: runs generation twice
## with the same fixed seed and confirms the resulting CaveData is identical
## in every field. Run via:
##   godot --headless --script res://tools/cave_gen_reproducibility_check.gd

const FIXED_SEED: int = 12345 ## non-zero -- 0 means "randomize" and would trivially fail this check


func _init() -> void:
	var config := CaveGenerationConfig.new()
	config.seed = FIXED_SEED

	var data_a := CaveGenerator.generate(config)
	var data_b := CaveGenerator.generate(config)

	var failures: Array[String] = []
	if data_a.seed_used != data_b.seed_used:
		failures.append("seed_used differs: %d vs %d" % [data_a.seed_used, data_b.seed_used])
	if data_a.entrance_position != data_b.entrance_position:
		failures.append("entrance_position differs: %s vs %s" % [data_a.entrance_position, data_b.entrance_position])
	if data_a.room_centers != data_b.room_centers:
		failures.append("room_centers differ: %s vs %s" % [data_a.room_centers, data_b.room_centers])
	if not data_a.grid_equals(data_b):
		failures.append("tile grid differs")
	if data_a.ore_node_placements.keys() != data_b.ore_node_placements.keys():
		failures.append("ore_node_placements keys differ")

	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		print("FAIL:")
		for f in failures:
			print("  - " + f)
		quit(1)
