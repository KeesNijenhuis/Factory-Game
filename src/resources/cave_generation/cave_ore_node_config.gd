extends Resource
class_name CaveOreNodeConfig
## One pickable floor ore node type's rarity for a single
## CaveGenerationConfig. Reuses the existing OreNodeType identity (the same
## resource the hand-authored level's OreNodeGenerator placeholder uses) --
## only the placement logic is new (seeded + rarity-weighted), not the
## node's scene/identity.

@export var node_type: OreNodeType
## Relative weight against every other configured rule for this level --
## final placement probability for a rule is
## rarity_weight / sum(all configured rarity_weights). E.g. giving gold a
## weight of 1.0 against copper's 5.0 makes gold roughly 6x rarer, without
## having to hand-compute node counts per ore.
@export var rarity_weight: float = 1.0
