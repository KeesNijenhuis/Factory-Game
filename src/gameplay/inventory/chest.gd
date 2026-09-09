extends InteractableContainer
class_name Chest

@onready var inventory: Node = $Inventory
@onready var input_slot: ItemInputSlotComponent = $InputSlot
@onready var output_slot: ItemOutputSlotComponent = $OutputSlot

## Items this chest starts with, set per-instance in the editor. Keys are the
## Item resources to add; values are the starting quantity of each.
@export var starting_items: Dictionary[Item, int] = {}

func _ready() -> void:
	super._ready()
	for item in starting_items:
		if item == null:
			continue
		inventory.add_item(item, maxi(starting_items[item], 1))

func _on_opened(hud: HUD) -> void:
	hud.chest_inventory_panel.open_for(inventory)

func _on_closed(hud: HUD) -> void:
	hud.chest_inventory_panel.close_inventory()

func get_save_data() -> Dictionary:
	var data := SaveSerializationUtils.serialize_inventory(inventory.items, inventory.quantities, inventory.durabilities)
	data["slot_facings"] = AutomationUtils.get_slot_facings(self)
	return data

func apply_save_data(data: Dictionary) -> void:
	SaveSerializationUtils.apply_inventory(inventory, data)
	AutomationUtils.apply_slot_facings(self, data.get("slot_facings", {}))
