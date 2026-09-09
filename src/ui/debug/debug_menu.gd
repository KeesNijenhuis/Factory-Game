extends Control

@onready var mining_checkbox: CheckBox = %MiningCheckBox
@onready var fps_checkbox: CheckBox = %FPSCheckBox
@onready var tool_checkbox: CheckBox = %ToolCheckBox
@onready var item_cheat_checkbox: CheckBox = %ItemCheatCheckBox
@onready var zoom_checkbox: CheckBox = %ZoomCheckBox
@onready var ore_debug_checkbox: CheckBox = %OreDebugCheckBox
@onready var placement_footprint_checkbox: CheckBox = %PlacementFootprintCheckBox


func _ready() -> void:
	visible = false
	mining_checkbox.toggled.connect(func(pressed: bool) -> void: DebugSettings.show_mining_debug = pressed)
	fps_checkbox.toggled.connect(func(pressed: bool) -> void: DebugSettings.show_fps = pressed)
	tool_checkbox.toggled.connect(func(pressed: bool) -> void: DebugSettings.show_tool_debug = pressed)
	item_cheat_checkbox.toggled.connect(func(pressed: bool) -> void: DebugSettings.enable_item_cheat = pressed)
	zoom_checkbox.toggled.connect(func(pressed: bool) -> void: DebugSettings.enable_camera_zoom = pressed)
	ore_debug_checkbox.toggled.connect(_on_ore_debug_toggled)
	placement_footprint_checkbox.toggled.connect(func(pressed: bool) -> void: DebugSettings.show_placement_footprint = pressed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_menu"):
		visible = not visible
		if visible:
			_populate()


func _populate() -> void:
	mining_checkbox.button_pressed = DebugSettings.show_mining_debug
	fps_checkbox.button_pressed = DebugSettings.show_fps
	tool_checkbox.button_pressed = DebugSettings.show_tool_debug
	item_cheat_checkbox.button_pressed = DebugSettings.enable_item_cheat
	zoom_checkbox.button_pressed = DebugSettings.enable_camera_zoom
	ore_debug_checkbox.button_pressed = DebugSettings.show_ore_debug_draw
	placement_footprint_checkbox.button_pressed = DebugSettings.show_placement_footprint


## Unlike the other flags here, CaveOreOverlayLayer only redraws when its own
## tiles change -- nothing polls this flag every frame -- so toggling it also
## has to explicitly nudge every current layer to repaint right away.
func _on_ore_debug_toggled(pressed: bool) -> void:
	DebugSettings.show_ore_debug_draw = pressed
	get_tree().call_group(&"ore_overlay_layers", &"queue_redraw")
