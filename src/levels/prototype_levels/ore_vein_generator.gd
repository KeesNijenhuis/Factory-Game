class_name OreVeinGenerator
extends Node
## Placeholder vein placement: for each configured OreVeinRule, picks a
## handful of random standing wall cells and grows each into a small
## connected blob via random walk, marking every cell in it as that rule's
## ore on ore_overlay_layer. Stands in for real vein logic (noise-based,
## density maps, whatever) until that's designed -- the point for now is to
## prove out the generator -> overlay -> mined-item pipeline end to end.

@export var walls_layer_path: NodePath
@export var ore_overlay_layer_path: NodePath
## Which ores this level can spawn, and how many veins/how big each one
## grows -- one rule per ore, editable per level.
@export var vein_rules: Array[OreVeinRule] = []

var walls_layer: CaveWallsLayer
var ore_overlay_layer: CaveOreOverlayLayer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	walls_layer = get_node(walls_layer_path)
	ore_overlay_layer = get_node(ore_overlay_layer_path)
	_generate_veins()


func _generate_veins() -> void:
	var wall_cells: Array[Vector2i] = []
	for cell in walls_layer.get_used_cells():
		if walls_layer.is_wall_cell(cell):
			wall_cells.append(cell)
	wall_cells.shuffle()
	# Shared across every rule so two ores never claim the same cell.
	var claimed_cells: Dictionary = {}
	var candidate_index := 0
	for rule in vein_rules:
		for _i in range(rule.vein_count):
			while candidate_index < wall_cells.size() and claimed_cells.has(wall_cells[candidate_index]):
				candidate_index += 1
			if candidate_index >= wall_cells.size():
				return
			_grow_vein(wall_cells[candidate_index], rule.vein_size, claimed_cells, rule.ore_type)
			candidate_index += 1


func _grow_vein(start: Vector2i, vein_size: int, claimed_cells: Dictionary, ore_type: OreType) -> void:
	var cells: Array[Vector2i] = [start]
	var frontier: Array[Vector2i] = [start]
	claimed_cells[start] = true
	while cells.size() < vein_size and not frontier.is_empty():
		var current: Vector2i = frontier.pick_random()
		var candidates: Array[Vector2i] = []
		for offset in CaveWallsLayer.NEIGHBOR_OFFSETS:
			var neighbor := current + offset
			if walls_layer.is_wall_cell(neighbor) and not claimed_cells.has(neighbor):
				candidates.append(neighbor)
		if candidates.is_empty():
			frontier.erase(current)
			continue
		var next: Vector2i = candidates.pick_random()
		cells.append(next)
		frontier.append(next)
		claimed_cells[next] = true
	for cell in cells:
		ore_overlay_layer.mark_ore_cell(cell, ore_type)
