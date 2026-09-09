@tool
class_name RecipeEditorItemButton
extends TextureButton
## One entry in the item picker grid: shows an item's icon, is clickable to
## select it, and is a native drag source so it can be dropped onto a
## RecipeEditorShapeCell to build a shaped recipe.

const DRAG_PAYLOAD_TYPE: String = "recipe_editor_item"
const ARMED_COLOR: Color = Color(1.0, 0.8, 0.2)

signal right_clicked(button: RecipeEditorItemButton)
signal drag_started

var item: Item
var armed: bool = false:
	set(value):
		armed = value
		queue_redraw()

const ICON_SIZE: Vector2 = Vector2(64, 64)

func setup(new_item: Item) -> void:
	item = new_item
	texture_normal = item.icon
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = ICON_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tooltip_text = item.name
	gui_input.connect(_on_gui_input)

## Connected to the `gui_input` signal rather than overriding the `_gui_input`
## virtual -- BaseButton's own internal (C++) _gui_input handles left-click
## presses, and a GDScript override would replace that instead of layering on
## top of it, breaking normal button clicks.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(self)

func _draw() -> void:
	if armed:
		draw_rect(Rect2(Vector2.ZERO, size), ARMED_COLOR, false, 2.0)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	drag_started.emit()
	var preview := TextureRect.new()
	preview.texture = item.icon
	preview.custom_minimum_size = ICON_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_drag_preview(preview)
	return {"type": DRAG_PAYLOAD_TYPE, "item": item}
