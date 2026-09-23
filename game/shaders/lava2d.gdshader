// The Deep: flowing molten rock for lava cells. Unshaded so it glows in
// the dark; the pattern is in world space so neighbouring cells join up.
shader_type canvas_item;
render_mode unshaded;

varying vec2 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15; }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = wpos / 48.0;
	float t = TIME * 0.35;
	// domain-warped flow, drifting sideways and slowly churning
	vec2 q = vec2(fbm(p + vec2(t, 0.0)), fbm(p + vec2(0.0, -t * 0.7) + 3.1));
	float n = fbm(p * 1.3 + q * 1.8 + vec2(t * 0.6, 0.0));
	// dark cooling crust with bright cracks between plates
	float crack = smoothstep(0.08, 0.0, abs(n - 0.5));
	float hot = smoothstep(0.35, 0.75, n);
	vec3 crust = vec3(0.28, 0.05, 0.02);
	vec3 molten = mix(vec3(1.0, 0.32, 0.04), vec3(1.0, 0.85, 0.35), hot);
	vec3 col = mix(crust, molten, clamp(hot * 0.8 + crack, 0.0, 1.0));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0 + p.x * 3.0);
	COLOR = vec4(col * pulse * 1.3, 1.0);
}
