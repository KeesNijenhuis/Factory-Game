extends Resource
class_name OreVeinRule
## One ore's spawn settings for a single level -- how many veins of it to
## place and how big each one grows. Kept separate from OreType so the same
## ore identity can spawn at different rates/sizes on different levels.

@export var ore_type: OreType
@export var vein_count: int = 5
@export var vein_size: int = 6
