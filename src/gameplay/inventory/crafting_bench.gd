extends InteractableContainer
class_name CraftingBench
## Whichever assigned recipe's shape matches the current 3x3 grid (see
## ShapedCraftingRecipe.shape/matches_shape) shows a live preview in the output
## slot, but nothing is consumed until the player actually takes it --
## CraftingBenchPanel is the one that calls craft_once() (single take) or
## repeatedly (shift-take), see its _craft_into_hand()/_craft_all_into_inventory().
## The grid itself just sits there like a normal inventory otherwise.

@onready var inventory: CraftingBenchInventory = $Inventory

var recipes: Array[ShapedCraftingRecipe] = []

signal state_changed

var current_recipe: ShapedCraftingRecipe

func _ready() -> void:
	super._ready()
	recipes = RecipeDatabase.crafting_recipes
	inventory.on_inventory_changed.connect(_on_inventory_changed)

func _on_opened(hud: HUD) -> void:
	hud.crafting_bench_panel.open_for_bench(self)

func _on_closed(hud: HUD) -> void:
	hud.crafting_bench_panel.close_inventory()

## The bench's sprite is a plain static Sprite2D (see interactable_container.gd)
## with no separate open/closed frame, so there's nothing to swap.
func _update_visual() -> void:
	pass

func _on_inventory_changed() -> void:
	current_recipe = _find_matching_recipe()
	_update_output_preview()
	state_changed.emit()

func _find_matching_recipe() -> ShapedCraftingRecipe:
	for recipe in recipes:
		if recipe != null and recipe.matches_shape(inventory.items):
			return recipe
	return null

## The output slot never holds real stock -- it always mirrors whatever the
## currently matched recipe would produce, purely for display. Writing it
## directly (not through place_item) is safe here since nothing else is
## allowed to write to OUTPUT_SLOT (see CraftingBenchInventory).
func _update_output_preview() -> void:
	if current_recipe == null or current_recipe.output_items.is_empty():
		inventory.items[CraftingBenchInventory.OUTPUT_SLOT] = null
		inventory.quantities[CraftingBenchInventory.OUTPUT_SLOT] = 0
	else:
		inventory.items[CraftingBenchInventory.OUTPUT_SLOT] = current_recipe.output_items[0]
		inventory.quantities[CraftingBenchInventory.OUTPUT_SLOT] = current_recipe.output_quantities[0] if not current_recipe.output_quantities.is_empty() else 1

## Consumes 1 of every currently-occupied grid slot (matches_shape guarantees
## a match never leaves anything in the grid outside the recipe's shape, so
## every occupied cell belongs to it) and returns [output_item,
## output_quantity, output_durability] (full durability for a tool, 0
## otherwise -- same rule Inventory.add_item/place_item use for any other
## freshly-created stack), or an empty array if nothing matches right now.
## Doesn't decide where the crafted item goes -- that's the panel's job.
func craft_once() -> Array:
	var recipe := current_recipe
	if recipe == null or recipe.output_items.is_empty():
		return []

	for i in CraftingBenchInventory.GRID_SIZE:
		if inventory.items[i] != null:
			inventory.remove_item(i, 1)

	var output_item: Item = recipe.output_items[0]
	var output_quantity: int = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	var output_durability: int = inventory._max_durability(output_item)
	_grant_experience(recipe)
	return [output_item, output_quantity, output_durability]

func _grant_experience(recipe: ShapedCraftingRecipe) -> void:
	var skills_manager := _find_skills_manager()
	if skills_manager:
		skills_manager.grant_experience(recipe.skill_type, recipe.experience_gain)

func _find_skills_manager() -> SkillsManager:
	var main_game: MainGame = get_tree().current_scene as MainGame
	if main_game == null or main_game.player == null:
		return null
	return main_game.player.skills_manager

func get_save_data() -> Dictionary:
	return SaveSerializationUtils.serialize_inventory(inventory.items, inventory.quantities, inventory.durabilities)

func apply_save_data(data: Dictionary) -> void:
	SaveSerializationUtils.apply_inventory(inventory, data)
