extends BaseLevel
class_name ProceduralCaveLevel
## Runtime-generated, chunk-streamed cave level: on _ready(), CaveChunkStreamer
## synchronously builds the chunks around ORIGIN_CHUNK (the level always
## "starts" at the same chunk coordinate -- there's no single global entrance
## once the world is a patchwork of independently-generated chunks, see the
## chunked-streaming plan's "regional connectivity" decision), then the
## player spawn marker is repositioned to that chunk's own entrance.
## Steady-state chunk loading/unloading then continues via the streamer's
## own _process(). Sibling to the hand-authored CaveLevel/cave_level.tscn --
## this scene reuses the same TileSet and layer scripts but never
## hand-paints a layout, and to the (non-streamed) procedural
## generate_and_build() path CaveBuilder also still supports.
##
## Everything in _ready() must stay synchronous (no await/call_deferred):
## MainGame._perform_level_load() calls level_root.add_child(_current_level)
## and then _place_player_at_level_spawn() with no frame in between, so
## get_default_player_spawn() must already reflect the generated entrance by
## the time add_child() returns -- see CaveChunkStreamer.load_initial_chunks(),
## which is written to never yield.

const ORIGIN_CHUNK: Vector2i = Vector2i.ZERO

@onready var player_spawn_marker: Marker2D = $LevelObjects/PlayerSpawn
@onready var player_camera: Camera2D = $LevelObjects/PlayerCamera
@onready var objects_layer: TileMapLayer = $Tilemaps/Objects
@onready var walls_layer: TileMapLayer = $Tilemaps/Walls
@onready var ground_layer: TileMapLayer = $Tilemaps/Ground
@onready var cave_chunk_streamer: CaveChunkStreamer = $LevelObjects/CaveChunkStreamer


func _ready() -> void:
	cave_chunk_streamer.prepare_startup_world_data(SaveManager.consume_startup_world_data())
	var entrance_global := cave_chunk_streamer.load_initial_chunks(ORIGIN_CHUNK)
	player_spawn_marker.global_position = entrance_global


func get_default_player_spawn() -> Vector2:
	return player_spawn_marker.global_position

func get_player_camera() -> Camera2D:
	return player_camera

func show_initial_grid_overview() -> void:
	player_camera.show_world_rect(cave_chunk_streamer.get_initial_grid_rect())

func get_objects_layer() -> TileMapLayer:
	return objects_layer

func get_walls_layer() -> TileMapLayer:
	return walls_layer

func get_ground_layer() -> TileMapLayer:
	return ground_layer
