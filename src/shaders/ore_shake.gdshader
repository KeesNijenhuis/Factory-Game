shader_type canvas_item;

#include "res://src/shaders/hit_flash.gdshaderinc"

uniform float shake_intensity = 0.0f;
uniform float shake_speed = 20.0f;


void vertex() {
	vec2 shake = vec2(0,0);

	//if(VERTEX.y < 0.0) {
		shake.x = sin(TIME * shake_speed + VERTEX.y) * shake_intensity;
	//}

	VERTEX.xy += shake;
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	// COLOR carries the node's self_modulate/modulate alpha into the shader --
	// multiply it back in so toggling self_modulate.a (e.g. hiding the ore
	// sprite during its respawn timer) still has an effect despite this
	// fragment() replacing COLOR wholesale.
	COLOR = vec4(apply_hit_flash(tex_color.rgb), tex_color.a * COLOR.a);
}
