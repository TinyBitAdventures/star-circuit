// The Micro Lab soup: a warm, murky broth seen down a microscope, in a bowl.
// Domain-warped broth, drifting fat droplets with bright rims, flecks of
// stuff, soft caustic light, and a glazed ceramic rim around the dish.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform vec2 center = vec2(800.0, 450.0);
uniform float radius = 400.0;
uniform vec4 broth_a : source_color = vec4(0.62, 0.42, 0.16, 1.0);
uniform vec4 broth_b : source_color = vec4(0.24, 0.30, 0.10, 1.0);
uniform vec4 rim_col : source_color = vec4(0.86, 0.82, 0.74, 1.0);
uniform float swirl = 0.0; // accumulated stir angle
uniform float t = 0.0;
uniform float heat = 0.0; // 0..1: the broth darkens and reddens as the culture goes off

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}
vec2 rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// fat droplets: returns (coverage, rim, highlight)
vec3 droplets(vec2 g, float size_lo, float size_hi, float keep) {
	vec2 i = floor(g), f = fract(g);
	vec3 best = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 h = hash2(i + n);
			if (hash(i + n + 7.3) > keep) {
				continue;
			}
			vec2 o = n + 0.5 + 0.35 * sin(t * 0.25 + 6.2831 * h) - f;
			float rr = mix(size_lo, size_hi, hash(i + n + 3.1));
			float d = length(o);
			float cov = smoothstep(rr, rr - 0.035, d);
			float rim = smoothstep(rr - 0.07, rr - 0.02, d) * cov;
			float hi = smoothstep(rr * 0.35, 0.0, length(o + vec2(rr * 0.35, rr * 0.4))) * cov;
			best = max(best, vec3(cov, rim, hi));
		}
	}
	return best;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 d = (px - center) / radius;
	float r = length(d);
	vec3 col;
	if (r < 1.0) {
		// the stir turns the middle faster than the edge
		vec2 s = rot(d, swirl * (1.0 - r * r) * 0.9 + t * 0.015);
		vec2 q = vec2(fbm(s * 1.6 + vec2(t * 0.03, 0.0)), fbm(s * 1.6 + vec2(4.1, -t * 0.025)));
		float n = fbm(s * 2.2 + q * 1.7 + t * 0.02);
		vec3 a = mix(broth_a.rgb, vec3(0.45, 0.12, 0.08), heat * 0.6);
		vec3 b = mix(broth_b.rgb, vec3(0.16, 0.05, 0.05), heat * 0.6);
		col = mix(b, a, smoothstep(0.3, 0.72, n));
		// darker swirls of sediment
		float streak = smoothstep(0.52, 0.5, abs(fbm(s * 3.5 + q * 2.5 - t * 0.03) - 0.5) + 0.46);
		col *= 1.0 - streak * 0.25;
		// soft caustic light from above
		float c = pow(1.0 - abs(noise(s * 7.0 + q * 3.0 + t * 0.12) * 2.0 - 1.0), 6.0);
		col += vec3(1.0, 0.9, 0.6) * c * 0.08;
		// flecks: herbs and grit suspended in the broth
		vec2 fg = s * 22.0 + q * 3.0;
		vec2 fi = floor(fg);
		float fh = hash(fi);
		if (fh > 0.93) {
			float fd = length(fract(fg) - 0.5 - 0.25 * (hash2(fi) - 0.5));
			col = mix(col, mix(vec3(0.14, 0.2, 0.06), vec3(0.35, 0.18, 0.05), hash(fi + 2.0)), smoothstep(0.12, 0.05, fd) * 0.8);
		}
		// fat droplets, big and sparse over small and many
		vec2 dg = s + q * 0.25 + vec2(t * 0.012, -t * 0.008);
		vec3 big = droplets(dg * 3.0, 0.2, 0.42, 0.28);
		vec3 small = droplets(dg * 7.0 + 11.0, 0.1, 0.26, 0.22);
		vec3 fat = max(big, small * vec3(0.9, 1.0, 0.8));
		vec3 oil = mix(col, vec3(1.0, 0.86, 0.45), 0.22);
		col = mix(col, oil, fat.x * 0.45);
		col += vec3(1.0, 0.92, 0.65) * fat.y * 0.12;
		col += vec3(1.0) * fat.z * 0.22;
		// depth: darker toward the bowl wall, a warm glow in the middle
		col *= mix(1.1, 0.55, smoothstep(0.35, 1.0, r));
		// the meniscus where broth meets the bowl
		col += rim_col.rgb * smoothstep(0.93, 1.0, r) * 0.25;
	} else {
		// glazed ceramic rim, then the dark lab bench
		float w = 0.16;
		float k = (r - 1.0) / w;
		if (k < 1.0) {
			float shade = 0.65 + 0.35 * sin(k * 3.14159);
			float light = dot(normalize(d), normalize(vec2(-0.6, -0.8)));
			col = rim_col.rgb * shade * (0.8 + 0.25 * light);
			col += vec3(1.0) * pow(max(0.0, sin(k * 3.14159)), 18.0) * max(0.0, light) * 0.6;
			// a thin glaze stripe
			col = mix(col, broth_a.rgb * 0.7, smoothstep(0.03, 0.0, abs(k - 0.72)) * 0.6);
		} else {
			float v = smoothstep(2.0, 1.1, r);
			col = vec3(0.02, 0.025, 0.05) + vec3(0.04, 0.05, 0.09) * v;
			// the bowl's shadow on the bench
			col *= 1.0 - smoothstep(1.35, 1.16, r) * 0.5;
		}
	}
	COLOR = vec4(col, 1.0);
}
