class_name PlayerSpawn
extends Marker2D


func _ready() -> void:
	if not Engine.is_editor_hint():
		$ReferenceVisual.hide()
