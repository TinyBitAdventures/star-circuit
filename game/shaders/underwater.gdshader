// Full-screen underwater look: the scene behind wobbles, takes on the
// water's colour with depth, and the surface throws moving caustics.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 water : source_color = vec3(0.1, 0.45, 0.6);
uniform float depth = 0.0;     // metres below the surface
uniform float lava = 0.0;      // 1 = molten sea (not used for oceans yet)
uniform float strength = 1.0;  // fades in and out at the surface

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// gentle refraction wobble
	vec2 wob = vec2(sin(uv.y * 24.0 + TIME * 1.7), cos(uv.x * 20.0 + TIME * 1.3)) * 0.0035 * strength;
	vec3 scene = textureLod(screen_tex, uv + wob, 0.0).rgb;
	float murk = clamp(0.35 + depth * 0.035, 0.0, 0.85);
	vec3 deep = water * (0.25 + 0.75 * exp(-depth * 0.06));
	vec3 col = mix(scene * mix(vec3(1.0), water * 1.6, 0.55), deep, murk);
	// caustics: brightest near the surface, strongest toward the top of the screen
	vec2 cp = uv * vec2(9.0, 6.0) + vec2(TIME * 0.25, TIME * 0.18);
	float c = noise(cp) * noise(cp * 1.7 + 3.1);
	float caust = smoothstep(0.35, 0.6, c) * exp(-depth * 0.12) * (1.0 - uv.y) * 0.35;
	col += vec3(0.7, 0.95, 1.0) * caust;
	// light shafts slanting down from above
	float ray = smoothstep(0.6, 1.0, noise(vec2(uv.x * 7.0 + uv.y * 2.0 + TIME * 0.1, 0.5))) * (1.0 - uv.y) * exp(-depth * 0.08) * 0.25;
	col += vec3(0.6, 0.9, 1.0) * ray;
	// vignette closes in with depth
	float v = smoothstep(0.95, 0.35, length(uv - 0.5) * (1.1 + depth * 0.02));
	col *= mix(0.55, 1.0, v);
	COLOR = vec4(mix(scene, col, strength), 1.0);
}
