extends HBoxContainer
class_name SaveSlotRow
## One row in the save/load menu: shows a slot's status and exposes
## Save/Load/Delete buttons. Pure UI -- SaveLoadPanel owns the SaveManager
## calls and just tells this row what to display via setup().

signal save_pressed(slot: int)
signal load_pressed(slot: int)
signal delete_pressed(slot: int)

@onready var label: Label = %Label
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var delete_button: Button = %DeleteButton

var _slot: int = -1

func _ready() -> void:
	save_button.pressed.connect(func(): save_pressed.emit(_slot))
	load_button.pressed.connect(func(): load_pressed.emit(_slot))
	delete_button.pressed.connect(func(): delete_pressed.emit(_slot))

func setup(slot: int, info: Dictionary) -> void:
	_slot = slot
	var exists: bool = info.get("exists", false)
	var slot_name := "Quicksave" if slot == SaveManager.QUICKSAVE_SLOT else "Save Game %d" % slot
	if exists:
		label.text = "%s - %s" % [slot_name, _format_timestamp(info.get("saved_at", ""))]
	else:
		label.text = "%s -- empty" % slot_name
	load_button.disabled = not exists
	delete_button.disabled = not exists

## Reformats the ISO 8601 datetime string SaveManager stores ("saved_at") into
## the human-readable "DD/MM/YYYY - HH:MM" shown in the panel.
func _format_timestamp(iso_datetime: String) -> String:
	if iso_datetime.is_empty():
		return ""
	var d := Time.get_datetime_dict_from_datetime_string(iso_datetime, false)
	return "%02d/%02d/%04d - %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]
