@tool
class_name TerrainTemplate
extends Resource

## A reusable "stamp" of terrain peering bits + collision, sized W x H tiles.
## Terrain SET/ID themselves are intentionally NOT stored here - they are
## picked at apply-time in the dock, so one template can be reused across
## different terrains and different TileSets.
##
## `cells` is a flat, row-major array (index = y * size.x + x). Each entry is
## a Dictionary shaped like:
## {
##   "bits": { <TileSet.CellNeighbor int>: true/false, ... },
##   "has_collision": bool,
##   "physics_layer": int,
##   "polygon": PackedVector2Array,  # tile-local, centered on the tile
##   "is_null": bool   # true = deliberately no tile here; Apply leaves the
##                      # destination tile completely untouched instead of
##                      # writing this cell's (all-empty) bits/collision to it
## }

enum ViewMode { TERRAIN, COLLISION }

## Sentinel "bit" for the unused center square of the 3x3 peering-bit grid.
## It has no TileSet.CellNeighbor counterpart and never affects terrain
## matching - it's purely a per-tile visual toggle (see get/set_cosmetic_
## center below) so the overlay can look like a solid filled block.
const CENTER_BIT := -2

const COSMETIC_CENTER_META := "terrain_bulk_editor_cosmetic_center"

const NEIGHBORS := [
	{"dir": Vector2i(1, 0), "enum": TileSet.CELL_NEIGHBOR_RIGHT_SIDE, "label": "E"},
	{"dir": Vector2i(1, 1), "enum": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, "label": "SE"},
	{"dir": Vector2i(0, 1), "enum": TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, "label": "S"},
	{"dir": Vector2i(-1, 1), "enum": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, "label": "SW"},
	{"dir": Vector2i(-1, 0), "enum": TileSet.CELL_NEIGHBOR_LEFT_SIDE, "label": "W"},
	{"dir": Vector2i(-1, -1), "enum": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, "label": "NW"},
	{"dir": Vector2i(0, -1), "enum": TileSet.CELL_NEIGHBOR_TOP_SIDE, "label": "N"},
	{"dir": Vector2i(1, -1), "enum": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, "label": "NE"},
]

## Maps each of the 8 non-center squares of a 3x3 division of tile_rect to its
## TileSet.CellNeighbor enum. Center square is intentionally omitted.
static func get_peering_bit_rects(tile_rect: Rect2) -> Dictionary:
	var cell_w := tile_rect.size.x / 3.0
	var cell_h := tile_rect.size.y / 3.0
	var rects := {}
	for n in NEIGHBORS:
		var gx: int = n["dir"].x + 1
		var gy: int = n["dir"].y + 1
		var pos := tile_rect.position + Vector2(gx * cell_w, gy * cell_h)
		rects[n["enum"]] = Rect2(pos, Vector2(cell_w, cell_h))
	rects[CENTER_BIT] = Rect2(tile_rect.position + Vector2(cell_w, cell_h), Vector2(cell_w, cell_h))
	return rects


## Returns the CellNeighbor enum for the square containing point (same
## coordinate space as tile_rect), or -1 outside tile_rect / in the center.
static func get_peering_bit_at_point(tile_rect: Rect2, point: Vector2) -> int:
	if not tile_rect.has_point(point):
		return -1
	var local := point - tile_rect.position
	var col: int = clampi(int(local.x / (tile_rect.size.x / 3.0)), 0, 2)
	var row: int = clampi(int(local.y / (tile_rect.size.y / 3.0)), 0, 2)
	if col == 1 and row == 1:
		return CENTER_BIT
	var dir := Vector2i(col - 1, row - 1)
	for n in NEIGHBORS:
		if n["dir"] == dir:
			return n["enum"]
	return -1


## Returns the destination Rect2 (within a control of available_size, inset
## by padding px on all sides) that content of content_size should be drawn
## into: uniformly scaled so pixel art is never stretched, and centered.
static func fit_content_rect(content_size: Vector2, available_size: Vector2, padding: float) -> Rect2:
	var avail := Vector2(max(available_size.x - padding * 2.0, 1.0), max(available_size.y - padding * 2.0, 1.0))
	var scale_factor: float = min(avail.x / content_size.x, avail.y / content_size.y)
	var drawn_size := content_size * scale_factor
	var origin := (available_size - drawn_size) * 0.5
	return Rect2(origin, drawn_size)


## Godot's real tile renderer draws a tile's texture shifted by
## -texture_origin (a per-tile visual-only nudge - e.g. for a prop sprite
## whose visible art is taller than its logical grid footprint). Collision
## and every other coordinate stay anchored to the tile's own cell,
## unaffected by texture_origin. Use this wherever a tile's texture is
## blitted so the drawn position matches what Godot actually renders -
## otherwise a tile with a non-zero texture_origin shows its sprite in the
## wrong spot relative to everything drawn on top of it (peering bits,
## collision overlay, and any collision a user draws by eye against the
## preview - drawing collision against a misplaced sprite produces collision
## that's correctly positioned in this addon's preview but visibly offset
## from the sprite once Godot renders it for real).
static func texture_draw_offset(td: TileData, dest_size: Vector2, tex_region_size: Vector2) -> Vector2:
	if td == null or tex_region_size.x <= 0.0 or tex_region_size.y <= 0.0:
		return Vector2.ZERO
	var scale_factor := Vector2(dest_size.x / tex_region_size.x, dest_size.y / tex_region_size.y)
	return -Vector2(td.texture_origin) * scale_factor


## Maps a collision-polygon point (tile-local, centered on the tile - the
## same space TileData.get_collision_polygon_points returns) into screen
## space within dest_rect, given the tile's real pixel size.
static func local_point_to_screen(point: Vector2, tile_pixel_size: Vector2, dest_rect: Rect2) -> Vector2:
	var scale := Vector2(dest_rect.size.x / tile_pixel_size.x, dest_rect.size.y / tile_pixel_size.y)
	var center := dest_rect.position + dest_rect.size * 0.5
	return center + point * scale


static func local_points_to_screen(points: PackedVector2Array, tile_pixel_size: Vector2, dest_rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = local_point_to_screen(points[i], tile_pixel_size, dest_rect)
	return out


## Inverse of local_point_to_screen - maps a screen-space click back into
## tile-local-centered space.
static func screen_point_to_local(point: Vector2, tile_pixel_size: Vector2, dest_rect: Rect2) -> Vector2:
	var scale := Vector2(dest_rect.size.x / tile_pixel_size.x, dest_rect.size.y / tile_pixel_size.y)
	var center := dest_rect.position + dest_rect.size * 0.5
	return (point - center) / scale


## Snaps point to a grid of the given per-axis spacing (in the same
## tile-local-centered space local_point_to_screen/screen_point_to_local
## use). spacing is typically tile_pixel_size / divisions, computed by the
## caller, so a fixed "divisions" count gives a consistent grid regardless
## of the tile's actual pixel size.
static func snap_point(point: Vector2, spacing: Vector2) -> Vector2:
	var x := point.x
	var y := point.y
	if spacing.x > 0.0:
		x = roundf(point.x / spacing.x) * spacing.x
	if spacing.y > 0.0:
		y = roundf(point.y / spacing.y) * spacing.y
	return Vector2(x, y)


## Purely cosmetic - has no effect on actual terrain matching, just lets a
## tile's peering-bit overlay look like a solid filled block instead of
## always having an empty center square. Stored as tile metadata so it's
## remembered per tile and saved along with the TileSet.
static func get_cosmetic_center(td: TileData) -> bool:
	return bool(td.get_meta(COSMETIC_CENTER_META, false))


static func set_cosmetic_center(td: TileData, value: bool) -> void:
	td.set_meta(COSMETIC_CENTER_META, value)


## Draws the full per-tile overlay - peering bits (incl. the cosmetic
## center) in Terrain mode, the first collision layer's polygon in Collision
## mode - for one tile into dest, on canvas ci. Must only be called from
## within ci's own _draw() (or a function called synchronously from it).
## tile_pixel_size is the tile's real, unscaled texture-region size (NOT
## dest.size, which may be zoomed/fit-scaled by the caller). Shared by
## TileGridDisplay, TilePreviewOverlay, and SelectionPreview in dock.gd,
## which previously each duplicated this block with only variable names
## differing.
static func draw_tile_overlay(ci: CanvasItem, td: TileData, tileset: TileSet, dest: Rect2, tile_pixel_size: Vector2, view_mode: int) -> void:
	if td == null or tileset == null:
		return
	if view_mode == ViewMode.TERRAIN:
		if td.terrain_set < 0 or td.terrain < 0:
			return
		var sub_rects: Dictionary = get_peering_bit_rects(dest)
		for e in sub_rects:
			var r: Rect2 = sub_rects[e]
			if e == CENTER_BIT:
				if get_cosmetic_center(td):
					var center_fill: Color = tileset.get_terrain_color(td.terrain_set, td.terrain)
					center_fill.a = 0.55
					ci.draw_rect(r, center_fill, true)
				else:
					ci.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
				continue
			var peer: int = td.get_terrain_peering_bit(e)
			if peer != -1:
				var fill: Color = tileset.get_terrain_color(td.terrain_set, peer)
				fill.a = 0.55
				ci.draw_rect(r, fill, true)
			else:
				ci.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	else:
		var layer := first_collision_layer(td, tileset)
		if layer == -1:
			return
		var poly := td.get_collision_polygon_points(layer, 0)
		if poly.size() < 3:
			return
		var pts := local_points_to_screen(poly, tile_pixel_size, dest)
		ci.draw_colored_polygon(pts, Color(1.0, 0.45, 0.1, 0.5))
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, Color(1.0, 0.3, 0.0, 1.0), 2.0)


## Marks a template cell as "deliberately no tile here" in a preview - a
## neutral grey fill + diagonal hatch, distinct from both the terrain-color
## bit fills and the collision-orange used above, so it can't be mistaken
## for either.
static func draw_null_cell_marker(ci: CanvasItem, dest: Rect2) -> void:
	ci.draw_rect(dest, Color(0.5, 0.5, 0.5, 0.25), true)
	var hatch_color := Color(0.15, 0.15, 0.15, 0.7)
	var steps := 4
	for i in range(-steps, steps + 1):
		var t: float = float(i) / steps
		var x0: float = dest.position.x + dest.size.x * clampf(t, 0.0, 1.0)
		var y0: float = dest.position.y + dest.size.y * clampf(-t, 0.0, 1.0)
		var x1: float = dest.position.x + dest.size.x * clampf(t + 1.0, 0.0, 1.0)
		var y1: float = dest.position.y + dest.size.y * clampf(1.0 - t, 0.0, 1.0)
		ci.draw_line(Vector2(x0, y0), Vector2(x1, y1), hatch_color, 1.5)


## Returns the first physics layer index on td that has a collision
## polygon, or -1 if none.
static func first_collision_layer(td: TileData, tileset: TileSet) -> int:
	for layer in tileset.get_physics_layers_count():
		if td.get_collision_polygons_count(layer) > 0:
			return layer
	return -1


## Clips polygon against an axis-aligned rect, returning zero, one, or
## multiple resulting pieces (multiple only if polygon is concave/self-
## crossing enough to be split by the rect's edges).
static func clip_polygon_to_rect(polygon: PackedVector2Array, rect: Rect2) -> Array[PackedVector2Array]:
	if polygon.size() < 3:
		return []
	var rect_poly := PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		rect.position + rect.size,
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	])
	return Geometry2D.intersect_polygons(polygon, rect_poly)


@export var template_name: String = "New Template"

@export var size: Vector2i = Vector2i(1, 1):
	set(value):
		size = Vector2i(max(1, value.x), max(1, value.y))
		_resize_cells()

@export var cells: Array[Dictionary] = []


func _init() -> void:
	_resize_cells()


func _resize_cells() -> void:
	var needed: int = size.x * size.y
	while cells.size() < needed:
		cells.append(make_empty_cell())
	while cells.size() > needed:
		cells.pop_back()


static func make_empty_cell() -> Dictionary:
	return {
		"bits": {},
		"has_collision": false,
		"physics_layer": 0,
		"polygon": PackedVector2Array(),
	}


## A cell meaning "deliberately no tile here" - Apply leaves the destination
## tile completely untouched instead of writing this cell's data to it. Kept
## as a distinct constructor (rather than a flag on make_empty_cell()) so
## call sites stay self-documenting about which kind of cell they're making.
static func make_null_cell() -> Dictionary:
	var cell := make_empty_cell()
	cell["is_null"] = true
	return cell


static func is_cell_null(cell: Dictionary) -> bool:
	return bool(cell.get("is_null", false))


func get_cell(x: int, y: int) -> Dictionary:
	var idx: int = y * size.x + x
	if idx < 0 or idx >= cells.size():
		return make_empty_cell()
	return cells[idx]


func set_cell(x: int, y: int, data: Dictionary) -> void:
	var idx: int = y * size.x + x
	if idx >= 0 and idx < cells.size():
		cells[idx] = data
