// Atmospheric halo seen from space.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.7, 1.0);
uniform float power = 3.0;
uniform float strength = 1.4;

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, power);
	float inner = smoothstep(1.0, 0.85, f);
	ALBEDO = color * rim * strength * inner;
}
