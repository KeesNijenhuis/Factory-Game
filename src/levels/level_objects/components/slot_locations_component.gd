class_name SlotLocationsComponent
extends Node2D
## Central bank of the possible edge-marker positions for one object,
## authored once per object (not once per ItemInputSlotComponent/
## ItemOutputSlotComponent sibling) via Sprite2D children -- drag those in the
## editor to line them up against this object's actual art. Every slot
## component on the same object reads get_marker_global_position() to find
## where its current facing (+ sub_position, for a multi-tile object) belongs.
##
## A 1x1 object only ever needs one marker per cardinal side: Up/Down/Left/
## Right. A bigger object (e.g. a 2x2 BlastFurnace) has 2 possible cells along
## each side, so it instead authors 8 markers -- UpLeft/UpRight, DownLeft/
## DownRight, LeftUp/LeftDown, RightUp/RightDown -- one per (facing,
## sub_position) combination; see get_quadrant()/ItemSlotComponent.
## get_sub_position(). Both schemes can coexist: lookups fall back from the
## compound key to the plain facing key, so an object only needs to author
## whichever set its own footprint actually uses.
##
## Every marker is a debug/editor-only reference position: _ready() hides
## them at runtime, since the visible arrow the player actually sees while
## the Wrench is equipped is painted separately by WrenchSlotIndicator.
##
## Looked up with get_node_or_null rather than $Up etc. -- editor tooling can
## instantiate this node to apply properties before its children exist yet,
## and a plain $Up would error in that transient state instead of just
## coming back null.
@onready var _markers: Dictionary = {
	"up": get_node_or_null("Up"),
	"down": get_node_or_null("Down"),
	"left": get_node_or_null("Left"),
	"right": get_node_or_null("Right"),
	"up_left": get_node_or_null("UpLeft"),
	"up_right": get_node_or_null("UpRight"),
	"down_left": get_node_or_null("DownLeft"),
	"down_right": get_node_or_null("DownRight"),
	"left_up": get_node_or_null("LeftUp"),
	"left_down": get_node_or_null("LeftDown"),
	"right_up": get_node_or_null("RightUp"),
	"right_down": get_node_or_null("RightDown"),
}
## Fixed 16x16 hit-region for this object, independent of wherever the
## Up/Down/Left/Right markers have been dragged for perspective. Clicking is
## tested against quadrants of this box (see get_quadrant()), and whether the
## mouse is over this object at all is tested against contains_point() --
## neither depends on marker position or the raw tile-grid cell, so both stay
## correct however far the box (or the decorative arrows) get dragged.
@onready var click_area: Area2D = get_node_or_null("ClickArea")
## Cached once here rather than re-resolved via get_node_or_null on every
## get_quadrant()/contains_point()/_click_origin() call -- those run every
## frame from WrenchSlotIndicator/ToolTargetIndicator while the Wrench/an
## Upgrade is equipped.
@onready var _click_shape_node: CollisionShape2D = click_area.get_node_or_null("CollisionShape2D") as CollisionShape2D if click_area else null

func _ready() -> void:
	for marker: Node2D in _markers.values():
		if marker:
			marker.visible = false

## Everything here works in global positions rather than composing local
## offsets by hand -- the box's actual reference point is whichever node
## someone dragged (the ClickArea itself, or its CollisionShape2D child, as
## today), and global_position always reflects that regardless of how many
## levels of nesting/offset are involved.
## sub_position ("" by default) picks the compound 8-way marker (e.g. facing
## "up", sub_position "left" -> "UpLeft") when this object authors one; falls
## back to the plain facing-only marker ("Up") when it doesn't -- so a 1x1
## object's caller can pass a sub_position without needing to know it'll be
## ignored.
func get_marker_global_position(facing: String, sub_position: String = "") -> Vector2:
	var marker: Node2D = null
	if sub_position != "":
		marker = _markers.get("%s_%s" % [facing, sub_position])
	if marker == null:
		marker = _markers.get(facing)
	return marker.global_position if marker else global_position

## Which edge of click_area a global point (e.g. a click) falls nearest --
## same up/down/left/right axis-dominant split as Player.vector_to_direction
## picks the primary facing (centered on the click box instead of this
## object's raw tile-grid cell), and the position along the other axis picks
## sub_position -- which half of that side the click fell on. footprint
## decides whether that half is meaningful at all: passing the object's own
## footprint (default Vector2i.ONE) collapses sub_position back to "" on
## whichever axis is only 1 tile wide/tall, so a 1x1 object's callers always
## get the same "" ItemSlotComponent.get_sub_position() reports for its own
## ports -- without this, a click on a 1x1 object always resolved to a
## specific "left"/"right" (or "up"/"down") half that no 1x1 port could ever
## match, silently breaking the Wrench there.
func get_quadrant(global_point: Vector2, footprint: Vector2i = Vector2i.ONE) -> Dictionary:
	var offset := global_point - _click_origin()
	if absf(offset.x) > absf(offset.y):
		var sub_position := "" if footprint.y <= 1 else ("down" if offset.y > 0.0 else "up")
		return {
			"facing": "right" if offset.x > 0.0 else "left",
			"sub_position": sub_position,
		}
	var down_up_sub_position := "" if footprint.x <= 1 else ("right" if offset.x > 0.0 else "left")
	return {
		"facing": "down" if offset.y > 0.0 else "up",
		"sub_position": down_up_sub_position,
	}

## True if global_point actually falls inside click_area's box -- used to
## decide which nearby object the mouse is over at all (see
## AutomationUtils.find_slot_target()), instead of the raw tile-grid cell,
## since the box can be dragged off that cell for perspective.
func contains_point(global_point: Vector2) -> bool:
	var shape := _click_shape()
	if shape == null or shape.shape == null:
		return false
	var rect_shape := shape.shape as RectangleShape2D
	if rect_shape == null:
		return false
	var local_point := shape.to_local(global_point)
	var half_size := rect_shape.size / 2.0
	return absf(local_point.x) <= half_size.x and absf(local_point.y) <= half_size.y

func _click_origin() -> Vector2:
	var shape := _click_shape()
	if shape:
		return shape.global_position
	return click_area.global_position if click_area else global_position

func _click_shape() -> CollisionShape2D:
	return _click_shape_node
