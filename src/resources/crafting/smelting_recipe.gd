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
## input this recipe needs (extra unrelated items in the arrays are ignored).
func matches_inputs(items: Array, quantities: Array) -> bool:
	for i in input_items.size():
		var needed_item: Item = input_items[i]
		var needed_quantity: int = input_quantities[i] if i < input_quantities.size() else 0
		if needed_item == null or needed_quantity <= 0:
			continue
		var available := 0
		for j in items.size():
			if items[j] == needed_item:
				available += quantities[j] if j < quantities.size() else 0
		if available < needed_quantity:
			return false
	return true
