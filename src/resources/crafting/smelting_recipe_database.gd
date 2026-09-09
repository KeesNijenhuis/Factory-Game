extends Resource
class_name SmeltingRecipeDatabase
## A single file holding every furnace/smelting recipe in the game. Authored
## via the Recipe Editor addon (addons/recipe_editor); RecipeDatabase
## (autoload) loads this at runtime for Furnace to consume.

@export var recipes: Array[SmeltingRecipe] = []
