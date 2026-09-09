@tool
extends Control
## Recipe Editor dock: authors Item resources plus the single-file
## CraftingRecipeDatabase and SmeltingRecipeDatabase resources. Auto-discovers
## every Item under src/resources/items/ for a filterable icon picker; every
## item slot (shape cells, output slots, smelting inputs) is a
## RecipeEditorShapeCell you drag an item onto -- the same interaction
## everywhere, including future tabs.

const CRAFTING_DB_PATH: String = "res://src/resources/crafting/crafting_recipes.tres"
const SMELTING_DB_PATH: String = "res://src/resources/crafting/smelting_recipes.tres"
const BLAST_FURNACE_DB_PATH: String = "res://src/resources/crafting/blast_furnace_recipes.tres"
const NEW_ITEM_DEFAULT_DIR: String = "res://src/resources/items/"
const NEW_TOOL_TIER_DIR: String = "res://src/resources/items/tools/tiers/"

const ItemButtonScript := preload("res://addons/recipe_editor/item_picker_button.gd")
const ShapeCellScript := preload("res://addons/recipe_editor/shape_grid_cell.gd")
const AtlasRegionPickerScript := preload("res://addons/recipe_editor/atlas_region_picker.gd")

const SKILL_NAMES: Array[String] = ["None", "Mining", "Woodcutting", "Crafting", "Smithing"]
const ITEM_TYPE_NAMES: Array[String] = ["None", "Item", "Tool", "Weapon", "Fuel"]
const SAVE_STATUS_DURATION_SEC: float = 2.5

var crafting_db: CraftingRecipeDatabase
var smelting_db: SmeltingRecipeDatabase
var blast_furnace_db: SmeltingRecipeDatabase
var all_items: Array[Item] = []
var _all_tool_tiers: Array[ToolTierType] = []

var _selected_crafting_index: int = -1
var _selected_smelting_index: int = -1
var _selected_blast_furnace_index: int = -1
var _selected_item_index: int = -1

## The item picker button currently armed for painting (right-clicked), and
## the Item it holds -- kept separately so arming survives the item grid
## being rebuilt on filter changes (the button instance doesn't).
var _armed_button: RecipeEditorItemButton
var _armed_item: Item

var _crafting_item_grid: GridContainer
var _crafting_list: ItemList
var _crafting_shape_cells: Array[RecipeEditorShapeCell] = []
var _crafting_output_cell: RecipeEditorShapeCell
var _crafting_output_qty: SpinBox
var _crafting_skill: OptionButton
var _crafting_exp: SpinBox
var _crafting_level: SpinBox

var _smelting_item_grid: GridContainer
var _smelting_list: ItemList
var _smelting_inputs_box: VBoxContainer
var _smelting_output_cell: RecipeEditorShapeCell
var _smelting_output_qty: SpinBox
var _smelting_skill: OptionButton
var _smelting_exp: SpinBox
var _smelting_level: SpinBox
var _smelting_craft_time: SpinBox

var _blast_furnace_item_grid: GridContainer
var _blast_furnace_list: ItemList
var _blast_furnace_inputs_box: VBoxContainer
var _blast_furnace_output_cell: RecipeEditorShapeCell
var _blast_furnace_output_qty: SpinBox
var _blast_furnace_skill: OptionButton
var _blast_furnace_exp: SpinBox
var _blast_furnace_level: SpinBox
var _blast_furnace_craft_time: SpinBox

var _item_list: ItemList
var _item_icon_preview: TextureRect
var _item_name: LineEdit
var _item_id: LineEdit
var _item_description: TextEdit
var _item_max_stack_size: SpinBox
var _item_value: SpinBox
var _item_is_consumable: CheckBox
var _item_type_option: OptionButton
var _item_placed_scene_path_label: Label
var _item_tool_section: Control
var _item_tool_type_option: OptionButton
var _item_tool_tier_option: OptionButton
var _item_fuel_section: Control
var _item_smelt_count: SpinBox

var _save_status_label: Label
var _save_status_timer: Timer
var _item_tab_content: Control
var _crafting_tab_content: Control
var _smelting_tab_content: Control
var _blast_furnace_tab_content: Control

func _ready() -> void:
	_load_or_create_databases()
	all_items = RecipeEditorItemScanner.scan()
	_all_tool_tiers = RecipeEditorItemScanner.scan_tool_tiers()

	var root_box := VBoxContainer.new()
	# This dock is a plain Control (not a Container), so root_box's size
	# flags alone do nothing to size it relative to its parent -- without an
	# explicit full-rect anchor it just renders at its own computed minimum
	# size instead of actually filling the window. That happened to look
	# right before purely because the properties panel's tall, unwrapped
	# field stack made that minimum size large by coincidence; wrapping it in
	# a ScrollContainer (which deliberately keeps its own minimum size small)
	# exposed the real bug by collapsing everything down to its true, tiny
	# minimum.
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_box)

	root_box.add_child(_build_header())

	_item_tab_content = _build_item_tab()
	_item_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(_item_tab_content)

	_crafting_tab_content = _build_crafting_tab()
	_crafting_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crafting_tab_content.visible = false
	root_box.add_child(_crafting_tab_content)

	_smelting_tab_content = _build_smelting_tab()
	_smelting_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_smelting_tab_content.visible = false
	root_box.add_child(_smelting_tab_content)

	_blast_furnace_tab_content = _build_blast_furnace_tab()
	_blast_furnace_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_blast_furnace_tab_content.visible = false
	root_box.add_child(_blast_furnace_tab_content)

	_refresh_item_list()
	_refresh_crafting_list()
	_refresh_smelting_list()
	_refresh_blast_furnace_list()
	_set_item_properties_enabled(false)
	_set_crafting_properties_enabled(false)
	_set_smelting_properties_enabled(false)
	_set_blast_furnace_properties_enabled(false)

	_save_status_timer = Timer.new()
	_save_status_timer.one_shot = true
	_save_status_timer.wait_time = SAVE_STATUS_DURATION_SEC
	_save_status_timer.timeout.connect(func() -> void: _save_status_label.text = "")
	add_child(_save_status_timer)

## The tab selector row -- three mutually-exclusive toggle buttons on the left
## switch which tab's content is visible, and a single Save button (saving
## everything at once) sits anchored to the right of that same row.
func _build_header() -> Control:
	var header := HBoxContainer.new()

	var tab_group := ButtonGroup.new()

	# Each callback rebuilds this array from the live member variables at
	# press-time rather than closing over a precomputed one -- _build_header()
	# runs before _item_tab_content/_crafting_tab_content/_smelting_tab_content
	# are assigned (they're built right after, in _ready()), so a single
	# array captured here up front would freeze in three nulls forever and
	# the buttons would visually toggle without ever switching any panel.
	var items_tab_button := _tab_toggle_button("Items", true, tab_group)
	items_tab_button.pressed.connect(func() -> void:
		_activate_tab(_item_tab_content, [_item_tab_content, _crafting_tab_content, _smelting_tab_content, _blast_furnace_tab_content])
	)
	header.add_child(items_tab_button)

	var crafting_tab_button := _tab_toggle_button("Crafting Bench", false, tab_group)
	crafting_tab_button.pressed.connect(func() -> void:
		_activate_tab(_crafting_tab_content, [_item_tab_content, _crafting_tab_content, _smelting_tab_content, _blast_furnace_tab_content])
	)
	header.add_child(crafting_tab_button)

	var smelting_tab_button := _tab_toggle_button("Smelting", false, tab_group)
	smelting_tab_button.pressed.connect(func() -> void:
		_activate_tab(_smelting_tab_content, [_item_tab_content, _crafting_tab_content, _smelting_tab_content, _blast_furnace_tab_content])
	)
	header.add_child(smelting_tab_button)

	var blast_furnace_tab_button := _tab_toggle_button("Blast Furnace", false, tab_group)
	blast_furnace_tab_button.pressed.connect(func() -> void:
		_activate_tab(_blast_furnace_tab_content, [_item_tab_content, _crafting_tab_content, _smelting_tab_content, _blast_furnace_tab_content])
	)
	header.add_child(blast_furnace_tab_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_save_status_label = Label.new()
	header.add_child(_save_status_label)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	header.add_child(save_button)

	var trailing_spacer := Control.new()
	trailing_spacer.custom_minimum_size = Vector2(12, 0)
	header.add_child(trailing_spacer)

	return header

func _tab_toggle_button(text: String, active: bool, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = active
	button.button_group = group
	return button

## Shows `target` and hides every other Control in `all_tabs` -- the single
## shared tab-activation routine so adding a tab never means duplicating
## hide/show pairs across every existing button's callback.
func _activate_tab(target: Control, all_tabs: Array[Control]) -> void:
	for tab in all_tabs:
		tab.visible = (tab == target)

func _on_save_pressed() -> void:
	var crafting_err := ResourceSaver.save(crafting_db, CRAFTING_DB_PATH)
	var smelting_err := ResourceSaver.save(smelting_db, SMELTING_DB_PATH)
	var blast_furnace_err := ResourceSaver.save(blast_furnace_db, BLAST_FURNACE_DB_PATH)
	var items_ok := true
	for item in all_items:
		if not item.resource_path.is_empty():
			if ResourceSaver.save(item, item.resource_path) != OK:
				items_ok = false
	_save_status_label.text = "Saved." if crafting_err == OK and smelting_err == OK and blast_furnace_err == OK and items_ok else "Save failed."
	_save_status_timer.start()

func _load_or_create_databases() -> void:
	crafting_db = load(CRAFTING_DB_PATH) as CraftingRecipeDatabase if ResourceLoader.exists(CRAFTING_DB_PATH) else CraftingRecipeDatabase.new()
	smelting_db = load(SMELTING_DB_PATH) as SmeltingRecipeDatabase if ResourceLoader.exists(SMELTING_DB_PATH) else SmeltingRecipeDatabase.new()
	blast_furnace_db = load(BLAST_FURNACE_DB_PATH) as SmeltingRecipeDatabase if ResourceLoader.exists(BLAST_FURNACE_DB_PATH) else SmeltingRecipeDatabase.new()

# ---------------------------------------------------------------- helpers --

## Word-wraps instead of forcing its container as wide as the full unbroken
## text -- without this, a long instructional label bloats the minimum width
## of whichever split-container column it's in, starving the other columns
## of the space needed for the split handles to be draggable at all.
func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _spin_box(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	return spin

func _skill_option_button() -> OptionButton:
	var option := OptionButton.new()
	for i in SKILL_NAMES.size():
		option.add_item(SKILL_NAMES[i], i)
	return option

## GDScript's array-literal ternary (e.g. `[item] if item else []`) does not
## reliably produce a genuinely Array[Item]-typed array at runtime even when
## the receiving local var is annotated Array[Item] -- assigning the result
## into a real typed-array property (Resource.output_items etc.) then fails
## with "Trying to assign an array of type Array to a variable of type
## Array[Item]". Building the array via .append() on an already-typed empty
## array sidesteps this entirely.
func _single_item_array(item: Item) -> Array[Item]:
	var result: Array[Item] = []
	if item:
		result.append(item)
	return result

func _single_int_array(value: int) -> Array[int]:
	var result: Array[int] = []
	result.append(value)
	return result

const COLUMN_RESIZE_MIN_WIDTH: float = 80.0

## Lays out three columns (item picker | recipe list | properties) with a
## draggable handle after each of the two fixed-width left columns, so both
## are freely resizable while the (expand-fill) rightmost column auto-fills
## whatever's left. Built as a plain HBoxContainer with hand-rolled drag
## handles rather than nested SplitContainers -- nested SplitContainers
## proved unreliable to drag here (the side columns kept getting starved to
## their bare minimum with no usable slack), and directly driving each
## column's custom_minimum_size on drag is simple to reason about and
## guaranteed to respond to every drag.
func _three_column_split(left: Control, center: Control, right: Control) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(_column_resize_handle(left, 1.0))
	row.add_child(center)
	row.add_child(_column_resize_handle(center, 1.0))
	row.add_child(right)
	return row

## A thin draggable handle that resizes `target` by directly adjusting its
## custom_minimum_size.x as the mouse moves. `direction` is 1.0 when the
## handle sits to target's right (dragging right widens it) or -1.0 when it
## sits to target's left (dragging left widens it).
func _column_resize_handle(target: Control, direction: float) -> Control:
	var handle := VSeparator.new()
	handle.custom_minimum_size = Vector2(6, 0)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_HSPLIT
	# Boxed in a single-element array so the closure below can mutate it.
	# Only a press that lands directly on the handle arms this -- native
	# item drag-and-drop also delivers left-button-held MOUSE_MOTION to
	# every control the cursor sweeps over (so it can poll _can_drop_data),
	# and without this guard that motion was mistaken for a resize drag.
	var dragging := [false]
	handle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging[0] = event.pressed
		elif event is InputEventMouseMotion and dragging[0]:
			var new_width: float = target.custom_minimum_size.x + event.relative.x * direction
			target.custom_minimum_size.x = maxf(COLUMN_RESIZE_MIN_WIDTH, new_width)
	)
	return handle

## One reusable item slot (shape cell, output slot, or a smelting input row's
## slot) wired to the given callbacks -- the shared building block every tab
## uses for "drag an item onto this spot".
func _make_drop_cell(index: int, on_dropped: Callable, on_cleared: Callable) -> RecipeEditorShapeCell:
	var cell: RecipeEditorShapeCell = ShapeCellScript.new()
	cell.cell_index = index
	cell.item_dropped.connect(on_dropped)
	cell.cell_cleared.connect(on_cleared)
	return cell

func _populate_item_grid(grid: GridContainer, filter_text: String) -> void:
	for child in grid.get_children():
		child.queue_free()
	var lower := filter_text.to_lower()
	for item in all_items:
		if not lower.is_empty() and not item.name.to_lower().contains(lower):
			continue
		var button: RecipeEditorItemButton = ItemButtonScript.new()
		button.setup(item)
		button.right_clicked.connect(_on_item_right_clicked)
		button.drag_started.connect(_disarm)
		if item == _armed_item:
			button.armed = true
			_armed_button = button
		grid.add_child(button)

## Returns the currently-armed Item to paint with (or null) -- wired up as
## the crafting shape grid cells' paint_source.
func _get_armed_item() -> Item:
	return _armed_item

func _disarm() -> void:
	if is_instance_valid(_armed_button):
		_armed_button.armed = false
	_armed_button = null
	_armed_item = null

## Right-clicking the armed item's button again disarms it; right-clicking
## a different item arms that one instead (only one item is armed at a time).
func _on_item_right_clicked(button: RecipeEditorItemButton) -> void:
	if _armed_item == button.item:
		_disarm()
		return
	_disarm()
	_armed_item = button.item
	_armed_button = button
	button.armed = true

func _item_picker_panel(on_filter_changed: Callable) -> Dictionary:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter items..."
	filter.text_changed.connect(on_filter_changed)
	box.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 3
	scroll.add_child(grid)
	box.add_child(scroll)
	scroll.resized.connect(func() -> void: _update_item_grid_columns(grid, scroll.size.x))
	return {"box": box, "grid": grid}

## Recomputes how many item-icon columns fit in the given width, so the
## picker grid re-flows to use more columns as its panel is resized wider
## (rather than staying at a fixed column count and wasting the extra space).
func _update_item_grid_columns(grid: GridContainer, available_width: float) -> void:
	var separation: float = grid.get_theme_constant("h_separation")
	var column_width: float = RecipeEditorItemButton.ICON_SIZE.x + separation
	grid.columns = maxi(1, floori((available_width + separation) / column_width))

## Builds a generic list column (list + New/Delete buttons); label/icon
## content is filled in by the caller's refresh function. Used for the
## recipe lists and the item list alike.
func _recipe_list_panel(on_selected: Callable, on_new: Callable, on_delete: Callable) -> Dictionary:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(160, 0)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.fixed_icon_size = Vector2(24, 24)
	list.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	list.item_selected.connect(on_selected)
	box.add_child(list)
	var buttons := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New"
	new_button.pressed.connect(on_new)
	buttons.add_child(new_button)
	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(on_delete)
	buttons.add_child(delete_button)
	box.add_child(buttons)
	return {"box": box, "list": list}

func _confirm_delete(prompt: String, on_confirmed: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = prompt
	add_child(dialog)
	dialog.confirmed.connect(on_confirmed)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

# ----------------------------------------------------------------- item tab --

func _build_item_tab() -> Control:
	var list_panel := _recipe_list_panel(_on_item_selected, _on_item_new, _on_item_delete)
	_item_list = list_panel["list"]

	var props_box := VBoxContainer.new()
	props_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	props_box.add_child(_label("Icon"))
	var icon_row := HBoxContainer.new()
	_item_icon_preview = TextureRect.new()
	_item_icon_preview.custom_minimum_size = RecipeEditorItemButton.ICON_SIZE
	_item_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_row.add_child(_item_icon_preview)
	var icon_buttons := VBoxContainer.new()
	var choose_icon_button := Button.new()
	choose_icon_button.text = "Choose Icon..."
	choose_icon_button.pressed.connect(_on_choose_icon_pressed)
	icon_buttons.add_child(choose_icon_button)
	var clear_icon_button := Button.new()
	clear_icon_button.text = "Clear"
	clear_icon_button.pressed.connect(_on_clear_icon_pressed)
	icon_buttons.add_child(clear_icon_button)
	icon_row.add_child(icon_buttons)
	props_box.add_child(icon_row)

	props_box.add_child(_label("Name"))
	_item_name = LineEdit.new()
	_item_name.text_changed.connect(_on_item_name_changed)
	props_box.add_child(_item_name)

	props_box.add_child(_label("Item ID"))
	_item_id = LineEdit.new()
	_item_id.text_changed.connect(_on_item_id_changed)
	props_box.add_child(_item_id)

	props_box.add_child(_label("Description"))
	_item_description = TextEdit.new()
	_item_description.custom_minimum_size = Vector2(0, 60)
	_item_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_item_description.text_changed.connect(_on_item_description_changed)
	props_box.add_child(_item_description)

	props_box.add_child(_label("Max Stack Size"))
	_item_max_stack_size = _spin_box(1, 9999, 1)
	_item_max_stack_size.value_changed.connect(_on_item_max_stack_size_changed)
	props_box.add_child(_item_max_stack_size)

	props_box.add_child(_label("Value"))
	_item_value = _spin_box(0, 999999, 1)
	_item_value.value_changed.connect(_on_item_value_changed)
	props_box.add_child(_item_value)

	_item_is_consumable = CheckBox.new()
	_item_is_consumable.text = "Is Consumable"
	_item_is_consumable.toggled.connect(_on_item_is_consumable_toggled)
	props_box.add_child(_item_is_consumable)

	props_box.add_child(_label("Item Type"))
	_item_type_option = OptionButton.new()
	for i in ITEM_TYPE_NAMES.size():
		_item_type_option.add_item(ITEM_TYPE_NAMES[i], i)
	_item_type_option.item_selected.connect(_on_item_type_changed)
	props_box.add_child(_item_type_option)

	props_box.add_child(_label("Placed Scene"))
	var scene_row := HBoxContainer.new()
	# Not the shared _label() helper -- its word-wrap is meant for the long
	# instructional text elsewhere, but on a short status label squeezed
	# into a tight horizontal row it degrades to wrapping letter-by-letter
	# (e.g. "None" rendering as one character per line) instead of just
	# truncating. This one takes the row's spare width and ellipsizes
	# instead of wrapping.
	_item_placed_scene_path_label = Label.new()
	_item_placed_scene_path_label.text = "None"
	_item_placed_scene_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_placed_scene_path_label.clip_text = true
	_item_placed_scene_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	scene_row.add_child(_item_placed_scene_path_label)
	var choose_scene_button := Button.new()
	choose_scene_button.text = "Choose..."
	choose_scene_button.pressed.connect(_on_choose_placed_scene_pressed)
	scene_row.add_child(choose_scene_button)
	var clear_scene_button := Button.new()
	clear_scene_button.text = "Clear"
	clear_scene_button.pressed.connect(_on_clear_placed_scene_pressed)
	scene_row.add_child(clear_scene_button)
	props_box.add_child(scene_row)

	_item_tool_section = VBoxContainer.new()
	_item_tool_section.add_child(_label("Tool Type"))
	_item_tool_type_option = OptionButton.new()
	for tool_name in Item.TOOL_TYPE_NAMES.values():
		_item_tool_type_option.add_item(tool_name)
	_item_tool_type_option.item_selected.connect(_on_item_tool_type_changed)
	_item_tool_section.add_child(_item_tool_type_option)

	_item_tool_section.add_child(_label("Tool Tier"))
	var tier_row := HBoxContainer.new()
	_item_tool_tier_option = OptionButton.new()
	_item_tool_tier_option.item_selected.connect(_on_item_tool_tier_changed)
	tier_row.add_child(_item_tool_tier_option)
	var new_tier_button := Button.new()
	new_tier_button.text = "New Tier..."
	new_tier_button.pressed.connect(_on_new_tool_tier_pressed)
	tier_row.add_child(new_tier_button)
	_item_tool_section.add_child(tier_row)
	_refresh_tool_tier_option_button()
	props_box.add_child(_item_tool_section)

	_item_fuel_section = VBoxContainer.new()
	_item_fuel_section.add_child(_label("Smelt Count"))
	_item_smelt_count = _spin_box(1, 9999, 1)
	_item_smelt_count.value_changed.connect(_on_item_smelt_count_changed)
	_item_fuel_section.add_child(_item_smelt_count)
	props_box.add_child(_item_fuel_section)

	# Wrapped in a ScrollContainer rather than added to the row directly --
	# without this, the properties panel's own minimum height (all its
	# fields stacked up) pushes the whole row taller than the window, which
	# both clips fields off the bottom on a small window AND starves the
	# item list of the scrollable height it needs (the row stretches every
	# column to its own oversized height, so the list never has to scroll
	# internally even though most of it renders off-screen). Isolating the
	# properties panel's height here also means toggling the tool/fuel
	# sections' visibility only reflows inside this scroll region instead of
	# jumping the item list and resize handle around every time you switch
	# selected items.
	# Padding on one shared wrapper rather than on each field/button
	# individually -- every row in props_box (fields, spin boxes, the icon
	# and placed-scene button rows) gets the same breathing room from the
	# scroll edge this way, instead of every widget needing its own margin.
	var props_margin := MarginContainer.new()
	# MarginContainer defaults to SIZE_FILL (no expand), unlike props_box
	# below which explicitly opts into SIZE_EXPAND_FILL -- without copying
	# that flag here, this wrapper (and everything inside it) collapses to
	# its natural minimum width instead of stretching to fill the scroll
	# area, undoing the "span the whole panel" behavior props_box already had.
	props_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	props_margin.add_theme_constant_override("margin_right", 12)
	props_margin.add_child(props_box)

	var props_scroll := ScrollContainer.new()
	props_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	props_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	props_scroll.add_child(props_margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(list_panel["box"])
	row.add_child(_column_resize_handle(list_panel["box"], 1.0))
	row.add_child(props_scroll)
	return row

## Shows/hides the tool-only and fuel-only sections -- mirrors the gating in
## Item._get_property_list() (src/resources/items/item.gd) so this hand-built
## panel stays in lockstep with what actually gets serialized. If that
## function's branches ever change, update this to match.
func _update_item_conditional_sections(item_type: Item.ItemType) -> void:
	_item_tool_section.visible = (item_type == Item.ItemType.TOOL)
	_item_fuel_section.visible = (item_type == Item.ItemType.FUEL)

func _item_label(item: Item, index: int) -> String:
	return item.name if not item.name.is_empty() else "Item #%d" % (index + 1)

func _refresh_item_list() -> void:
	_item_list.clear()
	for i in all_items.size():
		_item_list.add_item(_item_label(all_items[i], i), all_items[i].icon)
	if _selected_item_index >= 0 and _selected_item_index < _item_list.item_count:
		_item_list.select(_selected_item_index)

func _on_item_selected(index: int) -> void:
	_selected_item_index = index
	var item := all_items[index]
	_item_icon_preview.texture = item.icon
	_item_name.text = item.name
	_item_id.text = item.item_id
	_item_description.text = item.description
	_item_max_stack_size.value = item.max_stack_size
	_item_value.value = item.value
	_item_is_consumable.button_pressed = item.is_consumable
	_item_type_option.select(item.item_type)
	_item_placed_scene_path_label.text = item.placed_scene.resource_path if item.placed_scene else "None"
	_item_tool_type_option.select(item.tool_type)
	_select_tool_tier_option(item.tool_tier)
	_item_smelt_count.value = item.smelt_count
	_update_item_conditional_sections(item.item_type)
	_set_item_properties_enabled(true)

func _on_item_name_changed(text: String) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].name = text
	_refresh_item_list()
	_populate_item_grid(_crafting_item_grid, "")
	_populate_item_grid(_smelting_item_grid, "")

func _on_item_id_changed(text: String) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].item_id = text

func _on_item_description_changed() -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].description = _item_description.text

func _on_item_max_stack_size_changed(value: float) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].max_stack_size = int(value)

func _on_item_value_changed(value: float) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].value = int(value)

func _on_item_is_consumable_toggled(pressed: bool) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].is_consumable = pressed

func _on_item_type_changed(index: int) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].item_type = index
	_update_item_conditional_sections(index as Item.ItemType)

func _on_item_tool_type_changed(index: int) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].tool_type = index

func _on_item_smelt_count_changed(value: float) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].smelt_count = int(value)

func _refresh_tool_tier_option_button() -> void:
	_item_tool_tier_option.clear()
	for i in _all_tool_tiers.size():
		_item_tool_tier_option.add_item(_all_tool_tiers[i].resource_path.get_file().get_basename(), i)

func _select_tool_tier_option(tier: ToolTierType) -> void:
	_item_tool_tier_option.select(_all_tool_tiers.find(tier))

func _on_item_tool_tier_changed(index: int) -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].tool_tier = _all_tool_tiers[index]

## Opens a small dialog to author a brand new ToolTierType resource (shared
## across every tool of that material, matching how tool_tier_wood/copper/
## iron.tres are each referenced by several tools rather than duplicated).
func _on_new_tool_tier_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "New Tool Tier"
	var box := VBoxContainer.new()
	box.add_child(_label("File name (saved under src/resources/items/tools/tiers/)"))
	var name_edit := LineEdit.new()
	name_edit.text = "tool_tier_new.tres"
	box.add_child(name_edit)
	box.add_child(_label("Durability"))
	var durability_spin := _spin_box(1, 999, 1)
	durability_spin.value = 3
	box.add_child(durability_spin)
	box.add_child(_label("Required Level"))
	var level_spin := _spin_box(1, 999, 1)
	level_spin.value = 1
	box.add_child(level_spin)
	var error_label := _label("")
	box.add_child(error_label)
	dialog.add_child(box)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var path := NEW_TOOL_TIER_DIR.path_join(name_edit.text)
		if ResourceLoader.exists(path):
			error_label.text = "A tier already exists at that path -- pick a different name."
			return
		var tier := ToolTierType.new()
		tier.durability = int(durability_spin.value)
		tier.required_level = int(level_spin.value)
		if ResourceSaver.save(tier, path) != OK:
			error_label.text = "Failed to save tier."
			return
		tier.take_over_path(path)
		_all_tool_tiers.append(tier)
		_refresh_tool_tier_option_button()
		_select_tool_tier_option(tier)
		if _selected_item_index >= 0:
			all_items[_selected_item_index].tool_tier = tier
		dialog.hide()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _on_choose_icon_pressed() -> void:
	if _selected_item_index < 0:
		return
	var item := all_items[_selected_item_index]
	# The quick-open dialog is drawn inside the main editor's own window, so
	# it can only render above the recipe editor's separate floating window
	# by raising the main editor window itself for the moment it's open --
	# there's no direct handle to the dialog's own window to raise instead.
	# The recipe editor window is brought back to the front the instant the
	# dialog closes so it doesn't stay stuck behind the main editor.
	EditorInterface.get_base_control().get_window().move_to_foreground()
	EditorInterface.popup_quick_open(func(path: String) -> void:
		get_window().move_to_foreground()
		if path.is_empty():
			return
		var texture := ResourceLoader.load(path) as Texture2D
		if texture:
			_open_atlas_region_popup(texture, item)
	, PackedStringArray(["Texture2D"]))

## Pops up the click-drag atlas-region picker, seeded from `item`'s existing
## icon when it's already an AtlasTexture cropped from this same source
## texture, so re-cropping an icon starts from its current region instead of
## blank.
func _open_atlas_region_popup(texture: Texture2D, item: Item) -> void:
	var window := Window.new()
	window.title = "Select Icon Region"
	window.size = Vector2i(560, 560)
	var picker: Control = AtlasRegionPickerScript.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(picker)
	picker.source_texture = texture
	if item.icon is AtlasTexture and item.icon.atlas and item.icon.atlas.resource_path == texture.resource_path:
		picker.set_initial_region(item.icon.region)
	add_child(window)
	window.popup_centered()
	# Same reasoning as the quick-open dialog above -- this window can spawn
	# behind the recipe editor's own floating window otherwise.
	window.move_to_foreground()
	picker.region_selected.connect(func(region: Rect2) -> void:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = region
		item.icon = atlas
		if _selected_item_index >= 0 and all_items[_selected_item_index] == item:
			_item_icon_preview.texture = atlas
		_refresh_item_list()
		_populate_item_grid(_crafting_item_grid, "")
		_populate_item_grid(_smelting_item_grid, "")
		window.queue_free()
	)
	picker.canceled.connect(window.queue_free)
	window.close_requested.connect(window.queue_free)

func _on_clear_icon_pressed() -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].icon = null
	_item_icon_preview.texture = null
	_refresh_item_list()
	_populate_item_grid(_crafting_item_grid, "")
	_populate_item_grid(_smelting_item_grid, "")

func _on_choose_placed_scene_pressed() -> void:
	if _selected_item_index < 0:
		return
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tscn", "Scenes")
	dialog.current_dir = "res://src/levels/"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var scene := ResourceLoader.load(path) as PackedScene
		all_items[_selected_item_index].placed_scene = scene
		_item_placed_scene_path_label.text = path if scene else "None"
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func _on_clear_placed_scene_pressed() -> void:
	if _selected_item_index < 0:
		return
	all_items[_selected_item_index].placed_scene = null
	_item_placed_scene_path_label.text = "None"

func _on_item_new() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tres", "Item Resource")
	dialog.current_dir = NEW_ITEM_DEFAULT_DIR
	dialog.current_file = "new_item.tres"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var item := Item.new()
		var saved_name := path.get_file().get_basename()
		item.item_id = saved_name
		item.name = saved_name.capitalize()
		if ResourceSaver.save(item, path) != OK:
			_save_status_label.text = "Failed to create item."
			_save_status_timer.start()
			return
		item.take_over_path(path)
		all_items.append(item)
		_refresh_item_list()
		_populate_item_grid(_crafting_item_grid, "")
		_populate_item_grid(_smelting_item_grid, "")
		var new_index := all_items.size() - 1
		_item_list.select(new_index)
		_on_item_selected(new_index)
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func _on_item_delete() -> void:
	if _selected_item_index < 0:
		return
	var item := all_items[_selected_item_index]
	var reference_count := _count_recipe_references(item)
	var prompt := "Delete item '%s'?" % item.name
	if reference_count > 0:
		prompt += "\n\nWarning: %d recipe(s) reference this item. Deleting it will leave those recipes with a missing item reference." % reference_count
	_confirm_delete(prompt, func() -> void:
		if _armed_item == item:
			_disarm()
		if not item.resource_path.is_empty():
			var dir := DirAccess.open(item.resource_path.get_base_dir())
			if dir:
				dir.remove(item.resource_path.get_file())
		all_items.remove_at(_selected_item_index)
		_selected_item_index = -1
		_refresh_item_list()
		_set_item_properties_enabled(false)
		_populate_item_grid(_crafting_item_grid, "")
		_populate_item_grid(_smelting_item_grid, "")
	)

func _count_recipe_references(item: Item) -> int:
	var count := 0
	for recipe in crafting_db.recipes:
		var referenced := false
		for cell in recipe.shape:
			if cell == item:
				referenced = true
		for output in recipe.output_items:
			if output == item:
				referenced = true
		if referenced:
			count += 1
	for recipe in smelting_db.recipes:
		var referenced := false
		for input in recipe.input_items:
			if input == item:
				referenced = true
		for output in recipe.output_items:
			if output == item:
				referenced = true
		if referenced:
			count += 1
	for recipe in blast_furnace_db.recipes:
		var referenced := false
		for input in recipe.input_items:
			if input == item:
				referenced = true
		for output in recipe.output_items:
			if output == item:
				referenced = true
		if referenced:
			count += 1
	return count

func _set_item_properties_enabled(enabled: bool) -> void:
	_item_name.editable = enabled
	_item_id.editable = enabled
	_item_description.editable = enabled
	_item_max_stack_size.editable = enabled
	_item_value.editable = enabled
	_item_is_consumable.disabled = not enabled
	_item_type_option.disabled = not enabled
	_item_tool_type_option.disabled = not enabled
	_item_tool_tier_option.disabled = not enabled
	_item_smelt_count.editable = enabled
	if not enabled:
		_item_icon_preview.texture = null
		_item_name.text = ""
		_item_id.text = ""
		_item_description.text = ""
		_item_placed_scene_path_label.text = "None"
		_item_tool_section.visible = false
		_item_fuel_section.visible = false

# ------------------------------------------------------------ crafting tab --

func _build_crafting_tab() -> Control:
	var picker := _item_picker_panel(func(text: String) -> void: _populate_item_grid(_crafting_item_grid, text))
	_crafting_item_grid = picker["grid"]
	_populate_item_grid(_crafting_item_grid, "")

	var props_box := VBoxContainer.new()
	props_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props_box.add_child(_label("Shape (right-click an item to arm painting, then click/drag cells; or drag items directly; right-click a cell to clear)"))
	var shape_grid := GridContainer.new()
	var grid_size: Vector2i = ShapedCraftingRecipe.WORKBENCH_GRID_SIZE[ShapedCraftingRecipe.WorkbenchType.CRAFTING_BENCH]
	shape_grid.columns = grid_size.x
	for i in ShapedCraftingRecipe.SHAPE_SIZE * ShapedCraftingRecipe.SHAPE_SIZE:
		var cell := _make_drop_cell(i, _on_crafting_shape_cell_item_dropped, _on_crafting_shape_cell_cleared)
		cell.paint_source = _get_armed_item
		_crafting_shape_cells.append(cell)
		shape_grid.add_child(cell)
	props_box.add_child(shape_grid)

	props_box.add_child(_label("Output (drag an item here)"))
	var output_row := HBoxContainer.new()
	_crafting_output_cell = _make_drop_cell(0, _on_crafting_output_dropped, _on_crafting_output_cleared)
	output_row.add_child(_crafting_output_cell)
	_crafting_output_qty = _spin_box(1, 999, 1)
	_crafting_output_qty.value_changed.connect(_on_crafting_output_qty_changed)
	output_row.add_child(_crafting_output_qty)
	props_box.add_child(output_row)

	props_box.add_child(_label("Skill"))
	_crafting_skill = _skill_option_button()
	_crafting_skill.item_selected.connect(_on_crafting_skill_changed)
	props_box.add_child(_crafting_skill)

	props_box.add_child(_label("Experience Gain"))
	_crafting_exp = _spin_box(0, 99999, 1)
	_crafting_exp.value_changed.connect(_on_crafting_exp_changed)
	props_box.add_child(_crafting_exp)

	props_box.add_child(_label("Level Requirement"))
	_crafting_level = _spin_box(0, 99, 1)
	_crafting_level.value_changed.connect(_on_crafting_level_changed)
	props_box.add_child(_crafting_level)

	var list_panel := _recipe_list_panel(_on_crafting_recipe_selected, _on_crafting_new_recipe, _on_crafting_delete_recipe)
	_crafting_list = list_panel["list"]

	return _three_column_split(picker["box"], list_panel["box"], props_box)

func _crafting_recipe_label(recipe: ShapedCraftingRecipe, index: int) -> String:
	if not recipe.output_items.is_empty() and recipe.output_items[0]:
		return recipe.output_items[0].name
	return "Recipe #%d" % (index + 1)

func _refresh_crafting_list() -> void:
	_crafting_list.clear()
	for i in crafting_db.recipes.size():
		var recipe := crafting_db.recipes[i]
		var icon: Texture2D = recipe.output_items[0].icon if not recipe.output_items.is_empty() and recipe.output_items[0] else null
		_crafting_list.add_item(_crafting_recipe_label(recipe, i), icon)

func _on_crafting_recipe_selected(index: int) -> void:
	_selected_crafting_index = index
	var recipe := crafting_db.recipes[index]
	if recipe.shape.size() != ShapedCraftingRecipe.SHAPE_SIZE * ShapedCraftingRecipe.SHAPE_SIZE:
		recipe.shape.resize(ShapedCraftingRecipe.SHAPE_SIZE * ShapedCraftingRecipe.SHAPE_SIZE)
	for i in _crafting_shape_cells.size():
		_crafting_shape_cells[i].item = recipe.shape[i]
	_crafting_output_cell.item = recipe.output_items[0] if not recipe.output_items.is_empty() else null
	_crafting_output_qty.value = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	_crafting_skill.select(recipe.skill_type)
	_crafting_exp.value = recipe.experience_gain
	_crafting_level.value = recipe.level_requirement
	_set_crafting_properties_enabled(true)

func _on_crafting_new_recipe() -> void:
	var recipe := ShapedCraftingRecipe.new()
	recipe.shape.resize(ShapedCraftingRecipe.SHAPE_SIZE * ShapedCraftingRecipe.SHAPE_SIZE)
	crafting_db.recipes.append(recipe)
	_refresh_crafting_list()
	var new_index := crafting_db.recipes.size() - 1
	_crafting_list.select(new_index)
	_on_crafting_recipe_selected(new_index)

func _on_crafting_delete_recipe() -> void:
	if _selected_crafting_index < 0:
		return
	_confirm_delete("Delete this crafting recipe?", func() -> void:
		crafting_db.recipes.remove_at(_selected_crafting_index)
		_selected_crafting_index = -1
		_refresh_crafting_list()
		_set_crafting_properties_enabled(false)
	)

func _on_crafting_shape_cell_item_dropped(cell_index: int, item: Item) -> void:
	if _selected_crafting_index < 0:
		return
	crafting_db.recipes[_selected_crafting_index].shape[cell_index] = item

func _on_crafting_shape_cell_cleared(cell_index: int) -> void:
	if _selected_crafting_index < 0:
		return
	crafting_db.recipes[_selected_crafting_index].shape[cell_index] = null

func _on_crafting_output_dropped(_cell_index: int, item: Item) -> void:
	if _selected_crafting_index < 0:
		return
	var recipe := crafting_db.recipes[_selected_crafting_index]
	recipe.output_items = _single_item_array(item)
	if item and recipe.output_quantities.is_empty():
		recipe.output_quantities = _single_int_array(1)
	_refresh_crafting_list()

func _on_crafting_output_cleared(_cell_index: int) -> void:
	if _selected_crafting_index < 0:
		return
	crafting_db.recipes[_selected_crafting_index].output_items = _single_item_array(null)
	_refresh_crafting_list()

func _on_crafting_output_qty_changed(value: float) -> void:
	if _selected_crafting_index < 0:
		return
	var recipe := crafting_db.recipes[_selected_crafting_index]
	if recipe.output_quantities.is_empty():
		recipe.output_quantities = _single_int_array(int(value))
	else:
		recipe.output_quantities[0] = int(value)

func _on_crafting_skill_changed(index: int) -> void:
	if _selected_crafting_index < 0:
		return
	crafting_db.recipes[_selected_crafting_index].skill_type = index

func _on_crafting_exp_changed(value: float) -> void:
	if _selected_crafting_index < 0:
		return
	crafting_db.recipes[_selected_crafting_index].experience_gain = int(value)

func _on_crafting_level_changed(value: float) -> void:
	if _selected_crafting_index < 0:
		return
	crafting_db.recipes[_selected_crafting_index].level_requirement = int(value)

func _set_crafting_properties_enabled(enabled: bool) -> void:
	for cell in _crafting_shape_cells:
		cell.set_enabled(enabled)
	_crafting_output_cell.set_enabled(enabled)
	_crafting_output_qty.editable = enabled
	_crafting_skill.disabled = not enabled
	_crafting_exp.editable = enabled
	_crafting_level.editable = enabled

# ------------------------------------------------------------ smelting tab --

func _build_smelting_tab() -> Control:
	var picker := _item_picker_panel(func(text: String) -> void: _populate_item_grid(_smelting_item_grid, text))
	_smelting_item_grid = picker["grid"]
	_populate_item_grid(_smelting_item_grid, "")

	var props_box := VBoxContainer.new()
	props_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props_box.add_child(_label("Inputs (drag items onto slots, right-click to clear)"))
	_smelting_inputs_box = VBoxContainer.new()
	props_box.add_child(_smelting_inputs_box)
	var add_input_button := Button.new()
	add_input_button.text = "Add Input"
	add_input_button.pressed.connect(_on_smelting_add_input)
	props_box.add_child(add_input_button)

	props_box.add_child(_label("Output (drag an item here)"))
	var output_row := HBoxContainer.new()
	_smelting_output_cell = _make_drop_cell(0, _on_smelting_output_dropped, _on_smelting_output_cleared)
	output_row.add_child(_smelting_output_cell)
	_smelting_output_qty = _spin_box(1, 999, 1)
	_smelting_output_qty.value_changed.connect(_on_smelting_output_qty_changed)
	output_row.add_child(_smelting_output_qty)
	props_box.add_child(output_row)

	props_box.add_child(_label("Skill"))
	_smelting_skill = _skill_option_button()
	_smelting_skill.item_selected.connect(_on_smelting_skill_changed)
	props_box.add_child(_smelting_skill)

	props_box.add_child(_label("Experience Gain"))
	_smelting_exp = _spin_box(0, 99999, 1)
	_smelting_exp.value_changed.connect(_on_smelting_exp_changed)
	props_box.add_child(_smelting_exp)

	props_box.add_child(_label("Level Requirement"))
	_smelting_level = _spin_box(0, 99, 1)
	_smelting_level.value_changed.connect(_on_smelting_level_changed)
	props_box.add_child(_smelting_level)

	props_box.add_child(_label("Craft Time (s)"))
	_smelting_craft_time = _spin_box(0, 999, 0.1)
	_smelting_craft_time.value_changed.connect(_on_smelting_craft_time_changed)
	props_box.add_child(_smelting_craft_time)

	var list_panel := _recipe_list_panel(_on_smelting_recipe_selected, _on_smelting_new_recipe, _on_smelting_delete_recipe)
	_smelting_list = list_panel["list"]

	return _three_column_split(picker["box"], list_panel["box"], props_box)

func _smelting_recipe_label(recipe: SmeltingRecipe, index: int) -> String:
	if not recipe.output_items.is_empty() and recipe.output_items[0]:
		return recipe.output_items[0].name
	return "Recipe #%d" % (index + 1)

func _refresh_smelting_list() -> void:
	_smelting_list.clear()
	for i in smelting_db.recipes.size():
		var recipe := smelting_db.recipes[i]
		var icon: Texture2D = recipe.output_items[0].icon if not recipe.output_items.is_empty() and recipe.output_items[0] else null
		_smelting_list.add_item(_smelting_recipe_label(recipe, i), icon)

func _on_smelting_recipe_selected(index: int) -> void:
	_selected_smelting_index = index
	var recipe := smelting_db.recipes[index]
	_rebuild_smelting_input_rows(recipe)
	_smelting_output_cell.item = recipe.output_items[0] if not recipe.output_items.is_empty() else null
	_smelting_output_qty.value = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	_smelting_skill.select(recipe.skill_type)
	_smelting_exp.value = recipe.experience_gain
	_smelting_level.value = recipe.level_requirement
	_smelting_craft_time.value = recipe.craft_time
	_set_smelting_properties_enabled(true)

func _rebuild_smelting_input_rows(recipe: SmeltingRecipe) -> void:
	for child in _smelting_inputs_box.get_children():
		child.queue_free()
	for i in recipe.input_items.size():
		var row := HBoxContainer.new()
		var cell := _make_drop_cell(i, _on_smelting_input_dropped, _on_smelting_input_cleared)
		cell.item = recipe.input_items[i]
		row.add_child(cell)
		var qty := _spin_box(1, 999, 1)
		qty.value = recipe.input_quantities[i] if i < recipe.input_quantities.size() else 1
		qty.value_changed.connect(func(v: float) -> void: recipe.input_quantities[i] = int(v))
		row.add_child(qty)
		var remove_button := Button.new()
		remove_button.text = "x"
		remove_button.pressed.connect(func() -> void:
			recipe.input_items.remove_at(i)
			recipe.input_quantities.remove_at(i)
			_rebuild_smelting_input_rows(recipe)
		)
		row.add_child(remove_button)
		_smelting_inputs_box.add_child(row)

func _on_smelting_input_dropped(cell_index: int, item: Item) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].input_items[cell_index] = item

func _on_smelting_input_cleared(cell_index: int) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].input_items[cell_index] = null

func _on_smelting_new_recipe() -> void:
	var recipe := SmeltingRecipe.new()
	smelting_db.recipes.append(recipe)
	_refresh_smelting_list()
	var new_index := smelting_db.recipes.size() - 1
	_smelting_list.select(new_index)
	_on_smelting_recipe_selected(new_index)

func _on_smelting_delete_recipe() -> void:
	if _selected_smelting_index < 0:
		return
	_confirm_delete("Delete this smelting recipe?", func() -> void:
		smelting_db.recipes.remove_at(_selected_smelting_index)
		_selected_smelting_index = -1
		_refresh_smelting_list()
		_set_smelting_properties_enabled(false)
	)

func _on_smelting_add_input() -> void:
	if _selected_smelting_index < 0:
		return
	var recipe := smelting_db.recipes[_selected_smelting_index]
	recipe.input_items.append(null)
	recipe.input_quantities.append(1)
	_rebuild_smelting_input_rows(recipe)

func _on_smelting_output_dropped(_cell_index: int, item: Item) -> void:
	if _selected_smelting_index < 0:
		return
	var recipe := smelting_db.recipes[_selected_smelting_index]
	recipe.output_items = _single_item_array(item)
	if item and recipe.output_quantities.is_empty():
		recipe.output_quantities = _single_int_array(1)
	_refresh_smelting_list()

func _on_smelting_output_cleared(_cell_index: int) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].output_items = _single_item_array(null)
	_refresh_smelting_list()

func _on_smelting_output_qty_changed(value: float) -> void:
	if _selected_smelting_index < 0:
		return
	var recipe := smelting_db.recipes[_selected_smelting_index]
	if recipe.output_quantities.is_empty():
		recipe.output_quantities = _single_int_array(int(value))
	else:
		recipe.output_quantities[0] = int(value)

func _on_smelting_skill_changed(index: int) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].skill_type = index

func _on_smelting_exp_changed(value: float) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].experience_gain = int(value)

func _on_smelting_level_changed(value: float) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].level_requirement = int(value)

func _on_smelting_craft_time_changed(value: float) -> void:
	if _selected_smelting_index < 0:
		return
	smelting_db.recipes[_selected_smelting_index].craft_time = value

func _set_smelting_properties_enabled(enabled: bool) -> void:
	_smelting_output_cell.set_enabled(enabled)
	_smelting_output_qty.editable = enabled
	_smelting_skill.disabled = not enabled
	_smelting_exp.editable = enabled
	_smelting_level.editable = enabled
	_smelting_craft_time.editable = enabled

# ------------------------------------------------------------- blast furnace tab --
## Reuses SmeltingRecipe/SmeltingRecipeDatabase (a second, separate database
## file loaded into blast_furnace_db) rather than a distinct resource type --
## a blast furnace recipe is structurally identical to a smelting recipe
## (parallel input_items/input_quantities arrays), just consumed by a
## different machine with two physical input slots instead of one. This
## whole section otherwise mirrors the Smelting tab above 1:1.

func _build_blast_furnace_tab() -> Control:
	var picker := _item_picker_panel(func(text: String) -> void: _populate_item_grid(_blast_furnace_item_grid, text))
	_blast_furnace_item_grid = picker["grid"]
	_populate_item_grid(_blast_furnace_item_grid, "")

	var props_box := VBoxContainer.new()
	props_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props_box.add_child(_label("Inputs (drag items onto slots, right-click to clear)"))
	_blast_furnace_inputs_box = VBoxContainer.new()
	props_box.add_child(_blast_furnace_inputs_box)
	var add_input_button := Button.new()
	add_input_button.text = "Add Input"
	add_input_button.pressed.connect(_on_blast_furnace_add_input)
	props_box.add_child(add_input_button)

	props_box.add_child(_label("Output (drag an item here)"))
	var output_row := HBoxContainer.new()
	_blast_furnace_output_cell = _make_drop_cell(0, _on_blast_furnace_output_dropped, _on_blast_furnace_output_cleared)
	output_row.add_child(_blast_furnace_output_cell)
	_blast_furnace_output_qty = _spin_box(1, 999, 1)
	_blast_furnace_output_qty.value_changed.connect(_on_blast_furnace_output_qty_changed)
	output_row.add_child(_blast_furnace_output_qty)
	props_box.add_child(output_row)

	props_box.add_child(_label("Skill"))
	_blast_furnace_skill = _skill_option_button()
	_blast_furnace_skill.item_selected.connect(_on_blast_furnace_skill_changed)
	props_box.add_child(_blast_furnace_skill)

	props_box.add_child(_label("Experience Gain"))
	_blast_furnace_exp = _spin_box(0, 99999, 1)
	_blast_furnace_exp.value_changed.connect(_on_blast_furnace_exp_changed)
	props_box.add_child(_blast_furnace_exp)

	props_box.add_child(_label("Level Requirement"))
	_blast_furnace_level = _spin_box(0, 99, 1)
	_blast_furnace_level.value_changed.connect(_on_blast_furnace_level_changed)
	props_box.add_child(_blast_furnace_level)

	props_box.add_child(_label("Craft Time (s)"))
	_blast_furnace_craft_time = _spin_box(0, 999, 0.1)
	_blast_furnace_craft_time.value_changed.connect(_on_blast_furnace_craft_time_changed)
	props_box.add_child(_blast_furnace_craft_time)

	var list_panel := _recipe_list_panel(_on_blast_furnace_recipe_selected, _on_blast_furnace_new_recipe, _on_blast_furnace_delete_recipe)
	_blast_furnace_list = list_panel["list"]

	return _three_column_split(picker["box"], list_panel["box"], props_box)

func _blast_furnace_recipe_label(recipe: SmeltingRecipe, index: int) -> String:
	if not recipe.output_items.is_empty() and recipe.output_items[0]:
		return recipe.output_items[0].name
	return "Recipe #%d" % (index + 1)

func _refresh_blast_furnace_list() -> void:
	_blast_furnace_list.clear()
	for i in blast_furnace_db.recipes.size():
		var recipe := blast_furnace_db.recipes[i]
		var icon: Texture2D = recipe.output_items[0].icon if not recipe.output_items.is_empty() and recipe.output_items[0] else null
		_blast_furnace_list.add_item(_blast_furnace_recipe_label(recipe, i), icon)

func _on_blast_furnace_recipe_selected(index: int) -> void:
	_selected_blast_furnace_index = index
	var recipe := blast_furnace_db.recipes[index]
	_rebuild_blast_furnace_input_rows(recipe)
	_blast_furnace_output_cell.item = recipe.output_items[0] if not recipe.output_items.is_empty() else null
	_blast_furnace_output_qty.value = recipe.output_quantities[0] if not recipe.output_quantities.is_empty() else 1
	_blast_furnace_skill.select(recipe.skill_type)
	_blast_furnace_exp.value = recipe.experience_gain
	_blast_furnace_level.value = recipe.level_requirement
	_blast_furnace_craft_time.value = recipe.craft_time
	_set_blast_furnace_properties_enabled(true)

func _rebuild_blast_furnace_input_rows(recipe: SmeltingRecipe) -> void:
	for child in _blast_furnace_inputs_box.get_children():
		child.queue_free()
	for i in recipe.input_items.size():
		var row := HBoxContainer.new()
		var cell := _make_drop_cell(i, _on_blast_furnace_input_dropped, _on_blast_furnace_input_cleared)
		cell.item = recipe.input_items[i]
		row.add_child(cell)
		var qty := _spin_box(1, 999, 1)
		qty.value = recipe.input_quantities[i] if i < recipe.input_quantities.size() else 1
		qty.value_changed.connect(func(v: float) -> void: recipe.input_quantities[i] = int(v))
		row.add_child(qty)
		var remove_button := Button.new()
		remove_button.text = "x"
		remove_button.pressed.connect(func() -> void:
			recipe.input_items.remove_at(i)
			recipe.input_quantities.remove_at(i)
			_rebuild_blast_furnace_input_rows(recipe)
		)
		row.add_child(remove_button)
		_blast_furnace_inputs_box.add_child(row)

func _on_blast_furnace_input_dropped(cell_index: int, item: Item) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].input_items[cell_index] = item

func _on_blast_furnace_input_cleared(cell_index: int) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].input_items[cell_index] = null

func _on_blast_furnace_new_recipe() -> void:
	var recipe := SmeltingRecipe.new()
	recipe.input_items = [null, null]
	recipe.input_quantities = [1, 1]
	blast_furnace_db.recipes.append(recipe)
	_refresh_blast_furnace_list()
	var new_index := blast_furnace_db.recipes.size() - 1
	_blast_furnace_list.select(new_index)
	_on_blast_furnace_recipe_selected(new_index)

func _on_blast_furnace_delete_recipe() -> void:
	if _selected_blast_furnace_index < 0:
		return
	_confirm_delete("Delete this blast furnace recipe?", func() -> void:
		blast_furnace_db.recipes.remove_at(_selected_blast_furnace_index)
		_selected_blast_furnace_index = -1
		_refresh_blast_furnace_list()
		_set_blast_furnace_properties_enabled(false)
	)

func _on_blast_furnace_add_input() -> void:
	if _selected_blast_furnace_index < 0:
		return
	var recipe := blast_furnace_db.recipes[_selected_blast_furnace_index]
	recipe.input_items.append(null)
	recipe.input_quantities.append(1)
	_rebuild_blast_furnace_input_rows(recipe)

func _on_blast_furnace_output_dropped(_cell_index: int, item: Item) -> void:
	if _selected_blast_furnace_index < 0:
		return
	var recipe := blast_furnace_db.recipes[_selected_blast_furnace_index]
	recipe.output_items = _single_item_array(item)
	if item and recipe.output_quantities.is_empty():
		recipe.output_quantities = _single_int_array(1)
	_refresh_blast_furnace_list()

func _on_blast_furnace_output_cleared(_cell_index: int) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].output_items = _single_item_array(null)
	_refresh_blast_furnace_list()

func _on_blast_furnace_output_qty_changed(value: float) -> void:
	if _selected_blast_furnace_index < 0:
		return
	var recipe := blast_furnace_db.recipes[_selected_blast_furnace_index]
	if recipe.output_quantities.is_empty():
		recipe.output_quantities = _single_int_array(int(value))
	else:
		recipe.output_quantities[0] = int(value)

func _on_blast_furnace_skill_changed(index: int) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].skill_type = index

func _on_blast_furnace_exp_changed(value: float) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].experience_gain = int(value)

func _on_blast_furnace_level_changed(value: float) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].level_requirement = int(value)

func _on_blast_furnace_craft_time_changed(value: float) -> void:
	if _selected_blast_furnace_index < 0:
		return
	blast_furnace_db.recipes[_selected_blast_furnace_index].craft_time = value

func _set_blast_furnace_properties_enabled(enabled: bool) -> void:
	_blast_furnace_output_cell.set_enabled(enabled)
	_blast_furnace_output_qty.editable = enabled
	_blast_furnace_skill.disabled = not enabled
	_blast_furnace_exp.editable = enabled
	_blast_furnace_level.editable = enabled
	_blast_furnace_craft_time.editable = enabled
