// Sky dome seen from INSIDE a planet's atmosphere. Drawn on an inverted sphere.
// A deep zenith that pales into a thin band of haze at the horizon, a soft
// glow and disc around the sun, and warm dusk colour only on the sun's side.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 planet_center = vec3(0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.85, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float planet_radius = 170.0;
uniform float atmo_height = 140.0;
uniform float haze = 1.0; // how thick the horizon band is (per biome, thickened by storms)
uniform float haze_tint = 0.25; // how much of the world's horizon colour the haze takes (dusty worlds: more)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The colours the fog should use to match this sky (kept in step with planet_world.gd).
vec3 haze_color(vec3 zen, vec3 hor) {
	return mix(mix(zen, vec3(1.0), 0.35), hor, haze_tint) * 0.9;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 view = normalize(world_pos - cam);
	vec3 up = normalize(cam - planet_center);
	float alt = clamp((length(cam - planet_center) - planet_radius) / atmo_height, 0.0, 1.0);
	float vu = dot(view, up);
	float sun_up = dot(up, sun_dir);
	float day = smoothstep(-0.28, 0.22, sun_up);
	float dusk = exp(-pow(sun_up * 4.0, 2.0));

	// zenith: a deeper, richer take on the world's sky colour. AgX washes out
	// bright saturated colour, so the sky is kept darker and punchier going in.
	vec3 zen = pow(zenith_color, vec3(1.5)) * 0.62;
	vec3 hz = haze_color(zenith_color, horizon_color);
	// how far the sky is looking toward the sun, measured along the horizon
	vec3 view_h = normalize(view - up * vu + up * 0.0001);
	vec3 sun_h = normalize(sun_dir - up * sun_up + up * 0.0001);
	float toward_sun = max(dot(view_h, sun_h), 0.0);
	// dusk: orange and pink along the horizon, strongest toward the sun
	vec3 dusk_col = mix(vec3(1.0, 0.42, 0.28), vec3(1.0, 0.7, 0.45), toward_sun);
	hz = mix(hz, dusk_col, dusk * (0.35 + 0.55 * toward_sun));
	zen = mix(zen, zen * vec3(0.75, 0.7, 0.95), dusk * 0.6);

	// haze only in a band near the horizon; below it the sky stays hazy
	float h = clamp(1.0 - max(vu, 0.0), 0.0, 1.0);
	float band = pow(h, mix(7.0, 3.0, clamp(haze - 0.5, 0.0, 1.0)));
	vec3 col = mix(zen, hz, band);

	// sun: a wide soft glow, a tighter halo and the disc
	float sd = max(dot(view, sun_dir), 0.0);
	col += sun_color * (pow(sd, 8.0) * 0.12 + pow(sd, 64.0) * 0.45) * day;
	col += sun_color * pow(sd, 1400.0) * 8.0;

	float a = day * 0.97;
	a = max(a, band * 0.3 * (1.0 - day)); // faint night glow at the horizon
	a *= (1.0 - alt);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
