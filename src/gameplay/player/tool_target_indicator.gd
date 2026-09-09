extends Node2D
class_name ToolTargetIndicator
## Shows HoveredTileSprite over whatever the equipped tool would currently
## damage at the mouse-resolved target (see InteractionController) -- a
## standing Cave_Wall cell for a Pickaxe, or a placed object with a HitBox the
## equipped tool matches (the same match PlayerStateMining/
## PlayerStateWoodcutting's generic HitArea/HitBox swing already relies on) --
## so the player can see what they're about to destroy before swinging. Hidden
## whenever neither applies. Reads InteractionController's state rather than
## recomputing it: Player._process() (a parent, always processed before this
## child) already calls interaction_controller.update() earlier this frame.

@onready var player: Player = get_parent()
@onready var sprite: Sprite2D = $HoveredTileSprite
## One independent corner-bracket mark per corner (top-left, top-right,
## bottom-left, bottom-right), used instead of sprite for a bigger-than-1x1
## target (see _show_corners_for_footprint) -- sprite's own texture is 4 such
## marks pre-assembled into one image sized for exactly one tile, so
## uniformly scaling it up for a bigger object would fatten each mark's
## stroke along with the distance between them. Repositioning 4 unscaled
## copies instead only changes that distance, keeping every mark pixel-crisp
## at any footprint size.
@onready var corner_sprites: Array[Sprite2D] = [$CornerTL, $CornerTR, $CornerBL, $CornerBR]

## Sign of each corner_sprites entry's offset from the target's footprint
## center, in the same order.
const CORNER_SIGNS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

const TILE_SIZE_PX: float = 16.0
## How far beyond the footprint's own edge each corner mark sits -- matches
## the fixed visual overhang the original single-tile sprite already had
## (its corners sit 16px from a 16px tile's center, 8px past that tile's own
## edge), so a 1x1 target still looks identical to before.
const CORNER_OVERHANG_PX: float = 8.0

## sprite's own scene-authored modulate alpha -- shown for a selectable wall
## target that a swing right now wouldn't actually reach (occluded by a
## nearer wall) and for object targets, which have no occlusion concept.
const DEFAULT_ALPHA: float = 0.3137255
## Shown instead when the hovered wall target is actually mineable right
## now, so the highlight reads as a clear "yes, swing here" signal.
const MINEABLE_ALPHA: float = 1.0


func _process(_delta: float) -> void:
	sprite.visible = false
	_hide_corners()
	var ic: InteractionController = player.interaction_controller

	if player.current_tool_type == Item.ToolTypes.Pickaxe and ic.has_wall_target():
		global_position = ic.get_target_world_position()
		sprite.visible = true
		sprite.modulate.a = MINEABLE_ALPHA if ic.is_hovered_target_mineable() else DEFAULT_ALPHA
		return
	if player.current_tool_type == Item.ToolTypes.Shovel and ic.has_ground_target():
		global_position = ic.get_target_world_position()
		sprite.visible = true
		sprite.modulate.a = MINEABLE_ALPHA if ic.is_hovered_ground_target_diggable() else DEFAULT_ALPHA
		return
	if player.current_tool_type == Item.ToolTypes.Wrench:
		_update_for_wrench_target()
		return
	if player.current_hotbar_item != null and player.current_hotbar_item.item_type == Item.ItemType.UPGRADE:
		_update_for_upgrade_target(player.current_hotbar_item)
		return
	if ic.resolved_object != null and ic.has_object_target_for(player.current_tool_type):
		# Unlike a wall target, an object target has no occlusion concept --
		# has_object_target_for() already confirmed the equipped tool matches,
		# so a swing here would always land. Bright, same as a mineable wall.
		# Goes through the same _show_for_target() the Wrench/Upgrade branches
		# use below, rather than a bare 1-tile sprite, so a bigger-than-1x1
		# target (e.g. BlastFurnace) shows its real footprint here too instead
		# of a small, wrongly-placed box.
		_show_for_target(ic.resolved_object, MINEABLE_ALPHA)


## The Wrench targets whatever AutomationUtils.find_slot_target finds under
## the mouse -- a different resolution path than InteractionController's
## resolved_object (which only tracks tool-hit/HitBox targets, never slot
## objects) -- so it needs its own lookup here rather than reading ic's state.
## Dims the same way an out-of-reach wall does when the target exists but the
## Wrench couldn't actually click it from here.
func _update_for_wrench_target() -> void:
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		return
	var target := AutomationUtils.find_slot_target(objects_layer, get_global_mouse_position())
	if target == null:
		return
	var player_cell := objects_layer.local_to_map(objects_layer.to_local(player.global_position))
	var alpha := MINEABLE_ALPHA if AutomationUtils.is_object_within_reach(player_cell, objects_layer, target) else DEFAULT_ALPHA
	_show_for_target(target, alpha)

## An Upgrade item targets the same object AutomationUtils.find_slot_target
## resolves for the Wrench, but only lights up when that object actually has
## a still-disabled port of the held item's upgrade_type left to activate --
## the same check UpgradeController itself makes before a click does
## anything (see AutomationUtils.find_upgradeable_component). Dims the same
## way the Wrench branch does when the target exists but is out of reach.
func _update_for_upgrade_target(item: Item) -> void:
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		return
	var target := AutomationUtils.find_slot_target(objects_layer, get_global_mouse_position())
	if target == null or AutomationUtils.find_upgradeable_component(target, item.upgrade_type) == null:
		return
	var player_cell := objects_layer.local_to_map(objects_layer.to_local(player.global_position))
	var alpha := MINEABLE_ALPHA if AutomationUtils.is_object_within_reach(player_cell, objects_layer, target) else DEFAULT_ALPHA
	_show_for_target(target, alpha)

## A 1x1 target (every existing machine) keeps using the plain sprite,
## positioned by the target's own visual sprite offset exactly as before. A
## bigger target (e.g. BlastFurnace) switches to the 4 independent corner
## marks instead, positioned by the grid footprint itself rather than the
## visual sprite offset, since what's being highlighted here is the tile
## area a click would resolve against, not the (possibly off-grid) art.
func _show_for_target(target: Node2D, alpha: float) -> void:
	var footprint := AutomationUtils.get_object_footprint(target)
	if footprint == Vector2i.ONE:
		global_position = target.global_position + _get_target_sprite_offset(target)
		sprite.visible = true
		sprite.modulate.a = alpha
	else:
		global_position = target.global_position + Vector2(footprint.x - 1, footprint.y - 1) * TILE_SIZE_PX * 0.5
		_show_corners_for_footprint(footprint, alpha)

func _show_corners_for_footprint(footprint: Vector2i, alpha: float) -> void:
	var half_extent := Vector2(footprint.x, footprint.y) * TILE_SIZE_PX * 0.5
	for i in corner_sprites.size():
		var corner := corner_sprites[i]
		corner.position = CORNER_SIGNS[i] * (half_extent + Vector2(CORNER_OVERHANG_PX, CORNER_OVERHANG_PX))
		corner.modulate.a = alpha
		corner.visible = true

func _hide_corners() -> void:
	for corner in corner_sprites:
		corner.visible = false

## Mirrors PlacementController._get_ghost_offset -- target's own sprite may
## be drawn offset from its node origin (e.g. furnace/chest sprites sit above
## the tile's base), so the highlighter needs the same offset applied or it
## won't line up with what's actually rendered.
func _get_target_sprite_offset(target: Node2D) -> Vector2:
	for child_name in PlacementController.SPRITE_CHILD_NAMES:
		var target_sprite := target.get_node_or_null(NodePath(child_name)) as Node2D
		if target_sprite:
			return target_sprite.position + (target_sprite.get("offset") as Vector2)
	return Vector2.ZERO
