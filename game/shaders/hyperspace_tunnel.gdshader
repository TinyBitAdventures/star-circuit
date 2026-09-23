// The hyperspace tunnel: the inside of a long cylinder, streaked with light
// that rushes toward the camera. UV.x wraps around the tube, UV.y runs from
// the far end (0) to behind the camera (1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec3 col_a : source_color = vec3(0.35, 0.2, 1.0);
uniform vec3 col_b : source_color = vec3(0.2, 0.9, 1.0);
uniform float speed = 3.0;
uniform float twist = 1.4;
uniform float alarm = 0.0;  // pirates: red pulses through the walls
uniform float intensity = 1.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	float a = UV.x + UV.y * twist + TIME * 0.02;
	// wrap-safe around the tube: sample the angle on a circle
	vec2 ring = vec2(cos(a * 6.2831), sin(a * 6.2831));
	// long streaks of light racing toward us
	float s1 = noise(vec2(ring.x * 18.0 + ring.y * 11.0, UV.y * 22.0 - t * 3.0 + ring.x * 7.0));
	float streak = smoothstep(0.8, 0.98, s1);
	float s2 = noise(vec2(ring.x * 40.0 + ring.y * 27.0, UV.y * 60.0 - t * 5.0 + ring.y * 13.0));
	streak += smoothstep(0.9, 1.0, s2) * 0.6;
	// broad colour clouds
	float c1 = noise(vec2(ring.x * 2.5 + 3.0 + UV.y * 5.0 - t * 0.8, ring.y * 2.5));
	vec3 base = mix(col_a, col_b, c1);
	// rings pulsing past
	float rings = pow(0.5 + 0.5 * sin(UV.y * 90.0 - t * 12.0), 16.0) * 0.35;
	vec3 col = base * (0.07 + 0.12 * c1) + base * streak * 1.1 + vec3(1.0) * streak * 0.2 + base * rings * 0.7;
	// the far end glows white-hot; the near end fades so the tube's mouth isn't visible
	col += vec3(0.9, 0.95, 1.0) * smoothstep(0.2, 0.0, UV.y) * 0.9;
	col *= smoothstep(1.0, 0.8, UV.y);
	col = mix(col, col * vec3(1.6, 0.35, 0.35) + vec3(0.25, 0.0, 0.02), alarm * (0.5 + 0.5 * sin(TIME * 6.0)) * 0.6);
	ALBEDO = col * intensity;
}
