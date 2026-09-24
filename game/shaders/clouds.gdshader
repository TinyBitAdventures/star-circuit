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
uniform bool stylized = false; // illustrated globes: crisp puffs, flat two-tone light, inked edges

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
	if (stylized) {
		// scalloped puffs: a finer noise nibbles the edge into billows
		float nb = n + (vnoise(q * 7.0) - 0.5) * 0.12 + (vnoise(q * 15.0) - 0.5) * 0.04;
		float thr = coverage + 0.11;
		float aa = max(fwidth(nb), 1e-4);
		float cs = smoothstep(thr - aa, thr + aa, nb);
		vec3 nws = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);
		float ndl = dot(nws, sun_dir);
		// self-shading: sample the cloud a little toward the sun; where that is
		// thinner, this side of the puff faces away from the light
		vec3 ls = normalize((inverse(MODEL_MATRIX) * vec4(sun_dir, 0.0)).xyz);
		vec3 tg = ls - d * dot(ls, d);
		vec3 rs = normalize(r + tg * 0.05);
		vec3 qs = rs * scale + vec3(seed);
		qs += vec3(fbm(qs * 0.6), fbm(qs * 0.6 + 5.2), fbm(qs * 0.6 + 9.7)) * 0.9;
		float ns = fbm(qs) + 0.12 * sin(rs.y * 9.0) + (vnoise(qs * 7.0) - 0.5) * 0.12;
		float lit_side = smoothstep(thr - 0.02, thr + 0.06, ns);
		vec3 sc = mix(mix(shadow_color, cloud_color, 0.5), cloud_color * 1.08, lit_side);
		// inked outline just inside the puff
		float edge = 1.0 - smoothstep(thr + aa, thr + aa * 2.4, nb);
		sc = mix(sc, shadow_color * 0.6, edge * 0.85);
		ALBEDO = sc * (0.2 + 0.8 * smoothstep(-0.2, 0.08, ndl));
		ALPHA = cs;
	} else {
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
}
