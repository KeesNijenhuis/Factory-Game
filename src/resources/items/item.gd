@tool
extends Resource
class_name Item

enum ItemType {
	NONE, ITEM, TOOL, WEAPON, FUEL, UPGRADE
}

enum UpgradeTypes {
	None,
	Input,
	Output,
	SolidFuelInput
}

enum ToolTypes {
	None,
	Pickaxe,
	Axe,
	Shovel,
	Hoe,
	Sword,
	Wrench
}

const TOOL_TYPE_NAMES = {
	ToolTypes.None: "None",
	ToolTypes.Pickaxe: "Pickaxe",
	ToolTypes.Axe: "Axe",
	ToolTypes.Shovel: "Shovel",
	ToolTypes.Hoe: "Hoe",
	ToolTypes.Sword: "Sword",
	ToolTypes.Wrench: "Wrench"
}

@export var icon: Texture2D
@export var name: String
@export_multiline var description: String
@export var item_id: String
@export var max_stack_size: int = 64
@export var value: int
@export var is_consumable: bool = false
## Scene instantiated into the world when this item is placed by the player
## (e.g. chest.tscn, furnace.tscn). Null means this item cannot be placed.
@export var placed_scene: PackedScene
@export var item_type: ItemType = ItemType.ITEM:
	set(value):
		item_type = value
		notify_property_list_changed()


var tool_type: ToolTypes = ToolTypes.None
var tool_tier: ToolTierType
## How many furnace smelts one unit of this fuel powers. Only meaningful when
## item_type is FUEL.
var smelt_count: int = 1

## Which kind of port this upgrade activates -- Input for a plain
## ItemInputSlotComponent, Output for an ItemOutputSlotComponent, or
## SolidFuelInput for a SolidFuelInputSlotComponent specifically (a furnace's
## fuel port is its own type, so a plain Input Upgrade can no longer activate
## it, only a Solid Fuel Input Upgrade can). Only meaningful when item_type is
## UPGRADE.
var upgrade_type: UpgradeTypes = UpgradeTypes.None
## Seconds between transfers, copied onto the port's transfer_interval when
## this upgrade is applied. Only meaningful when item_type is UPGRADE.
var upgrade_transfer_interval: float = 1.0
## Items moved per transfer, copied onto the port's transfer_amount when this
## upgrade is applied. Only meaningful when item_type is UPGRADE.
var upgrade_transfer_amount: int = 1

func _get_property_list() -> Array[Dictionary]:
	if item_type == ItemType.TOOL:
		return [
			{
				"name": "tool_type",
				"type": TYPE_INT,
				"hint": PROPERTY_HINT_ENUM,
				"hint_string": "None,Pickaxe,Axe,Shovel,Hoe,Sword,Wrench",
				"usage": PROPERTY_USAGE_DEFAULT
			},
			{
				"name": "tool_tier",
				"type": TYPE_OBJECT,
				"hint": PROPERTY_HINT_RESOURCE_TYPE,
				"hint_string": "ToolTierType",
				"usage": PROPERTY_USAGE_DEFAULT
			}
		]
	if item_type == ItemType.FUEL:
		return [
			{
				"name": "smelt_count",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT
			}
		]
	if item_type == ItemType.UPGRADE:
		return [
			{
				"name": "upgrade_type",
				"type": TYPE_INT,
				"hint": PROPERTY_HINT_ENUM,
				"hint_string": "None,Input,Output,SolidFuelInput",
				"usage": PROPERTY_USAGE_DEFAULT
			},
			{
				"name": "upgrade_transfer_interval",
				"type": TYPE_FLOAT,
				"usage": PROPERTY_USAGE_DEFAULT
			},
			{
				"name": "upgrade_transfer_amount",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT
			}
		]
	return []
