// Planet atmosphere post-process, drawn over the finished frame:
//  - heat shimmer in a band along the horizon (hot worlds)
//  - sun shafts: bright sky streaming past silhouettes toward the sun
//  - frost creeping in at the screen edges (cold nights and blizzards)
//  - a gentle per-world colour grade
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float shimmer = 0.0;
uniform float horizon_y = 0.5;     // screen-space height of the horizon (0 top, 1 bottom)
uniform vec2 sun_uv = vec2(0.5, 0.2);
uniform float sun_vis = 0.0;       // 0 when the sun is behind the camera or below the horizon
uniform float rays = 0.0;
uniform vec3 ray_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float frost = 0.0;
uniform vec3 grade : source_color = vec3(1.0);
uniform float grade_amt = 0.0;
uniform float aspect = 1.777;

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
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = r * p * 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// heat haze hugs the horizon: strongest just below it, gone near the camera and high in the sky
	float band = smoothstep(horizon_y - 0.06, horizon_y + 0.02, uv.y) * (1.0 - smoothstep(horizon_y + 0.02, horizon_y + 0.3, uv.y));
	float n = noise(vec2(uv.x * 40.0, uv.y * 90.0 - TIME * 2.5));
	vec2 off = vec2(sin(uv.y * 160.0 + TIME * 5.0 + n * 6.0), 0.0) * 0.0022 * shimmer * band;
	off.y = (n - 0.5) * 0.002 * shimmer * band;
	vec3 col = textureLod(screen_tex, uv + off, 0.0).rgb;

	// sun shafts: march toward the sun gathering bright pixels
	if (rays > 0.0 && sun_vis > 0.0) {
		vec2 d = (sun_uv - uv) / 16.0;
		vec2 p = uv;
		float acc = 0.0;
		float w = 1.0;
		for (int i = 0; i < 16; i++) {
			p += d;
			vec3 s = textureLod(screen_tex, clamp(p, vec2(0.001), vec2(0.999)), 2.0).rgb;
			float l = dot(s, vec3(0.299, 0.587, 0.114));
			// only the brightest sky counts, and only above the horizon
			acc += smoothstep(0.82, 1.0, l) * step(p.y, horizon_y + 0.02) * w;
			w *= 0.9;
		}
		acc /= 9.0;
		vec2 to_sun = (uv - sun_uv) * vec2(aspect, 1.0);
		float near_sun = exp(-length(to_sun) * 2.2);
		col += ray_color * acc * rays * sun_vis * (0.15 + 0.85 * near_sun) * 0.6;
	}

	// frost: feathery rime growing in from the corners
	if (frost > 0.0) {
		vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
		float edge = length(c * vec2(0.85, 1.15)) / (length(vec2(aspect, 1.0)) * 0.5);
		vec2 q = c * 5.0;
		float warp = fbm(q + fbm(q * 1.7));
		float ferns = pow(abs(sin(warp * 28.0 + atan(c.y, c.x) * 3.0)), 6.0);
		float reach = 1.02 - frost * 0.3;
		float mask = smoothstep(reach, reach + 0.18, edge + (warp - 0.5) * 0.25);
		float a = mask * (0.35 + 0.45 * ferns);
		col = mix(col, vec3(0.86, 0.94, 1.0), clamp(a, 0.0, 0.85));
	}

	col = mix(col, col * grade, grade_amt);
	COLOR = vec4(col, 1.0);
}
