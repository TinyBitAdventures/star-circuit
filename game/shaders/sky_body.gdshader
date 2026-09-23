// Distant planets in the sky: vertex-coloured terrain, sun-lit, no fog,
// with a faint self-glow so the night side is still readable.
shader_type spatial;
render_mode fog_disabled, shadows_disabled;

uniform bool use_flat = false;
uniform vec4 flat_color : source_color = vec4(0.2, 0.5, 0.9, 1.0);

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	vec3 base = use_flat ? flat_color.rgb : srgb_to_linear(COLOR.rgb);
	ALBEDO = base;
	ROUGHNESS = use_flat ? 0.2 : 0.9;
	EMISSION = base * 0.12;
}
