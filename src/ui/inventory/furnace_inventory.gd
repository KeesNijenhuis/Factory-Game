extends "res://src/ui/inventory/inventory.gd"
class_name FurnaceInventory
## The furnace's 3-slot inventory: input, fuel, output. Reuses Inventory's
## storage/signal/drag-drop API as-is, only restricting what place_item()
## will accept into the fuel and output slots so InventoryPanel's existing
## click/drag logic can be reused unmodified.

const INPUT_SLOT: int = 0
const FUEL_SLOT: int = 1
const OUTPUT_SLOT: int = 2

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
## OUTPUT_SLOT and restrict fuel items to FUEL_SLOT only (never spilling into
## INPUT_SLOT) and non-fuel items to INPUT_SLOT only. Whatever doesn't fit in the
## target slot is left unmoved by the caller, which caps the transfer with
## get_item_capacity below.
func add_item(item: Item, amount: int = 1, durability: int = -1) -> bool:
	if item == null or amount <= 0:
		return false

	var slot_index: int = FUEL_SLOT if item.item_type == Item.ItemType.FUEL else INPUT_SLOT
	var remaining := amount
	var stack_limit: int = maxi(item.max_stack_size, 1)

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

## Mirrors add_item's single-slot restriction so shift-click's capacity check
## (used to cap how much gets moved, leaving the rest behind in the source slot)
## only counts the one slot a given item can actually land in.
func get_item_capacity(item: Item) -> int:
	if item == null:
		return 0

	var slot_index: int = FUEL_SLOT if item.item_type == Item.ItemType.FUEL else INPUT_SLOT
	var stack_limit: int = maxi(item.max_stack_size, 1)
	if items[slot_index] == item:
		return maxi(stack_limit - quantities[slot_index], 0)
	if items[slot_index] == null:
		return stack_limit
	return 0
