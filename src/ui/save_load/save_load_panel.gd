extends Control
class_name SaveLoadPanel
## Basic save/load menu: one SaveSlotRow per numbered slot. Toggled with the
## save_menu action, pauses the tree while open (mirrors the pattern other
## panels like SkillsPanel use for their own toggle keys).

const SAVE_SLOT_ROW_SCENE: PackedScene = preload("res://src/ui/save_load/save_slot_row.tscn")

@onready var container: VBoxContainer = %Container

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for slot in range(SaveManager.QUICKSAVE_SLOT, SaveManager.MAX_SLOTS + 1):
		var row: SaveSlotRow = SAVE_SLOT_ROW_SCENE.instantiate()
		container.add_child(row)
		row.save_pressed.connect(SaveManager.save_game)
		row.load_pressed.connect(SaveManager.load_game)
		row.delete_pressed.connect(SaveManager.delete_slot)
	SaveManager.save_completed.connect(func(_slot): _refresh())
	SaveManager.load_completed.connect(func(_slot): _close())
	SaveManager.slot_deleted.connect(func(_slot): _refresh())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"save_menu"):
		if not visible:
			var hud := get_tree().get_first_node_in_group("hud") as HUD
			if hud and hud.is_any_panel_visible():
				return
		visible = not visible
		get_tree().paused = visible
		if visible:
			_refresh()

func _refresh() -> void:
	var slots := SaveManager.list_slots()
	for i in slots.size():
		var row: SaveSlotRow = container.get_child(i)
		row.setup(slots[i].slot, slots[i])

func _close() -> void:
	visible = false
	get_tree().paused = false
