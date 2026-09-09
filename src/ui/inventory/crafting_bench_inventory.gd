extends "res://src/ui/inventory/inventory.gd"
class_name CraftingBenchInventory
## The crafting bench's 10-slot inventory: a 3x3 shaped crafting grid (see
## ShapedCraftingRecipe.shape) plus 1 output slot. OUTPUT_SLOT never holds real
## stock -- CraftingBench keeps it mirroring whatever the matched recipe would
## produce, purely for display -- so every read/write path that could let a
## player pull or duplicate that preview for free (take/split/collect, on top
## of place/add already blocked below) is closed off. The only way to actually
## get the crafted item is CraftingBenchPanel's click handling, which calls
## CraftingBench.craft_once() and hands the result to the player directly.

const GRID_COLUMNS: int = 3
const GRID_ROWS: int = 3
const GRID_SIZE: int = GRID_COLUMNS * GRID_ROWS
const OUTPUT_SLOT: int = GRID_SIZE
const SLOT_COUNT: int = GRID_SIZE + 1

func _resize_storage() -> void:
	items.resize(SLOT_COUNT)
	quantities.resize(SLOT_COUNT)
	durabilities.resize(SLOT_COUNT)

func place_item(slot_index: int, held_item: Item, held_quantity: int, held_durability: int = -1) -> Array:
	if slot_index == OUTPUT_SLOT:
		return [held_item, held_quantity, held_durability]
	return super.place_item(slot_index, held_item, held_quantity, held_durability)

func place_one_item(slot_index: int, held_item: Item, held_durability: int = -1) -> bool:
	if slot_index == OUTPUT_SLOT:
		return false
	return super.place_one_item(slot_index, held_item, held_durability)

func take_item(slot_index: int) -> Array:
	if slot_index == OUTPUT_SLOT:
		return []
	return super.take_item(slot_index)

func split_item(slot_index: int) -> Array:
	if slot_index == OUTPUT_SLOT:
		return []
	return super.split_item(slot_index)

## Double-clicking a held stack vacuums up matching items from every slot,
## OUTPUT_SLOT included -- hide the preview from the base implementation for
## the duration of the call so it can't be scooped up for free.
func collect_matching_item(item: Item, held_quantity: int) -> int:
	var preview_item: Item = items[OUTPUT_SLOT]
	var preview_quantity: int = quantities[OUTPUT_SLOT]
	items[OUTPUT_SLOT] = null
	quantities[OUTPUT_SLOT] = 0
	var result := super.collect_matching_item(item, held_quantity)
	items[OUTPUT_SLOT] = preview_item
	quantities[OUTPUT_SLOT] = preview_quantity
	return result

## Overrides Inventory.add_item (used by shift-click transfers) to keep items
## out of OUTPUT_SLOT; otherwise identical to the base free-slot search, just
## bounded to the grid slots.
func add_item(item: Item, amount: int = 1, durability: int = -1) -> bool:
	if item == null or amount <= 0:
		return false

	var remaining := amount
	var stack_limit: int = maxi(item.max_stack_size, 1)
	for index in GRID_SIZE:
		if items[index] == item and quantities[index] < stack_limit:
			var added := mini(remaining, stack_limit - quantities[index])
			quantities[index] += added
			remaining -= added
			if remaining == 0:
				on_inventory_changed.emit()
				return true

	for index in GRID_SIZE:
		if items[index] == null:
			var added := mini(remaining, stack_limit)
			items[index] = item
			quantities[index] = added
			durabilities[index] = durability if durability >= 0 else _max_durability(item)
			remaining -= added
			if remaining == 0:
				on_inventory_changed.emit()
				return true

	return false

## Mirrors add_item's bounds so shift-click's capacity check only counts the
## grid slots OUTPUT_SLOT is excluded from.
func get_item_capacity(item: Item) -> int:
	if item == null:
		return 0

	var capacity := 0
	var stack_limit: int = maxi(item.max_stack_size, 1)
	for index in GRID_SIZE:
		if items[index] == item:
			capacity += maxi(stack_limit - quantities[index], 0)
	for index in GRID_SIZE:
		if items[index] == null:
			capacity += stack_limit
	return capacity
