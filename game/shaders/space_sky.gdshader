shader_type sky;

uniform vec3 nebula_a : source_color = vec3(0.35, 0.1, 0.55);
uniform vec3 nebula_b : source_color = vec3(0.05, 0.35, 0.55);
uniform vec3 base_color : source_color = vec3(0.01, 0.01, 0.03);
uniform float seed = 0.0;
uniform float star_density = 0.985;
uniform float nebula_strength = 0.55;

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
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash(cell + seed);
	if (h < threshold) return 0.0;
	vec3 center = vec3(hash(cell + 1.3 + seed), hash(cell + 7.1 + seed), hash(cell + 3.7 + seed));
	float d = length(fract(p) - center);
	float size = 0.05 + 0.08 * (h - threshold) / (1.0 - threshold);
	return smoothstep(size, 0.0, d) * (0.5 + 2.5 * (h - threshold) / (1.0 - threshold));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 so = vec3(seed * 0.013, seed * 0.027, seed * 0.019);
	float n1 = fbm(d * 2.2 + so);
	float n2 = fbm(d * 3.5 - so + vec3(4.0));
	float band = exp(-pow(d.y * 2.6 + sin(d.x * 2.0 + seed) * 0.4, 2.0));
	vec3 neb = nebula_a * smoothstep(0.45, 0.85, n1) + nebula_b * smoothstep(0.5, 0.9, n2);
	neb *= (0.35 + band) * nebula_strength;
	float s = stars(d, 180.0, star_density) + stars(d, 420.0, star_density + 0.006) * 0.6;
	vec3 star_col = mix(vec3(1.0, 0.85, 0.7), vec3(0.7, 0.85, 1.0), hash(floor(d * 180.0)));
	COLOR = base_color + neb + star_col * s + vec3(0.9, 0.85, 1.0) * band * 0.03;
}
