extends Inventory
class_name SplitterInventory

const INPUT_SLOT: int = 0
const OUTPUT_SLOT: int = 1
const OUTPUT_SLOT_1: int = 2

# @onready var input_slot: ItemInputSlotComponent = $ItemInputSlotComponent
# @onready var output_slot: ItemOutputSlotComponent = $ItemOutputSlotComponent
# @onready var output_slot_1: ItemOutputSlotComponent = $ItemOutputSlotComponent2

# func remove_item(slot_index: int, amount: int = 1) -> bool:
# 	if slot_index < INPUT_SLOT or slot_index >= items.size() or items[slot_index] == null or amount <= 0:
# 		return false
# 	if quantities[slot_index] < amount:
# 		return false

	
# 	quantities[slot_index] -= amount
# 	if quantities[slot_index] == 0:
# 		items[slot_index] = null
# 		durabilities[slot_index] = 0

# 	print("slot index: ", slot_index)
	
# 	on_inventory_changed.emit()
# 	return true
	
