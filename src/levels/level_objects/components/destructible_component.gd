extends Node2D
class_name DestructibleComponent
## Drop-in "the right tool destroys this placed object" behavior. Instance
## as a child of any placed-object scene (transport belt, furnace, chest)
## and set required_tool_type/dropped_item -- no changes to the owning
## object's own script are needed. Owns a HitBox+DurabilityComponent pair,
## the same components ObjectResource already uses for trees/ore, so the
## existing HitArea-driven swing system (PlayerStateMining/
## PlayerStateWoodcutting) finds and damages it for free. The white hit-flash
## itself is delegated to a shared HitFlashComponent child, applied to the
## owner's sprite -- the same component ObjectResource's trees/ore optionally
## use, so a swing connecting reads the same way everywhere.
## Unlike ObjectResource's resource nodes, a broken placed object never
## respawns -- it drops dropped_item once and frees its owning node for good.

const ITEM_DROP_DELAY: float = 0.2

@export var required_tool_type: Item.ToolTypes = Item.ToolTypes.Pickaxe
@export var hits_to_break: int = 2
## item_id of the Item spawned as a GroundItem once this object breaks --
## normally the same Item whose placed_scene put this object in the world,
## so destroying it hands the item back. A plain id (resolved through
## ItemRegistry at drop time) rather than a direct Item resource reference,
## since that Item's own placed_scene field points right back at the scene
## this component lives in -- a direct reference here would make the two
## files load each other, which Godot's resource loader can't resolve.
@export var dropped_item_id: String = ""

@onready var hit_box: HitBox = $HitBox
@onready var durability_component: DurabilityComponent = $DurabilityComponent
@onready var hit_flash_component: HitFlashComponent = $HitFlashComponent

## True once max_durability_reached has fired -- guards against a swing that
## lands (or a still-pending telegraph) during the drop delay from
## re-triggering the flash/break sequence on a node that's about to free.
var _broken: bool = false

func _ready() -> void:
	hit_box.tool_type = required_tool_type
	durability_component.durability = hits_to_break
	hit_box.hit_flash.connect(_on_hit_flash)
	hit_box.on_hit.connect(_on_hit)
	durability_component.max_durability_reached.connect(_on_broken)

func _on_hit_flash() -> void:
	if _broken:
		return
	hit_flash_component.flash(_find_sprite())

func _on_hit(damage: int) -> void:
	if _broken:
		return
	durability_component.damage(damage)

func _on_broken() -> void:
	if _broken:
		return
	_broken = true
	var owner_node := get_parent()
	call_deferred("_drop_and_free", owner_node, owner_node.global_position)

func _drop_and_free(owner_node: Node2D, drop_position: Vector2) -> void:
	await get_tree().create_timer(ITEM_DROP_DELAY).timeout
	var dropped_item: Item = ItemRegistry.get_item(dropped_item_id) if dropped_item_id != "" else null
	if dropped_item:
		var entity_root: Node2D = get_tree().current_scene.get_node("%EntityRoot")
		var item_instance := GroundItem.spawn(entity_root, dropped_item, 1, drop_position)
		item_instance.z_index = 1
		item_instance.scale = Vector2(0.5, 0.5)
	owner_node.queue_free()

func _find_sprite() -> CanvasItem:
	var owner_node := get_parent()
	for child_name in [&"AnimatedSprite2D", &"Sprite2D"]:
		var sprite := owner_node.get_node_or_null(NodePath(child_name)) as CanvasItem
		if sprite:
			return sprite
	return null
