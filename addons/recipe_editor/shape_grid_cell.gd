@tool
class_name RecipeEditorShapeCell
extends Control
## A single item slot: shows the item placed there (or an empty bordered
## square so the drop target is visible before anything's placed), accepts a
## drag from a RecipeEditorItemButton, and clears itself on right-click.
## Generic enough to serve as a shaped-recipe grid cell, an output slot, or a
## smelting input slot -- any tab that needs "drag an item onto this spot".

signal item_dropped(cell_index: int, item: Item)
signal cell_cleared(cell_index: int)

const CELL_SIZE: float = 64.0
const ICON_PADDING: float = 6.0
const FILL_COLOR: Color = Color(1, 1, 1, 0.1)
const BORDER_COLOR: Color = Color(1, 1, 1, 0.5)

## Getter (bound Callable, no args) returning the currently-armed Item to
## paint with, or null if none -- wired up by the dock for shape-grid cells
## only. Left unset (invalid) for cells that shouldn't support painting
## (output slots, smelting inputs), which the input handler checks for.
var paint_source: Callable = Callable()

var cell_index: int = 0
var item: Item:
	set(value):
		item = value
		tooltip_text = item.name if item else ""
		queue_redraw()

func _init() -> void:
	# Set immediately (not just in _ready) so a cell built and populated
	# before it enters the tree (e.g. a dynamically added smelting input
	# row) already has its minimum size when the parent container first
	# lays out, instead of only after _ready() fires.
	custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, FILL_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, 1.0)
	if item and item.icon:
		draw_texture_rect(item.icon, _fit_icon_rect(rect.grow(-ICON_PADDING), item.icon.get_size()), false)

## Uniformly scales texture_size to fit inside bounds without stretching
## (pixel art must never be stretched off-aspect), centered.
func _fit_icon_rect(bounds: Rect2, texture_size: Vector2) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return bounds
	var scale_factor: float = minf(bounds.size.x / texture_size.x, bounds.size.y / texture_size.y)
	var drawn_size := texture_size * scale_factor
	var origin := bounds.position + (bounds.size - drawn_size) * 0.5
	return Rect2(origin, drawn_size)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == RecipeEditorItemButton.DRAG_PAYLOAD_TYPE

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item = data["item"]
	item_dropped.emit(cell_index, item)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		item = null
		cell_cleared.emit(cell_index)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_paint()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_try_paint()

## Applies the currently-armed paint item (if any) to this cell -- called on
## both an initial left-click and on drag-over, so click-and-drag paints
## every cell the cursor crosses.
func _try_paint() -> void:
	if not paint_source.is_valid():
		return
	var paint_item: Item = paint_source.call()
	if paint_item == null:
		return
	item = paint_item
	item_dropped.emit(cell_index, item)

func set_enabled(enabled: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	modulate.a = 1.0 if enabled else 0.4
