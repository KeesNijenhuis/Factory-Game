extends InteractableContainer
class_name BlastFurnace
## A bigger (2x2), dual-input Furnace: smelts two different ingredients +
## fuel into an output item, following whichever assigned recipe matches the
## current inputs. Structurally mirrors Furnace (fuel-burn reservoir, save/
## load, panel wiring) but everything that touches "the input slot" becomes
## "both input slots," matched order-independently via
## SmeltingRecipe.matches_inputs() -- written generically for N inputs, but
## never exercised by the single-input Furnace, which only ever reads index 0.

@onready var inventory: BlastFurnaceInventory = $Inventory
@onready var point_light: PointLight2D = $PointLight2D
@onready var input_a_slot: ItemInputSlotComponent = $InputASlot
@onready var input_b_slot: ItemInputSlotComponent = $InputBSlot
@onready var solid_fuel_input_slot: SolidFuelInputSlotComponent = $SolidFuelInputSlot
@onready var output_slot: ItemOutputSlotComponent = $OutputSlot

var recipes: Array[SmeltingRecipe] = []

signal state_changed

var current_recipe: SmeltingRecipe
var smelt_progress: float = 0.0
## Burn-seconds left in the currently loaded fuel, drained directly by delta
## every frame the furnace is burning (see _update_smelting) -- whether or
## not there's an active craft, so the fuel bar never jumps when input is
## added/removed mid-burn. This is the actual state, not a display cache.
var fuel_burn_time_remaining: float = 0.0
## Burn-seconds granted by the fuel unit currently loaded (item.smelt_count *
## the recipe's craft_time at load time). Only used as the UI bar's max;
## unchanged until the next unit is loaded.
var fuel_burn_time_max: float = 0.0

func _ready() -> void:
	super._ready()
	recipes = RecipeDatabase.blast_furnace_recipes
	inventory.on_inventory_changed.connect(_on_inventory_changed)

func _process(delta: float) -> void:
	super._process(delta)
	_update_smelting(delta)

func _on_opened(hud: HUD) -> void:
	hud.blast_furnace_panel.open_for_furnace(self)

func _on_closed(hud: HUD) -> void:
	hud.blast_furnace_panel.close_inventory()

## The furnace's lit/unlit look is driven by whether it's actively smelting,
## not by whether its panel happens to be open.
func _update_visual() -> void:
	pass

func _on_inventory_changed() -> void:
	current_recipe = _find_matching_recipe()
	if current_recipe == null:
		smelt_progress = 0.0
	state_changed.emit()

## Order-independent: either ingredient can sit in either input slot.
## Fuel slot contents deliberately don't factor in here: once a fuel unit is
## loaded (see _load_fuel), the burn reserve keeps a craft going even after
## that item is gone from the slot, so matching can't depend on the slot
## still holding fuel.
func _find_matching_recipe() -> SmeltingRecipe:
	var input_items := [inventory.items[BlastFurnaceInventory.INPUT_A_SLOT], inventory.items[BlastFurnaceInventory.INPUT_B_SLOT]]
	if input_items[0] == null and input_items[1] == null:
		return null
	var input_quantities := [inventory.quantities[BlastFurnaceInventory.INPUT_A_SLOT], inventory.quantities[BlastFurnaceInventory.INPUT_B_SLOT]]
	for recipe in recipes:
		if recipe == null or recipe.input_items.is_empty():
			continue
		if not recipe.matches_inputs(input_items, input_quantities):
			continue
		if not _output_has_room(recipe):
			continue
		return recipe
	return null

func _output_has_room(recipe: SmeltingRecipe) -> bool:
	if recipe.output_items.is_empty():
		return false
	var output_item: Item = recipe.output_items[0]
	var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	var current_output: Item = inventory.items[BlastFurnaceInventory.OUTPUT_SLOT]
	if current_output != null and current_output != output_item:
		return false
	var current_quantity: int = inventory.quantities[BlastFurnaceInventory.OUTPUT_SLOT] if current_output != null else 0
	return current_quantity + output_quantity <= maxi(output_item.max_stack_size, 1)

func _update_smelting(delta: float) -> void:
	# Captured locally: remove_item() below (via _consume_input) emits
	# on_inventory_changed, which reenters _on_inventory_changed() and can
	# reassign current_recipe before this function is done using it.
	var recipe := current_recipe

	if fuel_burn_time_remaining <= 0.0 and (recipe == null or not _load_fuel(recipe)):
		# Well and truly out of fuel: nothing left to burn, whether or not
		# there's something to smelt.
		smelt_progress = 0.0
		fuel_burn_time_remaining = 0.0
		fuel_burn_time_max = 0.0
		sprite.call("play", &"idle")
		point_light.visible = false
		return

	sprite.call("play", &"burning")
	point_light.visible = true

	# fuel_burn_time_remaining always drains -- whether idling or actively
	# smelting -- so the loaded fuel keeps burning away regardless of whether
	# there's something to smelt right now. smelt_progress only advances
	# while there's a craft to work toward. Both are driven by the identical
	# delta stream, so a full craft's worth of fuel and a full craft's worth
	# of progress reach their thresholds in the same frame -- no drift.
	fuel_burn_time_remaining = maxf(fuel_burn_time_remaining - delta, 0.0)
	if recipe != null:
		smelt_progress += delta

	if recipe != null and smelt_progress >= recipe.craft_time:
		smelt_progress -= recipe.craft_time
		for i in recipe.input_items.size():
			var needed_item: Item = recipe.input_items[i]
			var needed_quantity: int = recipe.input_quantities[i] if i < recipe.input_quantities.size() else 1
			if needed_item != null and needed_quantity > 0:
				_consume_input(needed_item, needed_quantity)
		var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
		if inventory.items[BlastFurnaceInventory.OUTPUT_SLOT] == null:
			inventory.items[BlastFurnaceInventory.OUTPUT_SLOT] = recipe.output_items[0]
		inventory.quantities[BlastFurnaceInventory.OUTPUT_SLOT] += output_quantity
		_grant_experience(recipe)
		inventory.on_inventory_changed.emit()
		return

	if fuel_burn_time_remaining <= 0.0:
		# Reservoir ran dry before a craft finished (idle burn ate into it);
		# abandon any in-flight progress rather than forcing the craft through.
		smelt_progress = 0.0

	state_changed.emit()

## Removes quantity of item from wherever it's sitting across the two input
## slots (it may be split across both, or entirely in one) -- matches_inputs()
## only checks sufficiency across both slots combined, so consumption has to
## scan the same way rather than assuming a fixed slot per ingredient.
func _consume_input(item: Item, quantity: int) -> void:
	var remaining := quantity
	for slot_index in [BlastFurnaceInventory.INPUT_A_SLOT, BlastFurnaceInventory.INPUT_B_SLOT]:
		if remaining <= 0:
			return
		if inventory.items[slot_index] != item:
			continue
		var take := mini(remaining, inventory.quantities[slot_index])
		inventory.remove_item(slot_index, take)
		remaining -= take

## Pulls 1 fuel item from the slot immediately and grants it smelt_count *
## recipe.craft_time seconds of burn time. Returns false (and does nothing)
## if there's no fuel available to load.
func _load_fuel(recipe: SmeltingRecipe) -> bool:
	var fuel_item: Item = inventory.items[BlastFurnaceInventory.FUEL_SLOT]
	if fuel_item == null or inventory.quantities[BlastFurnaceInventory.FUEL_SLOT] <= 0:
		return false
	inventory.remove_item(BlastFurnaceInventory.FUEL_SLOT, 1)
	fuel_burn_time_max = maxi(fuel_item.smelt_count, 1) * maxf(recipe.craft_time, 0.001)
	fuel_burn_time_remaining = fuel_burn_time_max
	return true

func _grant_experience(recipe: SmeltingRecipe) -> void:
	var skills_manager := _find_skills_manager()
	if skills_manager:
		skills_manager.grant_experience(recipe.skill_type, recipe.experience_gain)

func _find_skills_manager() -> SkillsManager:
	var main_game: MainGame = get_tree().current_scene as MainGame
	if main_game == null or main_game.player == null:
		return null
	return main_game.player.skills_manager

func get_save_data() -> Dictionary:
	var data := SaveSerializationUtils.serialize_inventory(inventory.items, inventory.quantities, inventory.durabilities)
	data["smelt_progress"] = smelt_progress
	data["fuel_burn_time_remaining"] = fuel_burn_time_remaining
	data["fuel_burn_time_max"] = fuel_burn_time_max
	data["slot_facings"] = AutomationUtils.get_slot_facings(self)
	return data

func apply_save_data(data: Dictionary) -> void:
	SaveSerializationUtils.apply_inventory(inventory, data)
	smelt_progress = data.get("smelt_progress", 0.0)
	fuel_burn_time_remaining = data.get("fuel_burn_time_remaining", 0.0)
	fuel_burn_time_max = data.get("fuel_burn_time_max", 0.0)
	AutomationUtils.apply_slot_facings(self, data.get("slot_facings", {}))
