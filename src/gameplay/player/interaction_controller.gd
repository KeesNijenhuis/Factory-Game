extends Node2D
class_name InteractionController
## Resolves whatever tile/object the mouse currently points at, within the 24
## tiles of the 5x5 area surrounding the player (same reach as
## PlacementController's ghost), for the destroy-tool FSM states (Mining/
## Woodcutting/Digging/Tilling) to act on instead of the old fixed
## facing-marker. update() must be called once per frame from
## Player._process() -- BEFORE FSM._process()/any state's enter_state() reads
## this controller's state this frame -- rather than running its own
## _process(), since sibling _process() ordering between this node and FSM
## isn't otherwise guaranteed. Sword attacks and containers/ladders are
## untouched by this system entirely.
##
## Also draws a debug outline of the 5x5 reach around the player at all
## times, to make the actual reach area visible during testing.
const REACH_RADIUS: int = 2

@onready var player: Player = get_parent()

var player_cell: Vector2i = Vector2i.ZERO
var target_cell: Vector2i = Vector2i.ZERO
## True within the 5x5 reach square, INCLUDING the player's own cell (see
## AutomationUtils.is_within_reach) -- a standing wall's collision can be
## inset from its tile's top edge for visual overhang, letting the player's
## tracked cell land on the wall cell they're flush against.
var is_in_reach: bool = false
## The resolved standing wall cell (Vector2i), or null if the mouse isn't
## over a minable wall/cap tile right now.
var resolved_wall_cell: Variant = null
## Whatever placed object (if any) occupies target_cell, or null.
var resolved_object: Node2D = null
## target_cell, if it's a diggable ground cell (no wall, no placed object,
## not already dug) right now -- otherwise null.
var resolved_ground_cell: Variant = null
## Whatever object AutomationUtils.find_slot_target resolves under the mouse
## right now, or null -- computed once per frame here so WrenchSlotIndicator
## and ToolTargetIndicator (previously each calling find_slot_target
## themselves, every frame, while the Wrench/an Upgrade was equipped) can
## both just read this instead of resolving the same target twice.
var resolved_slot_target: Node2D = null

func update() -> void:
	player_cell = Vector2i.ZERO
	target_cell = Vector2i.ZERO
	is_in_reach = false
	resolved_wall_cell = null
	resolved_object = null
	resolved_ground_cell = null
	resolved_slot_target = null
	queue_redraw()

	var level := _get_current_level()
	var objects_layer: TileMapLayer = level.get_objects_layer() if level else null
	if objects_layer == null:
		return

	player_cell = objects_layer.local_to_map(objects_layer.to_local(player.global_position))
	target_cell = objects_layer.local_to_map(objects_layer.to_local(player.get_global_mouse_position()))
	is_in_reach = AutomationUtils.is_within_reach(player_cell, target_cell)
	if player.current_tool_type == Item.ToolTypes.Wrench or (player.current_hotbar_item != null and player.current_hotbar_item.item_type == Item.ItemType.UPGRADE):
		resolved_slot_target = AutomationUtils.find_slot_target(objects_layer, player.get_global_mouse_position())
	if not is_in_reach:
		return

	var walls_layer := level.get_walls_layer() as CaveWallsLayer
	if walls_layer:
		resolved_wall_cell = walls_layer.resolve_mineable_cell(target_cell)
		# resolve_mineable_cell() can shift the target by one cell (a hovered
		# cap tile resolves to the wall standing above it), which can land
		# just outside the 5x5 reach even though the raw hovered cell was
		# inside it -- re-check reach against the resolved cell, not just the
		# original mouse-hovered one.
		if resolved_wall_cell != null and not AutomationUtils.is_within_reach(player_cell, resolved_wall_cell):
			resolved_wall_cell = null
	resolved_object = AutomationUtils.find_object_at_cell(objects_layer, target_cell)

	var ground_layer := level.get_ground_layer() as CaveGroundLayer
	if ground_layer and resolved_object == null \
			and (walls_layer == null or not (walls_layer.is_wall_cell(target_cell) or walls_layer.is_base_cell(target_cell))) \
			and ground_layer.is_diggable(target_cell):
		resolved_ground_cell = target_cell

func has_wall_target() -> bool:
	return resolved_wall_cell != null

func has_ground_target() -> bool:
	return resolved_ground_cell != null

## Whether resolved_ground_cell is actually diggable right now -- as with
## resolved_wall_cell, selectability (is there a candidate here at all) and
## validity (would a swing actually land) are deliberately separate checks,
## so the hover highlight can still show a dim "selected but invalid" state
## instead of hiding outright. The tile the player is standing on is always
## selectable (any clear ground cell is) but never a valid dig target.
func is_hovered_ground_target_diggable() -> bool:
	return resolved_ground_cell != null and resolved_ground_cell != player_cell

## Whether `cell` is actually reachable by the ray-fan cast from
## MarkerLineOfSight for the given facing's quadrant -- selectability (is
## there a candidate here at all, see resolved_wall_cell above) and
## mineability (can a ray actually reach it, unblocked by a nearer wall) are
## deliberately separate checks. Called once a mining swing actually starts,
## after facing has been snapped toward the target, not on every hover frame.
func is_mineable(cell: Vector2i, facing: String) -> bool:
	var level := _get_current_level()
	var walls_layer := level.get_walls_layer() as CaveWallsLayer if level else null
	if walls_layer == null:
		return false
	return walls_layer.is_mineable(cell, player_cell, facing, player.marker_line_of_sight.global_position)

## Whether resolved_object has some descendant HitBox that tool_type can
## damage. Deliberately doesn't require a child literally named
## "DestructibleComponent" (unlike the old ToolTargetIndicator check) -- any
## HitBox-owning object (e.g. ObjectResource trees/ore, which own their
## HitBox directly) qualifies, matching what HitArea's own physics query
## already damages today.
func has_object_target_for(tool_type: Item.ToolTypes) -> bool:
	return _find_matching_hit_box(tool_type) != null

func _find_matching_hit_box(tool_type: Item.ToolTypes) -> HitBox:
	if resolved_object == null:
		return null
	for hit_box in resolved_object.find_children("*", "HitBox", true, false):
		if (hit_box as HitBox).tool_type == tool_type:
			return hit_box
	return null

## World position of whatever actually resolved -- for the Pickaxe, the
## standing wall cell takes priority over the raw mouse cell (e.g. the mouse
## may be over a decorative cap tile one cell short of the wall it fronts).
## Gated to the Pickaxe specifically since resolved_wall_cell resolves
## regardless of which tool is equipped, but only the Pickaxe actually acts on
## a wall cell -- an equipped Shovel/Axe/Hoe should stay positioned on the
## raw hovered cell even while the mouse is over a wall's cap tile. Falls back
## to the old facing marker when the mouse isn't over an adjacent tile at all,
## so the ungated Digging/Tilling states still have somewhere sane to put
## their tool if the mouse happens to be out of range.
func get_target_world_position() -> Vector2:
	var level := _get_current_level()
	if not is_in_reach or level == null:
		var marker: Marker2D = player.attack_positions.get(player.last_direction)
		return marker.global_position if marker else player.global_position
	if resolved_wall_cell != null and player.current_tool_type == Item.ToolTypes.Pickaxe:
		var walls_layer := level.get_walls_layer()
		return walls_layer.to_global(walls_layer.map_to_local(resolved_wall_cell))
	var objects_layer := level.get_objects_layer()
	return objects_layer.to_global(objects_layer.map_to_local(target_cell))

## Snaps the player's facing to point toward target_cell. A target exactly
## one column over and one row up/down (e.g. a wall cell reached directly,
## with no Cave_Wall_Base cap tile to route the click through the same row)
## is a perfect diagonal -- unlike Player.vector_to_direction's general
## tie-break (which favors vertical, for movement input), facing here favors
## horizontal on that tie, since it's still reached by swinging sideways.
func snap_player_facing() -> void:
	if not is_in_reach:
		return
	var delta: Vector2i = target_cell - player_cell
	if delta == Vector2i.ZERO:
		# target_cell coincides with the player's own cell -- a wall's
		# collision can be inset from its tile's top edge, letting the
		# player's tracked cell land on the wall they're flush against.
		# There's no direction to derive from a zero delta, so keep
		# whatever facing got them here (already correct, since that's
		# the direction they walked in to end up touching it).
		return
	player.last_direction = _facing_from_delta(delta)

static func _facing_from_delta(delta: Vector2i) -> String:
	if delta.x != 0 and absi(delta.x) >= absi(delta.y):
		return "right" if delta.x > 0 else "left"
	return "down" if delta.y > 0 else "up"

## Turns the player to face resolved_wall_cell and reports whether it's
## actually mineable from that facing -- called once, when a mining swing is
## about to start. Facing updates either way: the player turns toward
## whatever they tried to mine even if a nearer wall blocks the swing, so a
## denied swing still gives some feedback. Returns false (no facing change)
## if there's no wall target at all.
func try_mine() -> bool:
	if resolved_wall_cell == null:
		return false
	snap_player_facing()
	return is_mineable(resolved_wall_cell, player.last_direction)

## Non-mutating preview of try_mine()'s result, for the hover highlight to
## show whether mining right now would actually succeed -- without turning
## the player just from hovering (see snap_player_facing's callers).
func is_hovered_target_mineable() -> bool:
	if resolved_wall_cell == null:
		return false
	var delta: Vector2i = target_cell - player_cell
	var facing := player.last_direction if delta == Vector2i.ZERO else _facing_from_delta(delta)
	return is_mineable(resolved_wall_cell, facing)

func _get_current_level() -> BaseLevel:
	var main_game := get_tree().current_scene as MainGame
	return main_game.get_current_level() if main_game else null

## Debug-only: outlines the 5x5 reach area around the player's current cell
## and draws the active mining quadrant's ray fan -- toggled from the F2
## debug menu, so reach/occlusion are easy to see while testing.
func _draw() -> void:
	if not DebugSettings.show_mining_debug:
		return
	var level := _get_current_level()
	var objects_layer := level.get_objects_layer() if level else null
	if objects_layer == null:
		return
	var half_tile := Vector2(objects_layer.tile_set.tile_size) * 0.5
	var top_left := objects_layer.to_global(objects_layer.map_to_local(player_cell - Vector2i(REACH_RADIUS, REACH_RADIUS))) - half_tile
	var bottom_right := objects_layer.to_global(objects_layer.map_to_local(player_cell + Vector2i(REACH_RADIUS, REACH_RADIUS))) + half_tile
	var local_top_left := to_local(top_left)
	var local_bottom_right := to_local(bottom_right)
	draw_rect(Rect2(local_top_left, local_bottom_right - local_top_left), Color(1.0, 1.0, 0.0, 0.7), false, 1.0)

	var walls_layer := level.get_walls_layer() as CaveWallsLayer
	if walls_layer == null:
		return
	_draw_ray_fan(walls_layer, player.last_direction)

func _draw_ray_fan(walls_layer: CaveWallsLayer, facing: String) -> void:
	var origin_global: Vector2 = player.marker_line_of_sight.global_position
	var result: Dictionary = walls_layer.find_mineable_cells_with_ray_ends(player_cell, facing, origin_global)
	var local_origin := to_local(origin_global)
	for ray_end_global in result.ray_ends:
		draw_line(local_origin, to_local(ray_end_global), Color(1.0, 0.6, 0.1, 0.6), 1.0)
