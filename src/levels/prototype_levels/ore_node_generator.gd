class_name OreNodeGenerator
extends Node
## Scatters ore-node scene instances (copper/iron/gold/coal's standalone
## harvestable objects) onto bare floor cells -- ground present and not dug
## out, no wall, no object already there. One rule per ore, editable per
## level, mirroring OreVeinGenerator's split between reusable identity
## (OreNodeType) and per-level spawn count (OreNodeSpawnRule).

@export var ground_layer_path: NodePath
@export var walls_layer_path: NodePath
@export var objects_layer_path: NodePath
@export var spawn_rules: Array[OreNodeSpawnRule] = []

var ground_layer: TileMapLayer
var walls_layer: TileMapLayer
var objects_layer: TileMapLayer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	ground_layer = get_node(ground_layer_path)
	walls_layer = get_node(walls_layer_path)
	objects_layer = get_node(objects_layer_path)
	_generate_nodes()


func _generate_nodes() -> void:
	var free_cells := _get_free_cells()
	free_cells.shuffle()
	var index := 0
	for rule in spawn_rules:
		for _i in range(rule.count):
			if index >= free_cells.size():
				return
			_spawn_node(free_cells[index], rule.node_type)
			index += 1


func _get_free_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in ground_layer.get_used_cells():
		if walls_layer.get_cell_source_id(cell) == -1 \
				and not (ground_layer as CaveGroundLayer).is_dug(cell) \
				and not AutomationUtils.is_cell_occupied(objects_layer, cell):
			cells.append(cell)
	return cells


func _spawn_node(cell: Vector2i, node_type: OreNodeType) -> void:
	var instance: Node2D = node_type.scene.instantiate()
	instance.position = objects_layer.map_to_local(cell)
	objects_layer.add_child(instance)
