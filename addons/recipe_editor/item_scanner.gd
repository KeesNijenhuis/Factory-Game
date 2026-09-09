@tool
class_name RecipeEditorItemScanner
extends RefCounted
## Recursively discovers every Item resource under the project's items
## folder. Deliberately a standalone copy of ItemRegistry's scan logic
## rather than a call to the ItemRegistry autoload: autoloads only exist
## inside a running game, not in plain editor/addon context, so this addon
## needs its own scan to work with no game running.

const ITEMS_ROOT: String = "res://src/resources/items/"
const TOOL_TIERS_ROOT: String = "res://src/resources/items/tools/tiers/"

static func scan() -> Array[Item]:
	var items: Array[Item] = []
	_scan_directory(ITEMS_ROOT, items)
	items.sort_custom(func(a: Item, b: Item) -> bool: return a.name < b.name)
	return items

static func scan_tool_tiers() -> Array[ToolTierType]:
	var tiers: Array[ToolTierType] = []
	_scan_directory_for_tiers(TOOL_TIERS_ROOT, tiers)
	tiers.sort_custom(func(a: ToolTierType, b: ToolTierType) -> bool: return a.resource_path < b.resource_path)
	return tiers

static func _scan_directory(path: String, out_items: Array[Item]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("RecipeEditorItemScanner: could not open directory: " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := path.path_join(entry)
		if dir.current_is_dir():
			_scan_directory(full_path, out_items)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var resource := ResourceLoader.load(full_path)
			if resource is Item:
				out_items.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()

static func _scan_directory_for_tiers(path: String, out_tiers: Array[ToolTierType]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("RecipeEditorItemScanner: could not open directory: " + path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := path.path_join(entry)
		if dir.current_is_dir():
			_scan_directory_for_tiers(full_path, out_tiers)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var resource := ResourceLoader.load(full_path)
			if resource is ToolTierType:
				out_tiers.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()
