class_name HitBox
extends Area2D

@export var tool_type: Item.ToolTypes = Item.ToolTypes.None

signal on_hit(damage: int)
## Fired the instant the swing starts, before the damage is confirmed, so the
## object can react immediately instead of waiting for the swing to finish.
signal hit_telegraphed
## Fired on the swing's impact frame (e.g. PlayerStateMining's FLASH_FRAME) --
## later than hit_telegraphed, timed to match when CaveWallsLayer starts its
## own wall hit-flash, so a DestructibleComponent's white flash lands the
## same moment the tool visually connects instead of at swing start.
signal hit_flash



## Called by HitArea.deal_damage() when this hitbox is hit by a matching tool.
func take_hit(damage: int) -> void:
	on_hit.emit(damage)

## Whether this hitbox belongs to an object that actually wears down tools,
## i.e. a sibling DurabilityComponent exists to receive the damage.
func has_durability_component() -> bool:
	var parent := get_parent()
	return parent != null and parent.has_node("DurabilityComponent")

## Called by HitArea.telegraph_hit() as soon as the player starts a swing aimed at this hitbox.
func telegraph_hit() -> void:
	hit_telegraphed.emit()

## Called by HitArea.flash_hit() on the swing's impact frame.
func flash_hit() -> void:
	hit_flash.emit()
