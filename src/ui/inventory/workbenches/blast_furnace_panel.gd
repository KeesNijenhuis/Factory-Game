extends InventoryPanel
class_name BlastFurnacePanel
## InventoryPanel's slot/drag machinery is reused as-is (the blast furnace's 4
## slots are just a restricted Inventory, see BlastFurnaceInventory). This
## adds only the smelt/fuel progress bars, driven by the bound BlastFurnace's
## state -- identical to FurnacePanel, just typed to BlastFurnace.

@onready var progress_bar: ProgressBar = %ProgressBar
@onready var fuel_progress_bar: ProgressBar = %FuelProgressBar

var furnace: BlastFurnace

func open_for_furnace(target: BlastFurnace) -> void:
	furnace = target
	open_for(target.inventory)
	_update_progress_bars()

func close_inventory() -> void:
	furnace = null
	super.close_inventory()
	_update_progress_bars()

func _process(delta: float) -> void:
	super._process(delta)
	_update_progress_bars()

func _update_progress_bars() -> void:
	if furnace != null and furnace.current_recipe != null:
		progress_bar.max_value = maxf(furnace.current_recipe.craft_time, 0.001)
		progress_bar.value = furnace.smelt_progress
	else:
		progress_bar.value = 0.0

	if furnace != null and furnace.fuel_burn_time_max > 0.0:
		fuel_progress_bar.max_value = furnace.fuel_burn_time_max
		fuel_progress_bar.value = furnace.fuel_burn_time_remaining
	else:
		fuel_progress_bar.value = 0.0
