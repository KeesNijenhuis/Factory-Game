extends Resource
class_name SmeltingRecipe
## Data for a single furnace smelt: what it consumes, what it produces, and
## what it costs to make. Input/output use parallel arrays (matching
## Inventory's items/quantities convention) rather than a Dictionary.

## Defaults to one empty slot so a freshly created recipe already has an
## input to drag an item onto, instead of starting with none.
@export var input_items: Array[Item] = [null]
@export var input_quantities: Array[int] = [1]
@export var output_items: Array[Item] = []
@export var output_quantities: Array[int] = []
@export var skill_type: Skill.Type
@export var experience_gain: int
@export var level_requirement: int = 1
## Seconds to smelt; drives Furnace's smelt progress.
@export var craft_time: float = 4.0

## Whether the given parallel item/quantity arrays contain enough of every
## input this recipe needs. Each input_items entry must be satisfiable by its
## own distinct slot (found via get_input_slot_assignment) -- so a recipe
## asking for the same item twice (e.g. 2x iron ingot for steel) needs that
## item present in two separate slots, not just stacked 2-deep in one.
func matches_inputs(items: Array, quantities: Array) -> bool:
	return get_input_slot_assignment(items, quantities) != null

## Assigns each input_items entry to a distinct slot index (into the given
## items/quantities arrays) that alone holds enough of the needed item, trying
## every free slot per entry (so ingredients can still land in any slot,
## order-independently). Returns null if no such assignment exists, otherwise
## a Dictionary of {input_items index: slot index} covering every entry that
## needed an item (entries with a null item/zero quantity are omitted).
func get_input_slot_assignment(items: Array, quantities: Array) -> Variant:
	var used_slots := {}
	var assignment := {}
	if _assign_input_slot(0, items, quantities, used_slots, assignment):
		return assignment
	return null

func _assign_input_slot(entry_index: int, items: Array, quantities: Array, used_slots: Dictionary, assignment: Dictionary) -> bool:
	if entry_index >= input_items.size():
		return true
	var needed_item: Item = input_items[entry_index]
	var needed_quantity: int = input_quantities[entry_index] if entry_index < input_quantities.size() else 1
	if needed_item == null or needed_quantity <= 0:
		return _assign_input_slot(entry_index + 1, items, quantities, used_slots, assignment)
	for slot_index in items.size():
		if used_slots.has(slot_index):
			continue
		if items[slot_index] != needed_item:
			continue
		var slot_quantity: int = quantities[slot_index] if slot_index < quantities.size() else 0
		if slot_quantity < needed_quantity:
			continue
		used_slots[slot_index] = true
		assignment[entry_index] = slot_index
		if _assign_input_slot(entry_index + 1, items, quantities, used_slots, assignment):
			return true
		used_slots.erase(slot_index)
		assignment.erase(entry_index)
	return false
