extends "res://src/ui/inventory/inventory.gd"
class_name BlastFurnaceInventory
## The blast furnace's 4-slot inventory: two independent inputs, fuel, and
## output. Mirrors FurnaceInventory's restriction pattern (output blocks
## manual placement, fuel slot only accepts FUEL-type items) applied to two
## input slots instead of one, so InventoryPanel's existing click/drag logic
## keeps working unmodified.

const INPUT_A_SLOT: int = 0
const INPUT_B_SLOT: int = 1
const FUEL_SLOT: int = 2
const OUTPUT_SLOT: int = 3

func get_colored_input_slots() -> Array[int]:
	return [INPUT_A_SLOT, INPUT_B_SLOT]

func place_item(slot_index: int, held_item: Item, held_quantity: int, held_durability: int = -1) -> Array:
	if slot_index == OUTPUT_SLOT:
		return [held_item, held_quantity, held_durability]
	if slot_index == FUEL_SLOT and held_item and held_item.item_type != Item.ItemType.FUEL:
		return [held_item, held_quantity, held_durability]
	return super.place_item(slot_index, held_item, held_quantity, held_durability)

func place_one_item(slot_index: int, held_item: Item, held_durability: int = -1) -> bool:
	if slot_index == OUTPUT_SLOT:
		return false
	if slot_index == FUEL_SLOT and held_item and held_item.item_type != Item.ItemType.FUEL:
		return false
	return super.place_one_item(slot_index, held_item, held_durability)

## Overrides Inventory.add_item (used by shift-click transfers) to keep items out of
## OUTPUT_SLOT, restrict fuel items to FUEL_SLOT, and route non-fuel items into
## whichever of INPUT_A_SLOT/INPUT_B_SLOT already holds a matching stack with
## room, else the first of the two that's empty -- same two-pass
## matching-then-empty preference the base Inventory.add_item uses over an
## arbitrary-size slot list, just scoped to these 2 candidates. Whatever
## doesn't fit is left unmoved by the caller, which caps the transfer with
## get_item_capacity below.
func add_item(item: Item, amount: int = 1, durability: int = -1) -> bool:
	if item == null or amount <= 0:
		return false

	if item.item_type == Item.ItemType.FUEL:
		return _add_to_slot(FUEL_SLOT, item, amount, durability)

	for slot_index in [INPUT_A_SLOT, INPUT_B_SLOT]:
		if items[slot_index] == item:
			return _add_to_slot(slot_index, item, amount, durability)
	for slot_index in [INPUT_A_SLOT, INPUT_B_SLOT]:
		if items[slot_index] == null:
			return _add_to_slot(slot_index, item, amount, durability)
	return false

func _add_to_slot(slot_index: int, item: Item, amount: int, durability: int) -> bool:
	var stack_limit: int = maxi(item.max_stack_size, 1)
	var remaining := amount

	if items[slot_index] == item and quantities[slot_index] < stack_limit:
		var added := mini(remaining, stack_limit - quantities[slot_index])
		quantities[slot_index] += added
		remaining -= added
		if remaining == 0:
			on_inventory_changed.emit()
			return true

	if items[slot_index] == null:
		var added := mini(remaining, stack_limit)
		items[slot_index] = item
		quantities[slot_index] = added
		durabilities[slot_index] = durability if durability >= 0 else _max_durability(item)
		remaining -= added
		if remaining == 0:
			on_inventory_changed.emit()
			return true

	return false

## Mirrors add_item's routing so shift-click's capacity check (used to cap how
## much gets moved, leaving the rest behind in the source slot) only counts
## the slot(s) a given item could actually land in.
func get_item_capacity(item: Item) -> int:
	if item == null:
		return 0

	var stack_limit: int = maxi(item.max_stack_size, 1)
	if item.item_type == Item.ItemType.FUEL:
		if items[FUEL_SLOT] == item:
			return maxi(stack_limit - quantities[FUEL_SLOT], 0)
		return stack_limit if items[FUEL_SLOT] == null else 0

	for slot_index in [INPUT_A_SLOT, INPUT_B_SLOT]:
		if items[slot_index] == item:
			return maxi(stack_limit - quantities[slot_index], 0)
	for slot_index in [INPUT_A_SLOT, INPUT_B_SLOT]:
		if items[slot_index] == null:
			return stack_limit
	return 0
