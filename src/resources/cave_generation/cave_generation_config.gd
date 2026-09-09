extends Resource
class_name CaveGenerationConfig
## Inspector-editable, saveable-as-.tres configuration for CaveGenerator.
## Every field here is read explicitly by CaveGenerator -- nothing about
## cave shape/content lives on a node's own exports -- so the same config
## can be reused across debug views, CaveBuilder instances, and the
## reproducibility check (see tools/cave_gen_reproducibility_check.gd).

enum RoomConnectionStrategy { MST, SEQUENTIAL_NEAREST_NEIGHBOR }

@export_group("Map")
@export var map_width: int = 96
@export var map_height: int = 64
## 0 = randomize a new seed each generation. Any other value is used as-is
## (see CaveGenerator.generate()).
@export var seed: int = 0

@export_group("Rooms & Corridors")
@export var room_count: int = 8
@export var room_placement_attempts: int = 20
@export var room_radius_min: float = 3.0
@export var room_radius_max: float = 7.0
@export var room_min_separation: float = 3.0
@export_range(0.0, 1.0) var room_roughness: float = 0.35
@export var room_boundary_samples: int = 16
@export var corridor_width: int = 2
@export_range(0.0, 1.0) var corridor_momentum: float = 0.7
@export var corridor_max_turn_degrees: float = 35.0
@export var corridor_step_length: int = 1
@export var room_connection_strategy: RoomConnectionStrategy = RoomConnectionStrategy.MST
@export_range(0.0, 1.0) var extra_loop_connection_chance: float = 0.15

@export_group("Connectivity")
@export var ca_smoothing_iterations: int = 2
## Out of 8 neighbors -- out-of-bounds neighbors always count as WALL, so
## this also seals the map edges.
@export var ca_wall_threshold: int = 5
@export var prune_min_pocket_size: int = 12
@export var reconnect_larger_pockets: bool = true
@export_range(0.0, 1.0) var min_reachable_floor_ratio: float = 0.85
@export var max_generation_retries: int = 5

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
@export var pool_size_min: int = 6
@export var pool_size_max: int = 20
## 0 = snaking random-walk growth, 1 = rounder flood-fill-like growth.
@export_range(0.0, 1.0) var pool_walk_bias: float = 0.5
@export var min_distance_from_entrance: float = 10.0
@export var min_distance_between_pools: float = 8.0
