// Ground cover blades / sprigs. UV.y = 0 at the root, 1 at the tip.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.2, 0.45, 0.15);
uniform vec3 tip_color : source_color = vec3(0.55, 0.85, 0.35);
uniform float wind = 1.0;
uniform float emissive = 0.0;
uniform float fade_near = 30.0;
uniform float fade_far = 44.0;

varying float h;
varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	h = UV.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 inst = MODEL_MATRIX[3].xyz;
	float t = TIME * 1.7 + dot(inst, vec3(0.13, 0.07, 0.11));
	float gust = sin(TIME * 0.4 + dot(inst, vec3(0.02, 0.03, 0.025))) * 0.5 + 0.5;
	float sway = (sin(t) + 0.45 * sin(t * 2.3)) * (0.08 + 0.12 * gust) * wind * h * h;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}

void fragment() {
	// dithered distance fade so the patch edge never pops
	float d = length(wpos - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_near, fade_far, d);
	if (hash2(FRAGCOORD.xy) > fade) {
		discard;
	}
	vec3 c = mix(base_color, tip_color, h);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	EMISSION = tip_color * emissive * h;
	BACKLIGHT = c * 0.4;
}
