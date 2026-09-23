// Banded gas giant with slow swirling storms.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform vec3 band_a : source_color = vec3(0.9, 0.7, 0.5);
uniform vec3 band_b : source_color = vec3(0.6, 0.4, 0.3);
uniform vec3 storm : source_color = vec3(0.95, 0.5, 0.35);
uniform float seed = 0.0;

varying vec3 obj;

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

void vertex() {
	obj = normalize(VERTEX);
}

void fragment() {
	float t = TIME * 0.01;
	vec3 d = obj;
	float warp = vnoise(d * 4.0 + vec3(seed, t, 0.0)) * 0.35 + vnoise(d * 11.0 - vec3(t)) * 0.12;
	float lat = d.y + warp * 0.25;
	float bands = sin(lat * 18.0 + seed) * 0.5 + 0.5;
	float fine = sin(lat * 57.0 + warp * 4.0) * 0.5 + 0.5;
	vec3 col = mix(band_b, band_a, bands);
	col = mix(col, col * 0.8, fine * 0.35);
	// a great storm spot
	vec3 spot_c = normalize(vec3(0.6, -0.25, 0.75));
	float spot = smoothstep(0.93, 0.985, dot(d, spot_c) + warp * 0.03);
	col = mix(col, storm, spot * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	RIM = 0.6;
	RIM_TINT = 0.3;
}
