class_name CaveOreDebugDraw
extends Node2D
## Child of a CaveOreOverlayLayer, drawn as its own CanvasItem so its
## z_index is independent of the tile layer's -- the layer's own z_index
## interacts with the parent Tilemaps' y_sort_enabled the same way every
## other wall cell does, which can leave parts of a whole-layer debug draw
## call hidden behind neighboring cells. Living on its own node with a high
## z_index keeps the outlines on top regardless of that.

const RECT_COLOR: Color = Color.BLUE
const RECT_WIDTH: float = 1.0
## Drawn a couple pixels smaller than the tile so the outline falls inside
## the tile border instead of sitting right on top of it.
const RECT_SIZE: Vector2 = Vector2(14, 14)

## Untyped rather than CaveOreOverlayLayer -- the two scripts would otherwise
## type-reference each other (this field vs. CaveOreOverlayLayer's own
## _debug_draw: CaveOreDebugDraw), and GDScript's compiler doesn't resolve
## that cycle cleanly.
var overlay_layer: TileMapLayer


func _draw() -> void:
	if not DebugSettings.show_ore_debug_draw:
		return
	var half_rect := RECT_SIZE / 2.0
	for cell: Vector2i in overlay_layer.call("get_ore_cells"):
		var center := overlay_layer.map_to_local(cell)
		draw_rect(Rect2(center - half_rect, RECT_SIZE), RECT_COLOR, false, RECT_WIDTH)
