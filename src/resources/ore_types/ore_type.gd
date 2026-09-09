extends Resource
class_name OreType
## Shared identity for one ore (copper, iron, gold, ...) -- what it looks like
## and what it drops. Reusable across any number of levels; how many veins of
## it spawn is a separate, per-level concern (see OreVeinRule).

@export var ore_name: String = ""
@export var dropped_item: Item
## Column in the shared Wall_*_Overlay / Base_Wall_*_Overlay atlas rows where
## this ore's mirrored block starts (0 = copper, 12 = iron, 24 = gold, ...).
@export var column_offset: int = 0
@export var fallback_source_id: int = -1
## Atlas coords of this ore's "fully enclosed" fallback icons in
## fallback_source_id -- one is picked at random per fully-enclosed cell.
@export var fallback_variants: Array[Vector2i] = []
