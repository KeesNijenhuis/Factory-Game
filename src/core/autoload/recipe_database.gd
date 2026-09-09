extends Node
## Autoload. Loads both recipe databases once at startup and exposes their
## recipe arrays -- the CraftingBench/Furnace lookup source, mirroring
## ItemRegistry's role for Item resources.

const CRAFTING_DB_PATH: String = "res://src/resources/crafting/crafting_recipes.tres"
const SMELTING_DB_PATH: String = "res://src/resources/crafting/smelting_recipes.tres"
const BLAST_FURNACE_DB_PATH: String = "res://src/resources/crafting/blast_furnace_recipes.tres"

var crafting_recipes: Array[ShapedCraftingRecipe] = []
var smelting_recipes: Array[SmeltingRecipe] = []
var blast_furnace_recipes: Array[SmeltingRecipe] = []

func _ready() -> void:
	var crafting_db := ResourceLoader.load(CRAFTING_DB_PATH) as CraftingRecipeDatabase
	if crafting_db:
		crafting_recipes = crafting_db.recipes
	else:
		push_warning("RecipeDatabase: could not load " + CRAFTING_DB_PATH)

	var smelting_db := ResourceLoader.load(SMELTING_DB_PATH) as SmeltingRecipeDatabase
	if smelting_db:
		smelting_recipes = smelting_db.recipes
	else:
		push_warning("RecipeDatabase: could not load " + SMELTING_DB_PATH)

	var blast_furnace_db := ResourceLoader.load(BLAST_FURNACE_DB_PATH) as SmeltingRecipeDatabase
	if blast_furnace_db:
		blast_furnace_recipes = blast_furnace_db.recipes
	else:
		push_warning("RecipeDatabase: could not load " + BLAST_FURNACE_DB_PATH)
