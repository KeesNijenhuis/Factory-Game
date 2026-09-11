extends Resource
class_name CaveGenerationConfig
## Inspector-editable, saveable-as-.tres configuration for CaveGenerator.
## Every field here is read explicitly by CaveGenerator's world-space chunk
## generator -- nothing about cave shape/content lives on a node's own
## exports -- so the same config can be reused across debug views,
## CaveBuilder instances, and the reproducibility check (see
## tools/cave_chunk_gen_reproducibility_check.gd).

@export_group("Map")
@export var map_width: int = 96
@export var map_height: int = 64

@export_group("Rooms & Corridors")
@export var room_count: int = 8
@export var room_radius_min: float = 3.0
@export var room_radius_max: float = 7.0
@export_range(0.0, 1.0) var room_roughness: float = 0.35
@export var corridor_width: int = 2
@export var corridor_max_turn_degrees: float = 35.0

@export_group("Ore")
@export var ore_veins: Array[CaveOreVeinConfig] = []

@export_group("Ore Nodes")
@export var ore_node_rules: Array[CaveOreNodeConfig] = []
@export var ore_node_total_count: int = 15
@export var ore_node_min_separation: float = 3.0

@export_group("Water & Lava")
@export var enable_water: bool = true
## Off by default -- CaveBuilder doesn't paint lava art yet (see
## CaveBuilder's doc comment), so leaving this on would spawn invisible
## hazards.
@export var enable_lava: bool = false
@export var water_pool_count: int = 3
@export var lava_pool_count: int = 1
