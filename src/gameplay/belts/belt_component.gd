class_name BeltComponent
extends Node2D
## Carries a queue of items along one belt tile, from its InputSlot edge to
## its facing edge. Advanced by this tile's owning BeltSegment (see
## belt_segment.gd), once per frame, via advance() -- NOT a per-node
## _process() on this component itself -- so a growing number of belts never
## costs more per-tile tilemap scans: BeltManager caches downstream_belt/
## downstream_slot once at placement time instead of this component looking
## up its neighbor itself every tick.
##
## Receives items from a machine via the sibling InputSlot (an ordinary
## ItemInputSlotComponent, unmodified -- any existing ItemOutputSlotComponent
## already knows how to find and feed it, so machines need zero changes to
## feed a belt). Receives items from an upstream belt directly via
## try_accept_item(), bypassing InputSlot entirely so belt-to-belt handoff
## is a single O(1) call rather than a second hop through inventory-style
## accept logic.

const TILE_SIZE_PX: float = 16.0

@export_enum("up", "down", "left", "right") var facing: String = "down"
## Pixels per second an item travels along this tile. 16.0 = 1 tile/sec.
@export var speed: float = 32.0
## Max items that fit end-to-end on this one tile -- sets the minimum gap
## between consecutive items as 1.0 / stack_size. Distinct from
## Item.max_stack_size, which governs inventory stacking of the belt-as-item.
@export var stack_size: int = 4

## Which named visual (atlas region) shows for each (input_facing, facing)
## pair -- see visual_for(). Exported so the placement ghost can read it
## straight off a throwaway scene instance too.
@export var visual_set: BeltVisualSet

@onready var input_slot: ItemInputSlotComponent = $InputSlot
@onready var sprite: Sprite2D = $Sprite2D
## Marks where on screen the belt's carrying surface actually sits -- the art
## is drawn with a perspective offset above the node's logical tile-center
## origin (see AnimatedSprite2D's own offset), so items must render relative
## to this marker, not global_position directly, or they visibly float off
## the belt.
@onready var item_render_pos: Marker2D = $ItemRenderPos

## Which edge this belt actually receives items from -- OPPOSITE_FACING[facing]
## (straight through) by default, or a perpendicular edge when BeltManager
## detects a turn (see BeltManager.compute_input_facing()). Mirrored onto
## input_slot.facing so a machine feeding this belt from that same side works
## too. Always a valid facing string once _ready() has run -- never "".
var input_facing: String = ""
## [{item: Item, progress: float}], index 0 = closest to the output edge.
## progress runs 0.0 (input edge) -> 1.0 (output edge).
var items_in_transit: Array[Dictionary] = []
## Purely decorative flow markers -- [progress: float], no Item/inventory
## semantics, rendered by this tile's owning BeltSegment's
## BeltFlowMarkerRenderer as small instanced chevron glyphs. Same index
## convention as items_in_transit: index 0 = highest progress = closest to
## the output edge. Advanced/handed off in _advance_markers() below,
## independently of items_in_transit, so a belt shows flowing markers
## whether or not anything is actually being carried. A marker appears fully
## formed the instant it's created (self-seeded, handed off, or refilled)
## and disappears instantly once it reaches a true dead end -- no fade.
var flow_markers: Array[float] = []
## Spacing between markers, in progress units -- derived from the source
## art's marker glyph repeating every 5px within a 16px tile (see
## bake_belt_flow_markers.py), not from stack_size/min_gap(), which govern
## real item spacing, an unrelated gameplay concept.
const MARKER_SPACING: float = 5.0 / TILE_SIZE_PX
## Cached by BeltManager at placement/connectivity-change time -- never both
## set at once. Null/null means "nothing downstream yet", not an error.
var downstream_belt: BeltComponent = null
var downstream_slot: ItemInputSlotComponent = null
## Symmetric to downstream_belt (the belt, if any, that feeds this one) --
## also cached by BeltManager. Used only to decide whether this belt is a
## true flow entry point that should self-seed new markers (see
## _maybe_self_seed_marker()); items don't need the equivalent, since a real
## item's arrival is always driven by the upstream belt calling
## try_accept_item() directly rather than this belt polling for one.
var upstream_belt: BeltComponent = null

var _save_id: String = ""
## Which BeltVisualEntry (by name) sprite is currently showing -- tracked
## separately from sprite.region_rect purely to skip redundant reassignment
## when the animation hasn't actually changed.
var _anim_name: StringName = &""

func _ready() -> void:
	input_facing = ItemSlotComponent.OPPOSITE_FACING[facing]
	input_slot.facing = input_facing
	_update_visual()
	_save_id = SaveSerializationUtils.compute_tile_object_id(self)
	if _save_id != "":
		add_to_group("saveable")
	BeltManager.register_belt(self)

func _exit_tree() -> void:
	BeltManager.unregister_belt(self)

func get_save_id() -> String:
	return _save_id

func min_gap() -> float:
	return 1.0 / maxf(float(maxi(stack_size, 1)), 1.0)

## Picks which BeltVisualSet entry shows (input_facing, facing) -- static (no
## belt instance needed) so PlacementController's ghost can call it too and
## always preview exactly the art a real belt would end up with. Carries one
## dedicated entry per straight direction ("moving_up"/"moving_down"/
## "moving_left"/"moving_right") plus one per turn pair drawn so far, named
## "<input_facing>_<output_facing>" (e.g. "down_left" for a belt receiving
## from below and turning out to the left). A turn pair with no dedicated
## entry yet falls back to the straight loop for out_facing, so belts keep
## working as more turn art arrives incrementally -- visuals is passed in
## (rather than read off an instance) so both a real belt and a ghost
## preview, each holding their own BeltVisualSet reference, can share this
## same lookup.
static func visual_for(visuals: BeltVisualSet, in_facing: String, out_facing: String) -> StringName:
	var turn_anim := StringName("%s_%s" % [in_facing, out_facing])
	if visuals != null and visuals.has_animation(turn_anim):
		return turn_anim
	return StringName("moving_%s" % out_facing)

func _update_visual() -> void:
	var anim := visual_for(visual_set, input_facing, facing)
	if anim == _anim_name:
		return
	_anim_name = anim
	var entry := visual_set.get_entry(anim)
	sprite.texture = visual_set.atlas
	sprite.region_enabled = true
	sprite.region_rect = entry.region

## Called by BeltManager once it's worked out which edge actually feeds this
## belt (straight-through by default, or a perpendicular neighbor on a turn).
## Mirrors the new value onto input_slot.facing so a machine sitting on that
## same edge can feed this belt too, and refreshes the sprite to match.
func set_input_facing(new_input_facing: String) -> void:
	if input_facing == new_input_facing:
		return
	input_facing = new_input_facing
	input_slot.facing = new_input_facing
	_update_visual()

## Rotates this belt's OUTPUT edge after it's already placed -- used by
## BeltManager to auto-turn a straight, dead-end belt into a corner when a new
## belt is placed against its flank (see
## BeltManager._maybe_turn_dead_end_belt()), so the player doesn't have to
## manually re-rotate the existing belt first. Unlike set_input_facing(),
## changing facing also changes which cell this belt targets, so the caller
## is responsible for re-running connectivity (BeltManager.recompute_after_facing_change())
## afterward -- this only updates this belt's own facing/sprite.
func set_facing(new_facing: String) -> void:
	if facing == new_facing:
		return
	facing = new_facing
	_update_visual()

## Single acceptance choke-point -- used both by an upstream belt's handoff
## and by this belt's own InputSlot drain, so there's one spacing rule
## instead of two copies of it.
func try_accept_item(item: Item, entry_progress: float = 0.0) -> bool:
	if item == null:
		return false
	if not items_in_transit.is_empty():
		var tail: Dictionary = items_in_transit[items_in_transit.size() - 1]
		if tail.progress < min_gap():
			return false
	items_in_transit.append({"item": item, "progress": entry_progress})
	return true

## Called by this tile's owning BeltSegment once per frame.
func advance(delta: float) -> void:
	_drain_input_slot()
	var step: float = (speed / TILE_SIZE_PX) * delta
	for i in items_in_transit.size():
		var entry: Dictionary = items_in_transit[i]
		# Capped against the item ahead of it (already updated this same
		# tick, since we iterate head-first) -- this is what prevents
		# overtaking with no extra bookkeeping.
		var cap: float = 1.0 if i == 0 else items_in_transit[i - 1].progress - min_gap()
		entry.progress = minf(entry.progress + step, cap)
	_try_handoff()
	_advance_markers(step)

## Parallel to the items_in_transit loop above, but markers never overtake
## each other (they all move at this belt's one speed), so there's no
## min_gap()-style cap to apply while advancing -- only entry-point seeding
## and end-of-tile handoff need bookkeeping.
func _advance_markers(step: float) -> void:
	_maybe_self_seed_marker()
	for i in flow_markers.size():
		flow_markers[i] += step
	_try_handoff_markers()

## Only a belt with nothing feeding it needs to manufacture its own markers --
## everywhere else, the upstream belt's own handoff (accept_marker()) is
## what keeps this belt's stream populated, and a self-seed here would
## collide with that arrival (see BeltManager._recompute_connectivity()'s
## ring-closure handling for the one case an upstream-fed belt still needs
## seeding once, at the moment a loop first closes).
func _maybe_self_seed_marker() -> void:
	if upstream_belt != null:
		return
	if flow_markers.is_empty() or flow_markers[flow_markers.size() - 1] >= MARKER_SPACING:
		flow_markers.append(0.0)

## Unlike _try_handoff(), markers aren't hard-capped at progress 1.0 while
## advancing, so more than one could cross it in a single tick (at high
## speed / low framerate) -- a while loop (not a single `if flow_markers[0]
## ...` check) handles all of them, not just the head. Progress stays
## monotonic by index (index 0 highest), so stopping at the first marker
## below 1.0 is a valid early-out.
func _try_handoff_markers() -> void:
	var i := 0
	while i < flow_markers.size():
		var progress: float = flow_markers[i]
		if progress < 1.0:
			break
		if downstream_belt != null and is_instance_valid(downstream_belt):
			downstream_belt.accept_marker(progress - 1.0)
		# Handed off, or a true dead end with nowhere to hand off to --
		# either way the marker leaves this tile immediately, no lingering
		# shrink-out. Removing at i (not advancing it) shifts the next
		# element into place for the next loop check.
		flow_markers.remove_at(i)

## Public like try_accept_item() (not underscore-prefixed) since it's called
## cross-instance, both by an upstream belt's own handoff above and by
## BeltSegment.refill_markers()/BeltManager when seeding a newly-closed ring.
## Always succeeds -- a marker is decoration, not inventory, so there's no
## capacity/backpressure concept to fail against the way try_accept_item()
## has. Appended at the end to match items_in_transit's convention (index 0
## = highest progress); a freshly-arrived marker's progress is always small
## (a fraction of one frame's step), so this stays naturally ordered without
## needing an explicit sort.
func accept_marker(entry_progress: float) -> void:
	flow_markers.append(entry_progress)

## World-space position for an item at the given progress: entry edge ->
## tile center -> exit edge, as two half-length lerps rather than one
## straight line -- on a turn tile this makes the item bend a sharp 90
## degrees at the center instead of cutting diagonally across the corner.
## For a straight belt (input_facing opposite facing) entry/center/exit are
## already colinear, so the two halves just retrace the same straight line
## as before. Centered on item_render_pos rather than global_position so
## items track the belt's actual visual surface.
func get_world_position_for(progress: float) -> Vector2:
	var center := item_render_pos.global_position
	var entry_point := center + Vector2(ItemSlotComponent.FACING_VECTORS[input_facing]) * (TILE_SIZE_PX * 0.5)
	var exit_point := center + Vector2(ItemSlotComponent.FACING_VECTORS[facing]) * (TILE_SIZE_PX * 0.5)
	if progress <= 0.5:
		return entry_point.lerp(center, progress * 2.0)
	return center.lerp(exit_point, (progress - 0.5) * 2.0)

## Straight-line position across this tile, along its own painted flow axis
## (BeltVisualEntry.axis/direction) -- unlike get_world_position_for(),
## never bends toward a perpendicular exit edge, even on a turn tile. A
## first attempt at this spanned the tile's full 16px width, which is
## correct for a straight tile but wrong for a turn tile: a turn's belt
## surface is L-shaped, not a full band, so part of that "full width" line
## fell on the bordered, non-belt pixels. entry.lo/hi (measured directly
## from the art at this tile's center row/column) constrain the line to
## the span that's actually open, instead of the full tile. progress 0 =
## this tile's entry edge along that axis, progress 1 = its exit edge along
## that same axis; the cross-axis coordinate is always the tile's center.
## Deliberately decoupled from input_facing/facing so a marker's visual
## line matches the tile's own art, not the logical item path -- see
## visual_for() for how _anim_name is chosen.
func get_marker_world_position_for(progress: float) -> Vector2:
	var entry := visual_set.get_entry(_anim_name)
	var t := progress if entry.direction > 0 else (1.0 - progress)
	var local := entry.lo + t * (entry.hi - entry.lo) - TILE_SIZE_PX * 0.5
	var offset := Vector2(local, 0.0) if entry.axis == "x" else Vector2(0.0, local)
	return item_render_pos.global_position + offset

## Constant direction matching get_marker_world_position_for()'s line --
## never varies across the tile, since rotation should only change at the
## boundary between two tiles, not mid-tile.
func get_marker_world_direction_for() -> Vector2:
	var entry := visual_set.get_entry(_anim_name)
	return Vector2(entry.direction, 0.0) if entry.axis == "x" else Vector2(0.0, entry.direction)

func get_save_data() -> Dictionary:
	var transit := []
	for entry in items_in_transit:
		transit.append({"item_id": entry.item.item_id, "progress": entry.progress})
	var input_item_id = null
	if input_slot.standalone_item != null:
		input_item_id = input_slot.standalone_item.item_id
	return {
		"facing": facing,
		"items_in_transit": transit,
		"input_item_id": input_item_id,
		"input_quantity": input_slot.standalone_quantity,
	}

func apply_save_data(data: Dictionary) -> void:
	facing = data.get("facing", facing)
	# Provisional straight-through reset -- a no-op if input_facing already
	# happened to be this value (so it won't restart the sprite needlessly),
	# and recompute_after_facing_change() at the end of this function corrects
	# input_facing to an actual turn if a neighbor calls for one.
	set_input_facing(ItemSlotComponent.OPPOSITE_FACING[facing])
	items_in_transit.clear()
	for entry in data.get("items_in_transit", []):
		var item := ItemRegistry.get_item(entry.get("item_id", ""))
		if item != null:
			items_in_transit.append({"item": item, "progress": entry.get("progress", 0.0)})
	var input_item_id = data.get("input_item_id", null)
	input_slot.standalone_item = ItemRegistry.get_item(input_item_id) if input_item_id else null
	input_slot.standalone_quantity = data.get("input_quantity", 0)
	# Placed objects respawn at their scene's authored default facing before
	# save data is applied (see SaveManager._apply_placed_objects), and every
	# belt's apply_save_data() runs in arbitrary group order -- so a full
	# neighbor rescan (not just fixing this belt's own links) is required,
	# or a neighbor that already linked against our stale default facing
	# would stay wrong.
	BeltManager.recompute_after_facing_change(self)
	# set_input_facing() above (directly, or via the recompute cascade) only
	# refreshes the sprite when input_facing itself changes -- but _ready()
	# may have already cached an input_facing (from a turn detected while
	# every belt still sat at its default facing) that happens to equal the
	# value recomputed from our real saved facing, even though facing itself
	# changed. _update_visual() depends on both fields, so it must be forced
	# unconditionally here rather than relying on either guarded setter.
	_update_visual()

func _drain_input_slot() -> void:
	if input_slot.standalone_item == null or input_slot.standalone_quantity <= 0:
		return
	if try_accept_item(input_slot.standalone_item):
		input_slot.standalone_quantity -= 1
		if input_slot.standalone_quantity <= 0:
			input_slot.standalone_item = null

func _try_handoff() -> void:
	if items_in_transit.is_empty():
		return
	var head: Dictionary = items_in_transit[0]
	if head.progress < 1.0:
		return
	if downstream_belt != null and is_instance_valid(downstream_belt):
		if downstream_belt.try_accept_item(head.item, head.progress - 1.0):
			items_in_transit.pop_front()
	elif downstream_slot != null and is_instance_valid(downstream_slot):
		if downstream_slot.receive_item(head.item, 1) > 0:
			items_in_transit.pop_front()
	# else: no downstream -- the head item parks at progress 1.0 and every
	# entry behind it backpressures naturally via the min_gap() cap.
