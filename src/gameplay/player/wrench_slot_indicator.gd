class_name WrenchSlotIndicator
extends Node2D
## Shows one arrow per slot component on the tile under the mouse while the
## Wrench is equipped -- the same white directional glyphs from hud.png used
## nowhere else in the project, at 50% scale. This script paints the actual
## visible arrows (a small pool of Sprite2D children, shown/hidden/textured/
## colored/positioned here); the Up/Down/Left/Right sprites on each object's
## SlotLocationsComponent are debug/editor-only position references, never
## shown to the player (see slot_locations_component.gd) -- this script just
## reads their positions via ItemSlotComponent.get_marker_global_position(). An
## ItemOutputSlotComponent's arrow points outward (its own facing direction,
## matching ejection); an ItemInputSlotComponent's arrow points inward (the
## opposite direction, matching intake).
##
## While an Upgrade item is held and hovering a target that still has a port
## of its type left to activate (see AutomationUtils.find_upgradeable_component),
## also shows one extra translucent "ghost" arrow (GhostArrow) at whichever
## edge zone the mouse currently hovers -- a preview of where UpgradeController
## would place that new port if clicked right now. Hidden whenever the hovered
## zone is already occupied by an enabled sibling, mirroring the occupancy
## check UpgradeController._handle_click itself makes before doing anything.

## Sliced from hud.png as standalone AtlasTexture resources (assets/art/ui/arrows/)
## rather than built from hardcoded Rect2s here, so each sprite's texture can
## also be set directly in the editor/inspector.
const DIRECTION_TEXTURES: Dictionary = {
	"up": preload("res://assets/art/ui/arrows/arrow_up.tres"),
	"down": preload("res://assets/art/ui/arrows/arrow_down.tres"),
	"left": preload("res://assets/art/ui/arrows/arrow_left.tres"),
	"right": preload("res://assets/art/ui/arrows/arrow_right.tres"),
}

const OUTPUT_COLOR: Color = Color(1.0, 0.4, 0.4)
const FUEL_COLOR: Color = Color(1.0, 1.0, 1.0)

## Alpha the ghost preview arrow renders at -- same translucency
## PlacementController.GHOST_MODULATE uses for its own placement ghost, so a
## previewed-but-not-yet-placed port reads the same way a previewed-but-not-
## yet-placed object does.
const GHOST_ALPHA: float = 0.5

@onready var player: Player = get_parent()
@onready var _arrow_sprites: Array[Sprite2D] = [$Arrow0, $Arrow1, $Arrow2, $Arrow3]
@onready var _ghost_arrow_sprite: Sprite2D = $GhostArrow

func _process(_delta: float) -> void:
	var holding_upgrade := player.current_hotbar_item != null and player.current_hotbar_item.item_type == Item.ItemType.UPGRADE
	if player.current_tool_type != Item.ToolTypes.Wrench and not holding_upgrade:
		_hide_all()
		return
	var objects_layer := AutomationUtils.get_objects_layer(self)
	if objects_layer == null:
		_hide_all()
		return
	var target := AutomationUtils.find_slot_target(objects_layer, get_global_mouse_position())
	if target:
		var player_cell := objects_layer.local_to_map(objects_layer.to_local(player.global_position))
		var target_cell := objects_layer.local_to_map(objects_layer.to_local(target.global_position))
		if not AutomationUtils.is_within_reach(player_cell, target_cell):
			target = null
	var components: Array[ItemSlotComponent] = []
	if target:
		for component in AutomationUtils.get_slot_components(target):
			if component.enabled:
				components.append(component)

	for i in _arrow_sprites.size():
		var sprite := _arrow_sprites[i]
		if i >= components.size():
			sprite.visible = false
			continue
		var component: ItemSlotComponent = components[i]
		var is_output := component is ItemOutputSlotComponent
		var arrow_direction: String = component.facing if is_output else ItemSlotComponent.OPPOSITE_FACING[component.facing]
		sprite.texture = DIRECTION_TEXTURES[arrow_direction]
		sprite.global_position = component.get_marker_global_position()
		sprite.modulate = _color_for(component, is_output)
		sprite.visible = true

	_update_ghost(player.current_hotbar_item, target, components)

func _color_for(component: ItemSlotComponent, is_output: bool) -> Color:
	if is_output:
		return OUTPUT_COLOR
	if component is SolidFuelInputSlotComponent:
		return FUEL_COLOR
	if component.linked_slot_index >= 0:
		return PortColors.COLORS[component.linked_slot_index % PortColors.COLORS.size()]
	# Standalone/any-slot inputs (e.g. Chest) have no fixed slot index to key
	# off of -- there's only ever one such port per object, so it always gets
	# the same first-in-list color the Furnace's single ore input gets.
	return PortColors.COLORS[0]

## Shows the ghost preview arrow at whichever edge zone the mouse currently
## hovers, if and only if item is an Upgrade that target still has a matching
## disabled port for (see AutomationUtils.find_upgradeable_component) and that
## hovered zone isn't already occupied by one of target's enabled_components
## (siblings' facing/sub_position -- same occupancy check
## UpgradeController._handle_click makes before placing anything). Hidden in
## every other case, including no target/no Upgrade held.
func _update_ghost(item: Item, target: Node2D, enabled_components: Array[ItemSlotComponent]) -> void:
	if item == null or item.item_type != Item.ItemType.UPGRADE or target == null:
		_ghost_arrow_sprite.visible = false
		return
	if AutomationUtils.find_upgradeable_component(target, item.upgrade_type) == null:
		_ghost_arrow_sprite.visible = false
		return
	var slot_locations: SlotLocationsComponent = target.get_node_or_null("SlotLocationsComponent")
	if slot_locations == null:
		_ghost_arrow_sprite.visible = false
		return
	var footprint := AutomationUtils.get_object_footprint(target)
	var hovered := slot_locations.get_quadrant(get_global_mouse_position(), footprint)
	var hovered_key := AutomationUtils.edge_zone_key(hovered["facing"], hovered["sub_position"])
	for sibling in enabled_components:
		if AutomationUtils.edge_zone_key(sibling.facing, sibling.get_sub_position()) == hovered_key:
			_ghost_arrow_sprite.visible = false
			return
	var is_output := item.upgrade_type == Item.UpgradeTypes.Output
	var arrow_direction: String = hovered["facing"] if is_output else ItemSlotComponent.OPPOSITE_FACING[hovered["facing"]]
	_ghost_arrow_sprite.texture = DIRECTION_TEXTURES[arrow_direction]
	_ghost_arrow_sprite.global_position = slot_locations.get_marker_global_position(hovered["facing"], hovered["sub_position"])
	_ghost_arrow_sprite.modulate = _ghost_color_for(item.upgrade_type)
	_ghost_arrow_sprite.visible = true

## Same base colors _color_for() picks for a real, already-enabled port
## (OUTPUT_COLOR/FUEL_COLOR), at GHOST_ALPHA -- a plain Input Upgrade's ghost
## has no PortColors entry to reuse yet (that's only assigned once a real port
## actually links to a neighbor), so it falls back to plain translucent white.
func _ghost_color_for(upgrade_type: Item.UpgradeTypes) -> Color:
	if upgrade_type == Item.UpgradeTypes.Output:
		return Color(OUTPUT_COLOR.r, OUTPUT_COLOR.g, OUTPUT_COLOR.b, GHOST_ALPHA)
	if upgrade_type == Item.UpgradeTypes.SolidFuelInput:
		return Color(FUEL_COLOR.r, FUEL_COLOR.g, FUEL_COLOR.b, GHOST_ALPHA)
	return Color(1.0, 1.0, 1.0, GHOST_ALPHA)

func _hide_all() -> void:
	for sprite in _arrow_sprites:
		sprite.visible = false
	_ghost_arrow_sprite.visible = false
