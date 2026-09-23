// Cloud shell around a planet, seen from below (surface) or above (orbit).
// Pattern depends only on direction, so both views show the same clouds.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 shadow_color : source_color = vec3(0.45, 0.5, 0.62);
uniform float coverage = 0.52;
uniform float density = 0.9;
uniform float speed = 0.004;
uniform float scale = 3.2;
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

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 d = normalize(obj);
	float ang = TIME * speed;
	vec3 r = vec3(d.x * cos(ang) - d.z * sin(ang), d.y, d.x * sin(ang) + d.z * cos(ang));
	// latitude bands + domain warp for swirly, painterly clouds
	vec3 q = r * scale + vec3(seed);
	q += vec3(fbm(q * 0.6), fbm(q * 0.6 + 5.2), fbm(q * 0.6 + 9.7)) * 0.9;
	float n = fbm(q) + 0.12 * sin(r.y * 9.0);
	float c = smoothstep(coverage, coverage + 0.18, n);
	vec3 nw = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);
	float lit = clamp(dot(nw, sun_dir) * 0.8 + 0.35, 0.0, 1.0);
	float thick = smoothstep(coverage, coverage + 0.35, n);
	vec3 col = mix(shadow_color, cloud_color, clamp(lit * (0.55 + 0.45 * thick), 0.0, 1.0));
	// sunset rim glow near the terminator
	float term = exp(-pow(dot(nw, sun_dir) * 5.0, 2.0));
	col += vec3(1.0, 0.55, 0.3) * term * 0.35 * c;
	ALBEDO = col * (0.15 + 0.85 * lit);
	ALPHA = c * density;
}
