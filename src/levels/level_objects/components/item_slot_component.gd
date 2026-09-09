class_name ItemSlotComponent
extends Node2D
## Shared base for ItemInputSlotComponent/ItemOutputSlotComponent: a single
## configurable "port" on one edge of an object's tile that automation can
## push items into or pull items out of.
##
## Storage is standalone (own item/quantity) by default, so a component can
## sit on an object with no Inventory at all (e.g. a future belt segment).
## Optionally linking linked_inventory_path to an owner's Inventory node lets
## the component instead read/write that Inventory directly -- either one
## fixed slot (linked_slot_index >= 0, e.g. Furnace's ore/fuel/output slots,
## keeping Furnace's own recipe logic as the single source of truth) or any
## non-empty/matching slot (linked_slot_index == -1, e.g. a Chest, which has
## no fixed slot roles).

enum LinkMode { STANDALONE, FIXED_SLOT, ANY_SLOT }

const FACING_VECTORS: Dictionary = {
	"up": Vector2i(0, -1),
	"down": Vector2i(0, 1),
	"left": Vector2i(-1, 0),
	"right": Vector2i(1, 0),
}
const OPPOSITE_FACING: Dictionary = {
	"up": "down",
	"down": "up",
	"left": "right",
	"right": "left",
}
## Clockwise cycle order shared by WrenchController (cycling a slot's facing)
## and PlacementController (cycling a belt's placement facing), so there's
## one definition of "clockwise" instead of two independent copies.
const FACING_ORDER: Array[String] = ["up", "right", "down", "left"]

## Which edge of this object's tile the slot is exposed on. Mutable at
## runtime -- the Wrench reassigns this.
@export_enum("up", "down", "left", "right") var facing: String = "down"
## Whether this port actually transfers items yet. Off by default -- the
## player turns a port on (and sets transfer_interval/transfer_amount, see
## UpgradeController) by right-clicking its edge with the matching Input/
## Output Upgrade item. Belts are the one exception: their own input port is
## always enabled from placement, since it's the conveyor itself rather than
## a machine port the player upgrades.
@export var enabled: bool = false
## Seconds between transfer attempts (ItemOutputSlotComponent only).
@export var transfer_interval: float = 1.0
## Items moved per successful transfer attempt.
@export var transfer_amount: int = 1
## Standalone-mode storage cap, on top of item.max_stack_size (ItemInputSlotComponent
## only). -1 (default) means "no extra cap" -- item.max_stack_size alone governs
## headroom. Belts set this to 1 so their staging buffer holds at most one item,
## which only clears once BeltComponent._drain_input_slot() actually pulls it into
## transit -- that's what makes belt-is-full backpressure reach all the way back to
## the sending inventory instead of the buffer silently absorbing pushes the belt
## has no room for.
@export var standalone_capacity: int = -1
## Owner's Inventory node to link to. Empty path = standalone storage.
@export var linked_inventory_path: NodePath
## -1 = "any slot" mode (requires linked_inventory_path set). >= 0 = that
## exact slot index of the linked Inventory. Ignored when standalone.
@export var linked_slot_index: int = -1

var standalone_item: Item = null
var standalone_quantity: int = 0
## item_id of whichever Upgrade item last enabled this port (see
## UpgradeController), so the Wrench can refund that exact item -- e.g. a
## Solid Fuel Input Upgrade, not a plain Input Upgrade -- when it removes the
## upgrade again. Empty for a port that was never enabled this way (e.g. a
## belt's always-enabled input, which no Upgrade item ever touches).
var applied_upgrade_item_id: String = ""

var _linked_inventory: Node = null

## The owner's shared bank of the 4 possible edge-arrow positions (one
## SlotLocationsComponent per object, sibling to every slot component on it)
## -- see slot_locations_component.gd. Positions are authored once per
## object rather than once per slot, and looked up fresh by current facing,
## so any slot rotated by the Wrench at runtime automatically finds the
## right spot with no extra math here.
@onready var slot_locations: SlotLocationsComponent = get_parent().get_node_or_null("SlotLocationsComponent")

func _ready() -> void:
	if linked_inventory_path != NodePath():
		_linked_inventory = get_node_or_null(linked_inventory_path)

## Where this slot's arrow belongs right now, in global/world space --
## this component's own global_position if the owner has no
## SlotLocationsComponent.
func get_marker_global_position() -> Vector2:
	return slot_locations.get_marker_global_position(facing, get_sub_position()) if slot_locations else global_position

## Which half of this component's facing edge it currently sits on -- derived
## from its own local position relative to the owning object's footprint (see
## AutomationUtils.get_object_footprint), not stored separately, so moving
## this component (see WrenchController/UpgradeController) is the single
## source of truth for both automation (get_owner_cell) and the marker
## position picked here. "" when the owner's footprint is only 1 tile
## wide/tall in the relevant axis (every existing 1x1 object), where
## SlotLocationsComponent's plain facing-only markers already cover it.
func get_sub_position() -> String:
	var footprint := AutomationUtils.get_object_footprint(get_parent())
	match facing:
		"up", "down":
			if footprint.x <= 1:
				return ""
			return "left" if position.x < (footprint.x - 1) * BeltComponent.TILE_SIZE_PX * 0.5 else "right"
		"left", "right":
			if footprint.y <= 1:
				return ""
			return "up" if position.y < (footprint.y - 1) * BeltComponent.TILE_SIZE_PX * 0.5 else "down"
	return ""

func get_link_mode() -> LinkMode:
	if _linked_inventory == null:
		return LinkMode.STANDALONE
	return LinkMode.FIXED_SLOT if linked_slot_index >= 0 else LinkMode.ANY_SLOT

func get_owner_cell(objects_layer: TileMapLayer) -> Vector2i:
	return objects_layer.local_to_map(objects_layer.to_local(global_position))

func get_neighbor_cell(objects_layer: TileMapLayer) -> Vector2i:
	return get_owner_cell(objects_layer) + FACING_VECTORS[facing]
