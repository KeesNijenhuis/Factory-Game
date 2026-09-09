extends Control

const ITEM_BUTTON_SIZE := Vector2(24, 24)

@onready var items_grid: GridContainer = %ItemsGrid


func _ready() -> void:
	visible = false
	_populate_item_buttons()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_item_menu"):
		visible = not visible


func _populate_item_buttons() -> void:
	for item in ItemRegistry.get_all_items():
		var button := TextureButton.new()
		button.texture_normal = item.icon
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = ITEM_BUTTON_SIZE
		button.tooltip_text = item.name
		button.pressed.connect(_on_item_button_pressed.bind(item))
		items_grid.add_child(button)


## Gives the player a max-size stack of item: hotbar first, then the general
## inventory, then dropped on the ground if both are full.
func _on_item_button_pressed(item: Item) -> void:
	var amount: int = maxi(item.max_stack_size, 1)
	var hud: HUD = get_tree().get_first_node_in_group("hud") as HUD
	if hud:
		var hotbar_inventory: Node = hud.hotbar.get_node("Inventory")
		if hotbar_inventory.can_add_item(item, amount):
			hotbar_inventory.add_item(item, amount)
			return
	if Inventory.can_add_item(item, amount):
		Inventory.add_item(item, amount)
		return
	var main_game: MainGame = get_tree().current_scene as MainGame
	if main_game and main_game.player:
		var ground_item := GroundItem.spawn(main_game.entity_root, item, amount, main_game.player.get_drop_position())
		ground_item.disable_collision_for(GroundItem.DROPPED_ITEM_PICKUP_DELAY)
