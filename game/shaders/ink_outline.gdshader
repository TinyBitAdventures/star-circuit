// Storybook ink outlines: a full-screen pass that finds depth and normal
// breaks in the opaque scene and draws them as soft dark lines, fading with
// distance so far scenery stays painterly.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec3 ink : source_color = vec3(0.08, 0.06, 0.12);
uniform float thickness = 2.0;
uniform float fade_near = 35.0;
uniform float fade_far = 120.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = thickness / VIEWPORT_SIZE;
	float c = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float dd = 0.0;
	float nd = 0.0;
	vec3 nc = texture(normal_tex, SCREEN_UV).xyz * 2.0 - 1.0;
	// eight neighbours: depth jumps (silhouettes) and normal breaks (creases)
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 o = vec2(cos(a), sin(a)) * px;
		float s = lin_depth(SCREEN_UV + o, INV_PROJECTION_MATRIX);
		dd = max(dd, (s - c) / max(c, 0.001));
		vec3 n = texture(normal_tex, SCREEN_UV + o).xyz * 2.0 - 1.0;
		nd = max(nd, 1.0 - dot(nc, n));
	}
	float edge_d = smoothstep(0.03, 0.09, dd);
	float edge_n = smoothstep(0.12, 0.35, nd);
	float fade = 1.0 - smoothstep(fade_near, fade_far, c);
	float e = max(edge_d, edge_n * 0.75) * fade;
	if (c > 4000.0) {
		e = 0.0; // sky
	}
	ALBEDO = ink;
	ALPHA = e * 0.9;
}
