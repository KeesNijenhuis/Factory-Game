extends Resource
class_name OreNodeSpawnRule
## One ore's spawn settings for a single level -- how many of its floor nodes
## to scatter. Kept separate from OreNodeType so the same ore identity can
## spawn at different rates on different levels.

@export var node_type: OreNodeType
@export var count: int = 10
