class_name AutomationUtils
extends RefCounted
## Shared helpers for tile-adjacency automation (ItemOutputSlotComponent
## looking up its neighbor, WrenchController/WrenchSlotIndicator/
## UpgradeController resolving the object under the mouse). Mirrors
## SaveSerializationUtils's role as a static helper library for a
## cross-cutting concern.

## True for any of the 24 tiles in the 5x5 area surrounding player_cell,
## excluding player_cell itself. Shared by PlacementController,
## WrenchController, and InteractionController, which all pick a target tile
## the same way.
static func is_adjacent(player_cell: Vector2i, target_cell: Vector2i) -> bool:
	var delta := target_cell - player_cell
	return delta != Vector2i.ZERO and absi(delta.x) <= 2 and absi(delta.y) <= 2

## Same 5x5 square as is_adjacent(), but also true when target_cell is the
## player's own cell. Needed by InteractionController's wall resolution (a
## standing wall's collision shape can be inset from its tile's edge -- e.g. a
## taller top face purely for visual overhang -- which lets the player's
## tracked cell land on the wall cell they just walked into and are now flush
## against) and by WrenchController/WrenchSlotIndicator/UpgradeController,
## since the player should be able to configure or upgrade an object's slots
## while standing on it, same as the Shovel. PlacementController is the one
## place is_adjacent()'s exclusion of the player's own cell is still correct
## for -- you can't place a new object on your own tile.
static func is_within_reach(player_cell: Vector2i, target_cell: Vector2i) -> bool:
	return target_cell == player_cell or is_adjacent(player_cell, target_cell)

## Same reach rule as is_within_reach(), but true if the player is in reach of
## ANY cell object's footprint covers, not just its anchor cell -- needed for
## a multi-tile object like BlastFurnace, where a player standing next to one
## of its far edges is in reach of that edge even though it's 2 cells from the
## object's own anchor. For a 1x1 object this is identical to checking the
## anchor cell alone. Shared by WrenchController, UpgradeController, and
## ToolTargetIndicator, which all resolve a target object and then need to know if
## the player can actually act on it from here.
static func is_object_within_reach(player_cell: Vector2i, objects_layer: TileMapLayer, object: Node2D) -> bool:
	var anchor := objects_layer.local_to_map(objects_layer.to_local(object.global_position))
	for cell in get_footprint_cells(anchor, get_object_footprint(object)):
		if is_within_reach(player_cell, cell):
			return true
	return false

static func get_objects_layer(from_node: Node) -> TileMapLayer:
	var main_game := from_node.get_tree().current_scene as MainGame
	var level := main_game.get_current_level() if main_game else null
	return level.get_objects_layer() if level else null

## How many tiles object occupies, anchored at its own cell -- reads the
## scene-authored grid_size property (see InteractableContainer.grid_size)
## when present, else Vector2i.ONE. Variant-safe: works uniformly for objects
## that declare a footprint and ones that don't (belts, ore nodes), with zero
## behavior change for anything that's always been 1x1.
static func get_object_footprint(object: Node) -> Vector2i:
	var size: Variant = object.get("grid_size")
	return size if size is Vector2i else Vector2i.ONE

## Every cell a footprint of size anchored at anchor_cell covers. Shared
## primitive behind placement validation, reach checks, and belt
## notification -- a 1x1 size always yields exactly [anchor_cell], so nothing
## downstream needs to special-case the common case.
static func get_footprint_cells(anchor_cell: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in maxi(size.x, 1):
		for dy in maxi(size.y, 1):
			cells.append(anchor_cell + Vector2i(dx, dy))
	return cells

## O(children) scan -- no spatial index exists anywhere in this codebase yet;
## acceptable at current scale. Tests whether cell falls anywhere within the
## child's own footprint rect (see get_object_footprint), not just its exact
## anchor cell, so a multi-tile object like BlastFurnace is found correctly
## from any of the cells it occupies -- for every 1x1 object this is
## identical to the old exact-equality check.
static func find_object_at_cell(objects_layer: TileMapLayer, cell: Vector2i) -> Node2D:
	for child in objects_layer.get_children():
		if child is Node2D:
			var anchor := objects_layer.local_to_map(child.position)
			var size := get_object_footprint(child)
			var rect := Rect2i(anchor, Vector2i(maxi(size.x, 1), maxi(size.y, 1)))
			if rect.has_point(cell):
				return child
	return null

## True if cell has a design-time TileSetScenesCollectionSource placement or a
## runtime-placed object as a child of objects_layer. Shared by
## PlacementController (placing new objects) and OreNodeGenerator (scattering
## ore nodes), which both need to know a cell is free before occupying it.
static func is_cell_occupied(objects_layer: TileMapLayer, cell: Vector2i) -> bool:
	return objects_layer.get_cell_source_id(cell) != -1 or find_object_at_cell(objects_layer, cell) != null

## Finds whichever nearby object's SlotLocationsComponent ClickArea actually
## contains global_point (e.g. the mouse), used by WrenchController/
## WrenchSlotIndicator/UpgradeController instead of a raw tile-grid cell
## lookup -- a ClickArea can be dragged off its own cell for perspective, so
## the object it belongs to isn't reliably "whatever's registered at this
## exact cell" anymore. Scans the 3x3 neighborhood around the point's nominal
## cell, which is enough slack for a dragged ClickArea to still be found
## while keeping the search bounded (no spatial index exists anywhere in this
## codebase yet).
static func find_slot_target(objects_layer: TileMapLayer, global_point: Vector2) -> Node2D:
	var nominal_cell := objects_layer.local_to_map(objects_layer.to_local(global_point))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var candidate := find_object_at_cell(objects_layer, nominal_cell + Vector2i(dx, dy))
			if candidate == null:
				continue
			var slot_locations: SlotLocationsComponent = candidate.get_node_or_null("SlotLocationsComponent")
			if slot_locations and slot_locations.contains_point(global_point):
				return candidate
	return null

static func get_slot_components(object: Node) -> Array[ItemSlotComponent]:
	var result: Array[ItemSlotComponent] = []
	if object == null:
		return result
	for child in object.get_children():
		if child is ItemSlotComponent:
			result.append(child)
	return result

## Finds a not-yet-enabled slot component on object whose class matches
## upgrade_type: Input -> a plain ItemInputSlotComponent (a
## SolidFuelInputSlotComponent doesn't count, even though it extends
## ItemInputSlotComponent -- a regular Input Upgrade can't activate a fuel
## port), Output -> ItemOutputSlotComponent, SolidFuelInput ->
## SolidFuelInputSlotComponent specifically. Null if object has no port of
## that kind left to activate. Its current facing doesn't matter to callers
## that go on to place it: UpgradeController immediately overwrites it with
## the clicked edge. When an object has more than one disabled port of the
## same class, this always returns whichever comes first in child order; each
## successive upgrade click then finds the next one, since the previous pick
## is no longer disabled. Shared by UpgradeController (deciding what a click
## enables) and ToolTargetIndicator (deciding whether to highlight a hovered
## object while an Upgrade item is held).
static func find_upgradeable_component(object: Node, upgrade_type: Item.UpgradeTypes) -> ItemSlotComponent:
	for component in get_slot_components(object):
		if component.enabled:
			continue
		if upgrade_type == Item.UpgradeTypes.Input and component is ItemInputSlotComponent and not component is SolidFuelInputSlotComponent:
			return component
		if upgrade_type == Item.UpgradeTypes.Output and component is ItemOutputSlotComponent:
			return component
		if upgrade_type == Item.UpgradeTypes.SolidFuelInput and component is SolidFuelInputSlotComponent:
			return component
	return null

## Local-space position (relative to the object's own anchor/origin node) of
## the specific cell a (facing, sub_position) pair refers to, for an object
## with the given footprint -- sub_position picks which column ("left"/
## "right") for an up/down facing, or which row ("up"/"down") for a left/
## right facing, when the footprint is more than 1 tile in that axis; ignored
## for a 1x1 footprint, where there's only one cell per edge anyway. Shared by
## WrenchController (re-facing AND repositioning an already-enabled port) and
## UpgradeController (placing a newly-enabled one), so a multi-tile object's
## ports can move freely between all of its edge cells, not just the one its
## scene happened to author.
static func get_edge_local_position(footprint: Vector2i, facing: String, sub_position: String) -> Vector2:
	var col := 0
	var row := 0
	match facing:
		"up":
			col = 0 if sub_position == "left" else footprint.x - 1
		"down":
			row = footprint.y - 1
			col = 0 if sub_position == "left" else footprint.x - 1
		"left":
			row = 0 if sub_position == "up" else footprint.y - 1
		"right":
			col = footprint.x - 1
			row = 0 if sub_position == "up" else footprint.y - 1
	return Vector2(col, row) * BeltComponent.TILE_SIZE_PX

## Every (facing, sub_position) edge zone a footprint exposes, in clockwise
## perimeter order starting at the top-left corner -- exactly the 4 plain
## facings (sub_position "") for a 1x1 footprint, in the same up/right/down/
## left order ItemSlotComponent.FACING_ORDER already cycled through, or 8
## zones for a footprint 2+ tiles wide/tall in both axes. Shared by
## WrenchController's re-facing cycle (skip whichever zones are already
## occupied, land on the next free one) and UpgradeController (rejecting a
## click on an already-occupied zone).
static func get_edge_zones(footprint: Vector2i) -> Array[Dictionary]:
	# Built with if/else rather than a ternary -- GDScript's "A if cond else
	# B" over two array literals evaluates to a plain, untyped Array at
	# runtime regardless of the declared Array[String] target, which throws
	# ("Trying to assign an array of type Array to a variable of type
	# Array[String]") the moment footprint.x/y is actually > 1.
	var x_subs: Array[String] = []
	if footprint.x > 1:
		x_subs = ["left", "right"]
	else:
		x_subs = [""]
	var y_subs: Array[String] = []
	if footprint.y > 1:
		y_subs = ["up", "down"]
	else:
		y_subs = [""]
	var zones: Array[Dictionary] = []
	for s in x_subs:
		zones.append({"facing": "up", "sub_position": s})
	for s in y_subs:
		zones.append({"facing": "right", "sub_position": s})
	var x_subs_rev := x_subs.duplicate()
	x_subs_rev.reverse()
	for s in x_subs_rev:
		zones.append({"facing": "down", "sub_position": s})
	var y_subs_rev := y_subs.duplicate()
	y_subs_rev.reverse()
	for s in y_subs_rev:
		zones.append({"facing": "left", "sub_position": s})
	return zones

## Canonical string key for an edge zone -- "up" for a 1x1 object's plain
## facing, "up_left" for a compound one -- used to compare/deduplicate zones
## without repeating the same "is sub_position empty" branch everywhere.
static func edge_zone_key(facing: String, sub_position: String) -> String:
	return facing if sub_position == "" else "%s_%s" % [facing, sub_position]

## Notifies BeltManager once per cell object's footprint covers, instead of
## just its anchor cell -- a belt sitting against any of a multi-tile
## object's edges needs to be re-checked, not only one sitting against the
## anchor cell specifically. For a 1x1 object this is exactly the one
## notify_object_placed() call every call site already made before this
## helper existed. Shared by PlacementController (after placing), and
## WrenchController/UpgradeController/apply_slot_facings (after a live facing
## edit), which all need to re-sync neighboring belts the same way.
static func notify_belt_manager_for_object(objects_layer: TileMapLayer, object: Node) -> void:
	var anchor := objects_layer.local_to_map(objects_layer.to_local(object.global_position))
	for cell in get_footprint_cells(anchor, get_object_footprint(object)):
		BeltManager.notify_object_placed(objects_layer, cell)

## Save/load: facing and position both need persisting now that a port on a
## multi-tile object can move between edge cells sharing the same facing (see
## get_edge_local_position) -- position alone wouldn't round-trip a 1x1
## object's port correctly (it never moves, so it's always just its
## scene-authored default, harmless to re-save), and facing alone wouldn't
## round-trip which of a multi-tile object's cells a port was moved to.
## enabled/transfer_interval/transfer_amount/applied_upgrade_item_id also need
## persisting -- they're exactly the fields UpgradeController sets when the
## player right-clicks an Input/Output/Solid Fuel Input Upgrade onto a port
## (see upgrade_controller.gd), so without them a reload would silently reset
## every placed upgrade back to its scene-authored disabled default. FIXED_SLOT/
## ANY_SLOT contents already persist through the owner's own Inventory
## serialization, and STANDALONE mode isn't used by any saveable object yet.
static func get_slot_facings(owner: Node) -> Dictionary:
	var facings := {}
	for component in get_slot_components(owner):
		facings[component.name] = {
			"facing": component.facing,
			"position": {"x": component.position.x, "y": component.position.y},
			"enabled": component.enabled,
			"transfer_interval": component.transfer_interval,
			"transfer_amount": component.transfer_amount,
			"applied_upgrade_item_id": component.applied_upgrade_item_id,
		}
	return facings

## A neighboring belt's downstream_slot is cached at placement/registration
## time and never re-checked on its own (see BeltManager's module comment) --
## objects like chests respawn at their scene's default slot facing before
## save data is applied (see SaveManager._apply_placed_objects), so a belt
## that already linked against that stale default keeps the wrong link
## forever unless something re-notifies BeltManager after the real facing
## is restored here, mirroring what WrenchController does for a live edit.
## Accepts old save data (a plain facing string per component, from before
## position was tracked here too) as well as the current {facing, position}
## shape, so an existing save still loads correctly -- just without its
## multi-tile ports' positions, which only matters for a save made after this
## feature existed anyway. Also tolerates a save written while position was
## briefly (incorrectly) serialized as a raw Vector2 -- JSON has no such type,
## so it round-tripped as a plain string like "(0, 0)" and crashed on load
## when assigned straight to component.position; that malformed value is
## simply skipped now instead of applied.
static func apply_slot_facings(owner: Node, data: Dictionary) -> void:
	var changed := false
	for component in get_slot_components(owner):
		var entry: Variant = data.get(component.name)
		if entry == null:
			continue
		if entry is Dictionary:
			component.facing = entry.get("facing", component.facing)
			var position_data: Variant = entry.get("position")
			if position_data is Dictionary:
				component.position = Vector2(position_data.get("x", component.position.x), position_data.get("y", component.position.y))
			component.enabled = entry.get("enabled", component.enabled)
			component.transfer_interval = entry.get("transfer_interval", component.transfer_interval)
			component.transfer_amount = entry.get("transfer_amount", component.transfer_amount)
			component.applied_upgrade_item_id = entry.get("applied_upgrade_item_id", component.applied_upgrade_item_id)
		else:
			component.facing = entry
		changed = true
	if not changed:
		return
	var objects_layer := get_objects_layer(owner)
	if objects_layer == null:
		return
	notify_belt_manager_for_object(objects_layer, owner)
