// Illustrated planet globe (see Globe.gd). The height/colour texture is baked
// from the planet's real generator; everything crisp is drawn per pixel.
shader_type spatial;
render_mode fog_disabled, shadows_disabled;

uniform sampler2D globe_tex : source_color, filter_linear, repeat_enable;
uniform bool has_sea = true;
uniform bool lava = false;
uniform vec3 deep_color : source_color = vec3(0.12, 0.35, 0.6);
uniform vec3 shallow_color : source_color = vec3(0.35, 0.7, 0.85);
uniform vec3 foam_color : source_color = vec3(0.8, 0.92, 1.0);
uniform vec3 ink_color : source_color = vec3(0.05, 0.08, 0.16);
uniform float seed = 0.0;

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
	return vnoise(p) * 0.55 + vnoise(p * 2.07) * 0.3 + vnoise(p * 4.3) * 0.15;
}

// a thin line where v crosses zero, anti-aliased by its screen-space width
float line(float v, float w) {
	float aa = max(fwidth(v), 1e-5);
	return 1.0 - smoothstep(aa * w * 0.5, aa * (w + 1.0), abs(v));
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 d = normalize(obj);
	float u = atan(d.x, d.z) / TAU + 0.5;
	vec2 uv = vec2(u, acos(clamp(d.y, -1.0, 1.0)) / PI);
	// sample without derivatives so the longitude wrap never shows a seam
	vec4 t = textureLod(globe_tex, uv, 0.0);
	vec3 sd = d * 12.0 + vec3(seed);
	// small wiggles give the coastline more detail than the texture holds
	float h = (t.a - 0.5) + (fbm(sd) - 0.5) * 0.024;

	// land: flat painted tones with a gentle brush grain
	vec3 land = t.rgb * (0.95 + 0.08 * vnoise(d * 38.0 + vec3(seed)));
	// contour lines up the hills
	float up_h = max(h - 0.018, 0.0);
	float band = fract(up_h / 0.045 + 0.5) - 0.5;
	float contour = line(band, 1.0) * step(0.0005, up_h);
	land *= 1.0 - contour * 0.22;
	vec3 col = land;
	float water = 0.0;

	if (has_sea) {
		float aa = max(fwidth(h), 1e-5);
		float is_land = smoothstep(-aa, aa, h);
		water = 1.0 - is_land;
		vec3 sea_col;
		if (lava) {
			float crust = smoothstep(0.52, 0.6, fbm(d * 7.0 + vec3(seed)));
			sea_col = mix(vec3(1.0, 0.42, 0.08) * 1.3, vec3(0.16, 0.07, 0.06), crust);
			sea_col = mix(sea_col, vec3(1.0, 0.8, 0.35) * 1.6, smoothstep(-0.04, -0.005, h) * (1.0 - crust));
			EMISSION = sea_col * water * (1.0 - crust) * 1.2;
		} else {
			float sh = smoothstep(-0.032 - aa, -0.032 + aa, h);
			sea_col = mix(deep_color, shallow_color, sh);
			// a dashed wave ring offshore, like an old sea chart
			float dash = step(0.42, vnoise(d * 55.0 + vec3(seed)));
			sea_col = mix(sea_col, foam_color, line(h + 0.05, 1.2) * dash * 0.75);
			// long brush strokes across the open sea
			sea_col *= 0.965 + 0.05 * sin(d.y * 140.0 + fbm(d * 5.0 + vec3(seed)) * 14.0) * (1.0 - sh);
		}
		col = mix(sea_col, land, is_land);
		// inked coastline
		col = mix(col, lava ? vec3(0.08, 0.03, 0.02) : ink_color, line(h, 1.4) * 0.85);
	}

	// ink silhouette
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, ink_color, smoothstep(0.86, 0.93, fres) * 0.9);

	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.05, water);
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lc = LIGHT_COLOR / PI;
	// two crisp light bands
	float d = smoothstep(-0.02, 0.05, ndl) * 0.62 + smoothstep(0.38, 0.46, ndl) * 0.38;
	// halftone dots soften the terminator into the night side
	vec2 fc = FRAGCOORD.xy * 0.2;
	fc = vec2(fc.x + fc.y, fc.y - fc.x) * 0.7071;
	float tone = smoothstep(-0.3, 0.03, ndl) * (1.0 - d);
	float rad = 0.62 * sqrt(tone);
	float dots = 1.0 - smoothstep(rad - 0.08, rad, length(fract(fc) - 0.5));
	DIFFUSE_LIGHT += lc * (d + dots * 0.32 * step(0.02, tone));
	if (LIGHT_IS_DIRECTIONAL) {
		// the shade is a cool violet, never grey
		DIFFUSE_LIGHT += vec3(0.2, 0.16, 0.46) * length(lc) * 0.5 * (1.0 - d);
		// warm edge on the lit limb
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * smoothstep(0.0, 0.4, ndl);
		DIFFUSE_LIGHT += lc * vec3(1.0, 0.82, 0.6) * rim * 0.5;
	}
	// one crisp painted glint on the water
	if (ROUGHNESS < 0.5) {
		float s = smoothstep(0.9935, 0.9955, dot(reflect(-LIGHT, NORMAL), VIEW));
		SPECULAR_LIGHT += lc * s * 1.1;
	}
}
