// Camera-facing health bar. Per-instance fill + colour, no material dupes.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, fog_disabled;

instance uniform float fill = 1.0;
instance uniform vec4 bar_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.02) + step(0.98, uv.x) + step(uv.y, 0.12) + step(0.88, uv.y);
	vec3 col = uv.x < fill ? bar_color.rgb : vec3(0.05, 0.05, 0.08);
	col = mix(col, vec3(0.0), clamp(border, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = 0.92;
}
