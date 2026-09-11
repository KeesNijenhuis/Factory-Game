class_name ChunkLoadDebugOverlay
extends Node2D

const GENERATED_COLOR := Color(1.0, 0.35, 0.2, 0.9)
const DISK_COLOR := Color(0.25, 0.85, 1.0, 0.9)
const SAVE_COLOR := Color(0.5, 1.0, 0.35, 0.9)

var _chunks: Dictionary = {}


func set_chunk_status(chunk_coord: Vector2i, rect: Rect2, status: String) -> void:
	_chunks[chunk_coord] = {"rect": rect, "status": status}
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for entry: Dictionary in _chunks.values():
		var rect: Rect2 = entry.rect
		var status: String = entry.status
		var color := GENERATED_COLOR
		if status == "disk":
			color = DISK_COLOR
		elif status == "save":
			color = SAVE_COLOR
		draw_rect(rect, color, false, 5.0)
		draw_string(font, rect.position + Vector2(12.0, 28.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, color)
