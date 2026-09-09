extends PlayerState
class_name PlayerStateAction
## Shared base for player states that play a one-shot tool/attack animation,
## returning to Walk/Idle once it finishes. Movement stays available but slowed
## (move_speed_acting) so an action doesn't fully root the player in place.
## Facing stays locked to whatever direction it was on entry, since the tool's
## hit-check position is fixed then too.

## 0-indexed frame every tool-swing animation shares as its impact frame --
## every current tool animation (mine/axe/etc.) is 6 frames at the same
## speed, so one shared frame works for all of them without each subclass
## re-deriving it. Drives _on_flash_frame() below, which fires whatever
## overlapping HitBox the equipped tool matches (e.g. a DestructibleComponent's
## white flash) at the moment the swing visually connects, regardless of which
## tool is equipped -- previously only PlayerStateMining wired this up, so an
## Axe swing (e.g. against a wooden chest) dealt damage but never flashed.
const FLASH_FRAME: int = 2

func enter_state() -> void:
	player.anim_sprite.animation_finished.connect(_on_animation_finished)
	# Reaction plays immediately on swing start; the actual damage still lands at
	# swing end via _on_animation_finished, once per animation loop.
	player.update_hit_area()
	player.hit_area.telegraph_hit()
	player.anim_sprite.frame_changed.connect(_on_frame_changed)

func process_physics_state(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.velocity = input_vector * player.move_speed_acting
	player.move_and_slide()

func exit_state() -> void:
	if player.anim_sprite.animation_finished.is_connected(_on_animation_finished):
		player.anim_sprite.animation_finished.disconnect(_on_animation_finished)
	if player.anim_sprite.frame_changed.is_connected(_on_frame_changed):
		player.anim_sprite.frame_changed.disconnect(_on_frame_changed)

func _on_frame_changed() -> void:
	if player.anim_sprite.frame != FLASH_FRAME:
		return
	player.anim_sprite.frame_changed.disconnect(_on_frame_changed)
	_on_flash_frame()

## Overridable so subclasses (e.g. Mining) can react to the same impact frame
## beyond flashing the hit HitBox (e.g. CaveWallsLayer's own wall flash).
func _on_flash_frame() -> void:
	player.hit_area.flash_hit()

func _on_animation_finished() -> void:
	var hit_durability_object := _deal_damage()
	if hit_durability_object:
		player.damage_equipped_tool()
	if player.is_moving():
		fsm.transition_to("Walk")
	else:
		fsm.transition_to("Idle")

## Overridable so subclasses (e.g. Mining) can extend what a swing can hit
## beyond HitBox overlap. Returns whether the swing hit something that
## should wear down the equipped tool.
func _deal_damage() -> bool:
	return player.hit_area.deal_damage()
