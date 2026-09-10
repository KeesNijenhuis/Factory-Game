@tool
class_name CaveWallsLayer
extends TileMapLayer
## Attach to a hand-painted Walls layer using the Cave Wall / Cave Wall Base
## terrain pair. Runs in-editor: whenever Cave Wall cells are painted or
## erased, automatically keeps the Cave Wall Base row underneath in sync
## (see CaveWallBase for the placement rule), so the base tiles never need
## to be painted by hand.

const TILESET_SOURCE_ID: int = 0
const HITS_TO_BREAK: int = 2
const ITEM_DROP_DELAY: float = 0.2
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]

## How long a hit's white flash takes to fade out, starting at full
## FLASH_PEAK_AMOUNT the instant the hit lands.
const FLASH_DURATION: float = 0.15
## How far a flash pushes the tile toward white (1.0 would be solid white,
## erasing the art entirely -- keep this under 1 so the tile's own texture
## still reads through the flash).
const FLASH_PEAK_AMOUNT: float = 0.85
const FLASH_SHADER: Shader = preload("res://src/shaders/wall_hit_flash.gdshader")

## Item dropped when a wall cell is fully mined.
@export var dropped_item: Item = preload("res://src/resources/items/materials/rock.tres")
## Sibling overlay layer that marks which wall cells are ore veins -- when
## set, mining an ore cell drops its dropped_item instead of this layer's own.
## Optional: left empty, no cell ever counts as an ore cell.
@export var ore_overlay_layer_path: NodePath
## Whether this layer registers itself into the "saveable" group for
## SaveManager's whole-level scan. Default true preserves today's behavior
## for hand-authored levels (cave_level.tscn). A chunk-streamed level
## (ProceduralCaveLevel) sets this false -- CaveChunkStreamer becomes the
## single "saveable" node instead, since SaveManager's group scan runs once,
## assuming every relevant node already exists in the tree, which isn't true
## when only nearby chunks are loaded (see cell_removed).
@export var self_register_saveable: bool = true

## Emitted whenever a wall cell is actually mined away (not when CaveBuilder
## erases cells for chunk-management painting, which calls erase_cell()
## directly rather than through _erase_wall_cell()). CaveChunkStreamer
## listens to this to record which cells were mined per chunk.
signal cell_removed(cell: Vector2i)

var ore_overlay_layer: CaveOreOverlayLayer
var _syncing: bool = false
## In-progress pickaxe hit counts, keyed by wall cell. Cleared once a cell
## breaks (or turns out not to be a wall cell after all).
var _wall_hits: Dictionary = {}
## Wall cells erased so far (by mining or by replaying a save), keyed by
## cell. This is the persisted record of what's been dug out -- the tile
## data itself only shows a cell's current state, not that it used to be a
## wall, so this is what get_save_data()/apply_save_data() round-trip.
var _removed_cells: Dictionary = {}
## Cells currently mid-flash from a hit, mirrored one-for-one onto
## _flash_layer's own cells. Every flashing cell shares one fade timer
## (_flash_elapsed) since they only ever start together, from the same hit.
var _flash_cells: Dictionary = {}
## Seconds since the flash currently playing started, or >= FLASH_DURATION
## when nothing is flashing.
var _flash_elapsed: float = FLASH_DURATION
## Overlay layer that only ever holds copies of currently-flashing cells,
## tinted toward white via wall_hit_flash.gdshader (see _flash_cell()).
var _flash_layer: TileMapLayer
var _wall_tile_lookup: Dictionary = {}
var _wall_lookup_tileset: TileSet


func _ready() -> void:
	changed.connect(_on_changed)
	if not ore_overlay_layer_path.is_empty():
		ore_overlay_layer = get_node(ore_overlay_layer_path)
	if not Engine.is_editor_hint():
		if self_register_saveable:
			add_to_group("saveable")
		_flash_layer = TileMapLayer.new()
		_flash_layer.tile_set = tile_set
		# Match the main layer's own y-sorting, so each mirrored tile sorts
		# against the player/other tiles exactly like its source tile does --
		# otherwise it draws as a single fixed-position batch instead and only
		# wins that per-tile sort on one side of the layer's own origin.
		_flash_layer.y_sort_enabled = y_sort_enabled
		var flash_material := ShaderMaterial.new()
		flash_material.shader = FLASH_SHADER
		_flash_layer.material = flash_material
		add_child(_flash_layer)
	set_process(false)


func _process(delta: float) -> void:
	_flash_elapsed += delta
	if _flash_elapsed >= FLASH_DURATION:
		for cell: Vector2i in _flash_cells:
			_flash_layer.erase_cell(cell)
		_flash_cells.clear()
		if ore_overlay_layer != null:
			ore_overlay_layer.clear_flash()
		set_process(false)
		return
	var flash_amount := (1.0 - _flash_elapsed / FLASH_DURATION) * FLASH_PEAK_AMOUNT
	var flash_material: ShaderMaterial = _flash_layer.material
	flash_material.set_shader_parameter("flash_amount", flash_amount)
	if ore_overlay_layer != null:
		ore_overlay_layer.set_flash_amount(flash_amount)


func get_save_id() -> String:
	return "cave_walls_layer"


func get_save_data() -> Dictionary:
	var cells := []
	for cell in _removed_cells:
		cells.append({"x": cell.x, "y": cell.y})
	return {"removed_cells": cells}


## Replays previously-erased cells after the level's baked tile data has
## loaded. Erases everything first and only refreshes/syncs once at the end,
## rather than going through damage_wall_cell()'s per-cell refresh, since
## restoring a whole save's worth of cells one at a time would recompute the
## same neighboring autotile shapes repeatedly.
func apply_save_data(data: Dictionary) -> void:
	var entries: Array = data.get("removed_cells", [])
	var erased: Array[Vector2i] = []
	for entry in entries:
		var cell := Vector2i(entry.get("x", 0), entry.get("y", 0))
		if _is_wall_cell(cell):
			_erase_wall_cell(cell)
			erased.append(cell)
	for cell in erased:
		_refresh_wall_terrain_around(cell)
	_sync_base_tiles()
	if ore_overlay_layer != null:
		ore_overlay_layer.resync()


## Resolves whichever cell the player actually mined-clicked on to the
## standing Cave_Wall cell it refers to: `cell` itself if it's already a wall,
## or the cell directly above it if `cell` is a decorative Cave_Wall_Base cap
## tile with a wall standing there (a cap tile always sits directly below the
## wall it belongs to -- see CaveWallBase.compute_base_tiles). Returns null if
## `cell` is neither a wall nor a cap tile fronting one.
func resolve_mineable_cell(cell: Vector2i) -> Variant:
	if _is_wall_cell(cell):
		return cell
	var above := cell + Vector2i.UP
	if _is_base_cell(cell) and _is_wall_cell(above):
		return above
	return null


## How many cells the mining quadrant/raycast reaches out to on each side of
## the player -- matches the 5x5 reach square used elsewhere (see
## AutomationUtils.is_adjacent / InteractionController.REACH_RADIUS).
const REACH_RADIUS: int = 2


## The half of the 5x5 reach square that's active for a given facing, as a
## cell-coordinate rect relative to `player_cell`. Each quadrant includes the
## player's own central row/column, so opposite quadrants overlap along that
## middle strip -- e.g. "up" and "down" both include the player's row.
func get_quadrant_rect(player_cell: Vector2i, facing: String) -> Rect2i:
	var min_x := player_cell.x - REACH_RADIUS
	var max_x := player_cell.x + REACH_RADIUS
	var min_y := player_cell.y - REACH_RADIUS
	var max_y := player_cell.y + REACH_RADIUS
	match facing:
		"up":
			max_y = player_cell.y
		"down":
			min_y = player_cell.y
		"left":
			max_x = player_cell.x
		"right":
			min_x = player_cell.x
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Every cell inside `facing`'s quadrant rect except the player's own cell --
## these are the ray-fan's targets, one ray per cell.
func get_quadrant_cells(player_cell: Vector2i, facing: String) -> Array[Vector2i]:
	var rect := get_quadrant_rect(player_cell, facing)
	var cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if cell != player_cell:
				cells.append(cell)
	return cells


## Which standing wall cells are actually reachable by a ray from
## `ray_origin_global` (the player's MarkerLineOfSight) toward every cell in
## `facing`'s quadrant, stopping each ray at the first wall cell it meets or
## at the edge of the 5x5 reach square, whichever comes first. A wall cell
## boxed in by other wall cells never appears here, since every ray toward it
## is blocked by a nearer wall first -- no special-casing needed. Also
## returns each ray's world-space endpoint (the wall cell it stopped at, or
## the quadrant cell it reached unobstructed), for debug drawing.
func find_mineable_cells_with_ray_ends(player_cell: Vector2i, facing: String, ray_origin_global: Vector2) -> Dictionary:
	var local_origin := to_local(ray_origin_global)
	var mineable: Dictionary = {}
	var ray_ends: Array[Vector2] = []
	for target_cell in get_quadrant_cells(player_cell, facing):
		var hit_cell = _raycast_wall_cell(local_origin, map_to_local(target_cell), player_cell)
		var end_cell: Vector2i = hit_cell if hit_cell != null else target_cell
		ray_ends.append(to_global(map_to_local(end_cell)))
		if hit_cell != null:
			mineable[hit_cell] = true
	var mineable_cells: Array[Vector2i] = []
	for cell in mineable:
		mineable_cells.append(cell)
	return {"mineable_cells": mineable_cells, "ray_ends": ray_ends}


func find_mineable_cells(player_cell: Vector2i, facing: String, ray_origin_global: Vector2) -> Array[Vector2i]:
	return find_mineable_cells_with_ray_ends(player_cell, facing, ray_origin_global).mineable_cells


## `cell == player_cell` is trivially mineable without casting a ray -- a
## standing wall's collision can be inset from its tile's top edge for visual
## overhang, letting the player's tracked cell land on the wall cell they
## just walked into and are now flush against. get_quadrant_cells() always
## excludes the player's own cell from the ray-fan's targets (it's meant to
## enumerate cells *around* the player), so that cell would otherwise never
## appear in find_mineable_cells() no matter which way the player is facing.
func is_mineable(cell: Vector2i, player_cell: Vector2i, facing: String, ray_origin_global: Vector2) -> bool:
	if cell == player_cell:
		return true
	return cell in find_mineable_cells(player_cell, facing, ray_origin_global)


## Traces one ray from `local_origin` toward `local_target` (both in this
## layer's local space) using an Amanatides & Woo grid walk -- the origin is
## a continuous position (the marker), not tile-snapped, so simple
## cell-to-cell stepping isn't enough to enumerate every cell the ray
## actually crosses. Returns the first standing wall cell hit, or null if the
## ray leaves the 5x5 reach square around `player_cell` first.
func _raycast_wall_cell(local_origin: Vector2, local_target: Vector2, player_cell: Vector2i) -> Variant:
	var direction := local_target - local_origin
	if direction.length_squared() < 0.0001:
		return null
	direction = direction.normalized()
	var cell_size := Vector2(tile_set.tile_size)
	var current_cell := local_to_map(local_origin)

	var step_x := 0
	if direction.x > 0.0:
		step_x = 1
	elif direction.x < 0.0:
		step_x = -1
	var step_y := 0
	if direction.y > 0.0:
		step_y = 1
	elif direction.y < 0.0:
		step_y = -1

	var t_max_x := INF
	var t_max_y := INF
	var t_delta_x := INF
	var t_delta_y := INF
	if step_x != 0:
		var next_boundary_x := float(current_cell.x + (1 if step_x > 0 else 0)) * cell_size.x
		t_max_x = (next_boundary_x - local_origin.x) / direction.x
		t_delta_x = cell_size.x / absf(direction.x)
	if step_y != 0:
		var next_boundary_y := float(current_cell.y + (1 if step_y > 0 else 0)) * cell_size.y
		t_max_y = (next_boundary_y - local_origin.y) / direction.y
		t_delta_y = cell_size.y / absf(direction.y)

	var min_cell := player_cell - Vector2i(REACH_RADIUS, REACH_RADIUS)
	var max_cell := player_cell + Vector2i(REACH_RADIUS, REACH_RADIUS)
	var max_steps := (REACH_RADIUS * 2 + 2) * 2
	for _i in range(max_steps):
		if current_cell.x < min_cell.x or current_cell.x > max_cell.x \
				or current_cell.y < min_cell.y or current_cell.y > max_cell.y:
			return null
		if _is_wall_cell(current_cell):
			return current_cell
		if t_max_x < t_max_y:
			current_cell.x += step_x
			t_max_x += t_delta_x
		else:
			current_cell.y += step_y
			t_max_y += t_delta_y
	return null


## Starts the hit-flash on `cell` if it's currently a standing wall, without
## registering an actual pickaxe hit. Called when a mining swing starts, so
## the flash reads as immediate feedback instead of lagging behind to when
## the swing animation finishes and damage_wall_cell() applies the hit.
func flash_minable_cell(cell: Vector2i) -> void:
	if _is_wall_cell(cell):
		_flash_cell(cell)


## Registers one pickaxe hit against `cell`. Returns whether the swing
## actually landed on a standing wall cell, erasing it and dropping an item
## once HITS_TO_BREAK is reached.
func damage_wall_cell(cell: Vector2i) -> bool:
	if not _is_wall_cell(cell):
		_wall_hits.erase(cell)
		return false
	var hits: int = _wall_hits.get(cell, 0) + 1
	if hits >= HITS_TO_BREAK:
		_wall_hits.erase(cell)
		var drop_position := to_global(map_to_local(cell))
		var item: Item = dropped_item
		if ore_overlay_layer != null and ore_overlay_layer.is_ore_cell(cell):
			item = ore_overlay_layer.get_ore_type(cell).dropped_item
		_erase_wall_cell(cell)
		# erase_cell() only removes this cell -- it doesn't recompute the
		# autotile shape of the neighbors that used to connect to it, so
		# their artwork would otherwise keep showing the stale connection.
		_refresh_wall_terrain_around(cell)
		_sync_base_tiles()
		if ore_overlay_layer != null:
			ore_overlay_layer.resync()
		call_deferred("_drop_item", drop_position, item)
	else:
		_wall_hits[cell] = hits
	return true


## Erases a wall cell and records it as removed, so both the live-mining path
## and apply_save_data()'s replay share one place that keeps _removed_cells
## in sync with the tile data.
func _erase_wall_cell(cell: Vector2i) -> void:
	erase_cell(cell)
	_removed_cells[cell] = true
	cell_removed.emit(cell)


## Whether `cell` is currently a standing wall -- unlike a bare tile-presence
## check (get_cell_source_id(cell) != -1), this excludes the walkable
## Cave_Wall_Base cap tile that _sync_base_tiles() paints along the strip at
## the foot of every wall, which callers like InteractionController's ground
## targeting need to not mistake for solid wall.
func is_wall_cell(cell: Vector2i) -> bool:
	return _is_wall_cell(cell)

func _is_wall_cell(cell: Vector2i) -> bool:
	var tile_data := get_cell_tile_data(cell)
	return tile_data != null \
		and tile_data.terrain_set == CaveWallBase.TERRAIN_SET \
		and tile_data.terrain == CaveWallBase.WALL_TERRAIN


## Whether `cell` currently holds a Cave_Wall_Base cap tile (the decorative
## strip _sync_base_tiles() paints along the foot of an exposed wall).
func is_base_cell(cell: Vector2i) -> bool:
	return _is_base_cell(cell)

func _is_base_cell(cell: Vector2i) -> bool:
	var tile_data := get_cell_tile_data(cell)
	return tile_data != null \
		and tile_data.terrain_set == CaveWallBase.TERRAIN_SET \
		and tile_data.terrain == CaveWallBase.BASE_TERRAIN


## Paints wall terrain using a precomputed TileSet peering-bit lookup.
## `all_wall_cells` is supplied by generated chunks because their cells do
## not exist on the layer yet. Returns false when the tileset has no usable
## lookup, allowing callers to retain the terrain-connect fallback.
func set_wall_cells_direct(cells: Array[Vector2i], all_wall_cells: Array[Vector2i] = []) -> bool:
	var lookup := _get_wall_tile_lookup()
	if lookup.is_empty() or cells.is_empty():
		return false
	var wall_set := {}
	if all_wall_cells.is_empty():
		for cell in cells:
			if _is_wall_cell(cell):
				wall_set[cell] = true
			for offset in CaveWallBase.PEERING_OFFSETS:
				var neighbor := cell + offset
				if _is_wall_cell(neighbor):
					wall_set[neighbor] = true
	else:
		for wall_cell in all_wall_cells:
			wall_set[wall_cell] = true

	var tile_for_cell := {}
	for cell in cells:
		var mask := _wall_peering_mask(cell, wall_set)
		if not lookup.has(mask):
			return false
		tile_for_cell[cell] = lookup[mask]

	_syncing = true
	for cell in tile_for_cell:
		var tile: Dictionary = tile_for_cell[cell]
		set_cell(cell, tile["source_id"], tile["atlas_coords"], tile["alternative"])
	_syncing = false
	return true


func has_direct_wall_lookup() -> bool:
	return not _get_wall_tile_lookup().is_empty()


func set_base_tiles_direct(base_tiles: Dictionary, sync_existing: bool = true) -> void:
	_syncing = true
	for cell: Vector2i in base_tiles:
		set_cell(cell, TILESET_SOURCE_ID, base_tiles[cell])
	_syncing = false
	if sync_existing:
		_sync_base_tiles()


## Recomputes existing wall cells after a mined cell or seam change without
## invoking the bulk terrain solver. This keeps the gameplay refresh path
## correct while making generated painting cheap.
func refresh_wall_cells_direct(cells: Array[Vector2i]) -> bool:
	return set_wall_cells_direct(cells)


func _get_wall_tile_lookup() -> Dictionary:
	if tile_set == null:
		return {}
	if _wall_lookup_tileset != tile_set:
		_wall_lookup_tileset = tile_set
		_wall_tile_lookup = CaveWallBase.build_terrain_tile_lookup(
			tile_set, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN
		)
	return _wall_tile_lookup


func _wall_peering_mask(cell: Vector2i, wall_set: Dictionary) -> int:
	var mask := 0
	for index in range(CaveWallBase.PEERING_OFFSETS.size()):
		if wall_set.has(cell + CaveWallBase.PEERING_OFFSETS[index]):
			mask |= 1 << index
	return mask


## Starts (or restarts) the white hit-flash on `wall_cell`, and on its
## attached Cave_Wall_Base cell underneath, if one is currently placed there.
## Takes effect the same frame it's called, at full FLASH_PEAK_AMOUNT, rather
## than waiting for the next _process tick to catch up.
func _flash_cell(wall_cell: Vector2i) -> void:
	for cell: Vector2i in _flash_cells:
		_flash_layer.erase_cell(cell)
	_flash_cells.clear()

	_flash_cells[wall_cell] = true
	_flash_layer.set_cell(wall_cell, get_cell_source_id(wall_cell), get_cell_atlas_coords(wall_cell), get_cell_alternative_tile(wall_cell))
	var base_cell := wall_cell + Vector2i.DOWN
	if _is_base_cell(base_cell):
		_flash_cells[base_cell] = true
		_flash_layer.set_cell(base_cell, get_cell_source_id(base_cell), get_cell_atlas_coords(base_cell), get_cell_alternative_tile(base_cell))
	if ore_overlay_layer != null:
		ore_overlay_layer.flash_cell(wall_cell)

	_flash_elapsed = 0.0
	var flash_material: ShaderMaterial = _flash_layer.material
	flash_material.set_shader_parameter("flash_amount", FLASH_PEAK_AMOUNT)
	if ore_overlay_layer != null:
		ore_overlay_layer.set_flash_amount(FLASH_PEAK_AMOUNT)
	set_process(true)


## Re-runs terrain autoconnection on every still-standing wall cell around
## `cell`, so their atlas tile updates to reflect that `cell` is now empty
## (e.g. a tile that used to show a connecting edge toward `cell` switches to
## a plain outer edge instead).
func _refresh_wall_terrain_around(cell: Vector2i) -> void:
	var neighbor_wall_cells: Array[Vector2i] = []
	for offset in NEIGHBOR_OFFSETS:
		var neighbor := cell + offset
		if _is_wall_cell(neighbor):
			neighbor_wall_cells.append(neighbor)
	if neighbor_wall_cells.is_empty():
		return
	if refresh_wall_cells_direct(neighbor_wall_cells):
		return
	# set_cells_terrain_connect() only recomputes a cell's shape when that
	# cell is newly transitioning onto the terrain -- calling it on cells
	# that already have Cave_Wall assigned is a no-op, so the stale shape
	# never gets refreshed. Erasing them first forces a genuine transition,
	# same as re-painting them by hand would.
	for neighbor in neighbor_wall_cells:
		erase_cell(neighbor)
	set_cells_terrain_connect(neighbor_wall_cells, CaveWallBase.TERRAIN_SET, CaveWallBase.WALL_TERRAIN)


func _drop_item(drop_position: Vector2, item: Item) -> void:
	await get_tree().create_timer(ITEM_DROP_DELAY).timeout
	var entity_root: Node2D = get_tree().current_scene.get_node("%EntityRoot")
	var item_instance := GroundItem.spawn(entity_root, item, 1, drop_position)
	item_instance.z_index = 2


func _on_changed() -> void:
	if _syncing:
		return
	_sync_base_tiles()


func _sync_base_tiles() -> void:
	var wall_cells := {}
	var existing_base_cells := {}
	for cell in get_used_cells():
		var tile_data := get_cell_tile_data(cell)
		if tile_data == null or tile_data.terrain_set != CaveWallBase.TERRAIN_SET:
			continue
		if tile_data.terrain == CaveWallBase.WALL_TERRAIN:
			wall_cells[cell] = true
		elif tile_data.terrain == CaveWallBase.BASE_TERRAIN:
			existing_base_cells[cell] = true

	var desired_base_tiles := CaveWallBase.compute_base_tiles(wall_cells)

	var stale_cells: Array[Vector2i] = []
	for cell in existing_base_cells:
		if not desired_base_tiles.has(cell):
			stale_cells.append(cell)

	var changed_anything := not stale_cells.is_empty()
	if not changed_anything:
		for cell in desired_base_tiles:
			if get_cell_atlas_coords(cell) != desired_base_tiles[cell]:
				changed_anything = true
				break
	if not changed_anything:
		return

	_syncing = true
	for cell in stale_cells:
		erase_cell(cell)
	for cell in desired_base_tiles:
		var atlas_coords: Vector2i = desired_base_tiles[cell]
		set_cell(cell, TILESET_SOURCE_ID, atlas_coords)
	_syncing = false
