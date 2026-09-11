extends InventoryPanel
class_name CraftingBenchPanel
## InventoryPanel's slot/drag machinery is reused as-is (the crafting bench's
## grid + output are just a restricted Inventory, see CraftingBenchInventory).
## This only adds the output slot, kept out of the shaped 3x3 grid container
## so it can sit apart from it visually, and binds panel open/close to a
## CraftingBench the same way FurnacePanel binds to a Furnace.

@onready var output_slot: InventorySlot = %OutputSlot

var crafting_bench: CraftingBench

func open_for_bench(target: CraftingBench) -> void:
	crafting_bench = target
	open_for(target.inventory)

func close_inventory() -> void:
	crafting_bench = null
	super.close_inventory()

## CraftingBenchInventory.items includes OUTPUT_SLOT on top of the 3x3 grid
## (see CraftingBenchInventory.SLOT_COUNT), so the grid itself is only
## GRID_SIZE slots, laid out GRID_COLUMNS wide.
func _grid_slot_count() -> int:
	return CraftingBenchInventory.GRID_SIZE

func _grid_columns() -> int:
	return CraftingBenchInventory.GRID_COLUMNS

## The base class only wires up slots found under %Container (the shaped 3x3
## grid); the output slot lives outside that container so it can be laid out
## separately, so it's appended here to line up with CraftingBenchInventory's
## OUTPUT_SLOT index (immediately after the grid's GRID_SIZE slots).
func _configure_slots() -> void:
	super._configure_slots()
	if not slots.has(output_slot):
		slots.append(output_slot)

## The output slot never holds real stock to click/drag with the base
## machinery (CraftingBenchInventory refuses to give it up through any of
## that) -- clicking it crafts fresh from the grid instead. Left-click takes
## one batch into the held-item slot; shift-click repeats that until the grid
## no longer matches or nowhere has room, dropping each batch straight into
## another open panel (almost always the player's own inventory, since
## opening this bench forces it open too) rather than the cursor.
func _on_slot_clicked(slot_index: int, button: int, double_click: bool, shift_click: bool) -> void:
	if slot_index == CraftingBenchInventory.OUTPUT_SLOT:
		if button != MOUSE_BUTTON_LEFT:
			return
		if shift_click:
			_craft_all_into_inventory()
		else:
			_craft_one_into_hand()
		return
	super._on_slot_clicked(slot_index, button, double_click, shift_click)

func _craft_one_into_hand() -> void:
	var recipe := crafting_bench.current_recipe
	if recipe == null or recipe.output_items.is_empty():
		return
	var output_item: Item = recipe.output_items[0]
	var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	if hud.held_item != null and hud.held_item != output_item:
		return
	var stack_limit: int = maxi(output_item.max_stack_size, 1)
	var held_quantity: int = hud.held_quantity if hud.held_item != null else 0
	if held_quantity + output_quantity > stack_limit:
		return

	var result: Array = crafting_bench.craft_once()
	if result.is_empty():
		return
	if hud.held_item == null:
		hud.held_item = result[0]
		hud.held_quantity = result[1]
		hud.held_durability = result[2] if result.size() > 2 else 0
		hud.held_source = self
	else:
		hud.held_quantity += result[1]
	_update_grabbed_slot()

func _craft_all_into_inventory() -> void:
	while true:
		var recipe := crafting_bench.current_recipe
		if recipe == null or recipe.output_items.is_empty():
			return
		var output_item: Item = recipe.output_items[0]
		var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
		var target := _find_transfer_target(output_item)
		if target == null or target.inventory.get_item_capacity(output_item) < output_quantity:
			return
		var result: Array = crafting_bench.craft_once()
		if result.is_empty():
			return
		target.inventory.add_item(result[0], result[1], result[2] if result.size() > 2 else -1)

## The base implementation moves the hovered slot's *existing* stock via
## Hotbar.move_item_from(), which reaches straight into the source
## inventory's arrays -- bypassing CraftingBenchInventory's OUTPUT_SLOT
## guards entirely. Since OUTPUT_SLOT never holds real stock, that let a
## hotbar-key press "move" the preview into the hotbar for free without ever
## calling craft_once(), a straight item duplication bug. Route it through a
## real craft instead, same as a click.
func _try_move_hovered_item_to_hotbar(event: InputEvent) -> bool:
	if hovered_slot_index != CraftingBenchInventory.OUTPUT_SLOT:
		return super._try_move_hovered_item_to_hotbar(event)
	if not visible or not inventory_panel.visible:
		return false
	if not inventory_panel.get_global_rect().has_point(get_global_mouse_position()):
		return false
	for index in Hotbar.SLOT_COUNT:
		if event.is_action_pressed(&"hotbar_%d" % (index + 1)):
			if _craft_into_hotbar_slot(index):
				get_viewport().set_input_as_handled()
				return true
			return false
	return false

func _craft_into_hotbar_slot(target_slot_index: int) -> bool:
	var recipe := crafting_bench.current_recipe
	if recipe == null or recipe.output_items.is_empty():
		return false
	var output_item: Item = recipe.output_items[0]
	var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	if not hud.hotbar.call("can_accept_crafted_item", output_item, output_quantity, target_slot_index):
		return false

	var result: Array = crafting_bench.craft_once()
	if result.is_empty():
		return false
	var durability: int = result[2] if result.size() > 2 else 0
	hud.hotbar.call("add_crafted_item", result[0], result[1], durability, target_slot_index)
	return true
