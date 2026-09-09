extends Resource
class_name CraftingRecipeDatabase
## A single file holding every crafting-bench recipe in the game. Authored
## via the Recipe Editor addon (addons/recipe_editor); RecipeDatabase
## (autoload) loads this at runtime for CraftingBench to consume.

@export var recipes: Array[ShapedCraftingRecipe] = []
