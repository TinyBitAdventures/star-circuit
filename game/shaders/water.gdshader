shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec4 water_color : source_color = vec4(0.2, 0.55, 0.85, 0.75);
uniform float emissive = 0.0;
uniform float wave_speed = 0.4;

varying vec3 world_pos;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	float n = vnoise(world_pos * 0.25 + vec3(t, t * 0.7, -t)) * 0.6 + vnoise(world_pos * 0.9 - vec3(t)) * 0.4;
	ALBEDO = water_color.rgb * (0.85 + 0.3 * n);
	ALPHA = water_color.a;
	ROUGHNESS = 0.08 + 0.2 * n;
	METALLIC = 0.1;
	SPECULAR = 0.8;
	EMISSION = water_color.rgb * emissive * (0.6 + 0.8 * n);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALPHA = clamp(water_color.a + fres * 0.25, 0.0, 1.0);
}
