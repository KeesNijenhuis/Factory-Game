extends Area2D
class_name InteractableContainer
## Shared proximity/facing-check interaction pattern for world objects that
## open a HUD panel when the player interacts with them (chest, furnace, and
## future workbenches). Subclasses implement _on_opened()/_on_closed() to
## show/hide their own panel, and may override _update_visual() if their open
## state isn't a simple two-frame sprite swap.
##
## sprite is typed Node2D (rather than AnimatedSprite2D) since not every
## subclass animates -- CraftingBench's is a plain static Sprite2D. Frame
## access below goes through set() rather than `.frame` so it stays a no-op
## for a node type that doesn't have that property, instead of a type error;
## subclasses that call AnimatedSprite2D-only methods (e.g. Furnace.play())
## need the same treatment.

@onready var sprite: Node2D = $AnimatedSprite2D

@export var interaction_range: float = 25
## How many tiles this object occupies on the Objects layer, anchored at its
## own cell (see AutomationUtils.get_object_footprint) -- 1x1 for every
## existing container; only a multi-tile machine like BlastFurnace overrides
## this. Placement validity, occupancy, reach checks, and belt-notification
## all key off this so a bigger object blocks/connects across every cell it
## covers, not just its anchor.
@export var grid_size: Vector2i = Vector2i(1, 1)
const REOPEN_LOCKOUT_DURATION: float = 0.3

var player_in_range: Player
var is_open: bool = false
var _reopen_lockout_until: float = 0.0
var _save_id: String = ""

## The one container currently open anywhere, if any -- at most one ever is
## (see _open()). Every read is guarded with is_instance_valid(): a container
## can be freed while it's the open one without ever going through _close()
## (e.g. a pickaxe destroying it, or a level unload via a ladder), which would
## otherwise leave this pointing at a freed instance.
static var current_open: InteractableContainer

func _ready() -> void:
	add_to_group("interactable_containers")
	_save_id = SaveSerializationUtils.compute_tile_object_id(self)
	if _save_id != "":
		add_to_group("saveable")
	area_entered.connect(_on_area_entered)
	sprite.set("frame", 0)

func _exit_tree() -> void:
	if current_open == self:
		current_open = null

func get_save_id() -> String:
	return _save_id

func _process(_delta: float) -> void:
	if is_open and player_in_range and global_position.distance_to(player_in_range.global_position) > interaction_range:
		player_in_range = null
		_close()

func _input(event: InputEvent) -> void:
	# Keyboard-only: "interact" is E-only (tool actions moved to their own
	# "tool_target_click", LMB-only, action), but this filter is kept as a
	# defensive guard against ever re-adding a mouse binding to "interact".
	if is_open and event is InputEventKey and event.is_action_pressed(&"interact"):
		# Closing only needs the player still within interaction_range (already
		# enforced by _process, which clears player_in_range once they leave it),
		# not the tighter facing check that gates opening -- otherwise stepping
		# back a little while staying open leaves E unable to close.
		if player_in_range == null:
			return
		_close()
		# The same key press still re-arms the player's HitArea this frame, which
		# would otherwise re-fire area_entered and reopen the container immediately.
		_reopen_lockout_until = Time.get_ticks_msec() / 1000.0 + REOPEN_LOCKOUT_DURATION

func _on_area_entered(area: Area2D) -> void:
	if is_open:
		# Already open: ignore spurious re-entries caused by the player's HitArea
		# re-arming every frame "interact" is held (e.g. while clicking slots).
		return
	if Time.get_ticks_msec() / 1000.0 < _reopen_lockout_until:
		return
	if area is HitArea and Input.is_action_pressed(&"interact"):
		var player := area.get_parent() as Player
		if player and _player_is_facing(player):
			player_in_range = player
			player.interaction_consumed = true
			# Opening can spawn a GroundItem (an Area2D), which the physics server
			# refuses to register while still flushing this collision callback.
			_open.call_deferred()

func _player_is_facing(player: Player) -> bool:
	# Checks only the axis implied by last_direction, not whichever axis of the
	# offset happens to be larger, since collision geometry keeps the gap on the
	# other axis small when approaching head-on.
	var offset := global_position - player.global_position
	match player.last_direction:
		"down":
			return offset.y > 0.0
		"up":
			return offset.y < 0.0
		"left":
			return offset.x < 0.0
		"right":
			return offset.x > 0.0
		_:
			return false

## Only one container is ever open at a time (current_open): opening this one
## first fully closes whichever other container currently holds that spot, if
## any -- e.g. walking straight from an open chest to a furnace and pressing E
## closes the chest (dropping any held item, same as walking away would)
## before this furnace's own panel takes over.
func _open() -> void:
	var hud := _get_hud()
	if hud == null:
		return
	if is_instance_valid(current_open) and current_open != self:
		current_open._close()
	is_open = true
	current_open = self
	_update_visual()
	var player_panel: InventoryPanel = hud.inventory_panel
	player_panel.toggle_with_inventory_key = false
	player_panel.show_inventory()
	_on_opened(hud)

## Public entry point for forcibly closing this container from outside (e.g.
## from HUD.close_all_panels(), which closes whichever container happens to
## be open without checking first).
func close_container() -> void:
	if is_open:
		_close()

func _close() -> void:
	var hud := _get_hud()
	if hud == null:
		return
	is_open = false
	if current_open == self:
		current_open = null
	player_in_range = null
	_update_visual()
	var player_panel: InventoryPanel = hud.inventory_panel
	_drop_held_item(hud)
	player_panel.toggle_with_inventory_key = true
	player_panel.hide_inventory()
	_on_closed(hud)

func _get_hud() -> HUD:
	return get_tree().root.find_child("HudRoot", true, false) as HUD

func _drop_held_item(hud: HUD) -> void:
	if is_instance_valid(hud.held_source):
		hud.held_source.call("drop_held_item")

## Default open/closed visual: swap between sprite frame 0 and 1. Override for
## containers whose visual state is driven independently of is_open (e.g. the
## furnace, whose burning animation depends on active smelting, not the panel).
func _update_visual() -> void:
	sprite.set("frame", 1 if is_open else 0)

## Override: show this container's panel and bind it to this container's data.
func _on_opened(_hud: HUD) -> void:
	pass

## Override: hide this container's panel.
func _on_closed(_hud: HUD) -> void:
	pass
