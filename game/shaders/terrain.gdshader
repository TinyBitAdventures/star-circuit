// Planet terrain: vertex colours from the generator, dressed up with
// procedural surface detail. Works at surface scale and orbital scale.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform float detail_scale = 0.35;  // noise frequency in object units
uniform float sea_radius = 0.0;     // object-space sea radius (0 = none)
uniform float bump_strength = 0.55;
uniform float snow_sparkle = 1.0;

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
	NORMAL = normalize(NORMAL - bump_view * bump_strength * (0.35 + 0.65 * near_detail) * (1.0 + rocky));

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

	ALBEDO = col;
	SPECULAR = 0.25;
	// soft Spore-ish rim
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION += col * rim * 0.06;
}
