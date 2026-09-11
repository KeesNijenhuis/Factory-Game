extends Node

## Emitted from elsewhere (player.gd), not this file -- the analyzer can't see
## that usage, so it flags these as unused without this annotation.
@warning_ignore("unused_signal")
signal tool_changed(tool_type: Item.ToolTypes)
@warning_ignore("unused_signal")
signal tool_durability_changed(current: int, max: int)
@warning_ignore("unused_signal")
signal hotbar_slot_selected(slot_index: int, item: Item)
@warning_ignore("unused_signal")
signal object_depleted(skill_type: Skill.Type, experience_amount: int)
@warning_ignore("unused_signal")
signal skill_experience_changed(skill_type: Skill.Type, experience: int, level: int)


func _ready():
	# Optional for Windows to allow stealing focus if launched from an editor like VS Code
	if DisplayServer.has_method("enable_for_stealing_focus"):
		DisplayServer.enable_for_stealing_focus(OS.get_process_id())
	
	# Move the window to the foreground
	DisplayServer.window_move_to_foreground()
