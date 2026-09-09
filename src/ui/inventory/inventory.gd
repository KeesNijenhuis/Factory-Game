extends Node

signal on_inventory_changed

@export_range(1, 12, 1) var rows: int = 6
@export_range(1, 12, 1) var columns: int = 4

var items: Array[Item] = []
var quantities: Array[int] = []
## Current durability per slot, parallel to items/quantities. Only meaningful for
## tool slots; 0 for everything else.
var durabilities: Array[int] = []

func _ready() -> void:
	_resize_storage()

func _resize_storage() -> void:
	var slot_count := maxi(rows, 1) * maxi(columns, 1)
	items.resize(slot_count)
	quantities.resize(slot_count)
	durabilities.resize(slot_count)

## Slot indices that get a distinct per-slot color when there's more than one
## of them (see PortColors) -- e.g. a Blast Furnace's two ore inputs. Empty by
## default; only multi-input containers override this.
func get_colored_input_slots() -> Array[int]:
	return []

func _max_durability(item: Item) -> int:
	if item and item.item_type == Item.ItemType.TOOL and item.tool_tier:
		return item.tool_tier.durability
	return 0

func add_item(item: Item, amount: int = 1, durability: int = -1) -> bool:
	if item == null or amount <= 0:
		return false

	var remaining := amount
	var stack_limit: int = maxi(item.max_stack_size, 1)
	for index in items.size():
		if items[index] == item and quantities[index] < stack_limit:
			var added := mini(remaining, stack_limit - quantities[index])
			quantities[index] += added
			remaining -= added
			if remaining == 0:
				on_inventory_changed.emit()
				return true

	for index in items.size():
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

func can_add_item(item: Item, amount: int = 1) -> bool:
	return get_item_capacity(item) >= amount

func get_item_capacity(item: Item) -> int:
	if item == null:
		return 0

	var capacity := 0
	var stack_limit: int = maxi(item.max_stack_size, 1)
	for index in items.size():
		if items[index] == item:
			capacity += maxi(stack_limit - quantities[index], 0)
	for index in items.size():
		if items[index] == null:
			capacity += stack_limit
	return capacity

func remove_item(slot_index: int, amount: int = 1) -> bool:
	if slot_index < 0 or slot_index >= items.size() or items[slot_index] == null or amount <= 0:
		return false
	if quantities[slot_index] < amount:
		return false

	quantities[slot_index] -= amount
	if quantities[slot_index] == 0:
		items[slot_index] = null
		durabilities[slot_index] = 0
	on_inventory_changed.emit()
	return true

## Decrements a tool's current durability, destroying (removing) it from its slot
## once durability reaches 0.
func damage_tool(slot_index: int, amount: int = 1) -> void:
	if slot_index < 0 or slot_index >= items.size() or items[slot_index] == null:
		return
	if items[slot_index].item_type != Item.ItemType.TOOL:
		return

	durabilities[slot_index] = maxi(durabilities[slot_index] - amount, 0)
	if durabilities[slot_index] == 0:
		items[slot_index] = null
		quantities[slot_index] = 0
	on_inventory_changed.emit()

func take_item(slot_index: int) -> Array:
	if slot_index < 0 or slot_index >= items.size() or items[slot_index] == null:
		return []

	var held_item: Item = items[slot_index]
	var held_quantity: int = quantities[slot_index]
	var held_durability: int = durabilities[slot_index]
	items[slot_index] = null
	quantities[slot_index] = 0
	durabilities[slot_index] = 0
	on_inventory_changed.emit()
	return [held_item, held_quantity, held_durability]

func split_item(slot_index: int) -> Array:
	if slot_index < 0 or slot_index >= items.size() or items[slot_index] == null or quantities[slot_index] < 2:
		return []

	var held_item: Item = items[slot_index]
	var held_quantity: int = floori(float(quantities[slot_index]) / 2.0)
	quantities[slot_index] -= held_quantity
	on_inventory_changed.emit()
	return [held_item, held_quantity]

func collect_matching_item(item: Item, held_quantity: int) -> int:
	if item == null or held_quantity <= 0:
		return held_quantity

	var stack_limit: int = maxi(item.max_stack_size, 1)
	var remaining_capacity: int = stack_limit - held_quantity
	if remaining_capacity <= 0:
		return held_quantity

	var matching_indices: Array[int] = []
	for index in items.size():
		if items[index] == null:
			continue
		var same_item_type := items[index] == item
		if not item.item_id.is_empty():
			same_item_type = items[index].item_id == item.item_id
		if same_item_type:
			matching_indices.append(index)
	matching_indices.sort_custom(func(a: int, b: int) -> bool: return quantities[a] < quantities[b])

	var changed := false
	for index in matching_indices:
		var moved_quantity: int = mini(quantities[index], remaining_capacity)
		held_quantity += moved_quantity
		remaining_capacity -= moved_quantity
		if moved_quantity == quantities[index]:
			items[index] = null
			quantities[index] = 0
			durabilities[index] = 0
		else:
			quantities[index] -= moved_quantity
		changed = changed or moved_quantity > 0
		if remaining_capacity == 0:
			break

	if changed:
		on_inventory_changed.emit()
	return held_quantity

## Deposits exactly one unit of held_item into slot_index if the slot is
## empty or already holds a matching stack with room, leaving any remainder
## held. Returns true if a unit was deposited.
func place_one_item(slot_index: int, held_item: Item, held_durability: int = -1) -> bool:
	if slot_index < 0 or slot_index >= items.size() or held_item == null:
		return false

	var target_item: Item = items[slot_index]
	if target_item == null:
		items[slot_index] = held_item
		quantities[slot_index] = 1
		durabilities[slot_index] = held_durability if held_durability >= 0 else _max_durability(held_item)
		on_inventory_changed.emit()
		return true

	if target_item == held_item:
		var stack_limit: int = maxi(target_item.max_stack_size, 1)
		if quantities[slot_index] >= stack_limit:
			return false
		quantities[slot_index] += 1
		on_inventory_changed.emit()
		return true

	return false

func place_item(slot_index: int, held_item: Item, held_quantity: int, held_durability: int = -1) -> Array:
	if slot_index < 0 or slot_index >= items.size() or held_item == null or held_quantity <= 0:
		return [held_item, held_quantity, held_durability]

	var target_item: Item = items[slot_index]
	var target_quantity: int = quantities[slot_index]
	var target_durability: int = durabilities[slot_index]
	if target_item == null:
		items[slot_index] = held_item
		quantities[slot_index] = held_quantity
		durabilities[slot_index] = held_durability if held_durability >= 0 else _max_durability(held_item)
		on_inventory_changed.emit()
		return []

	if target_item == held_item:
		var stack_limit: int = maxi(target_item.max_stack_size, 1)
		var moved_quantity: int = mini(held_quantity, stack_limit - target_quantity)
		quantities[slot_index] += moved_quantity
		held_quantity -= moved_quantity
		if held_quantity == 0:
			on_inventory_changed.emit()
			return []
		on_inventory_changed.emit()
		return [held_item, held_quantity, held_durability]

	items[slot_index] = held_item
	quantities[slot_index] = held_quantity
	durabilities[slot_index] = held_durability if held_durability >= 0 else _max_durability(held_item)
	on_inventory_changed.emit()
	return [target_item, target_quantity, target_durability]
