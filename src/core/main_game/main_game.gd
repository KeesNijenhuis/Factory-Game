class_name MainGame
extends Node
## Main entry point for the game
## Responisble for setting up the world layers and coordinating high level systems

const STARTING_LEVEL: String = "res://src/levels/prototype_levels/cave_level.tscn"
const PROC_LEVEL: String = "res://src/levels/prototype_levels/procedural_cave_level.tscn"


const PLAYER_SCENE_UID : String = "uid://doiund6pbioe4"

@export var load_quicksave_on_start: bool = false
@export var show_initial_chunk_grid_debug_view: bool = false

signal level_loaded(level: BaseLevel)

var player: Player = null
var current_level_uid: String = ""

var _current_level: BaseLevel = null

#Game World Root Nodes
@onready var level_root: Node2D = %LevelRoot
@onready var entity_root: Node2D = %EntityRoot
@onready var effect_root: Node2D = %EffectRoot

#UI Root Nodes
@onready var pause_root: Control = %PauseRoot
@onready var transition_root: ScreenTransition = %TransitionRoot
@onready var debug_root: Control = %DebugRoot

func _ready() -> void:
	SaveManager.register_main_game(self)
	_init_player()
	var startup_data := SaveManager.prepare_startup_quickload() if load_quicksave_on_start else {}
	var startup_level: String = startup_data.get("level_uid", PROC_LEVEL)
	load_level(startup_level, not startup_data.is_empty())
	await level_loaded
	if not startup_data.is_empty():
		await SaveManager.apply_startup_quickload()
	if show_initial_chunk_grid_debug_view and _current_level.has_method("show_initial_grid_overview"):
		_current_level.show_initial_grid_overview()
	
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return

	if event.is_action_pressed(&"debug_quit"):
		quit_game()
	elif event.is_action_pressed(&"quicksave"):
		SaveManager.quicksave()
	elif event.is_action_pressed(&"quickload"):
		SaveManager.quickload()
		

## Called to quit the application
## Propagates the close request notification to every node, and then quits the application
func quit_game() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


## Loads a level scene that must extend BaseLevel.
## If `hold_transition` is true, the screen stays faded to black after the
## level finishes loading -- the caller is responsible for calling
## finish_load_transition() once it has finished restoring additional state
## (e.g. SaveManager applying saved player/world data) that must not be seen
## mid-update.
func load_level(level_scene : String, hold_transition: bool = false) -> void:
	# Make sure this is called during idle time
	_perform_level_load.call_deferred(level_scene, hold_transition)


func _perform_level_load(level_scene_uid : String, hold_transition: bool = false) -> void:
	await transition_root.fade_out()

	if is_instance_valid(_current_level):
		_current_level.queue_free()
		_current_level = null
		# Wait to allow the queued deletion to process so it is out of the scene tree
		await get_tree().process_frame


	var new_level_packed : PackedScene = (
			ResourceLoader.load(level_scene_uid, "PackedScene") as PackedScene
	)

	if new_level_packed == null:
		push_error("Could not load level as a packed scene: " + level_scene_uid)
		await transition_root.fade_in()
		return

	var new_level : Node = new_level_packed.instantiate()

	if not new_level:
		push_error("Could not instantiate new level " + level_scene_uid)
		await transition_root.fade_in()
		return

	if new_level is not BaseLevel:
		new_level.free()  # Level must be freed to avoid unreferenced orphan nodes
		push_error("Loaded level is not of type BaseLevel " + level_scene_uid)
		await transition_root.fade_in()
		return
	# FUTURE (main menu): Should have a fall back scene

	_current_level = new_level as BaseLevel
	current_level_uid = level_scene_uid

	level_root.add_child(_current_level)

	_place_player_at_level_spawn()
	_setup_level_camera()
	snap_camera_to_player()

	level_loaded.emit(_current_level)

	# TileMapLayer scene-collection cells (and therefore belts) can finish
	# instantiating a frame or two after level_loaded fires -- wait for them
	# to settle, then eagerly populate every segment's markers so a level's
	# belts look fully flowing immediately instead of trickling in one
	# marker at a time from each stretch's entry point.
	await get_tree().process_frame
	await get_tree().process_frame
	BeltManager.rebuild_all_segments()

	if not hold_transition:
		await transition_root.fade_in()


func get_current_level() -> BaseLevel:
	return _current_level

## Instantiates the player and adds it to the entity layer
func _init_player() -> void:
	var player_scene : PackedScene = ResourceLoader.load(PLAYER_SCENE_UID) as PackedScene
	if player_scene == null:
		push_error("Could not load player scene: " + PLAYER_SCENE_UID)
		return

	var player_instance : Node = player_scene.instantiate()
	if not player_instance:
		push_error("Could not instantiate player scene " + PLAYER_SCENE_UID)
		return

	if player_instance is not Player:
		player_instance.free() # Node must be freed to avoid unreferenced orphan nodes
		push_error("Loaded player scene is not of type Player " + PLAYER_SCENE_UID)
		return

	player = player_instance as Player

	entity_root.add_child(player)


## Finds the default spawn location in currently loaded level, and places
##  the Player at that position.
func _place_player_at_level_spawn() -> void:
	if player == null:
		push_error("Cannot place player in level because it is null")
		return
	if _current_level == null:
		push_error("Cannot place player into level because level is null")
		return

	player.global_position = _current_level.get_default_player_spawn()

## Attaches player to the current camera as the target
func _setup_level_camera() -> void:
	if player == null or _current_level == null:
		return

	var level_camera : Camera2D = _current_level.get_player_camera()
	if level_camera == null:
		return

	# FUTURE (camera): Temporary hookup
	# NOTE: target variable was added as part of the custom camera script used for the prototype
	level_camera.target = player

## Instantly moves the level camera onto the player, bypassing follow
## smoothing. Called after the player's final position for this load is
## known, so nothing ever visibly glides into place.
func snap_camera_to_player() -> void:
	if _current_level == null:
		return
	var level_camera : Camera2D = _current_level.get_player_camera()
	if level_camera != null:
		level_camera.snap_to_target()

## Fades the transition overlay back in. Callers that pass
## hold_transition = true to load_level() must call this once they've
## finished restoring state that shouldn't be visible mid-update.
func finish_load_transition() -> void:
	await transition_root.fade_in()

# FUTURE (systems): Will be called to set up high level systems
