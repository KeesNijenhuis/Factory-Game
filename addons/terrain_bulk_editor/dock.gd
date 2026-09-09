@tool
extends Control

const TerrainTemplateScript := preload("res://addons/terrain_bulk_editor/terrain_template.gd")

const DEFAULT_TEMPLATE_FOLDER := "res://addons/terrain_bulk_editor/templates/"


# ---------------------------------------------------------------------------
# Inner class: draws the tile atlas and handles selection, zoom (mouse
# wheel, cursor-anchored) and pan (right-click drag). Tiles that span more
# than one atlas cell (irregular sizes) are drawn at their real footprint,
# not squashed into a single cell.
# ---------------------------------------------------------------------------
class TileGridDisplay:
	extends Control

	signal selection_changed

	const MIN_ZOOM := 0.5
	const MAX_ZOOM := 12.0
	const ZOOM_FACTOR := 1.1

	var tileset: TileSet
	var atlas_source: TileSetAtlasSource
	var region_size: Vector2i = Vector2i(16, 16)
	var zoom: float = 3.0
	var selected: Dictionary = {}  # Vector2i (origin coord) -> true
	var view_mode: int = TerrainTemplate.ViewMode.TERRAIN

	var scroll_container: ScrollContainer = null
	var _grid_size: Vector2i = Vector2i.ZERO
	var _panning: bool = false
	var _dragging: bool = false
	var _drag_start: Vector2i = Vector2i.ZERO
	var _drag_end: Vector2i = Vector2i.ZERO
	var _shift: bool = false
	var _ctrl: bool = false

	var _apply_preview_template: TerrainTemplate = null
	var _apply_preview_bounds: Rect2i = Rect2i()
	var _apply_preview_terrain_set: int = -1
	var _apply_preview_terrain: int = -1

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func setup(p_tileset: TileSet, p_atlas_source: TileSetAtlasSource) -> void:
		tileset = p_tileset
		atlas_source = p_atlas_source
		selected.clear()
		if atlas_source:
			region_size = atlas_source.texture_region_size
			_grid_size = atlas_source.get_atlas_grid_size()
			custom_minimum_size = Vector2(_grid_size) * Vector2(region_size) * zoom
		else:
			_grid_size = Vector2i.ZERO
			custom_minimum_size = Vector2.ZERO
		queue_redraw()
		selection_changed.emit()

	func set_apply_preview(template: TerrainTemplate, bounds: Rect2i, terrain_set: int, terrain: int) -> void:
		_apply_preview_template = template
		_apply_preview_bounds = bounds
		_apply_preview_terrain_set = terrain_set
		_apply_preview_terrain = terrain
		queue_redraw()

	func clear_apply_preview() -> void:
		_apply_preview_template = null
		queue_redraw()

	func set_view_mode(mode: int) -> void:
		if view_mode == mode:
			return
		view_mode = mode
		queue_redraw()

	func _cell_at(local_pos: Vector2) -> Vector2i:
		var cell_px: Vector2 = Vector2(region_size) * zoom
		return Vector2i(int(floor(local_pos.x / cell_px.x)), int(floor(local_pos.y / cell_px.y)))

	func _set_zoom(new_zoom: float, anchor: Vector2) -> void:
		new_zoom = clamp(new_zoom, MIN_ZOOM, MAX_ZOOM)
		if is_equal_approx(new_zoom, zoom):
			return
		var unscaled: Vector2 = anchor / zoom
		zoom = new_zoom
		custom_minimum_size = Vector2(_grid_size) * Vector2(region_size) * zoom
		queue_redraw()
		var delta: Vector2 = unscaled * zoom - anchor
		call_deferred("_apply_pan_delta", delta)

	func _apply_pan_delta(delta: Vector2) -> void:
		if scroll_container:
			scroll_container.scroll_horizontal += int(delta.x)
			scroll_container.scroll_vertical += int(delta.y)

	func _gui_input(event: InputEvent) -> void:
		if atlas_source == null:
			return

		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var cell := _cell_at(mb.position)
					_dragging = true
					_shift = mb.shift_pressed
					_ctrl = mb.ctrl_pressed
					_drag_start = cell
					_drag_end = cell
					queue_redraw()
				else:
					if _dragging:
						_apply_drag_selection()
						_dragging = false
						queue_redraw()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_set_zoom(zoom * ZOOM_FACTOR, mb.position)
				accept_event()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_set_zoom(zoom / ZOOM_FACTOR, mb.position)
				accept_event()
		elif event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _dragging:
				_drag_end = _cell_at(mm.position)
				queue_redraw()
			elif _panning and scroll_container:
				scroll_container.scroll_horizontal -= int(mm.relative.x)
				scroll_container.scroll_vertical -= int(mm.relative.y)

	func _apply_drag_selection() -> void:
		var min_c := Vector2i(min(_drag_start.x, _drag_end.x), min(_drag_start.y, _drag_end.y))
		var max_c := Vector2i(max(_drag_start.x, _drag_end.x), max(_drag_start.y, _drag_end.y))

		if not _shift and not _ctrl:
			selected.clear()

		for y in range(min_c.y, max_c.y + 1):
			for x in range(min_c.x, max_c.x + 1):
				var c := Vector2i(x, y)
				# get_tile_at_coords resolves any cell covered by a
				# multi-cell (irregular-size) tile back to its origin coord,
				# unlike has_tile which is only true at the origin itself.
				var origin: Vector2i = atlas_source.get_tile_at_coords(c)
				if origin == Vector2i(-1, -1):
					continue
				if _ctrl:
					selected.erase(origin)
				else:
					selected[origin] = true
		selection_changed.emit()

	func get_selection_bounds() -> Rect2i:
		if selected.is_empty():
			return Rect2i()
		var min_c: Vector2i = selected.keys()[0]
		var max_c: Vector2i = selected.keys()[0]
		for c in selected.keys():
			min_c = Vector2i(min(min_c.x, c.x), min(min_c.y, c.y))
			max_c = Vector2i(max(max_c.x, c.x), max(max_c.y, c.y))
		return Rect2i(min_c, max_c - min_c + Vector2i.ONE)

	func _draw() -> void:
		if atlas_source == null:
			return

		var cell_px: Vector2 = Vector2(region_size) * zoom

		# Tiles.
		for i in atlas_source.get_tiles_count():
			var coord: Vector2i = atlas_source.get_tile_id(i)
			var tex_region: Rect2i = atlas_source.get_tile_texture_region(coord)
			var size_in_atlas: Vector2i = atlas_source.get_tile_size_in_atlas(coord)
			var dest := Rect2(Vector2(coord) * cell_px, Vector2(size_in_atlas) * cell_px)
			var tile_data: TileData = atlas_source.get_tile_data(coord, 0)
			if atlas_source.texture:
				var tex_dest := dest
				tex_dest.position += TerrainTemplate.texture_draw_offset(tile_data, dest.size, Vector2(tex_region.size))
				draw_texture_rect_region(atlas_source.texture, tex_dest, tex_region)

			TerrainTemplate.draw_tile_overlay(self, tile_data, tileset, dest, Vector2(tex_region.size), view_mode)

			if selected.has(coord):
				draw_rect(dest, Color(0.3, 0.7, 1.0, 0.45), true)
				draw_rect(dest, Color(0.3, 0.7, 1.0, 1.0), false, 2.0)

			draw_rect(dest, Color(0, 0, 0, 0.25), false, 1.0)

		if _apply_preview_template != null:
			for coord in selected.keys():
				if not _apply_preview_bounds.has_point(coord):
					continue
				var size_in_atlas2: Vector2i = atlas_source.get_tile_size_in_atlas(coord)
				var dest2 := Rect2(Vector2(coord) * cell_px, Vector2(size_in_atlas2) * cell_px)
				var lx: int = posmod(coord.x - _apply_preview_bounds.position.x, _apply_preview_template.size.x)
				var ly: int = posmod(coord.y - _apply_preview_bounds.position.y, _apply_preview_template.size.y)
				var cell: Dictionary = _apply_preview_template.get_cell(lx, ly)
				if TerrainTemplate.is_cell_null(cell):
					TerrainTemplate.draw_null_cell_marker(self, dest2)
					continue
				var sub_rects2: Dictionary = TerrainTemplate.get_peering_bit_rects(dest2)
				for e in sub_rects2:
					if bool(cell["bits"].get(e, false)):
						var fill: Color = tileset.get_terrain_color(_apply_preview_terrain_set, _apply_preview_terrain)
						fill.a = 0.35
						draw_rect(sub_rects2[e], fill, true)
				if cell.get("has_collision", false):
					var poly2: PackedVector2Array = cell.get("polygon", PackedVector2Array())
					if poly2.size() >= 3:
						var tile_pixel_size2 := Vector2(atlas_source.get_tile_texture_region(coord).size)
						var pts2 := TerrainTemplate.local_points_to_screen(poly2, tile_pixel_size2, dest2)
						draw_colored_polygon(pts2, Color(1.0, 0.45, 0.1, 0.35))

		if _dragging:
			var min_c := Vector2i(min(_drag_start.x, _drag_end.x), min(_drag_start.y, _drag_end.y))
			var max_c := Vector2i(max(_drag_start.x, _drag_end.x), max(_drag_start.y, _drag_end.y))
			var rect := Rect2(Vector2(min_c) * cell_px, Vector2(max_c - min_c + Vector2i.ONE) * cell_px)
			draw_rect(rect, Color(1, 1, 0, 0.2), true)
			draw_rect(rect, Color(1, 1, 0, 0.9), false, 2.0)


# ---------------------------------------------------------------------------
# Inner class: enlarged preview of a single selected tile, with a 3x3
# peering-bit overlay when it has terrain. Left-click paints/erases the
# tile's terrain using whatever is active in the shared paint dropdown.
# Right-click on a bit region toggles that specific peering bit.
# ---------------------------------------------------------------------------
class TilePreviewOverlay:
	extends Control

	const PADDING := 12.0

	signal tile_left_clicked
	signal bit_right_clicked(bit_enum: int)

	var source_atlas: TileSetAtlasSource = null
	var source_coord: Vector2i = Vector2i.ZERO
	var source_tileset: TileSet = null
	var view_mode: int = TerrainTemplate.ViewMode.TERRAIN

	func _init() -> void:
		custom_minimum_size = Vector2(220, 220)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_tile(atlas_source: TileSetAtlasSource, coord: Vector2i, tileset: TileSet) -> void:
		source_atlas = atlas_source
		source_coord = coord
		source_tileset = tileset
		queue_redraw()

	func set_view_mode(mode: int) -> void:
		if view_mode == mode:
			return
		view_mode = mode
		queue_redraw()

	func _tile_rect() -> Rect2:
		if source_atlas == null:
			return Rect2(Vector2.ZERO, size)
		var tex_region: Rect2i = source_atlas.get_tile_texture_region(source_coord)
		return TerrainTemplate.fit_content_rect(Vector2(tex_region.size), size, PADDING)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15), true)
		if source_atlas == null:
			return

		var rect := _tile_rect()
		var td := source_atlas.get_tile_data(source_coord, 0)
		var tex_region := source_atlas.get_tile_texture_region(source_coord)
		if source_atlas.texture:
			var tex_dest := rect
			tex_dest.position += TerrainTemplate.texture_draw_offset(td, rect.size, Vector2(tex_region.size))
			draw_texture_rect_region(source_atlas.texture, tex_dest, tex_region)

		TerrainTemplate.draw_tile_overlay(self, td, source_tileset, rect, Vector2(tex_region.size), view_mode)

		draw_rect(rect, Color(0, 0, 0), false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if source_atlas == null:
			return
		if event is InputEventMouseButton and event.pressed:
			# Button mapping is mode-dependent: in Terrain mode, right-click
			# paints/erases the tile and left-click toggles a bit (swapped
			# on request); in Collision mode there's only one action (open
			# the polygon editor), on left-click.
			if view_mode == TerrainTemplate.ViewMode.TERRAIN:
				if event.button_index == MOUSE_BUTTON_RIGHT:
					tile_left_clicked.emit()
				elif event.button_index == MOUSE_BUTTON_LEFT:
					var rect := _tile_rect()
					var e: int = TerrainTemplate.get_peering_bit_at_point(rect, event.position)
					if e != -1:
						bit_right_clicked.emit(e)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				tile_left_clicked.emit()


# ---------------------------------------------------------------------------
# Inner class: enlarged preview of a whole multi-tile selection. COMMITTED
# mode renders each tile's own real texture + committed bits, and is
# interactive the same way TilePreviewOverlay is (left-click paints/erases
# a tile's terrain, right-click toggles one of its bits). PENDING mode
# renders each tile's texture + a not-yet-applied template's bits at
# reduced alpha, and is read-only (used for the Apply Template preview).
# ---------------------------------------------------------------------------
class SelectionPreview:
	extends Control

	enum Mode { COMMITTED, PENDING }

	const PADDING := 12.0

	signal tile_left_clicked(coord: Vector2i)
	signal bit_right_clicked(coord: Vector2i, bit_enum: int)

	var mode: Mode = Mode.COMMITTED
	var view_mode: int = TerrainTemplate.ViewMode.TERRAIN
	var atlas_source: TileSetAtlasSource = null
	var tileset: TileSet = null
	var region_size: Vector2i = Vector2i(16, 16)
	var bounds: Rect2i = Rect2i()
	var coords: Array = []

	var pending_template: TerrainTemplate = null
	var pending_terrain_set: int = -1
	var pending_terrain: int = -1

	func _init() -> void:
		custom_minimum_size = Vector2(280, 280)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func set_committed(p_atlas_source: TileSetAtlasSource, p_tileset: TileSet, p_region_size: Vector2i, p_bounds: Rect2i, p_coords: Array) -> void:
		mode = Mode.COMMITTED
		atlas_source = p_atlas_source
		tileset = p_tileset
		region_size = p_region_size
		bounds = p_bounds
		coords = p_coords
		pending_template = null
		queue_redraw()

	func set_pending(p_atlas_source: TileSetAtlasSource, p_tileset: TileSet, p_region_size: Vector2i, p_bounds: Rect2i, p_coords: Array, template: TerrainTemplate, terrain_set: int, terrain: int) -> void:
		mode = Mode.PENDING
		atlas_source = p_atlas_source
		tileset = p_tileset
		region_size = p_region_size
		bounds = p_bounds
		coords = p_coords
		pending_template = template
		pending_terrain_set = terrain_set
		pending_terrain = terrain
		queue_redraw()

	func set_view_mode(new_view_mode: int) -> void:
		if view_mode == new_view_mode:
			return
		view_mode = new_view_mode
		queue_redraw()

	func _fitted_rect() -> Rect2:
		var content_size := Vector2(bounds.size) * Vector2(region_size)
		return TerrainTemplate.fit_content_rect(content_size, size, PADDING)

	func _tile_and_rect_at(point: Vector2) -> Dictionary:
		if atlas_source == null or bounds.size.x <= 0 or bounds.size.y <= 0:
			return {}
		var content_size := Vector2(bounds.size) * Vector2(region_size)
		var fitted: Rect2 = _fitted_rect()
		var scale_factor: float = fitted.size.x / content_size.x
		var tile_px: Vector2 = Vector2(region_size) * scale_factor
		for coord in coords:
			var local: Vector2i = coord - bounds.position
			var size_in_atlas: Vector2i = atlas_source.get_tile_size_in_atlas(coord)
			var dest := Rect2(fitted.position + Vector2(local) * tile_px, Vector2(size_in_atlas) * tile_px)
			if dest.has_point(point):
				return {"coord": coord, "rect": dest}
		return {}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0.15, 0.15), true)
		if atlas_source == null or bounds.size.x <= 0 or bounds.size.y <= 0:
			return

		var content_size := Vector2(bounds.size) * Vector2(region_size)
		var fitted: Rect2 = _fitted_rect()
		var scale_factor: float = fitted.size.x / content_size.x
		var tile_px: Vector2 = Vector2(region_size) * scale_factor

		for coord in coords:
			var local: Vector2i = coord - bounds.position
			var size_in_atlas: Vector2i = atlas_source.get_tile_size_in_atlas(coord)
			var dest := Rect2(fitted.position + Vector2(local) * tile_px, Vector2(size_in_atlas) * tile_px)
			var tex_region: Rect2i = atlas_source.get_tile_texture_region(coord)
			var td := atlas_source.get_tile_data(coord, 0)
			if atlas_source.texture:
				var tex_dest := dest
				tex_dest.position += TerrainTemplate.texture_draw_offset(td, dest.size, Vector2(tex_region.size))
				draw_texture_rect_region(atlas_source.texture, tex_dest, tex_region)

			if mode == Mode.COMMITTED:
				TerrainTemplate.draw_tile_overlay(self, td, tileset, dest, Vector2(tex_region.size), view_mode)
			elif mode == Mode.PENDING and pending_template:
				var lx: int = posmod(local.x, pending_template.size.x)
				var ly: int = posmod(local.y, pending_template.size.y)
				var cell: Dictionary = pending_template.get_cell(lx, ly)
				if TerrainTemplate.is_cell_null(cell):
					TerrainTemplate.draw_null_cell_marker(self, dest)
				else:
					var sub_rects2: Dictionary = TerrainTemplate.get_peering_bit_rects(dest)
					for e in sub_rects2:
						if bool(cell["bits"].get(e, false)):
							var fill2: Color = tileset.get_terrain_color(pending_terrain_set, pending_terrain)
							fill2.a = 0.35
							draw_rect(sub_rects2[e], fill2, true)
					if cell.get("has_collision", false):
						var poly2: PackedVector2Array = cell.get("polygon", PackedVector2Array())
						if poly2.size() >= 3:
							var tile_pixel_size2 := Vector2(atlas_source.get_tile_texture_region(coord).size)
							var pts2 := TerrainTemplate.local_points_to_screen(poly2, tile_pixel_size2, dest)
							draw_colored_polygon(pts2, Color(1.0, 0.45, 0.1, 0.35))

			draw_rect(dest, Color(0, 0, 0, 0.25), false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if mode != Mode.COMMITTED or atlas_source == null:
			return
		if event is InputEventMouseButton and event.pressed:
			var hit := _tile_and_rect_at(event.position)
			if hit.is_empty():
				return
			# Button mapping is mode-dependent - see TilePreviewOverlay's
			# _gui_input for the same convention.
			if view_mode == TerrainTemplate.ViewMode.TERRAIN:
				if event.button_index == MOUSE_BUTTON_RIGHT:
					tile_left_clicked.emit(hit["coord"])
				elif event.button_index == MOUSE_BUTTON_LEFT:
					var e: int = TerrainTemplate.get_peering_bit_at_point(hit["rect"], event.position)
					if e != -1:
						bit_right_clicked.emit(hit["coord"], e)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				tile_left_clicked.emit(hit["coord"])


# ---------------------------------------------------------------------------
# Inner class: detailed, inline collision-polygon editor over a selection of
# one or more tiles. A single-tile selection edits immediately (click to
# add, drag to move, right-click to delete a point - writes straight to
# TileData on every mutation). A multi-tile selection instead draws one
# draft polygon across the whole selection; nothing touches real TileData
# until "Apply to Selection" clips it per tile (via Geometry2D.intersect_
# polygons) and writes each resulting piece onto its own tile.
# ---------------------------------------------------------------------------
class CollisionPolygonEditor:
	extends VBoxContainer

	signal changed

	const PADDING := 12.0
	const PICK_RADIUS := 10.0
	const POINT_RADIUS := 4.0
	const FILL_COLOR := Color(1.0, 0.45, 0.1, 0.5)
	const OUTLINE_COLOR := Color(1.0, 0.3, 0.0, 1.0)
	const GRID_COLOR := Color(1, 1, 1, 0.3)
	const TILE_BOUNDARY_COLOR := Color(1, 1, 1, 0.55)
	const POINT_COLOR := Color(1, 1, 1, 0.9)

	var atlas_source: TileSetAtlasSource = null
	var bounds: Rect2i = Rect2i()
	var coords: Array[Vector2i] = []
	var region_size: Vector2i = Vector2i.ONE
	var tileset: TileSet = null
	var physics_layer: int = 0
	var points: PackedVector2Array = PackedVector2Array()  # draft, in shared selection-local-centered space
	var drag_index: int = -1
	var snap_divisions: int = 4  # each tile is divided into this many equal steps per axis
	var copied_polygon: PackedVector2Array = PackedVector2Array()  # clipboard - persists across selection changes

	var snap_spinbox: SpinBox
	var layer_option: OptionButton
	var canvas: Control
	var apply_btn: Button
	var copy_btn: Button
	var paste_btn: Button
	var status_label: Label

	func _init() -> void:
		var header := HBoxContainer.new()
		add_child(header)

		var snap_label := Label.new()
		snap_label.text = "Grid divisions"
		header.add_child(snap_label)

		snap_spinbox = SpinBox.new()
		snap_spinbox.min_value = 1
		snap_spinbox.max_value = 32
		snap_spinbox.step = 1
		snap_spinbox.value = snap_divisions
		snap_spinbox.value_changed.connect(_on_snap_changed)
		header.add_child(snap_spinbox)

		layer_option = OptionButton.new()
		layer_option.visible = false
		layer_option.item_selected.connect(_on_layer_selected)
		header.add_child(layer_option)

		var clear_btn := Button.new()
		clear_btn.text = "Clear Polygon"
		clear_btn.pressed.connect(_on_clear_pressed)
		header.add_child(clear_btn)

		copy_btn = Button.new()
		copy_btn.text = "Copy Polygon"
		copy_btn.pressed.connect(_on_copy_pressed)
		header.add_child(copy_btn)

		paste_btn = Button.new()
		paste_btn.text = "Paste Polygon"
		paste_btn.disabled = true
		paste_btn.pressed.connect(_on_paste_pressed)
		header.add_child(paste_btn)

		apply_btn = Button.new()
		apply_btn.text = "Apply to Selection"
		apply_btn.visible = false
		apply_btn.pressed.connect(_on_apply_pressed)
		header.add_child(apply_btn)

		canvas = Control.new()
		canvas.custom_minimum_size = Vector2(320, 320)
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		canvas.draw.connect(_draw_canvas)
		canvas.gui_input.connect(_on_canvas_gui_input)
		add_child(canvas)

		status_label = Label.new()
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		add_child(status_label)

	func set_selection(p_atlas_source: TileSetAtlasSource, p_tileset: TileSet, p_region_size: Vector2i, p_bounds: Rect2i, p_coords: Array) -> void:
		atlas_source = p_atlas_source
		tileset = p_tileset
		region_size = p_region_size
		bounds = p_bounds
		coords.assign(p_coords)
		physics_layer = 0
		drag_index = -1
		status_label.text = ""
		_reload_points()
		_refresh_layer_picker()
		apply_btn.visible = coords.size() > 1
		canvas.queue_redraw()

	func _refresh_layer_picker() -> void:
		var n: int = tileset.get_physics_layers_count()
		layer_option.visible = n > 1
		if n > 1:
			layer_option.clear()
			for i in n:
				layer_option.add_item("Layer %d" % i)
			layer_option.select(physics_layer)

	## Single tile: reload its real current shape, unchanged.
	## Multiple tiles: merge every selected tile's real collision polygon(s)
	## on the current layer into one big draft shape (the inverse of what
	## Apply does), so editing a selection starts from what's already there
	## instead of blank.
	func _reload_points() -> void:
		# Always goes through _merge_existing_polygons(), even for a single
		# tile - a tile can end up with more than one real collision polygon
		# on a layer (e.g. a prior multi-tile Apply that clipped a concave
		# draft into several pieces landing on the same tile), and loading
		# only polygon index 0 would silently drop the rest the moment this
		# tile is edited again.
		var merged := _merge_existing_polygons()
		if merged.is_empty():
			points = PackedVector2Array()
		elif merged.size() == 1:
			points = merged[0]
		else:
			# Didn't all merge into one piece - the draft can only hold one
			# polygon, so keep the largest and tell the user the rest
			# weren't pulled in.
			var best_idx := 0
			var best_area := absf(_polygon_area(merged[0]))
			for k in range(1, merged.size()):
				var a := absf(_polygon_area(merged[k]))
				if a > best_area:
					best_idx = k
					best_area = a
			points = merged[best_idx]
			var noun := "tile" if coords.size() == 1 else "selection"
			status_label.text = "Loaded the largest of %d disconnected collision shapes on this %s - the rest weren't merged in." % [merged.size(), noun]

	## Collects every selected tile's real collision polygon(s) on the
	## current layer (shifted into the shared selection-local-centered
	## space) and repeatedly merges any pair that overlaps or shares an
	## edge, until no more merges are possible. Tiles that don't touch stay
	## as separate pieces in the result.
	func _merge_existing_polygons() -> Array[PackedVector2Array]:
		var content_px := _content_pixel_size()
		var polys: Array[PackedVector2Array] = []
		for c in coords:
			var td := atlas_source.get_tile_data(c, 0)
			if td == null:
				continue
			var tile_rect := _tile_local_rect(c, content_px)
			var tile_center_local := tile_rect.position + tile_rect.size * 0.5
			for pi in td.get_collision_polygons_count(physics_layer):
				var pts := td.get_collision_polygon_points(physics_layer, pi)
				if pts.size() < 3:
					continue
				var shared := PackedVector2Array()
				shared.resize(pts.size())
				for i in pts.size():
					shared[i] = pts[i] + tile_center_local
				polys.append(shared)
		var merged_again := true
		while merged_again:
			merged_again = false
			for i in polys.size():
				for j in range(i + 1, polys.size()):
					var result := Geometry2D.merge_polygons(polys[i], polys[j])
					if result.size() == 1:
						polys[i] = result[0]
						polys.remove_at(j)
						merged_again = true
						break
				if merged_again:
					break
		return polys

	func _polygon_area(poly: PackedVector2Array) -> float:
		var area := 0.0
		var n := poly.size()
		for i in n:
			var p1 := poly[i]
			var p2 := poly[(i + 1) % n]
			area += p1.x * p2.y - p2.x * p1.y
		return area * 0.5

	## Union of every selected tile's real pixel footprint, in the shared
	## selection-local space. NOT simply bounds.size * region_size - a
	## single irregular (multi-cell) tile always has bounds.size == (1,1)
	## since bounds is built from origin coords, but its real footprint can
	## span more than one nominal cell.
	func _content_pixel_size() -> Vector2:
		var extent := Vector2.ZERO
		for c in coords:
			var local_cell: Vector2i = c - bounds.position
			var size_in_atlas: Vector2i = atlas_source.get_tile_size_in_atlas(c)
			var far := Vector2(local_cell + size_in_atlas) * Vector2(region_size)
			extent.x = max(extent.x, far.x)
			extent.y = max(extent.y, far.y)
		if extent == Vector2.ZERO:
			extent = Vector2(region_size)
		return extent

	## One tile's own rect within the shared selection-local-centered space.
	func _tile_local_rect(coord: Vector2i, content_px: Vector2) -> Rect2:
		var local_cell: Vector2i = coord - bounds.position
		var size_in_atlas: Vector2i = atlas_source.get_tile_size_in_atlas(coord)
		var tile_px_size := Vector2(size_in_atlas) * Vector2(region_size)
		var half := content_px * 0.5
		var origin := Vector2(local_cell) * Vector2(region_size) - half
		return Rect2(origin, tile_px_size)

	func _content_rect() -> Rect2:
		return TerrainTemplate.fit_content_rect(_content_pixel_size(), canvas.size, PADDING)

	func _tile_screen_rect(coord: Vector2i, content_px: Vector2, rect: Rect2) -> Rect2:
		var tl := _tile_local_rect(coord, content_px)
		var p0 := TerrainTemplate.local_point_to_screen(tl.position, content_px, rect)
		var p1 := TerrainTemplate.local_point_to_screen(tl.position + tl.size, content_px, rect)
		return Rect2(p0, p1 - p0)

	## Single tile: writes straight through to real TileData, as always.
	func _sync_to_tiledata() -> void:
		var td := atlas_source.get_tile_data(coords[0], 0)
		var existing: int = td.get_collision_polygons_count(physics_layer)
		for i in range(existing - 1, -1, -1):
			td.remove_collision_polygon(physics_layer, i)
		if points.size() >= 3:
			td.add_collision_polygon(physics_layer)
			td.set_collision_polygon_points(physics_layer, 0, points)
		changed.emit()
		canvas.queue_redraw()

	func _point_at(screen_pos: Vector2, rect: Rect2, content_px: Vector2) -> int:
		for i in points.size():
			var p := TerrainTemplate.local_point_to_screen(points[i], content_px, rect)
			if p.distance_to(screen_pos) <= PICK_RADIUS:
				return i
		return -1

	## Where a newly-clicked point should be inserted so it lands as a new
	## stop along whichever existing edge it's closest to, rather than always
	## tacking it onto the end of the array (which used to draw a stray edge
	## back to point 0 regardless of where the click actually landed). With
	## fewer than 2 points there's no edge yet, so it just appends.
	func _insert_index_for_point(local: Vector2) -> int:
		if points.size() < 2:
			return points.size()
		var best_index := points.size()
		var best_dist := INF
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var d := Geometry2D.get_closest_point_to_segment(local, a, b).distance_to(local)
			if d < best_dist:
				best_dist = d
				best_index = i + 1
		return best_index

	func _clamp_to_content(local: Vector2, content_px: Vector2) -> Vector2:
		var half := content_px * 0.5
		return Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))

	## Based on the nominal region_size (not the whole selection's content
	## size), so snapped points always land on cell-grid multiples
	## regardless of which tile they're over - this is what guarantees
	## clean per-tile cuts.
	func _snap_grid_spacing() -> Vector2:
		var d: float = max(snap_divisions, 1)
		return Vector2(region_size) / d

	## Grid lines computed in closed form from an integer cell/division
	## index (not accumulated via += in a loop), so every tile boundary is
	## exact and self-consistent no matter how many tiles are selected -
	## an accumulating step could drift a fraction of a pixel off the true
	## edge by the time it reaches a tile several cells away.
	func _draw_grid(content_px: Vector2, rect: Rect2) -> void:
		var d: int = max(snap_divisions, 1)
		var half := content_px * 0.5
		var n_cols: int = int(round(content_px.x / float(region_size.x)))
		var n_rows: int = int(round(content_px.y / float(region_size.y)))
		for k in range(n_cols * d + 1):
			var x: float = -half.x + (k * region_size.x) / float(d)
			var is_boundary: bool = (k % d) == 0
			canvas.draw_line(
				TerrainTemplate.local_point_to_screen(Vector2(x, -half.y), content_px, rect),
				TerrainTemplate.local_point_to_screen(Vector2(x, half.y), content_px, rect),
				TILE_BOUNDARY_COLOR if is_boundary else GRID_COLOR,
				1.5 if is_boundary else 1.0)
		for k in range(n_rows * d + 1):
			var y: float = -half.y + (k * region_size.y) / float(d)
			var is_boundary: bool = (k % d) == 0
			canvas.draw_line(
				TerrainTemplate.local_point_to_screen(Vector2(-half.x, y), content_px, rect),
				TerrainTemplate.local_point_to_screen(Vector2(half.x, y), content_px, rect),
				TILE_BOUNDARY_COLOR if is_boundary else GRID_COLOR,
				1.5 if is_boundary else 1.0)

	func _draw_canvas() -> void:
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.12, 0.12, 0.12), true)
		if atlas_source == null or coords.is_empty():
			return

		var content_px := _content_pixel_size()
		var rect := _content_rect()

		for c in coords:
			if atlas_source.texture:
				var tex_region := atlas_source.get_tile_texture_region(c)
				var tex_dest := _tile_screen_rect(c, content_px, rect)
				var td := atlas_source.get_tile_data(c, 0)
				tex_dest.position += TerrainTemplate.texture_draw_offset(td, tex_dest.size, Vector2(tex_region.size))
				canvas.draw_texture_rect_region(atlas_source.texture, tex_dest, tex_region)

		_draw_grid(content_px, rect)

		if points.size() >= 3:
			var pts := TerrainTemplate.local_points_to_screen(points, content_px, rect)
			canvas.draw_colored_polygon(pts, FILL_COLOR)
			var closed := pts.duplicate()
			closed.append(pts[0])
			canvas.draw_polyline(closed, OUTLINE_COLOR, 2.0)
		elif points.size() == 2:
			var pts := TerrainTemplate.local_points_to_screen(points, content_px, rect)
			canvas.draw_line(pts[0], pts[1], OUTLINE_COLOR, 2.0)
		for p in points:
			canvas.draw_circle(TerrainTemplate.local_point_to_screen(p, content_px, rect), POINT_RADIUS, POINT_COLOR)

		canvas.draw_rect(rect, Color.WHITE, false, 2.0)

	func _on_canvas_gui_input(event: InputEvent) -> void:
		if atlas_source == null or coords.is_empty():
			return
		var content_px := _content_pixel_size()
		var rect := _content_rect()

		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var hit := _point_at(mb.position, rect, content_px)
					if hit != -1:
						drag_index = hit
					elif rect.has_point(mb.position):
						# Only add a point when the click actually landed on
						# the selection itself, not in the padding around it.
						var local := TerrainTemplate.screen_point_to_local(mb.position, content_px, rect)
						local = _clamp_to_content(TerrainTemplate.snap_point(local, _snap_grid_spacing()), content_px)
						var insert_index := _insert_index_for_point(local)
						points.insert(insert_index, local)
						drag_index = insert_index
						_commit_or_redraw()
				else:
					if drag_index != -1:
						_commit_or_redraw()
					drag_index = -1
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var hit := _point_at(mb.position, rect, content_px)
				if hit != -1:
					points.remove_at(hit)
					_commit_or_redraw()
		elif event is InputEventMouseMotion and drag_index != -1:
			var local := TerrainTemplate.screen_point_to_local(event.position, content_px, rect)
			points[drag_index] = _clamp_to_content(TerrainTemplate.snap_point(local, _snap_grid_spacing()), content_px)
			canvas.queue_redraw()

	## Single tile: every mutation writes straight through immediately, as
	## always (including mid-drag - the expensive write only actually
	## happens on release, see _on_canvas_gui_input). Multiple tiles: the
	## mutation only updates the draft; nothing real changes until Apply.
	func _commit_or_redraw() -> void:
		if coords.size() == 1:
			_sync_to_tiledata()
		else:
			canvas.queue_redraw()

	func _on_clear_pressed() -> void:
		points = PackedVector2Array()
		if coords.size() == 1:
			_sync_to_tiledata()
		else:
			canvas.queue_redraw()

	## Copies the current draft polygon to a clipboard that persists across
	## selection changes (it lives on this editor instance, not per-tile).
	func _on_copy_pressed() -> void:
		if points.size() < 3:
			status_label.text = "Nothing to copy - draw a polygon first."
			return
		copied_polygon = points.duplicate()
		paste_btn.disabled = false
		status_label.text = "Copied polygon (%d points)." % copied_polygon.size()

	## Pastes the clipboard onto whatever is currently selected - a single
	## tile writes immediately, a multi-tile selection only updates the draft
	## (Apply still cuts it up as usual).
	func _on_paste_pressed() -> void:
		if copied_polygon.size() < 3:
			status_label.text = "Nothing copied yet."
			return
		points = copied_polygon.duplicate()
		drag_index = -1
		_commit_or_redraw()
		status_label.text = "Pasted polygon (%d points)." % points.size()

	## Multi-tile only: clips the draft polygon against every selected
	## tile's own rect and writes the resulting piece(s) straight onto that
	## tile's real TileData (bypassing TerrainTemplate entirely - TileData
	## already natively supports multiple polygons per layer). Every
	## selected tile's existing polygons on the current layer are cleared
	## first, even ones the draft never reaches - Apply defines the
	## complete collision state for the whole selection, not an overlay.
	func _on_apply_pressed() -> void:
		if coords.size() <= 1:
			return
		var content_px := _content_pixel_size()
		var tiles_with_polygon := 0
		var tiles_empty := 0
		# Suppress "changed" while mutating every selected tile, same reason
		# as the outer script's _begin/_end_bulk_tileset_edit - this inner
		# class has no implicit access to those, so it blocks/unblocks
		# tileset and atlas_source itself.
		tileset.set_block_signals(true)
		atlas_source.set_block_signals(true)
		for c in coords:
			var td := atlas_source.get_tile_data(c, 0)
			var existing: int = td.get_collision_polygons_count(physics_layer)
			for i in range(existing - 1, -1, -1):
				td.remove_collision_polygon(physics_layer, i)
			if points.size() < 3:
				tiles_empty += 1
				continue
			var tile_rect := _tile_local_rect(c, content_px)
			var tile_center_local := tile_rect.position + tile_rect.size * 0.5
			var clipped := TerrainTemplate.clip_polygon_to_rect(points, tile_rect)
			var wrote_any := false
			for piece in clipped:
				if piece.size() < 3:
					continue
				var tile_local_piece := PackedVector2Array()
				tile_local_piece.resize(piece.size())
				for i in piece.size():
					tile_local_piece[i] = piece[i] - tile_center_local
				var idx: int = td.get_collision_polygons_count(physics_layer)
				td.add_collision_polygon(physics_layer)
				td.set_collision_polygon_points(physics_layer, idx, tile_local_piece)
				wrote_any = true
			tiles_with_polygon += 1 if wrote_any else 0
			tiles_empty += 0 if wrote_any else 1
		tileset.set_block_signals(false)
		atlas_source.set_block_signals(false)
		tileset.emit_changed()
		atlas_source.emit_changed()
		status_label.text = "Applied: %d tile(s) got collision, %d tile(s) cleared" % [tiles_with_polygon, tiles_empty]
		changed.emit()
		canvas.queue_redraw()

	func _on_layer_selected(idx: int) -> void:
		physics_layer = idx
		status_label.text = ""
		_reload_points()
		canvas.queue_redraw()

	func _on_snap_changed(value: float) -> void:
		snap_divisions = max(int(value), 1)
		canvas.queue_redraw()


# ---------------------------------------------------------------------------
# Main dock state
# ---------------------------------------------------------------------------
var current_tileset: TileSet
var current_source_id: int = -1

# UI refs
var tileset_picker: EditorResourcePicker
var save_tileset_btn: Button
var source_option: OptionButton
var grid_display: TileGridDisplay
var selection_label: Label
var status_label: Label

# Shared "active paint terrain" picker (None or an existing terrain), used
# by both the single-tile and multi-tile preview panels.
var paint_terrain_row: HBoxContainer
var paint_terrain_option: OptionButton
var paint_terrain_hint: Label
var clear_bits_btn: Button
var collision_hint: Label

# Terrain/Collision view-mode toggle, shared across all three view Controls.
var active_view: int = TerrainTemplate.ViewMode.TERRAIN
var view_toggle_terrain_btn: Button
var view_toggle_collision_btn: Button

# Panels built once in _build_ui(), toggled via .visible based on selection.
var panel_empty: VBoxContainer
var panel_single: VBoxContainer
var panel_multi: VBoxContainer
var panel_save_apply: VBoxContainer
var panel_template_list: VBoxContainer

var preview_single: TilePreviewOverlay
var multi_preview: SelectionPreview
var collision_editor: CollisionPolygonEditor

var terrain_set_option: OptionButton
var terrain_option: OptionButton
var new_terrain_name_edit: LineEdit
var apply_warning_label: Label
var apply_template_btn: Button

var template_name_edit: LineEdit
var template_list: ItemList

var delete_confirm_dialog: ConfirmationDialog = null
var _pending_delete_path: String = ""


var _ui_built: bool = false


func _ready() -> void:
	if _ui_built:
		return
	_ui_built = true
	custom_minimum_size = Vector2(360, 0)
	_build_ui()
	_set_status("Pick a TileSet to begin.")


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# --- TileSet + source picker ---
	var picker_row := HBoxContainer.new()
	root.add_child(picker_row)

	tileset_picker = EditorResourcePicker.new()
	tileset_picker.base_type = "TileSet"
	tileset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tileset_picker.resource_changed.connect(_on_tileset_changed)
	picker_row.add_child(tileset_picker)

	source_option = OptionButton.new()
	source_option.custom_minimum_size = Vector2(140, 0)
	source_option.item_selected.connect(_on_source_selected)
	picker_row.add_child(source_option)

	save_tileset_btn = Button.new()
	save_tileset_btn.text = "Save TileSet"
	save_tileset_btn.tooltip_text = "Every paint/apply here only edits the TileSet in memory - this writes it back to its .tres file."
	save_tileset_btn.pressed.connect(_on_save_tileset_pressed)
	picker_row.add_child(save_tileset_btn)

	root.add_child(HSeparator.new())

	# --- Split: tile grid | side panel ---
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)

	grid_display = TileGridDisplay.new()
	grid_display.scroll_container = scroll
	grid_display.selection_changed.connect(_on_selection_changed)
	scroll.add_child(grid_display)

	var side_scroll := ScrollContainer.new()
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_scroll.custom_minimum_size = Vector2(300, 0)
	split.add_child(side_scroll)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)

	var top_row := HBoxContainer.new()
	selection_label = Label.new()
	selection_label.text = "Selected: 0 tiles"
	selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(selection_label)

	var view_group := ButtonGroup.new()
	view_toggle_terrain_btn = Button.new()
	view_toggle_terrain_btn.text = "Terrain"
	view_toggle_terrain_btn.toggle_mode = true
	view_toggle_terrain_btn.button_pressed = true
	view_toggle_terrain_btn.button_group = view_group
	view_toggle_terrain_btn.pressed.connect(func(): _on_view_mode_changed(TerrainTemplate.ViewMode.TERRAIN))
	top_row.add_child(view_toggle_terrain_btn)
	view_toggle_collision_btn = Button.new()
	view_toggle_collision_btn.text = "Collision"
	view_toggle_collision_btn.toggle_mode = true
	view_toggle_collision_btn.button_group = view_group
	view_toggle_collision_btn.pressed.connect(func(): _on_view_mode_changed(TerrainTemplate.ViewMode.COLLISION))
	top_row.add_child(view_toggle_collision_btn)
	side.add_child(top_row)

	side.add_child(HSeparator.new())

	paint_terrain_row = HBoxContainer.new()
	paint_terrain_row.add_child(_label("Paint terrain"))
	paint_terrain_option = OptionButton.new()
	paint_terrain_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_terrain_row.add_child(paint_terrain_option)
	side.add_child(paint_terrain_row)
	paint_terrain_hint = _label("Right-click a tile below to paint it; left-click a region to toggle a bit.")
	side.add_child(paint_terrain_hint)
	clear_bits_btn = Button.new()
	clear_bits_btn.text = "Clear Bits on Selected"
	clear_bits_btn.pressed.connect(_on_clear_bits_pressed)
	side.add_child(clear_bits_btn)
	collision_hint = _label("Left-click a tile below to edit its collision shape.")
	collision_hint.visible = false
	side.add_child(collision_hint)

	side.add_child(HSeparator.new())

	# --- panel_empty ---
	panel_empty = VBoxContainer.new()
	panel_empty.add_child(_label("No tiles selected. Click or drag on the grid to select tiles."))
	side.add_child(panel_empty)

	# --- panel_single: exactly one tile selected ---
	panel_single = VBoxContainer.new()
	preview_single = TilePreviewOverlay.new()
	preview_single.tile_left_clicked.connect(_on_single_tile_left_clicked)
	preview_single.bit_right_clicked.connect(_on_single_bit_right_clicked)
	panel_single.add_child(preview_single)
	side.add_child(panel_single)

	# --- panel_multi: two or more tiles selected (just the preview) ---
	panel_multi = VBoxContainer.new()

	multi_preview = SelectionPreview.new()
	multi_preview.tile_left_clicked.connect(_on_multi_tile_left_clicked)
	multi_preview.bit_right_clicked.connect(_on_multi_bit_right_clicked)
	panel_multi.add_child(multi_preview)

	side.add_child(panel_multi)

	# --- collision_editor: shared inline polygon editor, sits directly below
	# whichever of panel_single/panel_multi is currently visible ---
	collision_editor = CollisionPolygonEditor.new()
	collision_editor.visible = false
	collision_editor.changed.connect(_on_collision_editor_changed)
	side.add_child(collision_editor)

	# --- panel_save_apply: save-as-template / apply-a-template, below the
	# preview + collision editor ---
	panel_save_apply = VBoxContainer.new()

	panel_save_apply.add_child(HSeparator.new())
	panel_save_apply.add_child(_label("Save selection as a template"))
	panel_save_apply.add_child(_label("Tip: leave gaps in your grid selection to mark those spots as \"no tile\" in the saved template."))
	var save_name_row := HBoxContainer.new()
	save_name_row.add_child(_label("Name"))
	template_name_edit = LineEdit.new()
	template_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	template_name_edit.text = "New Template"
	save_name_row.add_child(template_name_edit)
	panel_save_apply.add_child(save_name_row)
	var save_btn := Button.new()
	save_btn.text = "Save to Template"
	save_btn.pressed.connect(_on_save_captured_template_pressed)
	panel_save_apply.add_child(save_btn)

	panel_save_apply.add_child(HSeparator.new())
	panel_save_apply.add_child(_label("Apply a saved template to the selection"))
	var terrain_set_row := HBoxContainer.new()
	terrain_set_option = OptionButton.new()
	terrain_set_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_set_option.item_selected.connect(_on_terrain_set_selected)
	terrain_set_row.add_child(terrain_set_option)
	var new_terrain_set_btn := Button.new()
	new_terrain_set_btn.text = "+"
	new_terrain_set_btn.tooltip_text = "New Terrain Set"
	new_terrain_set_btn.custom_minimum_size = Vector2(28, 0)
	new_terrain_set_btn.pressed.connect(_on_add_terrain_set_pressed)
	terrain_set_row.add_child(new_terrain_set_btn)
	panel_save_apply.add_child(terrain_set_row)

	terrain_option = OptionButton.new()
	terrain_option.item_selected.connect(func(_i): _refresh_apply_panel())
	panel_save_apply.add_child(terrain_option)

	var new_terrain_row := HBoxContainer.new()
	new_terrain_name_edit = LineEdit.new()
	new_terrain_name_edit.placeholder_text = "New terrain name"
	new_terrain_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_terrain_row.add_child(new_terrain_name_edit)
	var add_terrain_btn := Button.new()
	add_terrain_btn.text = "Add Terrain"
	add_terrain_btn.pressed.connect(_on_add_terrain_pressed)
	new_terrain_row.add_child(add_terrain_btn)
	panel_save_apply.add_child(new_terrain_row)

	apply_warning_label = Label.new()
	apply_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	apply_warning_label.visible = false
	panel_save_apply.add_child(apply_warning_label)
	apply_template_btn = Button.new()
	apply_template_btn.text = "Apply Template"
	apply_template_btn.pressed.connect(_on_apply_template_pressed)
	panel_save_apply.add_child(apply_template_btn)

	side.add_child(panel_save_apply)

	# --- panel_template_list: shared by the save + apply sections above ---
	panel_template_list = VBoxContainer.new()
	panel_template_list.add_child(HSeparator.new())
	panel_template_list.add_child(_label("Templates"))
	template_list = ItemList.new()
	template_list.custom_minimum_size = Vector2(0, 100)
	template_list.item_selected.connect(func(_i): _refresh_apply_panel())
	panel_template_list.add_child(template_list)
	var list_btn_row := HBoxContainer.new()
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_template_list)
	list_btn_row.add_child(refresh_btn)
	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.pressed.connect(_on_delete_template_pressed)
	list_btn_row.add_child(delete_btn)
	panel_template_list.add_child(list_btn_row)
	side.add_child(panel_template_list)

	side.add_child(HSeparator.new())
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(status_label)

	_refresh_paint_terrain_dropdown()
	_refresh_template_list()
	_update_side_panel()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


# ---------------------------------------------------------------------------
# TileSet / source handling
# ---------------------------------------------------------------------------
func _on_tileset_changed(resource: Resource) -> void:
	current_tileset = resource as TileSet
	source_option.clear()
	current_source_id = -1
	grid_display.setup(null, null)
	terrain_set_option.clear()
	terrain_option.clear()

	if current_tileset == null:
		_refresh_paint_terrain_dropdown()
		_set_status("Pick a TileSet to begin.")
		return

	for i in current_tileset.get_source_count():
		var sid: int = current_tileset.get_source_id(i)
		var src := current_tileset.get_source(sid)
		if src is TileSetAtlasSource:
			source_option.add_item(_source_display_name(src as TileSetAtlasSource, sid), sid)

	for i in current_tileset.get_terrain_sets_count():
		terrain_set_option.add_item("Terrain Set %d" % i, i)

	if source_option.item_count > 0:
		source_option.select(0)
		_on_source_selected(0)

	if terrain_set_option.item_count > 0:
		terrain_set_option.select(0)
		_on_terrain_set_selected(0)

	_refresh_paint_terrain_dropdown()
	_set_status("TileSet loaded.")


## Prefers the source's own resource name, then its texture's file name, and
## only falls back to "Source <id>" if neither is set.
func _source_display_name(src: TileSetAtlasSource, sid: int) -> String:
	if not src.resource_name.is_empty():
		return src.resource_name
	if src.texture and not src.texture.resource_path.is_empty():
		return src.texture.resource_path.get_file()
	return "Source %d" % sid


func _on_source_selected(index: int) -> void:
	if current_tileset == null:
		return
	current_source_id = source_option.get_item_id(index)
	var src := current_tileset.get_source(current_source_id) as TileSetAtlasSource
	grid_display.setup(current_tileset, src)
	_on_selection_changed()


func _on_save_tileset_pressed() -> void:
	if current_tileset == null:
		_set_status("No TileSet loaded.")
		return
	var path: String = current_tileset.resource_path
	if path.is_empty():
		_set_status("This TileSet has no file path yet - use the picker's own \"Save As...\" first.")
		return
	var err := ResourceSaver.save(current_tileset, path)
	if err == OK:
		_set_status("Saved TileSet to %s" % path)
	else:
		_set_status("Failed to save TileSet (error %d)." % err)


func _on_terrain_set_selected(index: int) -> void:
	terrain_option.clear()
	if current_tileset == null or index < 0:
		return
	for i in current_tileset.get_terrains_count(index):
		terrain_option.add_item(current_tileset.get_terrain_name(index, i), i)
	if terrain_option.item_count > 0:
		terrain_option.select(0)
	_refresh_apply_panel()


## Wrapping a bulk edit in these two suppresses the "changed" signal on the
## TileSet (and optionally one atlas source) while several small mutations
## happen in a row. Left unsuppressed, every single mutation's "changed"
## signal reaches the editor immediately - the TileSet bottom panel, any
## open TileMapLayer using this TileSet, etc. - and each of them redraws or
## rebuilds its own caches right then, which is what actually makes
## multi-step operations like adding a terrain set or applying a template
## feel slow. A single emit_changed() at the end still refreshes everything
## that's listening, just once instead of once per mutation.
func _begin_bulk_tileset_edit(atlas_source: TileSetAtlasSource = null) -> void:
	current_tileset.set_block_signals(true)
	if atlas_source:
		atlas_source.set_block_signals(true)


func _end_bulk_tileset_edit(atlas_source: TileSetAtlasSource = null) -> void:
	current_tileset.set_block_signals(false)
	if atlas_source:
		atlas_source.set_block_signals(false)
	current_tileset.emit_changed()
	if atlas_source:
		atlas_source.emit_changed()


func _on_add_terrain_set_pressed() -> void:
	if current_tileset == null:
		return
	_begin_bulk_tileset_edit()
	current_tileset.add_terrain_set(-1)
	var new_set_id: int = current_tileset.get_terrain_sets_count() - 1
	current_tileset.set_terrain_set_mode(new_set_id, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	_end_bulk_tileset_edit()
	terrain_set_option.add_item("Terrain Set %d" % new_set_id, new_set_id)
	terrain_set_option.select(terrain_set_option.item_count - 1)
	_on_terrain_set_selected(terrain_set_option.selected)
	_refresh_paint_terrain_dropdown()
	_set_status("Added a new terrain set.")


func _on_add_terrain_pressed() -> void:
	if current_tileset == null:
		return
	var name_text := new_terrain_name_edit.text.strip_edges()
	if name_text.is_empty():
		_set_status("Type a terrain name first.")
		return
	if terrain_set_option.selected < 0:
		_set_status("Pick or create a terrain set first.")
		return

	var terrain_set: int = terrain_set_option.get_item_id(terrain_set_option.selected)
	_begin_bulk_tileset_edit()
	current_tileset.add_terrain(terrain_set, -1)
	var idx: int = current_tileset.get_terrains_count(terrain_set) - 1
	current_tileset.set_terrain_name(terrain_set, idx, name_text)
	current_tileset.set_terrain_color(terrain_set, idx, Color.from_hsv(randf(), 0.55, 0.85))
	_end_bulk_tileset_edit()

	new_terrain_name_edit.text = ""
	_on_terrain_set_selected(terrain_set_option.selected)
	for i in terrain_option.item_count:
		if terrain_option.get_item_id(i) == idx:
			terrain_option.select(i)
			break
	_refresh_apply_panel()
	_refresh_paint_terrain_dropdown()
	_set_status("Added terrain '%s'." % name_text)


# ---------------------------------------------------------------------------
# Shared "active paint terrain" dropdown (None + every terrain across every
# terrain set). Painting always overwrites whichever tile is clicked.
# ---------------------------------------------------------------------------
func _refresh_paint_terrain_dropdown() -> void:
	if paint_terrain_option == null:
		return
	paint_terrain_option.clear()
	paint_terrain_option.add_item("None")
	paint_terrain_option.set_item_metadata(paint_terrain_option.item_count - 1, Vector2i(-1, -1))
	if current_tileset:
		var multiple_sets: bool = current_tileset.get_terrain_sets_count() > 1
		for ts in current_tileset.get_terrain_sets_count():
			for t in current_tileset.get_terrains_count(ts):
				var label: String = current_tileset.get_terrain_name(ts, t)
				if multiple_sets:
					label = "Set %d: %s" % [ts, label]
				paint_terrain_option.add_item(label)
				paint_terrain_option.set_item_metadata(paint_terrain_option.item_count - 1, Vector2i(ts, t))
	paint_terrain_option.select(0)


func _paint_terrain_on(coord: Vector2i) -> void:
	if paint_terrain_option == null or paint_terrain_option.selected < 0:
		return
	var td := _get_tile_data(coord)
	if td == null:
		return
	var pair: Vector2i = paint_terrain_option.get_item_metadata(paint_terrain_option.selected)
	if pair.x < 0:
		td.terrain_set = -1
	else:
		td.terrain_set = pair.x
		td.terrain = pair.y
	grid_display.queue_redraw()
	_update_side_panel()


func _toggle_bit_on(coord: Vector2i, bit_enum: int) -> void:
	var td := _get_tile_data(coord)
	if td == null or td.terrain_set < 0:
		return
	if bit_enum == TerrainTemplate.CENTER_BIT:
		# Purely visual - the center square has no real peering-bit
		# counterpart, so this never touches terrain matching data.
		TerrainTemplate.set_cosmetic_center(td, not TerrainTemplate.get_cosmetic_center(td))
	else:
		var cur: int = td.get_terrain_peering_bit(bit_enum)
		td.set_terrain_peering_bit(bit_enum, -1 if cur != -1 else td.terrain)
	grid_display.queue_redraw()
	_update_side_panel()


## Clears all 8 real peering bits (and the cosmetic center) on every
## currently selected tile that has a terrain assigned - leaves the terrain
## assignment itself untouched, just like right-clicking a bit to unset it,
## but for the whole selection at once.
func _on_clear_bits_pressed() -> void:
	if current_tileset == null or current_source_id < 0:
		return
	var atlas_source := current_tileset.get_source(current_source_id) as TileSetAtlasSource
	var count := 0
	_begin_bulk_tileset_edit(atlas_source)
	for coord in grid_display.selected.keys():
		var td := _get_tile_data(coord)
		if td == null or td.terrain_set < 0:
			continue
		for n in TerrainTemplate.NEIGHBORS:
			td.set_terrain_peering_bit(n["enum"], -1)
		TerrainTemplate.set_cosmetic_center(td, false)
		count += 1
	_end_bulk_tileset_edit(atlas_source)
	grid_display.queue_redraw()
	_update_side_panel()
	if count == 0:
		_set_status("No selected tiles have terrain bits to clear.")
	else:
		_set_status("Cleared bits on %d tile(s)." % count)


func _on_single_tile_left_clicked() -> void:
	if grid_display.selected.size() != 1:
		return
	if active_view == TerrainTemplate.ViewMode.COLLISION:
		_open_collision_editor()
	else:
		_paint_terrain_on(grid_display.selected.keys()[0])


func _on_single_bit_right_clicked(bit_enum: int) -> void:
	if grid_display.selected.size() != 1:
		return
	_toggle_bit_on(grid_display.selected.keys()[0], bit_enum)


func _on_multi_tile_left_clicked(coord: Vector2i) -> void:
	if active_view == TerrainTemplate.ViewMode.COLLISION:
		_open_collision_editor()
	else:
		_paint_terrain_on(coord)


func _on_multi_bit_right_clicked(coord: Vector2i, bit_enum: int) -> void:
	_toggle_bit_on(coord, bit_enum)


# ---------------------------------------------------------------------------
# Terrain/Collision view mode + the inline collision-polygon editor
# ---------------------------------------------------------------------------
func _get_current_atlas_source() -> TileSetAtlasSource:
	if current_tileset == null or current_source_id < 0:
		return null
	return current_tileset.get_source(current_source_id) as TileSetAtlasSource


func _on_view_mode_changed(mode: int) -> void:
	if active_view == mode:
		return
	active_view = mode
	grid_display.set_view_mode(mode)
	preview_single.set_view_mode(mode)
	multi_preview.set_view_mode(mode)
	paint_terrain_row.visible = mode == TerrainTemplate.ViewMode.TERRAIN
	paint_terrain_hint.visible = mode == TerrainTemplate.ViewMode.TERRAIN
	clear_bits_btn.visible = mode == TerrainTemplate.ViewMode.TERRAIN
	collision_hint.visible = mode == TerrainTemplate.ViewMode.COLLISION
	if mode != TerrainTemplate.ViewMode.COLLISION:
		_close_collision_editor()


func _open_collision_editor() -> void:
	var sel_bounds := grid_display.get_selection_bounds()
	var sel_coords: Array = grid_display.selected.keys()
	if sel_coords.is_empty():
		return
	collision_editor.set_selection(_get_current_atlas_source(), current_tileset, grid_display.region_size, sel_bounds, sel_coords)
	collision_editor.visible = true


func _close_collision_editor() -> void:
	collision_editor.visible = false
	collision_editor.atlas_source = null
	collision_editor.coords = []
	collision_editor.bounds = Rect2i()


func _on_collision_editor_changed() -> void:
	grid_display.queue_redraw()
	preview_single.queue_redraw()
	multi_preview.queue_redraw()


# ---------------------------------------------------------------------------
# Selection -> contextual side panel
# ---------------------------------------------------------------------------
func _on_selection_changed() -> void:
	selection_label.text = "Selected: %d tiles" % grid_display.selected.size()
	_sync_paint_tool_to_selection()
	_update_side_panel()


## If the new selection (single tile or a region) has a terrain on any tile
## in it, switches the active paint tool to that terrain - lets you select
## an already-terrained tile/region as a quick way to pick up its terrain,
## like an eyedropper. Leaves the paint tool alone if nothing selected has
## a terrain yet.
func _sync_paint_tool_to_selection() -> void:
	if paint_terrain_option == null:
		return
	for coord in grid_display.selected.keys():
		var td := _get_tile_data(coord)
		if td == null or td.terrain_set < 0:
			continue
		for i in paint_terrain_option.item_count:
			var pair: Vector2i = paint_terrain_option.get_item_metadata(i)
			if pair.x == td.terrain_set and pair.y == td.terrain:
				paint_terrain_option.select(i)
				return
		return


func _get_tile_data(coord: Vector2i) -> TileData:
	if current_tileset == null or current_source_id < 0:
		return null
	var atlas_source := current_tileset.get_source(current_source_id) as TileSetAtlasSource
	if atlas_source == null:
		return null
	return atlas_source.get_tile_data(coord, 0)


func _classify_selection() -> String:
	var sel: Dictionary = grid_display.selected
	if sel.is_empty():
		return "empty"
	if sel.size() == 1:
		return "single"
	return "multi"


func _show_committed_multi_preview() -> void:
	var atlas_source: TileSetAtlasSource = null
	if current_tileset and current_source_id >= 0:
		atlas_source = current_tileset.get_source(current_source_id) as TileSetAtlasSource
	var bounds: Rect2i = grid_display.get_selection_bounds()
	multi_preview.set_committed(atlas_source, current_tileset, grid_display.region_size, bounds, grid_display.selected.keys())


func _update_side_panel() -> void:
	_close_collision_editor()
	var state := _classify_selection()
	panel_empty.visible = state == "empty"
	panel_single.visible = state == "single"
	panel_multi.visible = state == "multi"
	panel_save_apply.visible = state == "multi"
	panel_template_list.visible = state == "multi"
	paint_terrain_option.visible = state != "empty"

	var atlas_source: TileSetAtlasSource = null
	if current_tileset and current_source_id >= 0:
		atlas_source = current_tileset.get_source(current_source_id) as TileSetAtlasSource

	if state == "single":
		preview_single.set_tile(atlas_source, grid_display.selected.keys()[0], current_tileset)
	elif state == "multi":
		_show_committed_multi_preview()

	if state == "multi":
		_refresh_apply_panel()
	else:
		grid_display.clear_apply_preview()


func _validate_ready_for_edit() -> bool:
	if current_tileset == null or current_source_id < 0:
		_set_status("Pick a TileSet and source first.")
		return false
	if grid_display.selected.is_empty():
		_set_status("Select at least one tile in the grid first.")
		return false
	return true


# ---------------------------------------------------------------------------
# Template list / delete
# ---------------------------------------------------------------------------
func _refresh_template_list() -> void:
	template_list.clear()
	var folder: String = DEFAULT_TEMPLATE_FOLDER
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)

	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path: String = folder.path_join(file_name)
			var res: Resource = load(path)
			if res is TerrainTemplate:
				var tmpl := res as TerrainTemplate
				var idx := template_list.add_item(tmpl.template_name)
				template_list.set_item_metadata(idx, path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _get_selected_template() -> TerrainTemplate:
	var idxs: PackedInt32Array = template_list.get_selected_items()
	if idxs.is_empty():
		return null
	var path: String = template_list.get_item_metadata(idxs[0])
	return load(path) as TerrainTemplate


func _on_delete_template_pressed() -> void:
	var idxs: PackedInt32Array = template_list.get_selected_items()
	if idxs.is_empty():
		_set_status("Select a template in the list first.")
		return
	var item_name: String = template_list.get_item_text(idxs[0])
	_pending_delete_path = template_list.get_item_metadata(idxs[0])
	if delete_confirm_dialog == null:
		delete_confirm_dialog = ConfirmationDialog.new()
		delete_confirm_dialog.confirmed.connect(_on_delete_template_confirmed)
		add_child(delete_confirm_dialog)
	delete_confirm_dialog.dialog_text = "Delete template '%s'? This cannot be undone." % item_name
	delete_confirm_dialog.popup_centered()


func _on_delete_template_confirmed() -> void:
	if _pending_delete_path.is_empty():
		return
	DirAccess.remove_absolute(_pending_delete_path)
	_pending_delete_path = ""
	_refresh_template_list()
	_set_status("Deleted template file.")


# ---------------------------------------------------------------------------
# Save to template: bulk capture directly from the selected real tiles.
# ---------------------------------------------------------------------------
func _on_save_captured_template_pressed() -> void:
	if not _validate_ready_for_edit():
		return
	var sel: Dictionary = grid_display.selected
	var bounds: Rect2i = grid_display.get_selection_bounds()

	var atlas_source := current_tileset.get_source(current_source_id) as TileSetAtlasSource
	var tpl := TerrainTemplateScript.new()
	tpl.size = bounds.size

	# Iterates the whole bounding rect, not just sel.keys() - a gap in the
	# drag-selection (no real tile there) becomes a null cell, letting one
	# template represent a non-rectangular stamp shape.
	for y in range(bounds.size.y):
		for x in range(bounds.size.x):
			var coord: Vector2i = bounds.position + Vector2i(x, y)
			if not sel.has(coord):
				tpl.set_cell(x, y, TerrainTemplate.make_null_cell())
				continue
			var td := atlas_source.get_tile_data(coord, 0)
			if td == null:
				tpl.set_cell(x, y, TerrainTemplate.make_null_cell())
				continue

			var cell: Dictionary = TerrainTemplate.make_empty_cell()
			for n in TerrainTemplate.NEIGHBORS:
				var e: int = n["enum"]
				cell["bits"][e] = td.get_terrain_peering_bit(e) != -1
			cell["bits"][TerrainTemplate.CENTER_BIT] = TerrainTemplate.get_cosmetic_center(td)

			var chosen_layer := -1
			for layer in current_tileset.get_physics_layers_count():
				if td.get_collision_polygons_count(layer) > 0:
					chosen_layer = layer
					break
			if chosen_layer != -1:
				cell["has_collision"] = true
				cell["physics_layer"] = chosen_layer
				cell["polygon"] = td.get_collision_polygon_points(chosen_layer, 0)

			tpl.set_cell(x, y, cell)

	_save_template_resource(tpl, template_name_edit.text)


func _save_template_resource(tpl: TerrainTemplate, name_text: String) -> void:
	tpl.template_name = name_text.strip_edges()
	if tpl.template_name.is_empty():
		tpl.template_name = "Unnamed Template"

	var folder: String = DEFAULT_TEMPLATE_FOLDER
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)

	var safe_name := tpl.template_name.to_lower()
	safe_name = safe_name.replace(" ", "_")
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_\\-]")
	safe_name = regex.sub(safe_name, "", true)
	if safe_name.is_empty():
		safe_name = "template"

	var path: String = folder.path_join(safe_name + ".tres")
	var err := ResourceSaver.save(tpl, path)
	if err == OK:
		_set_status("Saved template (terrain bits + collision) to %s" % path)
		_refresh_template_list()
	else:
		_set_status("Failed to save template (error %d)." % err)


# ---------------------------------------------------------------------------
# Apply template to selection (supports tiling across a selection that is an
# exact multiple of the template's size). Live-previewed on the grid + the
# multi-tile preview before commit via _refresh_apply_panel(); only written
# on Apply.
# ---------------------------------------------------------------------------
func _refresh_apply_panel() -> void:
	if grid_display == null or apply_warning_label == null:
		return
	var sel: Dictionary = grid_display.selected
	grid_display.clear_apply_preview()
	_show_committed_multi_preview()

	if sel.is_empty():
		apply_warning_label.visible = false
		apply_template_btn.disabled = true
		return

	var bounds: Rect2i = grid_display.get_selection_bounds()

	var tpl := _get_selected_template()
	if tpl == null:
		apply_warning_label.text = "Pick a template from the list below."
		apply_warning_label.visible = true
		apply_template_btn.disabled = true
		return

	if bounds.size.x % tpl.size.x != 0 or bounds.size.y % tpl.size.y != 0:
		apply_warning_label.text = "Selection (%dx%d) is not an exact multiple of the template size (%dx%d)." % [bounds.size.x, bounds.size.y, tpl.size.x, tpl.size.y]
		apply_warning_label.visible = true
		apply_template_btn.disabled = true
		return

	if terrain_set_option.selected < 0 or terrain_option.selected < 0:
		apply_warning_label.text = "Pick a terrain set and terrain."
		apply_warning_label.visible = true
		apply_template_btn.disabled = true
		return

	apply_warning_label.visible = false
	apply_template_btn.disabled = false
	var terrain_set: int = terrain_set_option.get_item_id(terrain_set_option.selected)
	var terrain: int = terrain_option.get_item_id(terrain_option.selected)
	grid_display.set_apply_preview(tpl, bounds, terrain_set, terrain)

	var atlas_source: TileSetAtlasSource = null
	if current_tileset and current_source_id >= 0:
		atlas_source = current_tileset.get_source(current_source_id) as TileSetAtlasSource
	multi_preview.set_pending(atlas_source, current_tileset, grid_display.region_size, bounds, sel.keys(), tpl, terrain_set, terrain)


func _on_apply_template_pressed() -> void:
	if not _validate_ready_for_edit():
		return
	var tpl := _get_selected_template()
	if tpl == null:
		_set_status("Pick a template first.")
		return

	var bounds: Rect2i = grid_display.get_selection_bounds()

	var tw: int = tpl.size.x
	var th: int = tpl.size.y
	if bounds.size.x % tw != 0 or bounds.size.y % th != 0:
		_set_status("Selection (%dx%d) is not an exact multiple of the template size (%dx%d)." % [bounds.size.x, bounds.size.y, tw, th])
		return

	if terrain_set_option.selected < 0 or terrain_option.selected < 0:
		_set_status("Pick a terrain set and terrain.")
		return

	var atlas_source := current_tileset.get_source(current_source_id) as TileSetAtlasSource
	var terrain_set: int = terrain_set_option.get_item_id(terrain_set_option.selected)
	var terrain: int = terrain_option.get_item_id(terrain_option.selected)

	var applied := 0
	var skipped_no_tile := 0
	var skipped_null_template := 0

	_begin_bulk_tileset_edit(atlas_source)
	for coord in grid_display.selected.keys():
		var local_x: int = posmod(coord.x - bounds.position.x, tw)
		var local_y: int = posmod(coord.y - bounds.position.y, th)
		var cell: Dictionary = tpl.get_cell(local_x, local_y)

		if TerrainTemplate.is_cell_null(cell):
			skipped_null_template += 1
			continue

		var td := atlas_source.get_tile_data(coord, 0)
		if td == null:
			skipped_no_tile += 1
			continue

		td.terrain_set = terrain_set
		td.terrain = terrain

		for n in TerrainTemplate.NEIGHBORS:
			var e: int = n["enum"]
			td.set_terrain_peering_bit(e, terrain if bool(cell["bits"].get(e, false)) else -1)
		TerrainTemplate.set_cosmetic_center(td, bool(cell["bits"].get(TerrainTemplate.CENTER_BIT, false)))

		var layer: int = cell.get("physics_layer", 0)
		# Clear every physics layer, not just the template's own - otherwise
		# a stale polygon left on a different layer (from prior manual
		# editing, or a different template) would survive this Apply even
		# though Apply is meant to fully define the tile's collision state.
		for other_layer in current_tileset.get_physics_layers_count():
			var existing_count: int = td.get_collision_polygons_count(other_layer)
			for i in range(existing_count - 1, -1, -1):
				td.remove_collision_polygon(other_layer, i)
		if cell.get("has_collision", false):
			var poly: PackedVector2Array = cell.get("polygon", PackedVector2Array())
			if poly.size() >= 3:
				td.add_collision_polygon(layer)
				td.set_collision_polygon_points(layer, 0, poly)

		applied += 1
	_end_bulk_tileset_edit(atlas_source)

	grid_display.clear_apply_preview()
	grid_display.queue_redraw()
	if applied > 0:
		# Deselecting drops the template so _refresh_apply_panel() (called
		# from _update_side_panel() below) falls back to showing the real,
		# now-committed result instead of the same translucent pending
		# preview it was showing a moment ago - otherwise it looks like
		# nothing happened.
		template_list.deselect_all()
		_set_status("Applied template (terrain bits + collision) to %d tiles (%d skipped - no tile data, %d skipped - template has no tile there). Click \"Save TileSet\" above to write this to disk." % [applied, skipped_no_tile, skipped_null_template])
	else:
		_set_status("Nothing applied (%d skipped - no tile data, %d skipped - template has no tile there)." % [skipped_no_tile, skipped_null_template])
	_update_side_panel()
