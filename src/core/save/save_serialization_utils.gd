class_name SaveSerializationUtils
extends RefCounted
## Shared helpers for converting live game state to/from JSON-safe Dictionaries.
## Used by SaveManager and every "saveable" world object (Chest, Furnace,
## ObjectResource) so each doesn't reimplement inventory/id serialization.

## Derives a stable save id for a TileMapLayer-placed scene (chest, furnace,
## ore/tree object). These are placed via the TileMap editor's scene-collection
## tile sources, so Godot instantiates them as runtime children of the
## TileMapLayer with auto-generated, non-deterministic sibling names -- NodePath
## is not stable across loads. The placement cell coordinate is: since the node
## is parented directly under the TileMapLayer at the position it was placed,
## local_to_map(position) recovers the exact cell it came from.
static func compute_tile_object_id(node: Node2D) -> String:
	var layer := node.get_parent() as TileMapLayer
	if layer == null:
		push_warning("%s is not parented under a TileMapLayer -- no stable save id available" % node.name)
		return ""
	var cell: Vector2i = layer.local_to_map(node.position)
	return "%s@%d,%d" % [layer.name, cell.x, cell.y]

## Converts an inventory's parallel arrays into a JSON-safe Dictionary, keying
## each item by its item_id (resolved back to the shared Item resource via
## ItemRegistry on load) rather than serializing the Resource itself.
static func serialize_inventory(items: Array, quantities: Array, durabilities: Array) -> Dictionary:
	var item_ids: Array = []
	for item in items:
		item_ids.append(item.item_id if item != null else null)
	return {
		"items": item_ids,
		"quantities": quantities.duplicate(),
		"durabilities": durabilities.duplicate(),
	}

## Writes saved inventory data back into an existing Inventory node's arrays.
## Writes element-wise (rather than replacing the arrays outright) since
## Inventory._ready() has already sized items/quantities/durabilities to
## rows*columns -- a save from a differently-sized inventory config degrades
## gracefully instead of desyncing slot count. Emits on_inventory_changed so
## dependents (e.g. Furnace.current_recipe) self-derive from the new contents.
static func apply_inventory(inventory_node: Node, data: Dictionary) -> void:
	var saved_items: Array = data.get("items", [])
	var saved_quantities: Array = data.get("quantities", [])
	var saved_durabilities: Array = data.get("durabilities", [])
	for i in inventory_node.items.size():
		var item_id = saved_items[i] if i < saved_items.size() else null
		inventory_node.items[i] = ItemRegistry.get_item(item_id) if item_id else null
		inventory_node.quantities[i] = saved_quantities[i] if i < saved_quantities.size() else 0
		inventory_node.durabilities[i] = saved_durabilities[i] if i < saved_durabilities.size() else -1
	inventory_node.on_inventory_changed.emit()
