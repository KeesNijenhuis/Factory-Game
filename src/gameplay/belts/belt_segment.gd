class_name BeltSegment
extends Node2D
## One maximal, unbranching run of BeltComponent tiles -- from a true entry
## (upstream_belt == null) to a true exit (downstream_belt == null), or a
## closed ring. Owns its own per-frame advance of every tile it contains and
## its own BeltFlowMarkerRenderer (and therefore its own MultiMeshInstance2D)
## for that run's chevrons, independently of every other segment. This is
## what makes placing/removing one belt tile scoped to the one run it
## actually affects instead of the whole level: BeltManager (see its own
## class doc) only ever mutates the tiles array of the segment(s) touched by
## a given connectivity change, via append_tile()/prepend_tile() (no visual
## effect -- the new tile's own self-seed trickle fills its entrance) or
## refill_markers() (only on an actual merge/ring-close, scoped to this
## segment alone).
##
## Parented under the BeltManager autoload (mirroring the old global
## BeltFlowMarkerRenderer/BeltItemRenderer setup) rather than the current
## level -- see BeltItemRenderer's own class doc for why: a level is freed
## wholesale on reload, and a belt-side node tied to that lifetime crashed
## on the very next belt registration during the one-frame overlap between
## the old level's belts leaving and the new level's belts arriving. Segment
## cleanup doesn't need level-teardown to happen anyway: BeltManager's
## per-belt _detach_from_segment() already frees a segment explicitly the
## moment its last tile unregisters.

## Ordered entry -> exit (or an arbitrary rotation point for a ring).
var tiles: Array[BeltComponent] = []
var is_ring: bool = false

## A lag spike (a stall, a stutter, an editor breakpoint) can hand _process()
## a delta large enough for a marker/item's progress to overshoot 1.0 by more
## than a whole tile-length -- clamping keeps a single frame's advancement
## bounded to a fraction of a tile regardless of how long the frame actually
## took, so catching up after a stall costs a few extra (still-clamped)
## frames instead of one frame's worth of overshoot that then has to unwind.
const MAX_ADVANCE_DELTA: float = 0.1

var _marker_renderer: BeltFlowMarkerRenderer

func _ready() -> void:
	_marker_renderer = BeltFlowMarkerRenderer.new()
	add_child(_marker_renderer)

func _process(delta: float) -> void:
	var clamped_delta := minf(delta, MAX_ADVANCE_DELTA)
	# Exit-to-entry, the reverse of tiles' own entry->exit order -- so a tile
	# that hands a marker/item off to its downstream neighbor this frame
	# always does so AFTER that neighbor has already had its own turn to
	# advance. Advancing entry-first would let a freshly-arrived marker get
	# a second step added in the same frame it crosses the boundary,
	# compounding into a systematic speed-up (worse the more tiles a run
	# has) -- the same overtaking concern BeltComponent.advance() already
	# guards against within one tile by processing its output-side item
	# first, just applied at the tile-to-tile level too.
	for i in range(tiles.size() - 1, -1, -1):
		tiles[i].advance(clamped_delta)
	_marker_renderer.rebuild(tiles)

func append_tile(tile: BeltComponent) -> void:
	tiles.append(tile)

func prepend_tile(tile: BeltComponent) -> void:
	tiles.insert(0, tile)

## Rebuilds every tile's flow_markers from scratch, fully spaced, in one
## pass -- only called when this segment's own topology just changed in a
## way that actually requires respacing (a merge splicing two independently-
## phased runs together, or a ring closing). Never called for an append/
## prepend/shrink, since those don't invalidate the existing tiles' spacing.
func refill_markers() -> void:
	for tile in tiles:
		tile.flow_markers.clear()

	var total := float(tiles.size())
	var spacing := BeltComponent.MARKER_SPACING
	# A ring has no natural start/end, so fixed spacing from an arbitrary
	# walk-start point leaves one lone leftover gap wherever the walk
	# happened to begin -- a visible seam, but a stretched/compressed
	# spacing everywhere else to hide it would read as sub-pixel jitter.
	# Better to keep the exact 5px spacing everywhere and accept one seam
	# gap on a ring than to blur every gap on the ring to remove it.
	var pos := 0.0
	while pos < total:
		var idx := int(pos)
		tiles[idx].flow_markers.append(pos - float(idx))
		pos += spacing

	# flow_markers' convention is index 0 = highest progress (closest to the
	# output edge) -- markers were appended in ascending-progress order above.
	for tile in tiles:
		tile.flow_markers.reverse()
