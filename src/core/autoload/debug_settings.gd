extends Node

var show_mining_debug: bool = false
var show_fps: bool = true
var show_tool_debug: bool = false
var enable_item_cheat: bool = false
var enable_camera_zoom: bool = true
var show_ore_debug_draw: bool = false
var show_placement_footprint: bool = false
## Arrow keys teleport the player 200 tiles in that direction, separate from
## normal WASD movement.
var enable_debug_teleport: bool = true
## Enables detailed cave generation/streaming timing logs without adding
## per-frame logging to normal debug runs.
var profile_cave_generation: bool = OS.is_debug_build()
