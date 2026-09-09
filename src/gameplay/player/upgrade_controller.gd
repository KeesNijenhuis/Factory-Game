class_name UpgradeController
extends Node2D
## While an Input/Output/Solid Fuel Input Upgrade item is the selected hotbar
## item, a right-click on an object's edge zone within reach turns on a
## still-disabled slot component of the matching class (Input Upgrade -> a
## plain ItemInputSlotComponent, never a SolidFuelInputSlotComponent; Output
## Upgrade -> an ItemOutputSlotComponent; Solid Fuel Input Upgrade -> a
## SolidFuelInputSlotComponent specifically, e.g. a furnace's fuel port) and
## moves it to that zone -- its scene-authored facing/position is only ever
## the starting point, not a requirement, so any of the object's edge zones
## (4 plain facings for a 1x1 object, 8 (facing, sub_position) halves for a
## bigger one like BlastFurnace -- see AutomationUtils.get_edge_zones) can be
## picked freely as long as another enabled port isn't already sitting
## there. Also configures the port's transfer stats from the item and
## consumes one item from the stack. Mirrors WrenchController's mouse-driven
## targeting (reach check, edge resolution via SlotLocationsComponent) but
## never touches an already-enabled port -- moving an active port stays the
## Wrench's job, and left-click does nothing here.

@onready var player: Player = get_parent()

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var item := player.current_hotbar_item
	if item == null or item.item_type != Item.ItemType.UPGRADE:
		return
	if player.hud.is_any_panel_visible():
		return
	_handle_click(item)

func _handle_click(item: Item) -> void:
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		return
	var player_cell := objects_layer.local_to_map(objects_layer.to_local(player.global_position))
	var target := AutomationUtils.find_slot_target(objects_layer, get_global_mouse_position())
	if target == null:
		return
	if not AutomationUtils.is_object_within_reach(player_cell, objects_layer, target):
		return
	var slot_locations: SlotLocationsComponent = target.get_node_or_null("SlotLocationsComponent")
	if slot_locations == null:
		return
	var footprint := AutomationUtils.get_object_footprint(target)
	var clicked := slot_locations.get_quadrant(get_global_mouse_position(), footprint)
	var clicked_key := AutomationUtils.edge_zone_key(clicked["facing"], clicked["sub_position"])
	for sibling in AutomationUtils.get_slot_components(target):
		if sibling.enabled and AutomationUtils.edge_zone_key(sibling.facing, sibling.get_sub_position()) == clicked_key:
			return   # that edge zone already has an active port -- nothing to place here
	var component := AutomationUtils.find_upgradeable_component(target, item.upgrade_type)
	if component == null:
		return
	component.facing = clicked["facing"]
	component.position = AutomationUtils.get_edge_local_position(footprint, clicked["facing"], clicked["sub_position"])
	component.enabled = true
	component.transfer_interval = item.upgrade_transfer_interval
	component.transfer_amount = item.upgrade_transfer_amount
	component.applied_upgrade_item_id = item.item_id
	var hotbar := player.hud.hotbar as Hotbar
	hotbar.inventory.remove_item(hotbar.selected_slot, 1)
	AutomationUtils.notify_belt_manager_for_object(objects_layer, target)
