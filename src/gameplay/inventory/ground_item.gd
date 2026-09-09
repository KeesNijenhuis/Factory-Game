extends Area2D
class_name GroundItem

const SCENE: PackedScene = preload("res://src/gameplay/inventory/ground_item.tscn")
const DROPPED_ITEM_PICKUP_DELAY := 5.0

@export var item: Item
@export var quantity: int = 1
## Current durability carried by a dropped tool; -1 means "use the tool's max".
@export var durability: int = -1
@export_range(0.0, 2.0, 0.1) var spawn_randomness: float = 2.0
@export_range(0.0, 4.0, 0.1) var bob_height: float = 1.0
@export_range(0.0, 10.0, 0.1) var bob_speed: float = 3.0
@export_range(0.0, 5.0, 0.1) var pickup_delay: float = 0.2

@onready var item_icon: Sprite2D = $ItemIcon
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var bob_origin: Vector2
var collision_disabled_until: float = 0.0
var _collision_timer_running: bool = false

func _ready() -> void:
	bob_origin = global_position
	_refresh_visuals()
	body_entered.connect(_on_body_entered)
	disable_collision_for(pickup_delay)

func _process(_delta: float) -> void:
	var elapsed_time := Time.get_ticks_msec() / 1000.0
	global_position = bob_origin + Vector2(0.0, sin(elapsed_time * bob_speed) * bob_height)

static func spawn(entity_root: Node2D, item_data: Item, item_quantity: int, spawn_position: Vector2, item_durability: int = -1) -> GroundItem:
	var ground_item: GroundItem = SCENE.instantiate()
	entity_root.add_child(ground_item)
	ground_item.set_spawn_position(spawn_position)
	ground_item.set_item(item_data, item_quantity, item_durability)
	return ground_item

func set_item(item_data: Item, item_quantity: int = 1, item_durability: int = -1) -> void:
	item = item_data
	quantity = item_quantity
	durability = item_durability
	if is_node_ready():
		_refresh_visuals()

func set_spawn_position(base_position: Vector2) -> void:
	bob_origin = base_position + Vector2(
		randf_range(-spawn_randomness, spawn_randomness),
		randf_range(-spawn_randomness, spawn_randomness)
	)
	global_position = bob_origin

## Extends the collision-disabled window; safe to call repeatedly (e.g. once
## from _ready() and again when the item is dropped) since only the first
## call starts the polling loop that eventually re-enables collision -- later
## calls just push collision_disabled_until further out.
func disable_collision_for(duration: float) -> void:
	collision_shape.set_deferred("disabled", true)
	collision_disabled_until = maxf(
		collision_disabled_until,
		Time.get_ticks_msec() / 1000.0 + duration
	)
	if _collision_timer_running:
		return
	_collision_timer_running = true
	while is_inside_tree() and not is_queued_for_deletion():
		var remaining_time := collision_disabled_until - Time.get_ticks_msec() / 1000.0
		if remaining_time <= 0.0:
			collision_shape.set_deferred("disabled", false)
			_collision_timer_running = false
			return
		await get_tree().create_timer(remaining_time).timeout
	_collision_timer_running = false

func _refresh_visuals() -> void:
	item_icon.texture = item.icon if item else null

func _on_body_entered(body: Node2D) -> void:
	if not body is Player or item == null or quantity <= 0:
		return

	var remaining_quantity := quantity
	remaining_quantity -= _fill_existing_inventory_stacks(Inventory, item, remaining_quantity)

	var hud: HUD = get_tree().root.find_child("HudRoot", true, false) as HUD
	if hud:
		var hotbar_inventory: Node = hud.hotbar.get_node("Inventory")
		var hotbar_amount := mini(remaining_quantity, hotbar_inventory.get_item_capacity(item))
		if hotbar_amount > 0 and hotbar_inventory.add_item(item, hotbar_amount, durability):
			remaining_quantity -= hotbar_amount

	var inventory_amount := mini(remaining_quantity, Inventory.get_item_capacity(item))
	if inventory_amount > 0 and Inventory.add_item(item, inventory_amount, durability):
		remaining_quantity -= inventory_amount

	if remaining_quantity < quantity:
		quantity = remaining_quantity
	if remaining_quantity == 0:
		queue_free()

func _fill_existing_inventory_stacks(inventory_data: Node, item_data: Item, amount: int) -> int:
	var remaining_amount := amount
	var moved_amount := 0
	var stack_limit: int = maxi(item_data.max_stack_size, 1)
	for index in inventory_data.items.size():
		if inventory_data.items[index] != item_data or inventory_data.quantities[index] >= stack_limit:
			continue
		var amount_to_move := mini(remaining_amount, stack_limit - inventory_data.quantities[index])
		inventory_data.quantities[index] += amount_to_move
		remaining_amount -= amount_to_move
		moved_amount += amount_to_move
		if remaining_amount == 0:
			break
	if moved_amount > 0:
		inventory_data.on_inventory_changed.emit()
	return moved_amount
