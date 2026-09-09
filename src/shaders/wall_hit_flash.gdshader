shader_type canvas_item;
render_mode unshaded;
// Applied to CaveWallsLayer's HitFlash overlay child. That overlay only ever
// holds a copy of whichever cell is currently flashing, tinted toward white
// by flash_amount (see cave_walls_layer.gd's _process) instead of forced
// fully white, so the tile's own art still reads through the flash.
// unshaded so the flash reads as true white even in the cave's dim lighting,
// instead of getting darkened by the same Light2D/CanvasModulate as everything
// else on the layer.

#include "res://src/shaders/hit_flash.gdshaderinc"

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(apply_hit_flash(tex_color.rgb), tex_color.a);
}
