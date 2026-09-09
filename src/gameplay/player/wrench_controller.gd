class_name WrenchController
extends Node2D
## While the Wrench is equipped, clicking the edge an active (enabled) slot
## component currently occupies either re-faces it (left-click: cycles it
## clockwise to the next free edge) or removes its upgrade (right-click:
## disables it again and refunds the matching Input/Output Upgrade item to
## the player). Mouse-driven rather than the swing-based "tool_target_click"
## FSM every other tool uses, so this listens for the raw button event
## directly instead of that action (see InteractableContainer._on_area_entered's
## matching Wrench guard).

@onready var player: Player = get_parent()

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if player.current_tool_type != Item.ToolTypes.Wrench:
		return
	if player.hud.is_any_panel_visible():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_remove_click()

func _handle_click() -> void:
	var slot := _resolve_clicked_slot()
	if slot.is_empty():
		return
	_cycle_facing(slot["component"], slot["components"], slot["footprint"])
	# A neighboring belt's downstream_slot is cached at placement time (see
	# BeltManager) and never re-checked on its own -- without this, a belt
	# already linked (or already NOT linked) against this component's old
	# edge keeps that stale link forever, even though the arrow itself
	# updates immediately since it just reads facing live every frame.
	AutomationUtils.notify_belt_manager_for_object(slot["objects_layer"], slot["target"])

func _handle_remove_click() -> void:
	var slot := _resolve_clicked_slot()
	if slot.is_empty():
		return
	var component: ItemSlotComponent = slot["component"]
	component.enabled = false
	_refund_upgrade_item(component)
	AutomationUtils.notify_belt_manager_for_object(slot["objects_layer"], slot["target"])

## Resolves the enabled slot component sitting at the edge zone the player
## just clicked, plus the bits both click handlers need afterward -- shared
## by _handle_click (re-facing) and _handle_remove_click (removing an
## upgrade), which only differ in what they do with the result. Empty on any
## broken link in the chain: no target under the mouse, out of reach, no
## enabled component there at all, or none sitting on the clicked edge
## zone specifically -- an object's own footprint decides whether "the edge
## zone" means one of 4 plain facings or one of 8 (facing, sub_position)
## halves (see AutomationUtils.get_edge_zones/edge_zone_key).
func _resolve_clicked_slot() -> Dictionary:
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		return {}
	var player_cell := objects_layer.local_to_map(objects_layer.to_local(player.global_position))
	var target := AutomationUtils.find_slot_target(objects_layer, get_global_mouse_position())
	if target == null:
		return {}
	if not AutomationUtils.is_object_within_reach(player_cell, objects_layer, target):
		return {}
	var components: Array[ItemSlotComponent] = []
	for component in AutomationUtils.get_slot_components(target):
		if component.enabled:
			components.append(component)
	if components.is_empty():
		return {}
	var slot_locations: SlotLocationsComponent = target.get_node_or_null("SlotLocationsComponent")
	if slot_locations == null:
		return {}
	var footprint := AutomationUtils.get_object_footprint(target)
	var clicked := slot_locations.get_quadrant(get_global_mouse_position(), footprint)
	var clicked_key := AutomationUtils.edge_zone_key(clicked["facing"], clicked["sub_position"])
	var clicked_component: ItemSlotComponent = null
	for component in components:
		if AutomationUtils.edge_zone_key(component.facing, component.get_sub_position()) == clicked_key:
			clicked_component = component
			break
	if clicked_component == null:
		return {}
	return {
		"objects_layer": objects_layer,
		"target": target,
		"components": components,
		"component": clicked_component,
		"footprint": footprint,
	}

## Hands back whichever exact Upgrade item was used to enable this port (a
## Solid Fuel Input Upgrade refunds as a Solid Fuel Input Upgrade, not a
## plain Input Upgrade, even though both enable the same kind of port) --
## into the hotbar if it has room, else the main backpack, else dropped on
## the ground at the player's feet, the same fallback chain GroundItem uses
## when picking an item back up, so an upgrade is never just silently lost to
## a full inventory. Falls back to guessing the Input/Output/Solid Fuel Input
## Upgrade by the port's class if applied_upgrade_item_id was never set (e.g.
## a port enabled before that field existed).
func _refund_upgrade_item(component: ItemSlotComponent) -> void:
	var item_id := component.applied_upgrade_item_id
	if item_id.is_empty():
		if component is SolidFuelInputSlotComponent:
			item_id = "solid_fuel_input_upgrade"
		elif component is ItemInputSlotComponent:
			item_id = "input_upgrade"
		else:
			item_id = "output_upgrade"
	var item := ItemRegistry.get_item(item_id)
	if item == null:
		return
	var hotbar_inventory: Node = player.hud.hotbar.get_node("Inventory")
	if hotbar_inventory.get_item_capacity(item) > 0 and hotbar_inventory.add_item(item, 1):
		return
	if Inventory.get_item_capacity(item) > 0 and Inventory.add_item(item, 1):
		return
	var entity_root: Node2D = get_tree().current_scene.get_node("%EntityRoot")
	GroundItem.spawn(entity_root, item, 1, player.global_position)

## Cycles clockwise through every edge zone footprint exposes (4 plain
## facings for a 1x1 object, 8 (facing, sub_position) halves for a bigger one
## like BlastFurnace -- see AutomationUtils.get_edge_zones), skipping any
## zone another enabled sibling already occupies, so two components can never
## end up on the same specific edge cell -- that invariant is what lets
## ItemOutputSlotComponent match "the" input on a neighbor unambiguously
## (see its _find_matching_input, which additionally checks the exact owner
## cell for a multi-tile neighbor). Leaves facing/position unchanged if every
## other zone is already taken.
func _cycle_facing(component: ItemSlotComponent, siblings: Array, footprint: Vector2i) -> void:
	var occupied: Array[String] = []
	for sibling in siblings:
		if sibling != component:
			occupied.append(AutomationUtils.edge_zone_key(sibling.facing, sibling.get_sub_position()))
	var zones := AutomationUtils.get_edge_zones(footprint)
	var current_key := AutomationUtils.edge_zone_key(component.facing, component.get_sub_position())
	var start_index := 0
	for i in zones.size():
		if AutomationUtils.edge_zone_key(zones[i]["facing"], zones[i]["sub_position"]) == current_key:
			start_index = i
			break
	for step in range(1, zones.size() + 1):
		var candidate: Dictionary = zones[(start_index + step) % zones.size()]
		var key := AutomationUtils.edge_zone_key(candidate["facing"], candidate["sub_position"])
		if key not in occupied:
			component.facing = candidate["facing"]
			component.position = AutomationUtils.get_edge_local_position(footprint, candidate["facing"], candidate["sub_position"])
			return
