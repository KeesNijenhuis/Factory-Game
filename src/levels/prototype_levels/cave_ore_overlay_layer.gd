class_name CaveOreOverlayLayer
extends TileMapLayer
## Sibling of a CaveWallsLayer, drawn on top of it. Renders each ore's
## indicator on whichever wall cells have been marked via mark_ore_cell()
## (see OreVeinGenerator), keeping each cell's art in sync with the standing
## Cave_Wall tile underneath it as the wall gets mined -- CaveWallsLayer
## calls resync() directly after it finishes mining a cell (its own
## `changed` signal isn't a reliable trigger for this: damage_wall_cell()
## already re-syncs its own Cave_Wall_Base cap row with a direct call rather
## than going through that signal, for the same reason).

## Each Wall_*_Overlay terrain (terrain_set 1) was drawn as a sparse mirror
## of the Cave_Wall terrain's own 47-tile blob layout, in the same "Caves"
## atlas source, 10 rows further down -- same column (plus that ore's own
## OreType.column_offset), only some rows fully drawn. So the right overlay
## piece for a wall cell is always "the same atlas column as the wall's own
## tile, shifted by the ore's column_offset, 10 rows down", when that exact
## tile exists.
const OVERLAY_ROW_OFFSET: int = 10

@export var walls_layer_path: NodePath

## Debug aid, toggled from the in-game debug menu (F2, "Ore Overlay Debug
## Draw"): outlines every cell in _ore_cells, regardless of what (if
## anything) actually got drawn there -- lets you see where the ore data
## says copper is even when the art is blank (missing shape, mid-mining,
## etc). Drawn by a dedicated child node -- see CaveOreDebugDraw -- so its
## z_index doesn't ride along with this layer's own tile art.
const DEBUG_Z_INDEX: int = 6

## Same shader CaveWallsLayer uses for its own hit-flash -- see
## _flash_layer below.
const FLASH_SHADER: Shader = preload("res://src/shaders/wall_hit_flash.gdshader")

var walls_layer: CaveWallsLayer
var _debug_draw: CaveOreDebugDraw

## Overlay that only ever holds copies of whichever ore cell(s) are currently
## flashing, mirroring CaveWallsLayer's own _flash_layer -- without this, the
## ore art this layer draws on top of a wall cell would sit unaffected while
## the wall's own hit-flash washes out underneath it, so an ore vein getting
## mined would never visibly flash. Driven by CaveWallsLayer._flash_cell()/
## _process() in lockstep with its own flash timer, via flash_cell(),
## set_flash_amount() and clear_flash() below.
var _flash_layer: TileMapLayer
## Cells currently mirrored onto _flash_layer, keyed the same way as
## CaveWallsLayer's own _flash_cells.
var _flash_cells: Dictionary = {}

## Cells currently marked as ore veins, keyed to the OreType that claimed
## them. This is the authoritative record -- a marked cell can end up
## rendering nothing (an exposed edge shape with no drawn art) or a fallback
## sprite (no terrain_set/terrain of its own), so the tile data alone can't
## answer is_ore_cell() the way it can for CaveWallsLayer's plain
## wall/removed cells.
var _ore_cells: Dictionary = {}
## Which fallback icon each fully-enclosed cell rolled, chosen once the first
## time that cell is found fully enclosed and reused every time after --
## resync() re-applies every ore cell's art on every mining hit anywhere
## nearby, so without this a fully-enclosed cell's icon would reroll (and
## visibly flicker to a different variant) each time any wall gets mined.
var _fallback_variants: Dictionary = {}


func _ready() -> void:
	walls_layer = get_node(walls_layer_path)
	_debug_draw = CaveOreDebugDraw.new()
	_debug_draw.overlay_layer = self
	_debug_draw.z_index = DEBUG_Z_INDEX
	_debug_draw.add_to_group(&"ore_overlay_layers")
	add_child(_debug_draw)
	if not Engine.is_editor_hint():
		_flash_layer = TileMapLayer.new()
		_flash_layer.tile_set = tile_set
		_flash_layer.y_sort_enabled = y_sort_enabled
		var flash_material := ShaderMaterial.new()
		flash_material.shader = FLASH_SHADER
		_flash_layer.material = flash_material
		add_child(_flash_layer)


func mark_ore_cell(cell: Vector2i, ore_type: OreType) -> void:
	if _ore_cells.has(cell):
		return
	_ore_cells[cell] = ore_type
	_apply_cell(cell)
	_queue_debug_redraw()


func get_ore_cells() -> Dictionary:
	return _ore_cells


func get_ore_type(cell: Vector2i) -> OreType:
	return _ore_cells.get(cell)


func _queue_debug_redraw() -> void:
	if DebugSettings.show_ore_debug_draw:
		_debug_draw.queue_redraw()


func is_ore_cell(cell: Vector2i) -> bool:
	return _ore_cells.has(cell)


## Mirrors whatever ore art is currently drawn at `wall_cell` (and its base
## cap below it, if any) onto _flash_layer, so CaveWallsLayer's hit-flash
## reads on the ore art too instead of only on the plain wall tile underneath
## it. A no-op for either cell if this layer isn't drawing anything there.
## The cell below `wall_cell` only ever gets mirrored when it's actually the
## decorative Cave_Wall_Base cap belonging to `wall_cell` -- when two wall
## cells are stacked, that cell is itself a separate standing wall the hit
## never touched, and mirroring its ore art too would flash it right along
## with the cell that was actually mined.
func flash_cell(wall_cell: Vector2i) -> void:
	for cell: Vector2i in _flash_cells:
		_flash_layer.erase_cell(cell)
	_flash_cells.clear()
	_mirror_into_flash_layer(wall_cell)
	var base_cell := wall_cell + Vector2i.DOWN
	if walls_layer.is_base_cell(base_cell):
		_mirror_into_flash_layer(base_cell)


func _mirror_into_flash_layer(cell: Vector2i) -> void:
	if get_cell_source_id(cell) == -1:
		return
	_flash_cells[cell] = true
	_flash_layer.set_cell(cell, get_cell_source_id(cell), get_cell_atlas_coords(cell), get_cell_alternative_tile(cell))


## Called alongside CaveWallsLayer's own flash_material update, so both
## layers' flashes fade in lockstep off the one timer CaveWallsLayer owns.
func set_flash_amount(amount: float) -> void:
	var flash_material: ShaderMaterial = _flash_layer.material
	flash_material.set_shader_parameter("flash_amount", amount)


func clear_flash() -> void:
	for cell: Vector2i in _flash_cells:
		_flash_layer.erase_cell(cell)
	_flash_cells.clear()


## Re-derives every ore cell's art from the Walls layer's current state.
## Call after any wall change that could affect an ore cell's shape or
## enclosure: mining erases the cell itself and can flip a neighbor from
## fully-enclosed to exposed (or the reverse, once digging supports refilling).
func resync() -> void:
	for cell in _ore_cells.keys():
		_apply_cell(cell)


## Re-sync only ore cells whose wall neighborhood may have changed. This is
## used for chunk seam updates and single-cell mining, where a full overlay
## rebuild would revisit every ore cell in the loaded world. Expands each
## changed cell by all 8 neighbors (plus itself), matching the full
## neighborhood _is_fully_enclosed() checks -- a diagonal neighbor's
## enclosure art depends on `changed_cell` too, not just its orthogonal
## neighbors.
func resync_around(changed_cells: Array[Vector2i]) -> void:
	var affected := {}
	for changed_cell in changed_cells:
		for offset in [Vector2i.ZERO] + CaveWallsLayer.NEIGHBOR_OFFSETS:
			var cell: Vector2i = changed_cell + offset
			if _ore_cells.has(cell):
				affected[cell] = true
	for cell: Vector2i in affected:
		_apply_cell(cell)


## Picks the right art for `cell`, following the rule the game designer
## wants: fully-enclosed ore cells always get one of their ore's fallback
## sprites (picked at random); otherwise an exposed cell shows the mirrored
## Wall_*_Overlay piece if one is drawn for that shape, or nothing at all if
## it isn't. Also keeps the Cave_Wall_Base cap directly below `cell` (if any)
## in its own mirrored Base_Wall_*_Overlay piece -- but only when the wall
## itself actually rendered ore, since the base terrain's 4 shapes are all
## fully drawn while the wall terrain's 47 are sparse: without this check the
## cap would show ore more often than the wall above it ever does.
func _apply_cell(cell: Vector2i) -> void:
	if not walls_layer.is_wall_cell(cell):
		erase_cell(cell)
		_erase_if_unmanaged(cell + Vector2i.DOWN)
		_ore_cells.erase(cell)
		_fallback_variants.erase(cell)
		_queue_debug_redraw()
		return
	var ore_type: OreType = _ore_cells[cell]
	var wall_has_ore: bool
	if _is_fully_enclosed(cell):
		if not _fallback_variants.has(cell):
			_fallback_variants[cell] = ore_type.fallback_variants.pick_random()
		set_cell(cell, ore_type.fallback_source_id, _fallback_variants[cell])
		wall_has_ore = true
	else:
		wall_has_ore = _mirror_cell(cell, cell, ore_type)
	_apply_base_cell(cell, wall_has_ore, ore_type)


## The base cap belonging to `wall_cell` (the tile directly below it) has no
## enclosed/exposed distinction of its own -- a cap only ever exists where
## the wall above is already exposed at its foot -- so it's just a mirror,
## with no fallback-sprite case. Only mirrors when `wall_has_ore` is true;
## see _apply_cell()'s comment for why that check matters.
func _apply_base_cell(wall_cell: Vector2i, wall_has_ore: bool, ore_type: OreType) -> void:
	var base_cell := wall_cell + Vector2i.DOWN
	if wall_has_ore and walls_layer.is_base_cell(base_cell):
		_mirror_cell(base_cell, base_cell, ore_type)
	else:
		_erase_if_unmanaged(base_cell)


## Copies whatever atlas piece walls_layer is currently showing at
## `source_cell`, shifted by `ore_type.column_offset` columns and
## OVERLAY_ROW_OFFSET rows in the same atlas source, onto this layer at
## `target_cell` -- or erases `target_cell` if that specific piece has no
## drawn ore art. Returns whether a tile was set.
func _mirror_cell(source_cell: Vector2i, target_cell: Vector2i, ore_type: OreType) -> bool:
	var overlay_atlas: Vector2i = walls_layer.get_cell_atlas_coords(source_cell) + Vector2i(ore_type.column_offset, OVERLAY_ROW_OFFSET)
	if tile_set.get_source(CaveWallsLayer.TILESET_SOURCE_ID).has_tile(overlay_atlas):
		set_cell(target_cell, CaveWallsLayer.TILESET_SOURCE_ID, overlay_atlas)
		return true
	erase_cell(target_cell)
	return false


## Only a cell tracked in _ore_cells ever manages its own overlay tile via its
## own _apply_cell() call (mark_ore_cell()/resync()/resync_around() are the
## only things that ever call it) -- erasing `cell` here too, just because
## some other cell's cleanup happened to compute this position, would clobber
## whatever that ore cell legitimately drew, now or on its next resync.
## Checking is_wall_cell() here instead (the previous behavior) was wrong: a
## cap that turns out, once a neighboring chunk loads, to actually be a plain
## (non-ore) standing wall is_wall_cell()==true but was never and will never
## be tracked in _ore_cells, so nothing else was ever going to clean up its
## now-stale ore art -- leaving ore-overlay art sitting on a plain wall that
## reads as ore but neither drops ore nor (once it's a base cap instead of a
## wall) resolves as mineable at all.
func _erase_if_unmanaged(cell: Vector2i) -> void:
	if not is_ore_cell(cell):
		erase_cell(cell)


func _is_fully_enclosed(cell: Vector2i) -> bool:
	for offset in CaveWallsLayer.NEIGHBOR_OFFSETS:
		if not walls_layer.is_wall_cell(cell + offset):
			return false
	return true
