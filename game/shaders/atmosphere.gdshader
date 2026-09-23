// Sky dome seen from INSIDE a planet's atmosphere. Drawn on an inverted sphere.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 planet_center = vec3(0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.85, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float planet_radius = 170.0;
uniform float atmo_height = 140.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 view = normalize(world_pos - cam);
	vec3 up = normalize(cam - planet_center);
	float alt = clamp((length(cam - planet_center) - planet_radius) / atmo_height, 0.0, 1.0);
	float vu = dot(view, up);
	float sun_up = dot(up, sun_dir);
	float day = smoothstep(-0.28, 0.22, sun_up);
	float dusk = exp(-pow(sun_up * 4.5, 2.0));
	vec3 hz = mix(horizon_color, vec3(1.0, 0.45, 0.25), dusk * 0.7);
	vec3 col = mix(hz, zenith_color, smoothstep(-0.02, 0.55, vu));
	float sd = max(dot(view, sun_dir), 0.0);
	col += sun_color * (pow(sd, 900.0) * 6.0 + pow(sd, 12.0) * 0.35 * day);
	float horizon_haze = 1.0 - smoothstep(0.0, 0.7, vu);
	float a = day * (0.8 + horizon_haze * 0.2);
	a = max(a, horizon_haze * 0.25 * (1.0 - day)); // faint night glow
	a *= (1.0 - alt);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
