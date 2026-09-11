extends Control
class_name Hotbar

const SLOT_COUNT := 8
const INVENTORY_SLOT_SCENE: PackedScene = preload("res://src/ui/inventory/inventory_slot.tscn")

@onready var inventory: Node = $Inventory
@onready var slot_container: HBoxContainer = $MarginContainer/TextureRect/MarginContainer/HBoxContainer
@onready var hud: HUD = get_parent() as HUD
@onready var item_name_panel: PanelContainer = $ItemNameLabel
@onready var item_name_label: Label = $ItemNameLabel/MarginContainer/Label

var slots: Array[TextureButton] = []
var normal_textures: Array[Texture2D] = []
var selected_textures: Array[Texture2D] = []
var selected_slot: int = 0
var suppress_next_key_selection: bool = false
var hovered_slot_index: int = -1
var grabbed_slot: InventorySlot

var _hotbar_actions: Array[StringName] = []

func _ready() -> void:
	for index in SLOT_COUNT:
		_hotbar_actions.append(&"hotbar_%d" % (index + 1))
	for child in slot_container.get_children():
		if child is TextureButton:
			var slot := child as TextureButton
			var normal_texture := slot.texture_normal
			selected_textures.append(slot.texture_pressed)
			normal_textures.append(normal_texture)
			slot.toggle_mode = false
			slot.texture_pressed = normal_texture
			slot.pressed.connect(_on_slot_pressed.bind(slots.size()))
			slot.gui_input.connect(_on_slot_gui_input.bind(slots.size()))
			var inventory_slot := child as InventorySlot
			inventory_slot.on_slot_hovered.connect(_show_item_name)
			inventory_slot.on_slot_unhovered.connect(_hide_item_name)
			slots.append(slot)
	inventory.on_inventory_changed.connect(_refresh_slots)
	grabbed_slot = INVENTORY_SLOT_SCENE.instantiate() as InventorySlot
	grabbed_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grabbed_slot.disabled = true
	grabbed_slot.texture_normal = null
	grabbed_slot.texture_hover = null
	grabbed_slot.z_index = 10
	grabbed_slot.visible = false
	add_child(grabbed_slot)
	_refresh_slots()
	_select_slot(selected_slot)

func _process(_delta: float) -> void:
	if suppress_next_key_selection:
		suppress_next_key_selection = false
	else:
		for index in SLOT_COUNT:
			if Input.is_action_just_pressed(_hotbar_actions[index]):
				_select_slot(index)
	if hud.held_item and hud.held_source == self:
		grabbed_slot.global_position = get_global_mouse_position()
	if hovered_slot_index >= 0:
		_position_item_name_label()
	_update_item_name_visibility()

func _show_item_name(slot_index: int) -> void:
	hovered_slot_index = slot_index
	_update_item_name_visibility()

func _hide_item_name(slot_index: int) -> void:
	if slot_index == hovered_slot_index:
		hovered_slot_index = -1
	_update_item_name_visibility()

func _update_item_name_visibility() -> void:
	var can_show := hud.is_any_panel_visible() and not hud.held_item
	can_show = can_show and hovered_slot_index >= 0 and hovered_slot_index < inventory.items.size()
	can_show = can_show and inventory.items[hovered_slot_index] != null
	if can_show:
		item_name_label.text = inventory.items[hovered_slot_index].name
	item_name_panel.visible = can_show

func _position_item_name_label() -> void:
	var hovered_rect := Rect2()
	if hovered_slot_index >= 0 and hovered_slot_index < slots.size():
		hovered_rect = slots[hovered_slot_index].get_global_rect()
	item_name_panel.global_position = ItemNameTooltip.position(item_name_panel, get_global_mouse_position(), hovered_rect, get_viewport_rect().size)

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_select_slot(posmod(selected_slot + 1, SLOT_COUNT))
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_select_slot(posmod(selected_slot - 1, SLOT_COUNT))
		get_viewport().set_input_as_handled()

func _on_slot_pressed(slot_index: int) -> void:
	if hud.held_item:
		_place_held_item(slot_index)
		_restore_selection_visuals()
		return
	if Input.is_key_pressed(KEY_SHIFT) and _move_stack_to_inventory(slot_index):
		_restore_selection_visuals()
		return
	var taken: Array = inventory.take_item(slot_index)
	if not taken.is_empty():
		hud.held_item = taken[0]
		hud.held_quantity = taken[1]
		hud.held_durability = taken[2] if taken.size() > 2 else 0
		hud.held_source = self as Node
		_update_grabbed_slot()
	_restore_selection_visuals()

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not hud.held_item:
		var split: Array = inventory.split_item(slot_index)
		if split.is_empty():
			return
		hud.held_item = split[0]
		hud.held_quantity = split[1]
		hud.held_durability = 0
		hud.held_source = self as Node
		_update_grabbed_slot()
		get_viewport().set_input_as_handled()

func _move_stack_to_inventory(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= inventory.items.size() or inventory.items[slot_index] == null:
		return false
	var inventory_panel: InventoryPanel = hud.inventory_panel
	if not inventory_panel.visible or not inventory_panel.inventory_panel.visible:
		return false
	var item: Item = inventory.items[slot_index]
	var quantity: int = inventory.quantities[slot_index]
	var durability: int = inventory.durabilities[slot_index]
	if not inventory_panel.inventory.can_add_item(item, quantity):
		return false
	if inventory_panel.inventory.add_item(item, quantity, durability):
		inventory.remove_item(slot_index, quantity)
		return true
	return false

func move_stack_from(source_panel: InventoryPanel, source_slot_index: int) -> bool:
	if source_slot_index < 0 or source_slot_index >= source_panel.inventory.items.size():
		return false
	var item: Item = source_panel.inventory.items[source_slot_index]
	if item == null:
		return false
	var quantity: int = source_panel.inventory.quantities[source_slot_index]
	var durability: int = source_panel.inventory.durabilities[source_slot_index]
	var moved_quantity: int = mini(quantity, inventory.get_item_capacity(item))
	if moved_quantity <= 0:
		return false
	if not inventory.add_item(item, moved_quantity, durability):
		return false
	source_panel.inventory.remove_item(source_slot_index, moved_quantity)
	_refresh_slots()
	return true

func move_item_from(source_panel: InventoryPanel, source_slot_index: int, target_slot_index: int) -> bool:
	if source_slot_index < 0 or source_slot_index >= source_panel.inventory.items.size():
		return false
	if target_slot_index < 0 or target_slot_index >= inventory.items.size():
		return false
	var source_item: Item = source_panel.inventory.items[source_slot_index]
	if source_item == null:
		return false
	var source_quantity: int = source_panel.inventory.quantities[source_slot_index]
	var source_durability: int = source_panel.inventory.durabilities[source_slot_index]
	var target_item: Item = inventory.items[target_slot_index]
	var target_quantity: int = inventory.quantities[target_slot_index]
	var target_durability: int = inventory.durabilities[target_slot_index]

	if target_item == null:
		inventory.items[target_slot_index] = source_item
		inventory.quantities[target_slot_index] = source_quantity
		inventory.durabilities[target_slot_index] = source_durability
		source_panel.inventory.items[source_slot_index] = null
		source_panel.inventory.quantities[source_slot_index] = 0
		source_panel.inventory.durabilities[source_slot_index] = 0
	elif target_item == source_item:
		var stack_limit: int = maxi(target_item.max_stack_size, 1)
		var moved_quantity: int = mini(source_quantity, stack_limit - target_quantity)
		if moved_quantity <= 0:
			return false
		inventory.quantities[target_slot_index] += moved_quantity
		source_panel.inventory.quantities[source_slot_index] -= moved_quantity
		if source_panel.inventory.quantities[source_slot_index] == 0:
			source_panel.inventory.items[source_slot_index] = null
			source_panel.inventory.durabilities[source_slot_index] = 0
	else:
		inventory.items[target_slot_index] = source_item
		inventory.quantities[target_slot_index] = source_quantity
		inventory.durabilities[target_slot_index] = source_durability
		source_panel.inventory.items[source_slot_index] = target_item
		source_panel.inventory.quantities[source_slot_index] = target_quantity
		source_panel.inventory.durabilities[source_slot_index] = target_durability

	source_panel.inventory.on_inventory_changed.emit()
	inventory.on_inventory_changed.emit()
	suppress_next_key_selection = true
	return true

## Read-only capacity check for add_crafted_item, so a caller (see
## CraftingBenchPanel) can confirm a freshly crafted item will actually fit
## before spending the ingredients on it.
func can_accept_crafted_item(item: Item, quantity: int, target_slot_index: int) -> bool:
	if item == null or quantity <= 0 or target_slot_index < 0 or target_slot_index >= inventory.items.size():
		return false
	var target_item: Item = inventory.items[target_slot_index]
	if target_item != null and target_item != item:
		return false
	var stack_limit: int = maxi(item.max_stack_size, 1)
	var target_quantity: int = inventory.quantities[target_slot_index] if target_item != null else 0
	return target_quantity + quantity <= stack_limit

## Deposits an already-crafted item straight into a hotbar slot -- unlike
## move_item_from/move_stack_from, this never swaps out whatever's already
## there; call can_accept_crafted_item first and only craft if it's true.
func add_crafted_item(item: Item, quantity: int, durability: int, target_slot_index: int) -> void:
	if inventory.items[target_slot_index] == null:
		inventory.items[target_slot_index] = item
		inventory.quantities[target_slot_index] = quantity
		inventory.durabilities[target_slot_index] = durability
	else:
		inventory.quantities[target_slot_index] += quantity
	inventory.on_inventory_changed.emit()

func _place_held_item(slot_index: int) -> void:
	var source = hud.held_source
	var remaining: Array = inventory.place_item(slot_index, hud.held_item, hud.held_quantity, hud.held_durability)
	hud.held_item = remaining[0] if not remaining.is_empty() else null
	hud.held_quantity = remaining[1] if not remaining.is_empty() else 0
	hud.held_durability = remaining[2] if remaining.size() > 2 else 0
	if hud.held_item == null:
		hud.held_source = null
	if is_instance_valid(source) and source != self:
		source.call("_update_grabbed_slot")
	_update_grabbed_slot()
	_refresh_slots()

func _update_grabbed_slot() -> void:
	if hud.held_source == self and hud.held_item:
		grabbed_slot.setup(-1, hud.held_item, hud.held_quantity, hud.held_durability)
		grabbed_slot.visible = true
	else:
		grabbed_slot.visible = false
	_update_item_name_visibility()

func _select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slots.size():
		return
	selected_slot = slot_index
	_restore_selection_visuals()
	var item: Item = inventory.items[selected_slot] if selected_slot < inventory.items.size() else null
	EventBus.hotbar_slot_selected.emit(selected_slot, item)

func _restore_selection_visuals() -> void:
	for index in slots.size():
		var texture := selected_textures[index] if index == selected_slot else normal_textures[index]
		slots[index].texture_normal = texture
		slots[index].texture_pressed = texture

func emit_selection() -> void:
	_select_slot(selected_slot)

func is_pointer_over_slots(pointer_position: Vector2) -> bool:
	return slot_container.get_global_rect().has_point(pointer_position)

func _refresh_slots() -> void:
	for index in slots.size():
		var item: Item = inventory.items[index] if index < inventory.items.size() else null
		var quantity: int = inventory.quantities[index] if index < inventory.quantities.size() else 0
		var durability: int = inventory.durabilities[index] if index < inventory.durabilities.size() else -1
		(slots[index] as InventorySlot).setup(index, item, quantity, durability)
	var selected_item: Item = inventory.items[selected_slot] if selected_slot < inventory.items.size() else null
	EventBus.hotbar_slot_selected.emit(selected_slot, selected_item)

func drop_held_item() -> void:
	if hud.held_source != self:
		return
	var entity_root: Node2D = get_tree().current_scene.get_node("%EntityRoot")
	var main_game: MainGame = get_tree().current_scene as MainGame
	var drop_position := main_game.player.get_drop_position() if main_game and main_game.player else get_global_mouse_position()
	var ground_item := GroundItem.spawn(entity_root, hud.held_item, hud.held_quantity, drop_position, hud.held_durability)
	ground_item.disable_collision_for(GroundItem.DROPPED_ITEM_PICKUP_DELAY)
	hud.held_item = null
	hud.held_quantity = 0
	hud.held_durability = 0
	hud.held_source = null
	_update_grabbed_slot()
	_refresh_slots()
