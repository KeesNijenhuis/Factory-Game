extends InteractableContainer
class_name Splitter

@onready var inventory: Node = $Inventory

@onready var input_slot = $ItemInputSlotComponent
@onready var output_slot = $ItemOutputSlotComponent
@onready var output_slot_2 = $ItemOutputSlotComponent2

func _ready() -> void:
	super._ready()


func get_save_data() -> Dictionary:
	var data := SaveSerializationUtils.serialize_inventory(inventory.items, inventory.quantities, inventory.durabilities)
	data["slot_facings"] = AutomationUtils.get_slot_facings(self)
	return data

func apply_save_data(data: Dictionary) -> void:
	SaveSerializationUtils.apply_inventory(inventory, data)
	AutomationUtils.apply_slot_facings(self, data.get("slot_facings", {}))
