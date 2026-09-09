extends Control

@onready var fps_label: Label = $FPSLabel


func _process(_delta: float) -> void:
	visible = DebugSettings.show_fps
	if visible:
		show_fps_label()

func show_fps_label()-> void:
	fps_label.text = str("FPS: ", Engine.get_frames_per_second())
