extends Node
## Autoload. Orchestrates the full save/load system: numbered slots, autosave
## on level transition, and debug quicksave/quickload. Gathers/applies state
## from Player, the two Inventories, Hotbar, the current level's "saveable"
## group (containers, depletable resource nodes, and any future opt-in type),
## and dynamically-spawned GroundItems.

const SAVE_VERSION: int = 1
## Number of manual save slots shown in the Save/Load panel, in addition to
## the quicksave slot (slot id QUICKSAVE_SLOT), which is always listed first.
const MAX_SLOTS: int = 4
const QUICKSAVE_SLOT: int = 0
const SAVE_DIR: String = "user://saves/"
const QUICKSAVE_PATH: String = SAVE_DIR + "quicksave.json"
const AUTOSAVE_PATH: String = SAVE_DIR + "autosave.json"

signal save_completed(slot: int)
signal save_failed(slot: int, reason: String)
signal load_completed(slot: int)
signal load_failed(slot: int, reason: String)
signal slot_deleted(slot: int)

var _main_game: MainGame = null
var _busy: bool = false
var _is_loading: bool = false
var _has_completed_first_level_load: bool = false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func register_main_game(main_game: Node) -> void:
	_main_game = main_game as MainGame
	_main_game.level_loaded.connect(_on_level_loaded)

## --- Public save/load API ---------------------------------------------

func save_game(slot: int) -> void:
	_write_to_path(_slot_path(slot), slot)

func load_game(slot: int) -> void:
	await _load_from_path(_slot_path(slot), slot)

func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	slot_deleted.emit(slot)

func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in range(QUICKSAVE_SLOT, MAX_SLOTS + 1):
		var path := _slot_path(slot)
		var info := {"slot": slot, "exists": false, "saved_at": "", "level_uid": ""}
		if FileAccess.file_exists(path):
			var data := _read_json(path)
			if not data.is_empty():
				info.exists = true
				info.saved_at = data.get("saved_at", "")
				info.level_uid = data.get("level_uid", "")
		result.append(info)
	return result

func quicksave() -> void:
	_write_to_path(QUICKSAVE_PATH, -1)

func quickload() -> void:
	await _load_from_path(QUICKSAVE_PATH, -1)

func autosave() -> void:
	if _busy:
		return
	_write_to_path(AUTOSAVE_PATH, -1)

## --- Level-transition autosave hook -------------------------------------

func _on_level_loaded(_level: BaseLevel) -> void:
	if _is_loading:
		return # this transition came from our own load_game()/quickload(), not gameplay
	if not _has_completed_first_level_load:
		_has_completed_first_level_load = true
		return # skip the initial boot-time load
	autosave()

## --- Save --------------------------------------------------------------

func _write_to_path(path: String, slot: int) -> void:
	if _busy:
		return
	_busy = true
	var data := _gather_full_state()
	var ok := _write_json(path, data)
	_busy = false
	if ok:
		save_completed.emit(slot)
	else:
		save_failed.emit(slot, "Could not write save file: " + path)

func _gather_full_state() -> Dictionary:
	var main_game := _main_game
	var level := main_game.get_current_level()
	var hud := _find_hud()
	var data := {
		"save_version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"level_uid": main_game.current_level_uid,
		"player": _gather_player_state(main_game.player),
		"inventories": {
			"player": SaveSerializationUtils.serialize_inventory(Inventory.items, Inventory.quantities, Inventory.durabilities),
			"hotbar": _gather_hotbar_state(hud),
		},
		"world_objects": _gather_world_objects(level),
		"ground_items": _gather_ground_items(main_game.entity_root),
		"placed_objects": _gather_placed_objects(level),
	}
	return data

func _gather_player_state(player: Player) -> Dictionary:
	var skills := {}
	for skill in player.skills_manager.get_skills():
		skills[str(skill.skill_type)] = {"level": skill.level, "experience": skill.experience}
	return {
		"position": {"x": player.global_position.x, "y": player.global_position.y},
		"last_direction": player.last_direction,
		"god_mode": player.god_mode,
		"skills": skills,
	}

func _gather_hotbar_state(hud: HUD) -> Dictionary:
	if hud == null:
		return {}
	var hotbar_inventory: Node = hud.hotbar.get_node("Inventory")
	var data := SaveSerializationUtils.serialize_inventory(hotbar_inventory.items, hotbar_inventory.quantities, hotbar_inventory.durabilities)
	data["selected_slot"] = hud.hotbar.selected_slot
	return data

func _gather_world_objects(level: BaseLevel) -> Dictionary:
	var result := {}
	if level == null:
		return result
	for node in get_tree().get_nodes_in_group("saveable"):
		if not level.is_ancestor_of(node):
			continue
		var id: String = node.get_save_id()
		if id != "":
			result[id] = node.get_save_data()
	return result

func _gather_ground_items(entity_root: Node2D) -> Array:
	var result := []
	for child in entity_root.get_children():
		if child is GroundItem and child.item != null:
			result.append({
				"item_id": child.item.item_id,
				"quantity": child.quantity,
				"durability": child.durability,
				"position": {"x": child.global_position.x, "y": child.global_position.y},
			})
	return result

## Records world objects that were placed by the player at runtime (i.e.
## added as plain children of the Objects TileMapLayer, rather than backed by
## real tile-cell data like design-time TileSetScenesCollectionSource
## placements). Those recreate themselves automatically when the level scene
## reloads; these don't, so they need to be respawned explicitly on load --
## see _apply_placed_objects().
func _gather_placed_objects(level: BaseLevel) -> Array:
	var result := []
	if level == null:
		return result
	var objects_layer: TileMapLayer = level.get_objects_layer()
	for child in objects_layer.get_children():
		if child is not Node2D or child.scene_file_path == "":
			continue
		var cell: Vector2i = objects_layer.local_to_map(child.position)
		if objects_layer.get_cell_source_id(cell) != -1:
			continue
		result.append({
			"scene_path": child.scene_file_path,
			"cell": {"x": cell.x, "y": cell.y},
		})
	return result

## --- Load ----------------------------------------------------------------

func _load_from_path(path: String, slot: int) -> void:
	if _busy:
		return
	if not FileAccess.file_exists(path):
		load_failed.emit(slot, "Save file does not exist: " + path)
		return
	var data := _read_json(path)
	if data.is_empty():
		load_failed.emit(slot, "Could not read/parse save file: " + path)
		return

	_busy = true
	_is_loading = true

	var hud := _find_hud()
	if hud:
		hud.close_all_panels()

	var main_game := _main_game
	main_game.load_level(data.get("level_uid", main_game.current_level_uid), true)
	await main_game.level_loaded
	# TileMapLayer scene-collection cells (chests, furnaces, ore/tree objects)
	# can finish instantiating a frame or two after level_loaded fires -- wait
	# for them to settle before scanning the "saveable" group, or objects in
	# quadrants that haven't built yet get silently skipped.
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = main_game.player
	_apply_player_state(player, data.get("player", {}))
	main_game.snap_camera_to_player()

	SaveSerializationUtils.apply_inventory(Inventory, data.get("inventories", {}).get("player", {}))

	if hud != null:
		var hotbar_data: Dictionary = data.get("inventories", {}).get("hotbar", {})
		var hotbar_inventory: Node = hud.hotbar.get_node("Inventory")
		SaveSerializationUtils.apply_inventory(hotbar_inventory, hotbar_data)
		hud.hotbar.selected_slot = hotbar_data.get("selected_slot", 0)
		hud.hotbar.emit_selection()

	_apply_placed_objects(main_game.get_current_level(), data.get("placed_objects", []))
	_apply_world_objects(main_game.get_current_level(), data.get("world_objects", {}))
	_apply_ground_items(main_game.entity_root, data.get("ground_items", []))
	# Belts' real saved facing (just applied above via apply_save_data) can
	# still change their segment shape after main_game's own post-load
	# rebuild already ran once -- this is the authoritative, final pass once
	# every belt's facing has settled.
	BeltManager.rebuild_all_segments()

	await main_game.finish_load_transition()

	_is_loading = false
	_busy = false
	load_completed.emit(slot)

func _apply_player_state(player: Player, data: Dictionary) -> void:
	var position: Dictionary = data.get("position", {})
	if not position.is_empty():
		player.global_position = Vector2(position.get("x", player.global_position.x), position.get("y", player.global_position.y))
	player.last_direction = data.get("last_direction", player.last_direction)
	player.god_mode = data.get("god_mode", player.god_mode)
	var skills: Dictionary = data.get("skills", {})
	for skill in player.skills_manager.get_skills():
		var skill_data: Dictionary = skills.get(str(skill.skill_type), {})
		if not skill_data.is_empty():
			skill.level = skill_data.get("level", skill.level)
			skill.experience = skill_data.get("experience", skill.experience)

## Respawns objects the player placed at runtime (see _gather_placed_objects)
## before _apply_world_objects runs, so their InteractableContainer._ready()
## has already self-registered into "saveable" by the time that pass looks
## for a node to hand its inventory/state data to.
func _apply_placed_objects(level: BaseLevel, entries: Array) -> void:
	if level == null:
		return
	var objects_layer: TileMapLayer = level.get_objects_layer()
	for entry in entries:
		var scene_path: String = entry.get("scene_path", "")
		var packed_scene: PackedScene = load(scene_path) if scene_path != "" else null
		if packed_scene == null:
			continue
		var instance := packed_scene.instantiate()
		var cell_data: Dictionary = entry.get("cell", {})
		var cell := Vector2i(cell_data.get("x", 0), cell_data.get("y", 0))
		# Position must be set before add_child() -- see the matching comment
		# in PlacementController._place_item(). Getting this backwards here is
		# what silently dropped/misapplied saved inventories for every
		# runtime-placed furnace/chest: every respawned instance computed the
		# same wrong save id from the scene's default (0,0) position, so they
		# collided with each other's data instead of matching their own.
		instance.position = objects_layer.map_to_local(cell)
		objects_layer.add_child(instance)

func _apply_world_objects(level: BaseLevel, data: Dictionary) -> void:
	if level == null:
		return
	for node in get_tree().get_nodes_in_group("saveable"):
		if not level.is_ancestor_of(node):
			continue
		var id: String = node.get_save_id()
		if data.has(id):
			node.apply_save_data(data[id])

func _apply_ground_items(entity_root: Node2D, entries: Array) -> void:
	for child in entity_root.get_children():
		if child is GroundItem:
			child.queue_free()
	for entry in entries:
		var item: Item = ItemRegistry.get_item(entry.get("item_id", ""))
		if item == null:
			continue
		var position := Vector2(entry.get("position", {}).get("x", 0.0), entry.get("position", {}).get("y", 0.0))
		GroundItem.spawn(entity_root, item, entry.get("quantity", 1), position, entry.get("durability", -1))

## --- File I/O helpers ------------------------------------------------------

func _slot_path(slot: int) -> String:
	if slot == QUICKSAVE_SLOT:
		return QUICKSAVE_PATH
	return SAVE_DIR + "slot_%d.json" % slot

func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open for write: " + path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return {}
	return parsed

func _find_hud() -> HUD:
	return get_tree().root.find_child("HudRoot", true, false) as HUD
