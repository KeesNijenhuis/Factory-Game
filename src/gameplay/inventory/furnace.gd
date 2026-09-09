extends InteractableContainer
class_name Furnace
## Smelts an input item + fuel into an output item over time, following
## whichever assigned recipe matches the current input. Fuel is consumed as a
## single burn-time reserve (item.smelt_count * recipe.craft_time seconds,
## loaded one fuel unit at a time); the furnace keeps smelting off that
## reserve even once the item is gone from the fuel slot, only pulling a new
## unit once it runs dry. Progress/burn-time state lives here (per-instance),
## never on the shared Item resources themselves.

@onready var inventory: FurnaceInventory = $Inventory
@onready var point_light: PointLight2D = $PointLight2D
@onready var ore_input_slot: ItemInputSlotComponent = $OreInputSlot
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
	recipes = RecipeDatabase.smelting_recipes
	inventory.on_inventory_changed.connect(_on_inventory_changed)

func _process(delta: float) -> void:
	super._process(delta)
	_update_smelting(delta)

func _on_opened(hud: HUD) -> void:
	hud.furnace_panel.open_for_furnace(self)

func _on_closed(hud: HUD) -> void:
	hud.furnace_panel.close_inventory()

## The furnace's lit/unlit look is driven by whether it's actively smelting,
## not by whether its panel happens to be open.
func _update_visual() -> void:
	pass

func _on_inventory_changed() -> void:
	current_recipe = _find_matching_recipe()
	if current_recipe == null:
		smelt_progress = 0.0
	state_changed.emit()

## Only checks the input slot and output room. Fuel slot contents deliberately
## don't factor in here: once a fuel unit is loaded (see _load_fuel), the burn
## reserve keeps a craft going even after that item is gone from the slot, so
## matching can't depend on the slot still holding fuel.
func _find_matching_recipe() -> SmeltingRecipe:
	var input_item: Item = inventory.items[FurnaceInventory.INPUT_SLOT]
	if input_item == null:
		return null
	for recipe in recipes:
		if recipe == null or recipe.input_items.is_empty() or recipe.input_items[0] != input_item:
			continue
		var needed: int = recipe.input_quantities[0] if not recipe.input_quantities.is_empty() else 1
		if inventory.quantities[FurnaceInventory.INPUT_SLOT] < needed:
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
	var current_output: Item = inventory.items[FurnaceInventory.OUTPUT_SLOT]
	if current_output != null and current_output != output_item:
		return false
	var current_quantity: int = inventory.quantities[FurnaceInventory.OUTPUT_SLOT] if current_output != null else 0
	return current_quantity + output_quantity <= maxi(output_item.max_stack_size, 1)

func _update_smelting(delta: float) -> void:
	# Captured locally: remove_item() below emits on_inventory_changed, which
	# reenters _on_inventory_changed() and can reassign the current_recipe
	# member before this function is done using it.
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
		var input_quantity: int = recipe.input_quantities[0] if not recipe.input_quantities.is_empty() else 1
		inventory.remove_item(FurnaceInventory.INPUT_SLOT, input_quantity)
		var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
		if inventory.items[FurnaceInventory.OUTPUT_SLOT] == null:
			inventory.items[FurnaceInventory.OUTPUT_SLOT] = recipe.output_items[0]
		inventory.quantities[FurnaceInventory.OUTPUT_SLOT] += output_quantity
		_grant_experience(recipe)
		inventory.on_inventory_changed.emit()
		return

	if fuel_burn_time_remaining <= 0.0:
		# Reservoir ran dry before a craft finished (idle burn ate into it);
		# abandon any in-flight progress rather than forcing the craft through.
		smelt_progress = 0.0

	state_changed.emit()

## Pulls 1 fuel item from the slot immediately and grants it smelt_count *
## recipe.craft_time seconds of burn time. Returns false (and does nothing)
## if there's no fuel available to load.
func _load_fuel(recipe: SmeltingRecipe) -> bool:
	var fuel_item: Item = inventory.items[FurnaceInventory.FUEL_SLOT]
	if fuel_item == null or inventory.quantities[FurnaceInventory.FUEL_SLOT] <= 0:
		return false
	inventory.remove_item(FurnaceInventory.FUEL_SLOT, 1)
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
