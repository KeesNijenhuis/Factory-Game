extends Node
## Autoload. Central authority for belt-to-belt and belt-to-machine
## connectivity, and the registry of BeltSegment entities (see
## belt_segment.gd) -- each a continuous, independently-ticking stretch of
## belts.
##
## Connectivity (a belt's downstream_belt/downstream_slot) is only ever
## computed here -- on registration and on placement events -- never inside
## a per-frame loop. That's the actual fix for "item passover shouldn't
## happen between every belt tile" naively: the expensive AutomationUtils
## tilemap scans happen once per placement event, not once per tile per frame
## the way ItemOutputSlotComponent's per-instance timer does today.
##
## Deliberately holds no per-frame animation tick of its own: each
## BeltSegment owns its own _process() for the tiles it contains, so one
## placement can only ever disturb the one segment it actually touches
## instead of resetting every belt in the level. A segment boundary is
## simply a belt with upstream_belt == null (entry) or downstream_belt ==
## null (exit) -- this codebase's connectivity model already guarantees a
## belt has at most one upstream and one downstream (no fan-in/fan-out), so
## no separate junction-detection is needed.

const VERTICAL_FACINGS: Array[String] = ["up", "down"]

var _belts: Array[BeltComponent] = []
var _belts_by_cell: Dictionary = {}   # Vector2i -> BeltComponent (single active level, same assumption AutomationUtils already makes)
var _renderer: BeltItemRenderer

var _segments: Array[BeltSegment] = []
var _segment_by_belt: Dictionary = {}   # BeltComponent -> BeltSegment

func _ready() -> void:
	_renderer = BeltItemRenderer.new()
	add_child(_renderer)

func get_all_belts() -> Array[BeltComponent]:
	return _belts

## One-shot bulk pass used only right after a level load/reload -- throws
## away every segment built so far and reconstructs the segment graph from
## scratch, purely from each belt's current upstream_belt/downstream_belt.
## Load applies every belt's real saved facing via apply_save_data() in
## arbitrary group order (see that function's own comment), each correction
## cascading through _reconcile_segment_links(); that incremental path
## assumes a tile joining a segment is genuinely new/empty, which is true
## for a live placement but not for a tile mid-load, which can carry
## markers forward from whatever transient (soon-obsolete) grouping it had
## a moment before, since append/prepend deliberately don't clear anything
## (see _reconcile_segment_links()'s own doc). Rebuilding fresh once
## everything has settled -- instead of trusting the incremental structure
## -- avoids that entirely. Mirrors the same open-chains-then-rings walk
## the old, pre-segment _refill_all_markers()/_fill_marker_chain() used to
## do directly over flow_markers.
func rebuild_all_segments() -> void:
	for segment in _segments:
		segment.tiles.clear()   # so a same-frame _process() before free() does nothing
		segment.queue_free()
	_segments.clear()
	_segment_by_belt.clear()

	var visited: Dictionary = {}
	for belt in _belts:
		if belt.upstream_belt == null and not visited.has(belt):
			_build_segment_from_chain(belt, visited, false)
	# Whatever's left has no reachable entry point at all -- by construction
	# that can only be a closed ring (every member's upstream_belt != null).
	for belt in _belts:
		if not visited.has(belt):
			_build_segment_from_chain(belt, visited, true)

func _build_segment_from_chain(start: BeltComponent, visited: Dictionary, is_ring: bool) -> void:
	var chain: Array[BeltComponent] = []
	var probe: BeltComponent = start
	while probe != null and not visited.has(probe):
		visited[probe] = true
		chain.append(probe)
		probe = probe.downstream_belt
	var segment := _create_segment(chain)
	segment.is_ring = is_ring
	segment.refill_markers()

func register_belt(belt: BeltComponent) -> void:
	_belts.append(belt)
	_index_and_recompute(belt)

func unregister_belt(belt: BeltComponent) -> void:
	_belts.erase(belt)
	_detach_from_segment(belt)
	var removed_cell: Vector2i
	var found_cell := false
	# Erase every cell mapped to this belt, not just the first -- a belt
	# should only ever occupy one, but leaving a second, stale one behind
	# would dangle a freed-instance reference in _belts_by_cell for the next
	# lookup to crash on.
	for cell in _belts_by_cell.keys():
		if _belts_by_cell[cell] == belt:
			removed_cell = cell
			found_cell = true
			_belts_by_cell.erase(cell)
	for other in _belts:
		if other.downstream_belt == belt:
			other.downstream_belt = null
		if other.upstream_belt == belt:
			other.upstream_belt = null
	if not found_cell:
		return
	# The removed belt may have been a neighbor's chosen input_facing (a
	# straight predecessor, or a turn's upstream) -- rescan them so they fall
	# back to straight-through instead of keeping a stale input_facing that
	# now points at empty ground.
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		return
	for direction in ItemSlotComponent.FACING_VECTORS.values():
		var neighbor: BeltComponent = _belts_by_cell.get(removed_cell + direction)
		if neighbor != null:
			_recompute_connectivity(neighbor, objects_layer, removed_cell + direction)

## Re-derives this belt's cell and connectivity from scratch. Used by
## BeltComponent.apply_save_data() after facing may have changed away from
## the scene's authored default -- see that function's comment for why a
## full rescan (not just this belt's own links) is required there.
func recompute_after_facing_change(belt: BeltComponent) -> void:
	_index_and_recompute(belt)

## Called by PlacementController after EVERY placement (belt or not), so a
## belt already pointing at empty ground picks up a machine placed next to
## it afterward.
func notify_object_placed(objects_layer: TileMapLayer, cell: Vector2i) -> void:
	# A newly-placed belt gets first refusal at pulling a straight, dead-end
	# neighbor's flank into a corner aimed at itself -- must run before the
	# neighbor recompute below, since that's what would otherwise leave the
	# neighbor's stale facing/visual (still pointing at its old, empty target)
	# untouched forever: nothing else ever revisits an existing belt's facing
	# once it's placed.
	var placed_belt: BeltComponent = _belts_by_cell.get(cell)
	if placed_belt != null:
		for dir_name in ItemSlotComponent.FACING_ORDER:
			var neighbor: BeltComponent = _belts_by_cell.get(cell + ItemSlotComponent.FACING_VECTORS[dir_name])
			if neighbor != null:
				_maybe_turn_dead_end_belt(neighbor, placed_belt, cell, objects_layer)

	for direction in ItemSlotComponent.FACING_VECTORS.values():
		var neighbor: BeltComponent = _belts_by_cell.get(cell + direction)
		if neighbor != null:
			_recompute_connectivity(neighbor, objects_layer, cell + direction)

## If neighbor is a straight (non-turn), dead-end belt sitting flank-on to
## target_cell -- i.e. target_cell sits to neighbor's side, not straight ahead
## of or behind it -- rotates neighbor to face target_cell instead, popping a
## corner into place so the belt just placed there connects immediately
## instead of requiring the player to manually re-rotate neighbor first.
## Left alone if neighbor is already a turn (its input_facing already picked a
## side deliberately) or already has somewhere to go (its owner placed it
## pointing at a real target on purpose, so redirecting it would silently
## discard that choice). Only ever fires for a belt just placed at
## target_cell -- see notify_object_placed()'s only call site -- since a
## machine's fixed InputSlot layout isn't guaranteed to accept from wherever
## neighbor would end up facing.
##
## Also left alone if target_belt faces along the same axis as neighbor (both
## horizontal or both vertical, same direction or opposite) -- that's two
## independent parallel lanes sitting side by side, not a corner in progress,
## and merging them would silently bend a lane the player placed straight on
## purpose. A genuine corner-in-progress has target_belt facing the other
## axis (e.g. neighbor runs left/right, target_belt continues up/down).
##
## target_belt.upstream_belt is re-checked against an earlier neighbor in the
## same notify_object_placed() call (FACING_ORDER decides who goes first) --
## without it, two separate dead-end runs both flanking the same newly-placed
## cell would each turn to face it, and this codebase's connectivity model
## guarantees at most one real upstream per belt (see BeltManager's class
## doc), so the second turn would just leave that belt aimed at a target that
## already rejects it.
func _maybe_turn_dead_end_belt(neighbor: BeltComponent, target_belt: BeltComponent, target_cell: Vector2i, objects_layer: TileMapLayer) -> void:
	if neighbor.input_facing != ItemSlotComponent.OPPOSITE_FACING[neighbor.facing]:
		return   # already a corner -- its turn was a deliberate choice, not ours to override
	if neighbor.downstream_belt != null or neighbor.downstream_slot != null:
		return   # already feeding something -- don't redirect it
	if target_belt.upstream_belt != null and target_belt.upstream_belt != neighbor:
		return   # another flanking belt already claimed target_belt's input edge this same placement
	if VERTICAL_FACINGS.has(neighbor.facing) == VERTICAL_FACINGS.has(target_belt.facing):
		return   # same axis as neighbor -- a parallel lane, not a corner to form
	var neighbor_cell: Vector2i = objects_layer.local_to_map(objects_layer.to_local(neighbor.global_position))
	var new_facing := ""
	for dir_name in ItemSlotComponent.FACING_ORDER:
		if neighbor_cell + ItemSlotComponent.FACING_VECTORS[dir_name] == target_cell:
			new_facing = dir_name
			break
	# new_facing == "" means target_cell isn't even adjacent to neighbor (not
	# possible given the call site, but cheap to guard); == neighbor.facing
	# means target_cell was already straight ahead, the ordinary case the
	# recompute below already handles with no rotation needed; == neighbor's
	# own input side means target_cell is BEHIND neighbor, which is an
	# upstream relationship, not something to turn towards.
	if new_facing == "" or new_facing == neighbor.facing or new_facing == neighbor.input_facing:
		return
	neighbor.set_facing(new_facing)
	recompute_after_facing_change(neighbor)

## O(1) lookup -- safe to call every frame (PlacementController's ghost does,
## for auto-orient).
func get_belt_at(_objects_layer: TileMapLayer, cell: Vector2i) -> BeltComponent:
	return _belts_by_cell.get(cell)

## Which edge a belt at cell, with the given output facing, would actually
## receive items from: the straight-through opposite edge by default, or a
## perpendicular neighbor belt's edge if one already faces into cell (a
## turn) -- ties (e.g. a T-junction where two neighbors both qualify) break
## via FACING_ORDER, straight preferred first, same tie-break PlacementController's
## own _auto_orient_facing() uses for picking a NEW belt's output facing.
## Used both by _recompute_connectivity() for a real belt and by
## PlacementController to preview the correct straight/turn ghost art before
## placing.
func compute_input_facing(cell: Vector2i, facing: String) -> String:
	var straight: String = ItemSlotComponent.OPPOSITE_FACING[facing]
	var priority: Array[String] = [straight]
	for dir_name in ItemSlotComponent.FACING_ORDER:
		if dir_name != straight:
			priority.append(dir_name)
	for dir_name in priority:
		if dir_name == facing:
			continue   # can't receive from your own output edge
		var neighbor: BeltComponent = _belts_by_cell.get(cell + ItemSlotComponent.FACING_VECTORS[dir_name])
		if neighbor != null and neighbor.facing == ItemSlotComponent.OPPOSITE_FACING[dir_name]:
			return dir_name
	return straight

func _index_and_recompute(belt: BeltComponent) -> void:
	var objects_layer := AutomationUtils.get_objects_layer(belt)
	if objects_layer == null:
		return
	var cell: Vector2i = objects_layer.local_to_map(objects_layer.to_local(belt.global_position))
	_belts_by_cell[cell] = belt
	_recompute_connectivity(belt, objects_layer, cell)
	# A newly (re)placed/rotated belt can also change what its neighbors
	# should link to -- e.g. an existing belt that previously had nothing
	# downstream now feeds straight into this one.
	for direction in ItemSlotComponent.FACING_VECTORS.values():
		var neighbor: BeltComponent = _belts_by_cell.get(cell + direction)
		if neighbor != null and neighbor != belt:
			_recompute_connectivity(neighbor, objects_layer, cell + direction)

## downstream_belt is never decided by looking forward from belt itself --
## it's set (below) by the RECEIVING belt when THAT belt recomputes its own
## input_facing and finds belt behind it. That's the only way to guarantee
## fresh data: a neighbor's input_facing can change as a side effect of
## belt's own placement, and the neighbor-cascade in _index_and_recompute()/
## unregister_belt() runs belt's own recompute before its neighbors', so
## checking a neighbor's input_facing from here would often see stale data.
func _recompute_connectivity(belt: BeltComponent, objects_layer: TileMapLayer, cell: Vector2i) -> void:
	var new_input_facing := compute_input_facing(cell, belt.facing)
	belt.set_input_facing(new_input_facing)   # no-op if already this value

	var upstream: BeltComponent = _belts_by_cell.get(cell + ItemSlotComponent.FACING_VECTORS[new_input_facing])
	var upstream_is_valid_feed: bool = upstream != null and upstream.facing == ItemSlotComponent.OPPOSITE_FACING[new_input_facing]
	var real_upstream: BeltComponent = upstream if upstream_is_valid_feed else null

	# Clear any OTHER neighbor still claiming to feed belt that isn't
	# real_upstream -- checking all 4 neighbors here, not just whichever
	# direction belt.input_facing used to point at, matters because
	# BeltComponent.apply_save_data() pre-sets input_facing directly via a
	# provisional set_input_facing() call before this function ever runs.
	# If that provisional value already happens to match what this call
	# computes as new_input_facing (common, since both default to the same
	# straight-through guess), belt.input_facing == new_input_facing was
	# already true on entry -- so a change-detection keyed on "did
	# input_facing change THIS call" silently never clears the OLD belt's
	# stale downstream_belt claim. A stale claim like that made
	# _reconcile_segment_links() below treat two physically unrelated belts
	# as bridged (merging their whole chains into one segment) and made the
	# stale claimant hand its markers/items off into a totally unrelated
	# belt instead of correctly despawning them at its own true dead end.
	# Scanning every neighbor and clearing on the actual current mismatch
	# -- not on whether something changed this specific call -- is the fix.
	var unclaimed: Array[BeltComponent] = []
	for direction in ItemSlotComponent.FACING_VECTORS.values():
		var neighbor: BeltComponent = _belts_by_cell.get(cell + direction)
		if neighbor != null and neighbor != real_upstream and neighbor.downstream_belt == belt:
			neighbor.downstream_belt = null
			unclaimed.append(neighbor)

	if real_upstream != null:
		if real_upstream.downstream_belt != belt:
			real_upstream.downstream_belt = belt
			real_upstream.downstream_slot = null
	# Always authoritative (unlike downstream_belt, upstream_belt is purely
	# a query of belt's own surroundings, not a claim some other belt writes
	# onto it under an ordering race) -- so it's safe, and necessary, to
	# recompute this unconditionally on every call.
	belt.upstream_belt = real_upstream

	_reconcile_segment_links(belt)
	if real_upstream != null:
		_reconcile_segment_links(real_upstream)
	for neighbor in unclaimed:
		_reconcile_segment_links(neighbor)

	if belt.downstream_belt != null:
		if is_instance_valid(belt.downstream_belt):
			return   # already claimed by the belt ahead, via the block above (this call or an earlier one)
		belt.downstream_belt = null

	var target_cell: Vector2i = cell + ItemSlotComponent.FACING_VECTORS[belt.facing]
	var target_object := AutomationUtils.find_object_at_cell(objects_layer, target_cell)
	if target_object == null or target_object == belt:
		belt.downstream_slot = null
		return
	# A belt at target_cell that hasn't claimed us (checked above) falls
	# through here too (it's just another Node2D) -- get_slot_components()
	# would find its InputSlot, but that InputSlot's facing mirrors its
	# input_facing, which is exactly the "hasn't claimed us" case already
	# excluded above. So an unrelated neighbor belt never gets side-loaded
	# into by accident; this is the existing ItemOutputSlotComponent matching
	# rule doing the work for free.
	#
	# enabled and get_owner_cell() both matter here for the same reason they
	# matter to ItemOutputSlotComponent._find_matching_input(): a multi-tile
	# object like BlastFurnace can have more than one port sharing a facing
	# (e.g. two ports both facing "up" on different cells) and starts every
	# port disabled until an Upgrade item turns it on. Without both checks
	# this could latch onto a still-disabled port, or one sitting on a
	# different cell than the one this belt actually feeds -- either way,
	# downstream_slot would point at a port that silently refuses every item
	# forever, jamming this belt with nothing to show why.
	for component in AutomationUtils.get_slot_components(target_object):
		if component is ItemInputSlotComponent and component.enabled and component.facing == ItemSlotComponent.OPPOSITE_FACING[belt.facing] and component.get_owner_cell(objects_layer) == target_cell:
			belt.downstream_slot = component
			return
	belt.downstream_slot = null

## Makes belt's segment membership match its CURRENT upstream_belt/
## downstream_belt. Idempotent and safe to call redundantly (every placement
## cascades into several of these for belts whose links didn't actually
## change) -- if belt's existing segment already has it wired to the right
## neighbors, this is a no-op, so an unrelated placement elsewhere never
## touches a segment it didn't actually affect.
func _reconcile_segment_links(belt: BeltComponent) -> void:
	var seg: BeltSegment = _segment_by_belt.get(belt)
	if seg != null and _segment_neighbors_match(seg, belt):
		return
	if seg != null:
		_detach_from_segment(belt)

	var seg_up: BeltSegment = _segment_by_belt.get(belt.upstream_belt) if belt.upstream_belt != null else null
	var seg_down: BeltSegment = _segment_by_belt.get(belt.downstream_belt) if belt.downstream_belt != null else null

	if seg_up == null and seg_down == null:
		_create_segment([belt])
	elif seg_up != null and seg_down == null:
		seg_up.append_tile(belt)
		_segment_by_belt[belt] = seg_up
	elif seg_up == null and seg_down != null:
		seg_down.prepend_tile(belt)
		_segment_by_belt[belt] = seg_down
	elif seg_up == seg_down:
		# belt bridges the two loose ends of one already-open chain -- a ring
		# closing on itself.
		seg_up.append_tile(belt)
		_segment_by_belt[belt] = seg_up
		seg_up.is_ring = true
		seg_up.refill_markers()
	else:
		# belt bridges two previously-separate, independently-phased runs --
		# the one case that genuinely needs a scoped refill, since the
		# merged run's markers need to line up as one continuous stream.
		seg_up.append_tile(belt)
		_segment_by_belt[belt] = seg_up
		for tile in seg_down.tiles:
			seg_up.append_tile(tile)
			_segment_by_belt[tile] = seg_up
		_segments.erase(seg_down)
		seg_down.queue_free()
		seg_up.refill_markers()

## True if belt already sits in seg with its immediate tiles-array neighbors
## matching its actual upstream_belt/downstream_belt right now.
func _segment_neighbors_match(seg: BeltSegment, belt: BeltComponent) -> bool:
	var idx := seg.tiles.find(belt)
	if idx == -1:
		return false
	var count := seg.tiles.size()
	var prev: BeltComponent = null
	var next: BeltComponent = null
	if seg.is_ring:
		prev = seg.tiles[(idx - 1 + count) % count]
		next = seg.tiles[(idx + 1) % count]
	else:
		prev = seg.tiles[idx - 1] if idx > 0 else null
		next = seg.tiles[idx + 1] if idx < count - 1 else null
	return prev == belt.upstream_belt and next == belt.downstream_belt

func _create_segment(tiles: Array[BeltComponent]) -> BeltSegment:
	var segment := BeltSegment.new()
	add_child(segment)
	# Items must draw above every segment's chevrons, but both renderers
	# share the same z_index (2 -- tuned to clear the belt tile layer while
	# staying correctly behind/in front of the player, see
	# BeltFlowMarkerRenderer's own z_index comment), so same-z_index draw
	# order falls back to sibling order instead. _renderer was added once in
	# _ready(), before any segment existed, so every segment added since
	# would otherwise draw on top of it -- re-pinning it last here, each
	# time a new segment joins, keeps items on top without touching either
	# renderer's carefully-tuned z_index.
	move_child(_renderer, -1)
	segment.tiles = tiles
	for tile in tiles:
		_segment_by_belt[tile] = segment
	_segments.append(segment)
	return segment

## Removes belt from whichever segment it's currently in -- freeing the
## segment if belt was its only tile, shrinking it if belt was at either end,
## or splitting it into two segments if belt was in the middle. None of
## these cases need a marker refill: removing one tile doesn't invalidate
## the spacing already laid out among the tiles that remain.
func _detach_from_segment(belt: BeltComponent) -> void:
	var seg: BeltSegment = _segment_by_belt.get(belt)
	if seg == null:
		return
	_segment_by_belt.erase(belt)
	var idx := seg.tiles.find(belt)
	if idx == -1:
		return

	if seg.tiles.size() == 1:
		seg.tiles.clear()
		_segments.erase(seg)
		seg.queue_free()
		return

	if seg.is_ring:
		# Any single detach opens a ring back up into a chain, rotated to
		# start right after the removed tile.
		var rotated: Array[BeltComponent] = []
		for offset in range(1, seg.tiles.size()):
			rotated.append(seg.tiles[(idx + offset) % seg.tiles.size()])
		seg.tiles = rotated
		seg.is_ring = false
		return

	if idx == 0 or idx == seg.tiles.size() - 1:
		seg.tiles.remove_at(idx)
		return

	# belt was in the middle -- the prefix stays in seg, the suffix becomes
	# its own new segment.
	var suffix: Array[BeltComponent] = seg.tiles.slice(idx + 1)
	seg.tiles.resize(idx)
	_create_segment(suffix)
