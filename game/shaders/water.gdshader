// Planet oceans (and lava): depth-based shallows + shoreline foam, animated
// ripple normals, fresnel.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform vec4 water_color : source_color = vec4(0.2, 0.55, 0.85, 0.75);
uniform float emissive = 0.0;
uniform float wave_speed = 0.4;
uniform float foam_amount = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

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

float waves(vec3 p, float t) {
	return vnoise(p * 0.25 + vec3(t, t * 0.7, -t)) * 0.6 + vnoise(p * 0.9 - vec3(t)) * 0.4;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * wave_speed;
	float n = waves(world_pos, t);
	// ripple normal from the wave gradient
	float e = 0.4;
	vec3 g = vec3(waves(world_pos + vec3(e, 0, 0), t) - n, waves(world_pos + vec3(0, e, 0), t) - n, waves(world_pos + vec3(0, 0, e), t) - n) / e;
	vec3 up = normalize(world_pos);
	g -= up * dot(g, up);
	NORMAL = normalize(NORMAL - (VIEW_MATRIX * vec4(g, 0.0)).xyz * 0.8);

	// how much water lies between this surface and the ground behind it
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float scene_z = -v.z / v.w;
	float water_depth = max(0.0, scene_z - (-VERTEX.z));
	float shallow = 1.0 - smoothstep(0.0, 6.0, water_depth);
	float foam_n = vnoise(world_pos * 1.3 + vec3(0.0, TIME * 0.6, 0.0));
	float foam = (1.0 - smoothstep(0.0, 1.1 + foam_n * 0.8, water_depth)) * foam_amount;

	vec3 deep = water_color.rgb * 0.55;
	vec3 col = mix(deep, water_color.rgb * 1.25, shallow) * (0.88 + 0.24 * n);
	col = mix(col, vec3(0.95, 0.98, 1.0), foam * 0.85);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ALPHA = clamp(mix(water_color.a * (0.55 + 0.45 * (1.0 - shallow)), 1.0, foam) + fres * 0.25, 0.0, 1.0);
	ROUGHNESS = 0.05 + 0.25 * foam;
	METALLIC = 0.05;
	SPECULAR = 0.9;
	EMISSION = water_color.rgb * emissive * (0.6 + 0.8 * n) + vec3(1.0, 0.6, 0.2) * emissive * foam * 0.5;
}
