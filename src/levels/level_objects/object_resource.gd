extends Sprite2D
class_name ObjectResource

const ACTION_DENIED_SCENE: PackedScene = preload("res://src/levels/level_objects/components/action_denied_indicator.tscn")

@onready var hit_box: HitBox = $HitBox
@onready var durability_component: DurabilityComponent = $DurabilityComponent
@onready var experience_component: ExperienceComponent = get_node_or_null("ExperienceComponent")
## Optional, same as experience_component -- only ore_node.tscn (so far) opts
## into the white hit-flash DestructibleComponent's placed objects already
## use, by having a HitFlashComponent child. Trees keep their existing
## shake-only reaction, matching how experience_component is skill-specific
## rather than assumed for every resource node.
@onready var hit_flash_component: HitFlashComponent = get_node_or_null("HitFlashComponent")

@export var dropped_item_data: Item
@export var empty_node: Sprite2D
@export var respawn_time: float = 3.0
@export var item_drop_delay: float = 0.2
## Whether this instance registers itself into the "saveable" group for
## SaveManager's whole-level scan. Default true preserves today's behavior
## for hand-authored/scattered ore nodes (OreNodeGenerator). CaveBuilder
## sets this false right after instantiating an ore node in a chunk-streamed
## level -- CaveChunkStreamer captures/restores this instance's state itself
## instead, scoped per chunk (see CaveWallsLayer.self_register_saveable for
## the full reasoning).
@export var self_register_saveable: bool = true

var depleted: bool = false
var _save_id: String = ""

func _ready() -> void:
	hit_box.hit_telegraphed.connect(_on_hit_telegraphed)
	hit_box.on_hit.connect(_on_hit)
	if hit_flash_component:
		hit_box.hit_flash.connect(_on_hit_flash)
	durability_component.max_durability_reached.connect(_on_max_durability_reached)
	empty_node.visible = false
	_save_id = SaveSerializationUtils.compute_tile_object_id(self)
	if self_register_saveable and _save_id != "":
		add_to_group("saveable")

func get_save_id() -> String:
	return _save_id

func get_save_data() -> Dictionary:
	return {"depleted": depleted, "accumulated_damage": durability_component.accumulated_damage}

func apply_save_data(data: Dictionary) -> void:
	durability_component.accumulated_damage = data.get("accumulated_damage", 0)
	if data.get("depleted", false) and not depleted:
		depleted = true
		start_respawn_timer()

## Plays the shake immediately when the swing starts, instead of waiting for it to land.
func _on_hit_telegraphed() -> void:
	if depleted:
		return
	await get_tree().create_timer(0.2).timeout
	material.set_shader_parameter("shake_intensity", 0.8)
	await get_tree().create_timer(0.1).timeout
	material.set_shader_parameter("shake_intensity", 0.0)

func _on_hit_flash() -> void:
	if depleted:
		return
	hit_flash_component.flash(self)

func _on_hit(damage: int) -> void:
	if depleted:
		return
	durability_component.damage(damage)

func _on_max_durability_reached() -> void:
	if depleted:
		return
	depleted = true
	grant_experience()
	call_deferred("drop_item")
	start_respawn_timer()

func grant_experience() -> void:
	if experience_component == null:
		return
	EventBus.object_depleted.emit(experience_component.skill_type, experience_component.experience_amount)

## Called by Player when it attempts to use a tool against this object without
## meeting the tool's required skill level.
func show_action_denied() -> void:
	add_child(ACTION_DENIED_SCENE.instantiate())

func start_respawn_timer() -> void:
	self_modulate.a = 0
	empty_node.visible = true
	await get_tree().create_timer(respawn_time).timeout
	self_modulate.a = 1
	empty_node.visible = false
	durability_component.reset_damage()
	depleted = false

func drop_item() -> void:
	await get_tree().create_timer(item_drop_delay).timeout
	var entity_root: Node2D = get_tree().current_scene.get_node("%EntityRoot")
	var item_instance := GroundItem.spawn(entity_root, dropped_item_data, 1, global_position + Vector2(0, 4))
	item_instance.z_index = 1
