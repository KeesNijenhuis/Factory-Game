class_name HitArea
extends Area2D


@export var needed_tool: Item.ToolTypes = Item.ToolTypes.None
@export var hit_damage: int = 1

## Applies damage to the single frontmost overlapping HitBox that matches this
## tool (see _pick_frontmost_hit_box()). Called once per swing, at the end of
## the tool/attack animation, rather than on overlap-enter, so holding the
## interact button damages the target once per animation loop. Returns
## whether the hit HitBox belongs to an object with a DurabilityComponent, so
## callers know whether the swing should wear down the tool.
func deal_damage() -> bool:
	var hit_box := _pick_frontmost_hit_box()
	if hit_box == null:
		return false
	hit_box.take_hit(hit_damage)
	return hit_box.has_durability_component()

## Tells the single frontmost matching HitBox that a swing has started, so it
## can play its hit reaction immediately instead of waiting for deal_damage()
## at swing end.
func telegraph_hit() -> void:
	var hit_box := _pick_frontmost_hit_box()
	if hit_box:
		hit_box.telegraph_hit()

## Tells the single frontmost matching HitBox that the swing has reached its
## impact frame. Called separately from telegraph_hit() (and later, once per
## swing) by states that track their animation's own impact frame, e.g.
## PlayerStateMining alongside its wall hit-flash.
func flash_hit() -> void:
	var hit_box := _pick_frontmost_hit_box()
	if hit_box:
		hit_box.flash_hit()

## Picks whichever matching HitBox belongs to the object actually rendered on
## top, so a swing only ever affects the one object the player can see under
## their cursor -- e.g. two ore nodes accidentally occupying the same spot
## previously both flashed/shook from one hit, since the physics query below
## returns every overlapping HitBox with no notion of which one is in front.
## Mirrors the same y-sort convention CaveWallsLayer's flash layer follows
## (see its _ready()): a higher z_index always wins, and among ties the
## greater global y (further "south", drawn later/on top) wins.
func _pick_frontmost_hit_box() -> HitBox:
	var hit_boxes := get_matching_hit_boxes()
	if hit_boxes.is_empty():
		return null
	var frontmost := hit_boxes[0]
	for i in range(1, hit_boxes.size()):
		if _is_more_frontmost(hit_boxes[i], frontmost):
			frontmost = hit_boxes[i]
	return frontmost

static func _is_more_frontmost(candidate: HitBox, current: HitBox) -> bool:
	var candidate_owner := candidate.get_parent() as CanvasItem
	var current_owner := current.get_parent() as CanvasItem
	var candidate_z := candidate_owner.z_index if candidate_owner else 0
	var current_z := current_owner.z_index if current_owner else 0
	if candidate_z != current_z:
		return candidate_z > current_z
	return candidate.global_position.y > current.global_position.y

## Uses a fresh physics query instead of get_overlapping_areas(), since that cached
## list can still be empty right after monitoring turns on (no physics step yet to
## populate it) or stale after the shape has just moved. Public so callers can find
## the object(s) currently in range without actually swinging (e.g. to show a
## denied-action indicator on them).
func get_matching_hit_boxes() -> Array[HitBox]:
	var hit_boxes: Array[HitBox] = []
	var collision_shape := _get_collision_shape()
	if collision_shape == null or collision_shape.shape == null:
		return hit_boxes
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var hit_box := result.collider as HitBox
		if hit_box and hit_box.tool_type == needed_tool:
			hit_boxes.append(hit_box)
	return hit_boxes

func _get_collision_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child
	return null
