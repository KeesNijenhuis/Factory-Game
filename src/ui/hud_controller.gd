extends Control
class_name HUD

## Fixed left-to-right slot order for the side-by-side panels; each panel
## takes the next slot only while visible, so panels shift left to fill gaps
## left by whichever of these aren't currently open. The skills panel is
## anchored to the right side of the screen instead and sits outside this
## slot order.
const PANEL_WIDTH: float = 150.0

@onready var hotbar: Control = %Hotbar
@onready var inventory_panel: InventoryPanel = %InventoryPanel
@onready var furnace_panel: FurnacePanel = %FurnacePanel
@onready var blast_furnace_panel: BlastFurnacePanel = %BlastFurnacePanel
@onready var crafting_bench_panel: CraftingBenchPanel = %CraftingBenchPanel
@onready var chest_inventory_panel: InventoryPanel = %ChestInventoryPanel
@onready var skills_panel: SkillsPanel = %SkillsPanel

var held_item: Item
var held_quantity: int = 0
var held_durability: int = 0
var held_source: Node

func _ready() -> void:
	add_to_group("hud")
	update_panel_layout()

func update_panel_layout() -> void:
	var index := 0
	for panel: InventoryPanel in [inventory_panel, furnace_panel, blast_furnace_panel, crafting_bench_panel, chest_inventory_panel]:
		if not panel.is_panel_visible():
			continue
		panel.offset_left = index * PANEL_WIDTH
		panel.offset_right = index * PANEL_WIDTH
		index += 1

func is_any_panel_visible() -> bool:
	return inventory_panel.is_panel_visible() \
		or furnace_panel.is_panel_visible() \
		or blast_furnace_panel.is_panel_visible() \
		or crafting_bench_panel.is_panel_visible() \
		or chest_inventory_panel.is_panel_visible() \
		or skills_panel.is_panel_visible()

## Closes every open interface: the player inventory, any open chest/furnace
## (via their InteractableContainer, which also restores the player panel's
## own toggle key and drops any held item), and the skills panel.
func close_all_panels() -> void:
	for container in get_tree().get_nodes_in_group("interactable_containers"):
		container.call("close_container")
	inventory_panel.hide_inventory()
	skills_panel.visible = false
	update_panel_layout()
