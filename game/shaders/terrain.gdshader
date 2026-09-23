// Planet terrain: vertex colours from the generator, dressed up with
// procedural surface detail. Works at surface scale and orbital scale.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform float detail_scale = 0.35;  // noise frequency in object units
uniform float sea_radius = 0.0;     // object-space sea radius (0 = none)
uniform float bump_strength = 0.55;
uniform float snow_sparkle = 1.0;
uniform float grid_glow = 0.0; // machine world: glowing circuit lines
uniform float paint = 1.0; // TOON variant: how bold the colour is

varying vec3 obj_pos;
varying vec3 obj_n;
varying vec3 world_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

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
	return vnoise(p) * 0.55 + vnoise(p * 2.13) * 0.3 + vnoise(p * 4.7) * 0.15;
}

void vertex() {
	obj_pos = VERTEX;
	obj_n = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	vec3 up = normalize(obj_pos);
	float slope = 1.0 - clamp(dot(normalize(obj_n), up), 0.0, 1.0);
	float r = length(obj_pos);
	vec3 p = obj_pos * detail_scale;

	// fade fine detail with distance to avoid shimmer
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_detail = 1.0 - smoothstep(35.0, 140.0, dist * detail_scale / 0.35);

	// broad patches + fine speckle
	float n1 = fbm(p * 0.35);
	float n2 = vnoise(p * 3.1);
	vec3 col = base * (0.82 + 0.3 * n1) * (0.94 + 0.12 * n2 * near_detail);

	// rock strata on slopes
	float strata = sin(r * detail_scale * 9.0 + n1 * 6.0) * 0.5 + 0.5;
	float rocky = smoothstep(0.1, 0.3, slope);
	col *= mix(1.0, 0.72 + 0.35 * strata, rocky);

	// wet, darker sand just above the waterline
	if (sea_radius > 0.0) {
		float above = (r - sea_radius) / max(sea_radius, 1.0);
		float wet = 1.0 - smoothstep(0.0, 0.004, above);
		wet *= step(-0.01, above);
		col *= mix(1.0, 0.62, wet);
		ROUGHNESS = mix(0.92, 0.35, wet);
	} else {
		ROUGHNESS = 0.92;
	}

	// procedural micro bump: perturb the normal with the noise gradient
	// single-octave gradient: cheap, and the fbm colour already carries detail
	float e = 0.35;
	vec3 pb = p * 1.6;
	float h0 = vnoise(pb);
	vec3 grad = vec3(vnoise(pb + vec3(e, 0, 0)) - h0, vnoise(pb + vec3(0, e, 0)) - h0, vnoise(pb + vec3(0, 0, e)) - h0) / e;
	grad -= up * dot(grad, up);
	vec3 bump_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(grad, 0.0)).xyz;
#ifdef TOON
	// illustrative: landforms carry the light, not micro-bumps
	NORMAL = normalize(NORMAL - bump_view * bump_strength * 0.12 * (1.0 + rocky));
#define TOON_SOFT
#else
	NORMAL = normalize(NORMAL - bump_view * bump_strength * (0.35 + 0.65 * near_detail) * (1.0 + rocky));
#endif

	// snow / ice sparkle
	float luma = dot(base, vec3(0.299, 0.587, 0.114));
	if (luma > 0.62 && snow_sparkle > 0.0) {
		vec3 cell = world_pos * 5.0;
		float g = hash(floor(cell));
		// a tiny round glint inside the cell, not the whole cell
		float dotm = 1.0 - smoothstep(0.03, 0.08, length(fract(cell) - 0.5));
		float tw = step(0.93, g) * dotm * (0.4 + 0.6 * sin(TIME * 3.0 + g * 40.0));
		EMISSION = vec3(1.0) * max(tw, 0.0) * 2.5 * near_detail * snow_sparkle;
	}

	if (grid_glow > 0.0) {
		vec3 g = abs(fract(up * 60.0) - 0.5);
		float line = smoothstep(0.03, 0.0, min(g.x, min(g.y, g.z)));
		float pulse = 0.6 + 0.4 * sin(TIME * 1.5 + dot(up, vec3(40.0)));
		EMISSION += vec3(1.0, 0.45, 0.12) * line * pulse * grid_glow * (0.4 + 0.6 * near_detail);
		col *= 0.9;
		METALLIC = 0.6;
	}
#ifdef TOON
	// illustrative: two-tone painted patches, crisp rock bands, richer colour
	vec3 wp = obj_pos * detail_scale;
	float warp = fbm(wp * 0.6);
	float blot = smoothstep(0.47, 0.53, fbm(wp * 0.9 + vec3(warp * 2.0)));
	float fine = smoothstep(0.5, 0.56, vnoise(wp * 3.3 + vec3(warp * 3.0))) * near_detail;
	// sunlit patches lean warm and light, shaded patches cool: like broad brush strokes
	vec3 warm = base * vec3(1.1, 1.06, 0.86);
	vec3 cool = base * vec3(0.86, 0.93, 1.04);
	vec3 flat_col = mix(cool, warm, blot) * (0.97 + 0.06 * fine);
	float rocky_t = smoothstep(0.19, 0.23, slope);
	flat_col *= mix(1.0, 0.8 + 0.12 * step(0.5, strata), rocky_t);
	col = mix(col, flat_col, 0.85);
	float luma2 = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma2), col, 1.0 + 0.08 * paint);
#endif
	ALBEDO = col;
	SPECULAR = 0.25;
	// soft Spore-ish rim
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION += col * rim * 0.06;
}
