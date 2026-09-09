@tool
extends EditorPlugin

const DockScript := preload("res://addons/terrain_bulk_editor/dock.gd")

var dock_instance: Control


func _enter_tree() -> void:
	# TerrainTemplate already declares "class_name TerrainTemplate" so it is
	# globally registered by Godot automatically - no add_custom_type() needed.
	dock_instance = DockScript.new()
	dock_instance.name = "Terrain Bulk Editor"
	add_control_to_bottom_panel(dock_instance, "Terrain Bulk Editor")


func _exit_tree() -> void:
	remove_control_from_bottom_panel(dock_instance)
	if is_instance_valid(dock_instance):
		dock_instance.queue_free()
