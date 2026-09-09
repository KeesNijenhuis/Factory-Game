extends Node

signal tool_changed(tool_type: Item.ToolTypes)
signal tool_durability_changed(current: int, max: int)
signal hotbar_slot_selected(slot_index: int, item: Item)
signal object_depleted(skill_type: Skill.Type, experience_amount: int)
signal skill_experience_changed(skill_type: Skill.Type, experience: int, level: int)


func _ready():
	# Optional for Windows to allow stealing focus if launched from an editor like VS Code
	if DisplayServer.has_method("enable_for_stealing_focus"):
		DisplayServer.enable_for_stealing_focus(OS.get_process_id())
	
	# Move the window to the foreground
	DisplayServer.window_move_to_foreground()
