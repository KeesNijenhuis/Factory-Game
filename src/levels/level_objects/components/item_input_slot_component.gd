class_name ItemInputSlotComponent
extends ItemSlotComponent
## Passive half of the automation port pair: exposes receive_item(), called
## by a neighboring ItemOutputSlotComponent whose facing points back at this
## component's facing (see ItemOutputSlotComponent._find_matching_input).

## Returns the quantity actually accepted (0 if rejected/full/mismatched).
func receive_item(item: Item, quantity: int) -> int:
	if not enabled or item == null or quantity <= 0:
		return 0
	match get_link_mode():
		LinkMode.STANDALONE:
			return _receive_standalone(item, quantity)
		LinkMode.FIXED_SLOT:
			return _receive_fixed_slot(item, quantity)
		LinkMode.ANY_SLOT:
			return _receive_any_slot(item, quantity)
	return 0

func _receive_standalone(item: Item, quantity: int) -> int:
	if standalone_item != null and standalone_item != item:
		return 0
	var cap: int = item.max_stack_size if standalone_capacity < 0 else mini(item.max_stack_size, standalone_capacity)
	var headroom: int = maxi(cap, 1) - standalone_quantity
	var accepted: int = clampi(mini(quantity, transfer_amount), 0, headroom)
	if accepted <= 0:
		return 0
	standalone_item = item
	standalone_quantity += accepted
	return accepted

## Inventory.place_item() swaps and discards the existing stack if the slot
## already holds a different item -- must refuse rather than call it blindly,
## or an automated delivery would silently destroy whatever's already there
## (e.g. ore mid-smelt).
func _receive_fixed_slot(item: Item, quantity: int) -> int:
	var current: Item = _linked_inventory.items[linked_slot_index]
	if current != null and current != item:
		return 0
	var requested: int = mini(quantity, transfer_amount)
	var leftover: Array = _linked_inventory.place_item(linked_slot_index, item, requested)
	var leftover_qty: int = leftover[1] if leftover.size() >= 2 else 0
	return requested - leftover_qty

## Inventory.add_item() can partially mutate slots yet still return false
## without emitting on_inventory_changed -- pre-clamp by get_item_capacity()
## so it's only ever called with an amount guaranteed to fully succeed.
func _receive_any_slot(item: Item, quantity: int) -> int:
	var requested: int = mini(quantity, transfer_amount)
	var accepted: int = mini(requested, _linked_inventory.get_item_capacity(item))
	if accepted > 0:
		_linked_inventory.add_item(item, accepted)
	return accepted
