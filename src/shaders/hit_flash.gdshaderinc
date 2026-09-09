// Shared "swing landed" white flash, blended into whatever color a
// fragment() has already computed. #include this from any canvas_item
// shader that wants to support HitFlashComponent -- e.g. a resource node's
// own persistent shake shader (ore_shake.gdshader), so the flash can be
// tweened on that same material instead of HitFlashComponent installing a
// separate one and silently stepping on the shader-driven effect already
// running there.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

vec3 apply_hit_flash(vec3 color) {
	return mix(color, vec3(1.0), flash_amount);
}
