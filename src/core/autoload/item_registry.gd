extends Node
## Autoload. Resolves an Item's item_id back to the shared preloaded Item
## resource instance -- the save system's item lookup. Scans every .tres/.res
## under ITEMS_ROOT at startup and caches by item_id. ResourceLoader.load()
## returns Godot's cached resource instance for a given path, so this always
## hands back the same shared Item singleton used everywhere else in the game,
## never a duplicate.

const ITEMS_ROOT: String = "res://src/resources/items/"

var _items_by_id: Dictionary = {}

func _ready() -> void:
	_scan_directory(ITEMS_ROOT)

func get_item(item_id: String) -> Item:
	return _items_by_id.get(item_id)

func get_all_items() -> Array[Item]:
	var result: Array[Item] = []
	for item in _items_by_id.values():
		result.append(item)
	result.sort_custom(func(a: Item, b: Item) -> bool: return a.item_id < b.item_id)
	return result

func _scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ItemRegistry: could not open directory: " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := path.path_join(entry)
		if dir.current_is_dir():
			_scan_directory(full_path)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			_register_item_resource(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _register_item_resource(resource_path: String) -> void:
	var resource := ResourceLoader.load(resource_path)
	if resource is not Item:
		return
	var item := resource as Item
	if item.item_id.is_empty():
		push_warning("ItemRegistry: item at %s has an empty item_id, skipping" % resource_path)
		return
	if _items_by_id.has(item.item_id):
		push_warning("ItemRegistry: duplicate item_id '%s' (%s)" % [item.item_id, resource_path])
	_items_by_id[item.item_id] = item
