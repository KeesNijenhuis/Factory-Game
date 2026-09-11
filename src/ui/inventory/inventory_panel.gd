extends Control
class_name InventoryPanel

@export_node_path("Node") var inventory_path: NodePath
@export var toggle_with_inventory_key: bool = true
@export var container_name: String = "Inventory"

const INVENTORY_SLOT_SCENE: PackedScene = preload("res://src/ui/inventory/inventory_slot.tscn")
const COPPER_ORE: Item = preload("res://src/resources/items/ores/copper_ore.tres")
const IRON_ORE: Item = preload("res://src/resources/items/ores/iron_ore.tres")


@onready var inventory_panel: Control = $HBoxContainer/Inventory
@onready var container_name_label: Label = $HBoxContainer/Inventory/MarginContainer/VBoxContainer/ContainerNameLabel
@onready var item_name_panel: PanelContainer = $ItemNameLabel
@onready var item_name_label: Label = $ItemNameLabel/MarginContainer/Label
@onready var container: GridContainer = %Container
@onready var hud: HUD = get_parent() as HUD

var inventory: Node
var slots: Array[InventorySlot] = []
var grabbed_slot: InventorySlot
var hovered_slot_index: int = -1

## Playtesting aid for conveyor belts: dev-only cheat items granted straight
## to the hotbar (see _process()'s debug_add_items handling below), not a
## starting loadout -- remove once belts are done being tested. Loaded via
## load() rather than a top-level preload() const: these placeable Items
## pull in their placed_scene (furnace.tscn/chest.tscn), which transitively
## reaches FurnacePanel/ChestInventoryPanel -- both extend InventoryPanel --
## and preloading that chain from inside inventory_panel.gd itself deadlocks
## on InventoryPanel's own not-yet-finished compile. Deferring to _ready()
## runs after every script is already compiled, so no cycle.
var _debug_transport_belt: Item
var _debug_chest: Item
var _debug_furnace: Item

func _ready() -> void:
	add_to_group("inventory_panels")
	container_name_label.text = container_name
	inventory_panel.visible = visible
	inventory = get_node_or_null(inventory_path) if not inventory_path.is_empty() else get_node("/root/Inventory")
	_connect_inventory()
	_configure_slots()
	_connect_slots()
	_apply_role_colors()
	grabbed_slot = INVENTORY_SLOT_SCENE.instantiate() as InventorySlot
	_debug_transport_belt = load("res://src/resources/items/placeables/transport_belt.tres")
	_debug_chest = load("res://src/resources/items/placeables/chest.tres")
	_debug_furnace = load("res://src/resources/items/placeables/furnace.tres")
	grabbed_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grabbed_slot.disabled = true
	grabbed_slot.texture_normal = null
	grabbed_slot.texture_hover = null
	grabbed_slot.z_index = 10
	grabbed_slot.visible = false
	add_child(grabbed_slot)
	_refresh_slots()
	_hide_item_name(-1)

## Whether the panel is actually showing on screen right now. The root
## Control's own `visible` isn't a reliable signal by itself: hide_inventory()
## only hides the inner `inventory_panel` NinePatchRect, leaving the root
## visible so drag/drop bookkeeping in _process keeps running.
func is_panel_visible() -> bool:
	return visible and inventory_panel.visible

func open_for(storage: Node) -> void:
	if inventory != storage:
		if is_instance_valid(inventory) and inventory.on_inventory_changed.is_connected(_refresh_slots):
			inventory.on_inventory_changed.disconnect(_refresh_slots)
		inventory = storage
		_connect_inventory()
		_configure_slots()
		_connect_slots()
		_apply_role_colors()
	_refresh_slots()
	visible = true
	inventory_panel.visible = true
	hud.update_panel_layout()

func close_inventory() -> void:
	visible = false
	inventory_panel.visible = false
	item_name_panel.visible = false
	hud.update_panel_layout()

func show_inventory() -> void:
	visible = true
	inventory_panel.visible = true
	hud.update_panel_layout()

func hide_inventory() -> void:
	inventory_panel.visible = false
	item_name_panel.visible = false
	hud.update_panel_layout()

func _connect_inventory() -> void:
	if not inventory.on_inventory_changed.is_connected(_refresh_slots):
		inventory.on_inventory_changed.connect(_refresh_slots)

## How many grid slots this panel should render, and how many columns to lay
## them out in. Default: the open Inventory's own size -- CraftingBenchPanel
## overrides both, since CraftingBenchInventory bundles a non-grid output
## slot into its item count (see CraftingBenchInventory.SLOT_COUNT) that
## isn't part of this grid.
func _grid_slot_count() -> int:
	return inventory.items.size()

func _grid_columns() -> int:
	return inventory.columns

## Sizes the slot grid to whatever Inventory is currently open rather than a
## fixed count on this panel -- the same panel scene is reused across
## different-sized inventories (e.g. the shared chest panel opens both a
## wooden chest's and an iron chest's Inventory), so a count fixed here
## instead of read from the open Inventory silently hides that Inventory's
## extra slots: shift-click quick-transfer still finds room in them and
## drops items there, but nothing on screen ever shows they arrived. Re-run
## via open_for() whenever the open Inventory changes, so it's written to be
## safe to call more than once.
func _configure_slots() -> void:
	slots.clear()
	container.columns = _grid_columns()
	for child in container.get_children():
		if child is InventorySlot:
			slots.append(child as InventorySlot)
	var target_slot_count: int = _grid_slot_count()
	while slots.size() > target_slot_count:
		slots.pop_back().queue_free()
	while slots.size() < target_slot_count:
		var slot := INVENTORY_SLOT_SCENE.instantiate() as InventorySlot
		container.add_child(slot)
		slots.append(slot)

## Connects every slot currently in `slots` -- called after _configure_slots()
## (and any subclass additions to `slots`, e.g. CraftingBenchPanel's
## output_slot) has finished. Safe to call more than once: already-connected
## slots are skipped.
func _connect_slots() -> void:
	for slot in slots:
		if not slot.on_slot_clicked.is_connected(_on_slot_clicked):
			slot.on_slot_hovered.connect(_show_item_name)
			slot.on_slot_unhovered.connect(_hide_item_name)
			slot.on_slot_clicked.connect(_on_slot_clicked)

## Tints each of this container's colored-input slots (see
## Inventory.get_colored_input_slots) to match its port's world-space arrow
## color -- only when there's more than one, since a single input slot has
## no ambiguity to resolve.
func _apply_role_colors() -> void:
	var colored_indices: Array[int] = inventory.get_colored_input_slots()
	if colored_indices.size() <= 1:
		return
	for slot_index in colored_indices:
		if slot_index < slots.size():
			var color_index := slot_index % PortColors.COLORS.size()
			slots[slot_index].set_role_color(PortColors.COLORS[color_index], PortColors.COLORS_DARK[color_index])

func _process(_delta: float) -> void:
	if DebugSettings.enable_item_cheat and inventory_panel.visible and Input.is_action_pressed(&"debug_add_items") and inventory == get_node("/root/Inventory"):
		inventory.add_item(COPPER_ORE)
		inventory.add_item(IRON_ORE)
		# Playtesting aid, not a starting loadout -- see the vars' doc comment above.
		hud.hotbar.inventory.add_item(_debug_transport_belt, _debug_transport_belt.max_stack_size)
		hud.hotbar.inventory.add_item(_debug_chest, _debug_chest.max_stack_size)
		hud.hotbar.inventory.add_item(_debug_furnace, _debug_furnace.max_stack_size)
	if hud.held_item and hud.held_source == self:
		grabbed_slot.global_position = get_global_mouse_position()
	if hovered_slot_index >= 0:
		_position_item_name_label()
	_update_item_name_visibility()

func _input(event: InputEvent) -> void:
	if _try_move_hovered_item_to_hotbar(event):
		return
	if toggle_with_inventory_key and event.is_action_pressed(&"inventory"):
		if inventory_panel.visible:
			hide_inventory()
		else:
			show_inventory()
	elif event.is_action_pressed(&"drop_item") and hud.held_item and hud.held_source == self:
		_drop_item(hud.held_item, hud.held_quantity, hud.held_durability)
		hud.held_item = null
		hud.held_quantity = 0
		hud.held_durability = 0
		hud.held_source = null
		_update_grabbed_slot()
	elif event.is_action_pressed(&"drop_item") and hovered_slot_index >= 0:
		var taken: Array = inventory.take_item(hovered_slot_index)
		if not taken.is_empty():
			_drop_item(taken[0], taken[1], taken[2] if taken.size() > 2 else 0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hud.held_item and hud.held_source == self:
		var inside_inventory := inventory_panel.get_global_rect().has_point(event.position)
		if not inside_inventory and not _is_over_other_panel(event.position):
			_drop_item(hud.held_item, hud.held_quantity, hud.held_durability)
			hud.held_item = null
			hud.held_quantity = 0
			hud.held_durability = 0
			hud.held_source = null
			_update_grabbed_slot()
			# This same click is also "tool_target_click" (LMB), which would
			# otherwise also start a tool-use animation the instant the item
			# is dropped.
			var main_game: MainGame = get_tree().current_scene as MainGame
			if main_game and main_game.player:
				main_game.player.interaction_consumed = true

func _try_move_hovered_item_to_hotbar(event: InputEvent) -> bool:
	if not visible or not inventory_panel.visible or hovered_slot_index < 0:
		return false
	if not inventory_panel.get_global_rect().has_point(get_global_mouse_position()):
		return false
	if hovered_slot_index >= inventory.items.size() or inventory.items[hovered_slot_index] == null:
		return false
	for index in Hotbar.SLOT_COUNT:
		if event.is_action_pressed(&"hotbar_%d" % (index + 1)):
			if hud.hotbar.call("move_item_from", self, hovered_slot_index, index):
				get_viewport().set_input_as_handled()
				return true
	return false

func _is_over_other_panel(pointer_position: Vector2) -> bool:
	if hud.hotbar.visible and hud.hotbar.call("is_pointer_over_slots", pointer_position):
		return true
	for panel in get_tree().get_nodes_in_group("inventory_panels"):
		if panel == self or not panel.visible:
			continue
		if panel.inventory_panel.get_global_rect().has_point(pointer_position):
			return true
	return false

func _refresh_slots() -> void:
	for index in slots.size():
		var item: Item = inventory.items[index] if index < inventory.items.size() else null
		var quantity: int = inventory.quantities[index] if index < inventory.quantities.size() else 0
		var durability: int = inventory.durabilities[index] if index < inventory.durabilities.size() else -1
		slots[index].setup(index, item, quantity, durability)

func _position_item_name_label() -> void:
	var hovered_rect := Rect2()
	if hovered_slot_index >= 0 and hovered_slot_index < slots.size():
		hovered_rect = slots[hovered_slot_index].get_global_rect()
	item_name_panel.global_position = ItemNameTooltip.position(item_name_panel, get_global_mouse_position(), hovered_rect, get_viewport_rect().size)

func _show_item_name(slot_index: int) -> void:
	hovered_slot_index = slot_index
	_update_item_name_visibility()

func _hide_item_name(slot_index: int) -> void:
	if slot_index == hovered_slot_index:
		hovered_slot_index = -1
	_update_item_name_visibility()

func _update_item_name_visibility() -> void:
	var can_show := visible and inventory_panel.visible and not hud.held_item
	can_show = can_show and hovered_slot_index >= 0 and hovered_slot_index < inventory.items.size()
	can_show = can_show and inventory.items[hovered_slot_index] != null
	if can_show:
		item_name_label.text = inventory.items[hovered_slot_index].name
	item_name_panel.visible = can_show

func _drop_item(item: Item, quantity: int, durability: int = -1) -> void:
	var entity_root: Node2D = get_tree().current_scene.get_node("%EntityRoot")
	var main_game: MainGame = get_tree().current_scene as MainGame
	var drop_position := main_game.player.get_drop_position() if main_game and main_game.player else get_global_mouse_position()
	var ground_item := GroundItem.spawn(entity_root, item, quantity, drop_position, durability)
	ground_item.disable_collision_for(GroundItem.DROPPED_ITEM_PICKUP_DELAY)

func drop_held_item() -> void:
	if hud.held_item == null:
		return
	_drop_item(hud.held_item, hud.held_quantity, hud.held_durability)
	hud.held_item = null
	hud.held_quantity = 0
	hud.held_durability = 0
	hud.held_source = null
	_update_grabbed_slot()

func _on_slot_clicked(slot_index: int, button: int, double_click: bool, shift_click: bool) -> void:
	if button == MOUSE_BUTTON_LEFT and shift_click and not hud.held_item and inventory_panel.get_global_rect().has_point(get_global_mouse_position()):
		_move_stack_to_other_container(slot_index)
		return
	if button == MOUSE_BUTTON_LEFT and double_click and hud.held_item and hud.held_source == self:
		hud.held_quantity = inventory.collect_matching_item(hud.held_item, hud.held_quantity)
		_update_grabbed_slot()
		return
	if button == MOUSE_BUTTON_RIGHT and not hud.held_item:
		var split: Array = inventory.split_item(slot_index)
		if split.is_empty():
			return
		hud.held_item = split[0]
		hud.held_quantity = split[1]
		hud.held_durability = 0
		hud.held_source = self
		_update_grabbed_slot()
		return
	if button == MOUSE_BUTTON_RIGHT and hud.held_item:
		var source_panel := hud.held_source
		if inventory.place_one_item(slot_index, hud.held_item, hud.held_durability):
			hud.held_quantity -= 1
			if hud.held_quantity <= 0:
				hud.held_item = null
				hud.held_quantity = 0
				hud.held_durability = 0
				hud.held_source = null
			if is_instance_valid(source_panel) and source_panel != self:
				source_panel.call("_update_grabbed_slot")
			_update_grabbed_slot()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	if not hud.held_item:
		var taken: Array = inventory.take_item(slot_index)
		if taken.is_empty():
			return
		hud.held_item = taken[0]
		hud.held_quantity = taken[1]
		hud.held_durability = taken[2] if taken.size() > 2 else 0
		hud.held_source = self
	else:
		var source_panel := hud.held_source
		var remaining: Array = inventory.place_item(slot_index, hud.held_item, hud.held_quantity, hud.held_durability)
		hud.held_item = remaining[0] if not remaining.is_empty() else null
		hud.held_quantity = remaining[1] if not remaining.is_empty() else 0
		hud.held_durability = remaining[2] if remaining.size() > 2 else 0
		if hud.held_item == null:
			hud.held_source = null
		if is_instance_valid(source_panel):
			source_panel.call("_update_grabbed_slot")
	_update_grabbed_slot()

func _move_stack_to_other_container(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= inventory.items.size() or inventory.items[slot_index] == null:
		return
	var item: Item = inventory.items[slot_index]
	var target_panel: InventoryPanel = _find_transfer_target(item)
	if target_panel == null:
		if hud.hotbar.visible and hud.hotbar.call("move_stack_from", self, slot_index):
			return
		return
	var quantity: int = inventory.quantities[slot_index]
	var durability: int = inventory.durabilities[slot_index]
	var moved_quantity: int = mini(quantity, target_panel.inventory.get_item_capacity(item))
	if moved_quantity <= 0:
		return
	if target_panel.inventory.add_item(item, moved_quantity, durability):
		inventory.remove_item(slot_index, moved_quantity)

## Multiple containers (e.g. a chest and a furnace) can be open at the same
## time, so picking "whichever other panel happens to be open" isn't enough:
## fuel should specifically prefer an open furnace's fuel slot over, say, a
## chest that's also open, and any item should prefer a panel that actually
## has room for it over one that doesn't.
func _find_transfer_target(item: Item) -> InventoryPanel:
	var candidates: Array[InventoryPanel] = []
	for panel in get_tree().get_nodes_in_group("inventory_panels"):
		if panel != self and panel.visible and panel.inventory_panel.visible:
			candidates.append(panel as InventoryPanel)
	if candidates.is_empty():
		return null

	if item and item.item_type == Item.ItemType.FUEL:
		for panel in candidates:
			if panel.inventory is FurnaceInventory and panel.inventory.get_item_capacity(item) > 0:
				return panel

	for panel in candidates:
		if panel.inventory.get_item_capacity(item) > 0:
			return panel

	return candidates[0]


func _update_grabbed_slot() -> void:
	if hud.held_source == self and hud.held_item:
		grabbed_slot.setup(-1, hud.held_item, hud.held_quantity, hud.held_durability)
		grabbed_slot.visible = true
	else:
		grabbed_slot.visible = false
	_update_item_name_visibility()
