extends CharacterBody2D
class_name Player

@export_group("Player Stats")
@export var move_speed: float = 60.0
@export var move_speed_sprinting: float = 100
## Movement speed while performing any tool/attack action (mining, digging,
## tilling, woodcutting, attacking) — lets the player keep moving, just slower.
@export var move_speed_acting: float = 40
@export var damage: float = 5.0
@export var god_mode: bool = false

@export_group("Dash")
## Peak speed reached partway through the dash.
@export var dash_top_speed: float = 300.0
## How fast the dash ramps up to dash_top_speed (units/sec^2).
@export var dash_acceleration: float = 3000.0
## How fast the dash sheds speed after the peak (units/sec^2). Keep this higher
## than dash_acceleration so the dash snaps back down faster than it ramped up.
@export var dash_deceleration: float = 6000.0
## Max distance the dash can cover; solid objects (not walls) and dug-ground pits are passed through for this range. Default is the width of 4 tiles (16px tiles).
@export var dash_distance: float = 64.0

var dash_direction: Vector2 = Vector2.ZERO

@onready var anim_sprite: AnimatedSprite2D = $AnimSprite
#@onready var health_component: HealthComponent = $HealthComponent
@onready var fsm: FSM = $FSM
@onready var hit_area: HitArea = $HitArea
@onready var weapon: Node2D = $Weapon
@onready var skills_manager: SkillsManager = $SkillsManager
@onready var held_item_sprite: Sprite2D = $HoldItemPos/HeldItemSprite
@onready var placement_controller: PlacementController = $PlacementController
@onready var interaction_controller: InteractionController = $InteractionController
## Ray origin for the mining quadrant/line-of-sight check (InteractionController).
@onready var marker_line_of_sight: Marker2D = $MarkerLineOfSight
@onready var hud: HUD = get_tree().root.find_child("HudRoot", true, false) as HUD

@onready var attack_positions: Dictionary = {
	"down": $AttackPos/Down,
	"up": $AttackPos/Up,
	"right": $AttackPos/Right,
	"left": $AttackPos/Left
}


var last_direction: String = "down"
var current_tool_type: Item.ToolTypes = Item.ToolTypes.None
var current_tool_slot_index: int = -1
var current_tool_item: Item = null
## The hotbar's currently selected item, tool or not. Used to decide whether
## to play the "hold_*" animations (visually carrying a non-tool item).
var current_hotbar_item: Item = null

## The last base animation name passed to play_direction_animation (before any
## "hold_" prefix), so a hotbar switch can immediately replay it.
var last_anim_base: String = "idle"

var interaction_consumed: bool = false

# TEMP debug: spawn with furnace-testing materials. Remove once the furnace is
# confirmed working.
const DEBUG_OAK_LOG: Item = preload("res://src/resources/items/materials/oak_log.tres")
const DEBUG_COPPER_ORE: Item = preload("res://src/resources/items/ores/copper_ore.tres")
# TEMP debug: spawn with placeable stacks for testing the placement system.
# Remove once placement is confirmed working.
const DEBUG_CHEST: Item = preload("res://src/resources/items/placeables/chest.tres")

const DEBUG_FURNACE: Item = preload("res://src/resources/items/placeables/furnace.tres")
const DEBUG_PICKAXE: Item = preload("res://src/resources/items/tools/wood/pickaxe_wood.tres")
const DEBUG_WRENCH: Item = preload("res://src/resources/items/tools/wrench.tres")
const DEBUG_AXE: Item = preload("res://src/resources/items/tools/wood/axe_wood.tres")
const DEBUG_BELT: Item = preload("res://src/resources/items/placeables/transport_belt.tres")
const DEBUG_SHOVEL: Item = preload("res://src/resources/items/tools/wood/shovel_wood.tres")



func _ready() -> void:
	EventBus.hotbar_slot_selected.connect(_on_hotbar_slot_selected)
	hit_area.monitoring = false
	god_mode = true
	var player_inventory := get_node("/root/Inventory")
	player_inventory.add_item(DEBUG_OAK_LOG, DEBUG_OAK_LOG.max_stack_size * 4)
	player_inventory.add_item(DEBUG_COPPER_ORE, DEBUG_COPPER_ORE.max_stack_size * 4)
	player_inventory.add_item(DEBUG_CHEST, DEBUG_CHEST.max_stack_size * 2)
	player_inventory.add_item(DEBUG_FURNACE, DEBUG_FURNACE.max_stack_size * 2)
	if hud:
		# TEMP debug: equip a pickaxe straight into the hotbar on spawn (rather
		# than the backpack, like the other debug items above) so mining can
		# be tested immediately without dragging one over by hand.
		(hud.hotbar as Hotbar).get_node("Inventory").add_item(DEBUG_PICKAXE, 1)
		(hud.hotbar as Hotbar).get_node("Inventory").add_item(DEBUG_WRENCH, 1)
		(hud.hotbar as Hotbar).get_node("Inventory").add_item(DEBUG_AXE, 1)
		(hud.hotbar as Hotbar).get_node("Inventory").add_item(DEBUG_SHOVEL, 1)
		(hud.hotbar as Hotbar).get_node("Inventory").add_item(DEBUG_BELT, 50)
		
		(hud.hotbar as Hotbar).emit_selection()



func _process(_delta: float) -> void:
	interaction_controller.update()
	if not Input.is_action_pressed(&"interact") and not Input.is_action_pressed(&"tool_target_click"):
		interaction_consumed = false
	if not _hit_area_owned_by_action_state():
		update_hit_area()
	set_hit_area_active(Input.is_action_pressed(&"interact") or Input.is_action_pressed(&"tool_target_click"))

## Mining/Woodcutting/Digging/Tilling now position hit_area themselves, off
## the mouse-resolved target rather than the fixed facing marker -- this stops
## the unconditional marker-tracking above from clobbering that position every
## frame those states are active. Attack is untouched: it still wants the
## fixed marker, unchanged.
func _hit_area_owned_by_action_state() -> bool:
	var state: State = fsm.curr_state
	return (state is PlayerStateMining or state is PlayerStateWoodcutting \
		or state is PlayerStateDigging or state is PlayerStateTilling)


func _on_hotbar_slot_selected(slot_index: int, item: Item) -> void:
	var is_tool := item and item.item_type == Item.ItemType.TOOL
	current_tool_type = item.tool_type if is_tool else Item.ToolTypes.None
	current_tool_slot_index = slot_index if is_tool else -1
	current_tool_item = item if is_tool else null
	current_hotbar_item = item
	EventBus.tool_changed.emit(current_tool_type)
	hit_area.needed_tool = current_tool_type
	_emit_tool_durability(item, is_tool)
	_update_held_item_visual()
	# Swap to/from the holding pose immediately, rather than waiting for the
	# next movement-triggered animation change.
	if last_anim_base in HOLDABLE_ANIMATIONS:
		play_direction_animation(last_anim_base)

## Shows the held item's icon at HoldItemPos while a non-tool item is
## selected, and hides it otherwise (tools are drawn by the swing animations
## themselves, not this sprite).
func _update_held_item_visual() -> void:
	held_item_sprite.visible = is_holding_item()
	held_item_sprite.texture = current_hotbar_item.icon if is_holding_item() else null

## Whether the selected hotbar item should be shown in the player's hands
## (anything except a tool, e.g. placeable blocks or materials).
func is_holding_item() -> bool:
	return current_hotbar_item != null and current_hotbar_item.item_type != Item.ItemType.TOOL

## Broadcasts the equipped tool's current/max durability. Also fires whenever
## the hotbar inventory changes (e.g. after damage_equipped_tool breaks a tool),
## since that re-emits hotbar_slot_selected for the currently selected slot.
func _emit_tool_durability(item: Item, is_tool: bool) -> void:
	if not is_tool or item.tool_tier == null:
		EventBus.tool_durability_changed.emit(0, 0)
		return
	var max_durability: int = item.tool_tier.durability
	var current_durability: int = max_durability
	if hud:
		var hotbar_inventory: Node = hud.hotbar.get_node("Inventory")
		if current_tool_slot_index >= 0 and current_tool_slot_index < hotbar_inventory.durabilities.size():
			current_durability = hotbar_inventory.durabilities[current_tool_slot_index]
	EventBus.tool_durability_changed.emit(current_durability, max_durability)

## Wears down the currently equipped tool by one use, destroying it once its
## durability is spent. Called each time a tool-use animation starts.
func damage_equipped_tool() -> void:
	if current_tool_slot_index < 0 or hud == null:
		return
	var hotbar_inventory: Node = hud.hotbar.get_node("Inventory")
	hotbar_inventory.damage_tool(current_tool_slot_index)

## "tool_target_click" is the same left-click used to move inventory items
## around, so clicking a slot would otherwise also be read as a tool swing.
## Only block tool actions while the cursor is actually over an open
## inventory panel, so LMB still works normally for gameplay while a panel
## happens to be open elsewhere.
func is_mouse_over_inventory_panel() -> bool:
	if hud == null:
		return false
	return _panel_contains_mouse(hud.inventory_panel) or _panel_contains_mouse(hud.chest_inventory_panel)

func _panel_contains_mouse(panel: InventoryPanel) -> bool:
	if not panel.inventory_panel.visible:
		return false
	return panel.inventory_panel.get_global_rect().has_point(panel.get_global_mouse_position())

func is_moving() -> bool:
	return Input.is_action_pressed(&"move_down") \
		or Input.is_action_pressed(&"move_right") \
		or Input.is_action_pressed(&"move_left") \
		or Input.is_action_pressed(&"move_up")

func update_direction(input_vector: Vector2) -> void:
	if input_vector == Vector2.ZERO:
		return
	last_direction = vector_to_direction(input_vector)

static func vector_to_direction(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	else:
		return "down" if v.y > 0.0 else "up"

func update_hit_area() -> void:
	var direction_marker: Marker2D = attack_positions.get(last_direction)
	if direction_marker:
		hit_area.global_position = direction_marker.global_position

const ACTION_DENIED_SCENE: PackedScene = preload("res://src/levels/level_objects/components/action_denied_indicator.tscn")

## Flashes a "not allowed" indicator on whatever object the equipped tool is
## currently facing, without dealing damage. Called when a tool swing is
## blocked by an unmet skill level requirement. Falls back to the player's
## active facing marker when nothing is actually in range to hit.
func show_tool_denied_indicator() -> void:
	update_hit_area()
	var hit_boxes := hit_area.get_matching_hit_boxes()
	if hit_boxes.is_empty():
		_show_denied_indicator_on_marker()
		return

	for hit_box in hit_boxes:
		var target: Node = hit_box.get_parent()
		if target and target.has_method("show_action_denied"):
			target.show_action_denied()

func _show_denied_indicator_on_marker() -> void:
	var direction_marker: Marker2D = attack_positions.get(last_direction)
	if direction_marker:
		# AttackPos (the markers' parent) has visible = false since it only
		# exists to hold reference positions, which would hide the indicator
		# if parented directly under the marker. Parent it to the player
		# instead and just borrow the marker's position.
		var indicator: Node2D = ACTION_DENIED_SCENE.instantiate()
		add_child(indicator)
		indicator.global_position = direction_marker.global_position

func get_drop_position() -> Vector2:
	var direction_marker: Marker2D = attack_positions.get(last_direction)
	return direction_marker.global_position if direction_marker else global_position

	
const HOLDABLE_ANIMATIONS := ["idle", "walk", "sprint"]

func play_direction_animation(anim_name: String) -> void:
		last_anim_base = anim_name
		if last_direction == "left":
			anim_sprite.flip_h = true
		else:
			anim_sprite.flip_h = false
		held_item_sprite.flip_h = anim_sprite.flip_h
		if is_holding_item() and anim_name in HOLDABLE_ANIMATIONS:
			anim_name = "hold_%s" % anim_name
		var full_anim_name: String = "%s_%s" % [anim_name, last_direction]
		# play() restarts from frame 0 even when the same animation is already
		# playing, so guard against calling it redundantly every _process frame.
		if anim_sprite.animation != full_anim_name or not anim_sprite.is_playing():
			anim_sprite.play(full_anim_name)
		
	
func set_hit_area_active(value: bool) -> void:
	hit_area.monitoring = value
	hit_area.visible = value
