@tool
class_name RecipeEditorAtlasRegionPicker
extends VBoxContainer
## Lets the user click-drag a grid-snapped rectangle over a source texture to
## define an AtlasTexture region -- used by the Items tab's icon picker so
## icons cropped from a shared spritesheet follow the same convention as
## every hand-authored item today (materials/ores/ingots crop a shared
## spritesheet; tools crop a dedicated per-item PNG at full size).

signal region_selected(region: Rect2)
signal canceled

const ZOOM: float = 4.0

var source_texture: Texture2D:
	set(value):
		source_texture = value
		if is_instance_valid(_canvas):
			_canvas.texture = value
			_canvas.custom_minimum_size = value.get_size() * ZOOM if value else Vector2.ZERO
			_canvas.queue_redraw()

var grid_size: Vector2i = Vector2i(16, 16):
	set(value):
		grid_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		if is_instance_valid(_canvas):
			_canvas.queue_redraw()

var _selection: Rect2 = Rect2()
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _canvas: TextureRect

func _ready() -> void:
	var grid_row := HBoxContainer.new()
	grid_row.add_child(_make_label("Grid Width"))
	var grid_width_spin := _make_spin_box(grid_size.x)
	grid_width_spin.value_changed.connect(func(v: float) -> void: grid_size = Vector2i(int(v), grid_size.y))
	grid_row.add_child(grid_width_spin)
	grid_row.add_child(_make_label("Grid Height"))
	var grid_height_spin := _make_spin_box(grid_size.y)
	grid_height_spin.value_changed.connect(func(v: float) -> void: grid_size = Vector2i(grid_size.x, int(v)))
	grid_row.add_child(grid_height_spin)
	add_child(grid_row)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = TextureRect.new()
	_canvas.texture = source_texture
	_canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_canvas.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.custom_minimum_size = source_texture.get_size() * ZOOM if source_texture else Vector2.ZERO
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.draw.connect(_on_canvas_draw)
	scroll.add_child(_canvas)
	add_child(scroll)

	var button_row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(spacer)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func() -> void: canceled.emit())
	button_row.add_child(cancel_button)
	var choose_button := Button.new()
	choose_button.text = "Choose"
	choose_button.pressed.connect(func() -> void: region_selected.emit(_selection))
	button_row.add_child(choose_button)
	add_child(button_row)

## Seeds the initial selection rect (e.g. an existing icon's AtlasTexture
## region) in source-texture pixel space, before the picker is shown.
func set_initial_region(region: Rect2) -> void:
	_selection = region
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _make_spin_box(value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 4096
	spin.step = 1
	spin.value = value
	return spin

func _snap_to_grid(point: Vector2) -> Vector2:
	return Vector2(
		roundf(point.x / grid_size.x) * grid_size.x,
		roundf(point.y / grid_size.y) * grid_size.y
	)

func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = _snap_to_grid(event.position / ZOOM)
			_selection = Rect2(_drag_start, Vector2.ZERO)
		else:
			_dragging = false
		_canvas.queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		var current := _snap_to_grid(event.position / ZOOM)
		_selection = Rect2(_drag_start, current - _drag_start).abs()
		_canvas.queue_redraw()

func _on_canvas_draw() -> void:
	if source_texture == null:
		return
	var size := source_texture.get_size()
	var x := 0.0
	while x <= size.x:
		_canvas.draw_line(Vector2(x, 0) * ZOOM, Vector2(x, size.y) * ZOOM, Color(1, 1, 1, 0.15))
		x += grid_size.x
	var y := 0.0
	while y <= size.y:
		_canvas.draw_line(Vector2(0, y) * ZOOM, Vector2(size.x, y) * ZOOM, Color(1, 1, 1, 0.15))
		y += grid_size.y
	if _selection.size != Vector2.ZERO:
		var draw_rect := Rect2(_selection.position * ZOOM, _selection.size * ZOOM)
		_canvas.draw_rect(draw_rect, Color(1, 1, 0, 0.25), true)
		_canvas.draw_rect(draw_rect, Color(1, 1, 0, 1.0), false, 2.0)
