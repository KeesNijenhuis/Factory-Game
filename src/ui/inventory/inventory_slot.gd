extends TextureButton
class_name InventorySlot

signal on_slot_clicked(slot_index: int, button: int, double_click: bool, shift_click: bool)
signal on_slot_hovered(slot_index: int)
signal on_slot_unhovered(slot_index: int)

var slot_index: int = -1
var item: Item
var _role_color: Color = Color.WHITE
var _role_color_dark: Color = Color.WHITE

@onready var item_icon: TextureRect = $ItemIcon
@onready var quantity_label: Label = $Label
@onready var durability_bar: ProgressBar = $DurabilityBar

## Tints this slot with one of PortColors' colors -- used for a multi-input
## machine's slots (e.g. Blast Furnace ore inputs) so each one visually
## matches its corresponding world-space port arrow. color_dark is shown
## while the mouse hovers the slot.
func set_role_color(color: Color, color_dark: Color) -> void:
	_role_color = color
	_role_color_dark = color_dark
	self_modulate = _role_color

func setup(index: int, slot_item: Item, quantity: int, durability: int = -1) -> void:
	slot_index = index
	item = slot_item
	item_icon.texture = item.icon if item else null
	quantity_label.text = str(quantity) if item and quantity > 1 else ""
	_update_durability_bar(durability)

func _update_durability_bar(durability: int) -> void:
	var max_durability := item.tool_tier.durability if item and item.item_type == Item.ItemType.TOOL and item.tool_tier else 0
	durability_bar.visible = max_durability > 0 and durability >= 0
	if durability_bar.visible:
		durability_bar.max_value = max_durability
		durability_bar.value = durability

func _on_mouse_entered() -> void:
	self_modulate = _role_color_dark
	if item:
		on_slot_hovered.emit(slot_index)

func _on_mouse_exited() -> void:
	self_modulate = _role_color
	on_slot_unhovered.emit(slot_index)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		on_slot_clicked.emit(slot_index, event.button_index, event.double_click, event.shift_pressed)
