class_name ItemOutputSlotComponent
extends ItemSlotComponent
## Active half of the automation port pair: on its own timer, looks at the
## tile in its facing direction and, if there's an ItemInputSlotComponent
## there facing back at it, pushes up to transfer_amount items into it.

var _transfer_accumulator: float = 0.0

func _process(delta: float) -> void:
	if not enabled:
		return
	_transfer_accumulator += delta
	if _transfer_accumulator < transfer_interval:
		return
	_transfer_accumulator = 0.0
	_try_transfer()

func _try_transfer() -> void:
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		return
	var neighbor_cell := get_neighbor_cell(objects_layer)
	var neighbor := AutomationUtils.find_object_at_cell(objects_layer, neighbor_cell)
	if neighbor == null:
		return
	var input_component := _find_matching_input(neighbor, objects_layer, neighbor_cell)
	if input_component == null:
		return
	match get_link_mode():
		LinkMode.STANDALONE:
			_send_standalone(input_component)
		LinkMode.FIXED_SLOT:
			_send_fixed_slot(input_component)
		LinkMode.ANY_SLOT:
			_send_any_slot(input_component)

## Physical matching rule: an output facing "right" pairs only with an input
## facing "left" whose own owner cell is exactly the cell this output pushes
## into -- checking the neighbor's owner cell, not just its facing, is what
## keeps this correct once a multi-tile object (e.g. BlastFurnace) can have
## more than one input sharing the same facing on different edge cells; for a
## 1x1 neighbor there's only ever one cell a given facing could belong to
## anyway, so this is a no-op generalization there.

var test: bool = true

func _find_matching_input(neighbor: Node, objects_layer: TileMapLayer, target_cell: Vector2i) -> ItemInputSlotComponent:
	var components := AutomationUtils.get_slot_components(neighbor) as Array[ItemSlotComponent]

	for component in components:
		if components.size() == 1:
			print("size 1")
			if component is ItemInputSlotComponent and component.enabled and component.facing == OPPOSITE_FACING[facing] and component.get_owner_cell(objects_layer) == target_cell:

				return component
		# elif component.size() > 1 :
		# 	if component is ItemInputSlotComponent and component.enabled and component.facing == OPPOSITE_FACING[facing] and component.get_owner_cell(objects_layer) == target_cell:
		# 		#return components[(components.size() - 1) % components.size()] as ItemInputSlotComponent
		# 		return components[1]

	return null


func _send_standalone(input_component: ItemInputSlotComponent) -> void:
	if standalone_item == null or standalone_quantity <= 0:
		return
	var amount: int = mini(transfer_amount, standalone_quantity)
	var accepted: int = input_component.receive_item(standalone_item, amount)
	standalone_quantity -= accepted
	if standalone_quantity <= 0:
		standalone_item = null

func _send_fixed_slot(input_component: ItemInputSlotComponent) -> void:
	var item: Item =  _linked_inventory.items[linked_slot_index] 
	if item == null:
		return
	var amount: int = mini(transfer_amount, _linked_inventory.quantities[linked_slot_index])
	var accepted: int = input_component.receive_item(item, amount)
	if accepted > 0:
		_linked_inventory.remove_item(linked_slot_index, accepted)

## Scans every non-empty slot in order, stopping at the first the neighbor
## actually accepts -- so a chest that can't dump its first stack (neighbor
## full, or only accepts a different item) still sends whatever else it can.
func _send_any_slot(input_component: ItemInputSlotComponent) -> void:
	for index in _linked_inventory.items.size():
		var item: Item = _linked_inventory.items[index]
		if item == null:
			continue
		var amount: int = mini(transfer_amount, _linked_inventory.quantities[index])
		var accepted: int = input_component.receive_item(item, amount)
		if accepted > 0:
			_linked_inventory.remove_item(index, accepted)
			return
