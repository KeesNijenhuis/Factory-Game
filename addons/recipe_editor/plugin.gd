@tool
extends EditorPlugin

const DockScript := preload("res://addons/recipe_editor/dock.gd")

const MENU_ITEM_NAME: String = "Recipe Editor"
const WINDOW_STATE_PATH: String = "user://recipe_editor_window_state.cfg"
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(1150, 750)
const MIN_WINDOW_SIZE: Vector2i = Vector2i(900, 600)

var dock_instance: Control
var window: Window
var docked_to_bottom_panel: bool = false


func _enter_tree() -> void:
	dock_instance = DockScript.new()
	dock_instance.name = "Recipe Editor"
	dock_instance.set_anchors_preset(Control.PRESET_FULL_RECT)

	window = Window.new()
	window.title = "Recipe Editor"
	window.min_size = MIN_WINDOW_SIZE
	# Window defaults to visible=true, so it would otherwise pop up empty
	# the moment it's added to the tree, even though nothing has shown it yet.
	window.visible = false
	add_child(window)
	_restore_window_state()
	window.close_requested.connect(_on_window_close_requested)
	# There's no dedicated "moved" signal on Window, so size_changed is the
	# only live hook available -- it also fires on most resize interactions,
	# which is enough to catch a crash/force-quit that skips the
	# close_requested/_exit_tree save points below.
	window.size_changed.connect(_save_window_state)

	# Docked to the bottom panel by default; the tool menu item pops it out
	# into the floating window instead.
	add_control_to_bottom_panel(dock_instance, MENU_ITEM_NAME)
	docked_to_bottom_panel = true

	add_tool_menu_item(MENU_ITEM_NAME, _show_as_window)


func _exit_tree() -> void:
	_save_window_state()
	remove_tool_menu_item(MENU_ITEM_NAME)
	if docked_to_bottom_panel:
		remove_control_from_bottom_panel(dock_instance)
		docked_to_bottom_panel = false
	if is_instance_valid(window):
		window.queue_free()
	if is_instance_valid(dock_instance) and dock_instance.get_parent() == null:
		dock_instance.queue_free()


## Closing the floating window re-homes the editor as a bottom panel tab
## (like Output/Debugger) instead of just hiding it, so it stays reachable.
func _on_window_close_requested() -> void:
	_save_window_state()
	window.remove_child(dock_instance)
	window.hide()
	add_control_to_bottom_panel(dock_instance, MENU_ITEM_NAME)
	docked_to_bottom_panel = true


func _show_as_window() -> void:
	if docked_to_bottom_panel:
		remove_control_from_bottom_panel(dock_instance)
		docked_to_bottom_panel = false
	if dock_instance.get_parent() != window:
		window.add_child(dock_instance)
	window.show()
	window.grab_focus()

## Window position/size live in user:// (per-project local editor state, not
## a committed project resource) rather than ProjectSettings, since this is a
## personal UI preference that shouldn't end up in version control.
func _restore_window_state() -> void:
	var config := ConfigFile.new()
	if config.load(WINDOW_STATE_PATH) == OK:
		window.size = config.get_value("window", "size", DEFAULT_WINDOW_SIZE)
		window.position = config.get_value("window", "position", window.position)
	else:
		window.size = DEFAULT_WINDOW_SIZE

func _save_window_state() -> void:
	if not is_instance_valid(window):
		return
	var config := ConfigFile.new()
	config.set_value("window", "size", window.size)
	config.set_value("window", "position", window.position)
	config.save(WINDOW_STATE_PATH)
