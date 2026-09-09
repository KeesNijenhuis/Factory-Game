class_name ItemNameTooltip

const GAP: float = 8.0

## Picks a global position for `panel` that stays fully inside `viewport_size`
## and never overlaps `hovered_rect` (the slot being hovered). Each candidate
## sits entirely above, below, right of, or left of `hovered_rect` on one axis
## -- guaranteeing no overlap by construction -- while the other axis follows
## `mouse_global_position`, clamped to the viewport. A fixed offset from the
## cursor alone can't satisfy this for both a mid-screen inventory grid and a
## hotbar pinned to the bottom edge, so placement is anchored to the hovered
## slot instead and only nudged toward the cursor.
static func position(panel: Control, mouse_global_position: Vector2, hovered_rect: Rect2, viewport_size: Vector2) -> Vector2:
	var size := panel.get_combined_minimum_size()
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var max_x := maxf(0.0, viewport_rect.size.x - size.x)
	var max_y := maxf(0.0, viewport_rect.size.y - size.y)
	var clamped_mouse_x := clampf(mouse_global_position.x, 0.0, max_x)
	var clamped_mouse_y := clampf(mouse_global_position.y, 0.0, max_y)

	var candidates: Array[Vector2] = [
		Vector2(clamped_mouse_x, hovered_rect.end.y + GAP), # below
		Vector2(clamped_mouse_x, hovered_rect.position.y - size.y - GAP), # above
		Vector2(hovered_rect.end.x + GAP, clamped_mouse_y), # right
		Vector2(hovered_rect.position.x - size.x - GAP, clamped_mouse_y), # left
	]
	for candidate in candidates:
		if viewport_rect.encloses(Rect2(candidate, size)):
			return candidate

	return Vector2(clamped_mouse_x, clamped_mouse_y)
