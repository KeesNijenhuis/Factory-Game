extends Node2D
class_name HitFlashComponent
## Reusable "swing landed" white flash, shared by every HitBox-owning object
## (DestructibleComponent's placed objects, ObjectResource's trees/ore) so a
## tool connecting always reads the same way no matter what it hit. Instance
## as a child of the object and call flash(sprite) from a hit_box.hit_flash
## handler.

const FLASH_SHADER: Shader = preload("res://src/shaders/wall_hit_flash.gdshader")
const FLASH_DURATION: float = 0.15
const FLASH_PEAK_AMOUNT: float = 0.85
const FLASH_PARAM: StringName = &"flash_amount"

## Lazily created once per object and reused across hits, rather than a fresh
## ShaderMaterial per flash -- see flash()'s swap branch.
var _flash_material: ShaderMaterial
var _flash_tween: Tween

## If `sprite` already carries a material (e.g. ore_node's own shake shader,
## which #includes hit_flash.gdshaderinc), its flash_amount uniform is tweened
## directly -- installing a separate flash-only material instead would
## silently steal the sprite's material slot away from whatever shader-driven
## effect (like the shake) is already running on it. Otherwise a dedicated
## flash-only material is swapped in for the duration of the flash and then
## cleared back to null. It can't just be left in place afterward the way the
## ore case can: wall_hit_flash.gdshader is `render_mode unshaded`, so once
## installed it would permanently exempt the sprite from the level's
## Light2D/CanvasModulate shading even at flash_amount 0, reading as "stuck
## lit up" instead of returning to normal.
func flash(sprite: CanvasItem) -> void:
	if sprite == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		# A still-fading flash from the previous hit -- kill it so its
		# tween_method/tween_callback calls can't race the new one's.
		_flash_tween.kill()
	if sprite.material == null:
		if _flash_material == null:
			_flash_material = ShaderMaterial.new()
			_flash_material.shader = FLASH_SHADER
		sprite.material = _flash_material
	var target_material: ShaderMaterial = sprite.material
	target_material.set_shader_parameter(FLASH_PARAM, FLASH_PEAK_AMOUNT)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float): target_material.set_shader_parameter(FLASH_PARAM, v), FLASH_PEAK_AMOUNT, 0.0, FLASH_DURATION)
	if target_material == _flash_material:
		_flash_tween.tween_callback(func(): sprite.material = null)
