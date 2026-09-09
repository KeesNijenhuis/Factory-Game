extends Resource
class_name CaveOreVeinConfig
## One wall ore vein's noise settings for a single CaveGenerationConfig.
## ore_slot picks which fixed CaveData.TileType this vein targets --
## GDScript enums are static, so this is the indirection that lets the
## Inspector-editable ore_veins list stay freely reorderable/resizable
## without allowing a slot to point at a non-ore TileType (see
## CaveGenerator._generate_ore_veins()). ore_type is the actual resource used
## later by CaveBuilder for overlay art and drop items.

enum OreSlot { COPPER, IRON, GOLD }

@export var ore_slot: OreSlot = OreSlot.COPPER
@export var ore_type: OreType
@export var noise_frequency: float = 0.08
## Accepted noise band is [vein_threshold, vein_threshold + band_width] --
## a bounded window, not "above threshold," is what produces thin banded
## veins instead of solid ore blobs. Simplex noise values cluster near the
## middle of the remapped [0,1] range rather than spreading uniformly, so
## these defaults sit well off-center to keep coverage sparse (~5% of wall
## cells at the defaults below, empirically measured) -- moving the band
## toward 0.5 gets denser fast.
@export_range(0.0, 1.0) var vein_threshold: float = 0.65
@export_range(0.0, 1.0) var band_width: float = 0.03
## Added to the attempt seed before seeding this vein's FastNoiseLite, so
## each configured ore gets an independent noise pattern instead of every
## ore following the exact same bands.
@export var seed_offset: int = 0


static func slot_to_tile_type(slot: OreSlot) -> CaveData.TileType:
	match slot:
		OreSlot.COPPER:
			return CaveData.TileType.ORE_COPPER
		OreSlot.IRON:
			return CaveData.TileType.ORE_IRON
		OreSlot.GOLD:
			return CaveData.TileType.ORE_GOLD
	return CaveData.TileType.WALL
