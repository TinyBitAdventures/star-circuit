// Orbit view: a sliced world. Drawn on a square ColorRect centred on the
// planet; everything is in units of the planet radius. Surface, clouds and
// atmosphere on the rim, then crust strata, a convecting mantle, a churning
// outer core and a white-hot inner core.
shader_type canvas_item;

uniform float rot = 0.0;          // planet rotation (screen angle = local + rot)
uniform float extent = 1.4;       // rect half-size in planet radii
uniform float seed = 0.0;
uniform bool giant = false;
uniform bool sea = false;
uniform vec3 c_surface : source_color = vec3(0.3, 0.6, 0.25);
uniform vec3 c_low : source_color = vec3(0.5, 0.8, 0.3);
uniform vec3 c_peak : source_color = vec3(0.95);
uniform vec3 c_water : source_color = vec3(0.15, 0.4, 0.7);
uniform vec3 c_crust : source_color = vec3(0.45, 0.4, 0.35);
uniform vec3 c_mantle : source_color = vec3(0.35, 0.12, 0.06);
uniform vec3 c_atmo : source_color = vec3(0.5, 0.8, 1.0);
uniform vec2 sun_dir = vec2(-0.7, -0.7); // toward the sun, screen space

// layer boundaries (fractions of radius)
const float CRUST = 0.86;
const float MANTLE = 0.55;
const float CORE = 0.26;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.55;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}
// periodic noise around the circle
float ring_noise(float ang, float k, float off) {
	return fbm(vec2(cos(ang), sin(ang)) * k + vec2(seed * 0.013 + off, seed * 0.007));
}

void fragment() {
	vec2 sp = (UV - 0.5) * 2.0 * extent; // screen-oriented, in radii
	float r = length(sp);
	float sang = atan(sp.y, sp.x);
	float ang = sang - rot;               // planet-local angle
	vec2 lp = vec2(cos(ang), sin(ang)) * r; // planet-local position
	float light = dot(normalize(sp + 1e-5), normalize(sun_dir));
	vec4 col = vec4(0.0);

	// terrain height around the rim
	float h = ring_noise(ang, 1.8, 0.0) - 0.5;
	float land = giant ? 1.0 : 1.0 + (sea ? max(h, 0.0) : h) * 0.1;
	float surf_top = max(land, 1.0);

	if (r > surf_top) {
		// atmosphere + clouds
		float t = (r - surf_top) / 0.22;
		float glow = exp(-t * 3.2) * smoothstep(1.0, 0.0, t);
		vec3 a = c_atmo * (0.55 + 0.6 * clamp(light, 0.0, 1.0));
		col = vec4(a, glow * 0.75);
		float cl = ring_noise(ang - TIME * 0.03, 4.0, 7.0);
		float band = smoothstep(0.035, 0.0, abs(r - surf_top - 0.045));
		float cloud = smoothstep(0.52, 0.62, cl) * band;
		col = mix(col, vec4(vec3(1.0) * (0.7 + 0.3 * clamp(light, 0.0, 1.0)), 0.92), cloud);
	} else if (giant) {
		// gas envelope, metallic sea, rocky-ice core
		if (r > 0.8) {
			float b = sin(lp.y * 30.0 + fbm(lp * 5.0 + vec2(TIME * 0.05, 0.0)) * 5.0);
			vec3 c = mix(c_surface, c_low, b * 0.5 + 0.5);
			c = mix(c, c_peak, smoothstep(0.6, 0.9, fbm(lp * 9.0 - vec2(TIME * 0.03, 0.0))) * 0.35);
			col = vec4(c * (0.75 + 0.35 * clamp(light, 0.0, 1.0)), 1.0);
		} else if (r > MANTLE) {
			// metallic hydrogen sea
			float s = fbm(lp * 4.0 + vec2(TIME * 0.04, -TIME * 0.03));
			vec3 deep = vec3(0.14, 0.16, 0.42);
			vec3 c = mix(deep, deep * 1.9 + c_low * 0.15, s);
			c *= 0.75 + 0.35 * smoothstep(MANTLE, 0.8, r);
			col = vec4(c, 1.0);
		} else if (r > CORE) {
			// hot, crushing slush around the core
			float s = fbm(lp * 5.0 + vec2(TIME * 0.1, TIME * 0.06));
			vec3 c = mix(vec3(0.55, 0.3, 0.55), vec3(0.95, 0.55, 0.3), s);
			c = mix(c, vec3(1.0, 0.8, 0.45), smoothstep(MANTLE - 0.1, CORE, r) * 0.5);
			col = vec4(c, 1.0);
		} else {
			float s = fbm(lp * 6.0 + TIME * 0.1);
			vec3 c = mix(vec3(1.0, 0.85, 0.5), vec3(1.0, 0.98, 0.9), smoothstep(CORE, 0.0, r) + s * 0.3);
			col = vec4(c * 1.25, 1.0);
		}
	} else {
		float wob = (ring_noise(ang, 3.0, 3.0) - 0.5) * 0.05;
		float wob2 = (ring_noise(ang, 2.5, 9.0) - 0.5) * 0.06;
		float crust_top = 0.955 + wob * 0.4;
		if (r > crust_top) {
			// the living surface: oceans, grass, snowy peaks
			if (sea && r > land) {
				col = vec4(c_water * (0.8 + 0.3 * clamp(light, 0.0, 1.0)), 1.0);
				col.rgb += vec3(0.25) * smoothstep(0.004, 0.0, abs(r - 1.0)); // shoreline foam
			} else {
				vec3 c = mix(c_surface, c_low, smoothstep(land - 0.03, land, r));
				c = mix(c, c_peak, smoothstep(0.25, 0.4, h) * smoothstep(land - 0.02, land, r));
				c *= 0.8 + 0.35 * clamp(light, 0.0, 1.0);
				col = vec4(c, 1.0);
			}
		} else if (r > CRUST + wob) {
			// crust: layered strata with pebbles
			float st = sin(r * 140.0 + fbm(lp * 6.0) * 7.0);
			vec3 c = c_crust * (0.82 + 0.12 * st);
			c = mix(c, c_crust * 1.35, step(0.93, noise(lp * 90.0)));
			c *= 0.8 + 0.25 * smoothstep(CRUST, 0.955, r);
			col = vec4(c, 1.0);
		} else if (r > MANTLE + wob2) {
			// mantle: slow convection
			float s = fbm(lp * 3.5 + vec2(TIME * 0.02, -TIME * 0.015));
			float vein = smoothstep(0.04, 0.0, abs(s - 0.5));
			vec3 c = mix(c_mantle * 0.7, c_mantle * 1.3, s);
			c += vec3(0.9, 0.3, 0.05) * vein * 0.28;
			c = mix(c, vec3(0.5, 0.14, 0.04), smoothstep(CRUST - 0.1, MANTLE, r) * 0.45);
			col = vec4(c, 1.0);
		} else if (r > CORE + wob * 0.5) {
			// outer core: molten and churning
			float s = fbm(lp * 5.0 + vec2(TIME * 0.12, TIME * 0.08));
			vec3 c = mix(vec3(0.62, 0.12, 0.02), vec3(0.95, 0.42, 0.06), s);
			c = mix(c, vec3(1.0, 0.7, 0.3), smoothstep(MANTLE - 0.1, CORE, r) * 0.45);
			col = vec4(c * 1.05, 1.0);
		} else {
			// inner core
			float pulse = 0.9 + 0.1 * sin(TIME * 2.2);
			vec3 c = mix(vec3(1.0, 0.85, 0.45), vec3(1.0, 1.0, 0.92), smoothstep(CORE, 0.05, r));
			col = vec4(c * 1.25 * pulse, 1.0);
		}
		// dark seams between layers, Spore-style
		float seam = smoothstep(0.006, 0.0, abs(r - (CRUST + wob))) + smoothstep(0.006, 0.0, abs(r - (MANTLE + wob2)))
			+ smoothstep(0.005, 0.0, abs(r - crust_top)) * 0.6;
		col.rgb *= 1.0 - clamp(seam, 0.0, 1.0) * 0.45;
	}
	// hot glow bleeding out of the core
	if (r < MANTLE && !giant) {
		col.rgb += vec3(1.0, 0.45, 0.1) * smoothstep(MANTLE, CORE, r) * 0.06;
	}
	COLOR = col;
}
