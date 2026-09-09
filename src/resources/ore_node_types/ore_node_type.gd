extends Resource
class_name OreNodeType
## Shared identity for one ore's floor node (copper, iron, gold, ...) -- which
## scene to instantiate. Reusable across any number of levels; how many spawn
## is a separate, per-level concern (see OreNodeSpawnRule).

@export var ore_name: String = ""
@export var scene: PackedScene
