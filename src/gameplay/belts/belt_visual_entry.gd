class_name BeltVisualEntry
extends Resource
## One entry in a BeltVisualSet: which atlas region shows a given belt
## animation (e.g. "moving_down", "down_left"). The belt's own sprite is
## purely static -- the flowing chevron marks are rendered separately by
## BeltFlowMarkerRenderer, instanced along the belt's path rather than baked
## into this tile's pixels.

@export var anim_name: StringName = &""
## Pixel rect within the BeltVisualSet's atlas texture.
@export var region: Rect2 = Rect2(0, 0, 16, 16)
## Which way this tile's own painted chevron art flows, in image/screen
## space (both top-down, y increasing downward, so no sign flip is needed
## between them) -- verified by reading marker-pixel positions directly out
## of the source art and cross-checking against each turn tile's border
## shape. Used by BeltComponent.get_marker_world_position_for()/
## get_marker_world_direction_for() to draw a flow marker's straight-line
## path across this tile in the same direction the art was painted to move,
## never bending toward a perpendicular exit edge even on a turn tile.
@export_enum("x", "y") var axis: String = "x"
@export_range(-1, 1, 2) var direction: int = 1
## First/last flowable pixel (0-16) along axis, measured at this tile's
## center row (axis "x") or column (axis "y") directly from the source art.
## A straight tile is open across ~the full width (defaults below already
## cover that case); a turn tile's belt surface is L-shaped, not a full
## band, so its actual open span is narrower -- using the full tile width
## for a turn tile put markers on its bordered, non-belt pixels for part of
## their travel.
@export var lo: int = 0
@export var hi: int = 16
