// Cave rock: world-space noise colour + bump, with glowing mineral seams.
shader_type spatial;
render_mode diffuse_lambert_wrap, cull_disabled;

uniform vec3 rock_color : source_color = vec3(0.3, 0.28, 0.32);
uniform vec3 seam_color : source_color = vec3(0.5, 0.9, 1.0);
uniform float seam_amount = 0.35;

varying vec3 wpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.6) * 0.2;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = wpos * 0.45;
	float n = fbm(p);
	float strata = sin(wpos.y * 2.2 + n * 5.0) * 0.5 + 0.5;
	vec3 col = rock_color * (0.65 + 0.55 * n) * (0.85 + 0.25 * strata);
	float e = 0.3;
	vec3 g = vec3(fbm(p + vec3(e, 0, 0)) - n, fbm(p + vec3(0, e, 0)) - n, fbm(p + vec3(0, 0, e)) - n) / e;
	NORMAL = normalize(NORMAL - (VIEW_MATRIX * vec4(g, 0.0)).xyz * 0.9);
	// thin veins, broken up so they read as mineral seams, not wallpaper
	float v = abs(fbm(wpos * 0.42) - 0.5);
	float breakup = smoothstep(0.45, 0.7, vnoise(wpos * 0.25));
	float seam = smoothstep(0.012, 0.0, v) * breakup * seam_amount;
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = seam_color * seam * 1.6;
}
