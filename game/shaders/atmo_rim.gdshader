// Atmospheric halo seen from space.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.4, 0.7, 1.0);
uniform float power = 3.0;
uniform float strength = 1.4;
uniform bool stylized = false; // illustrated globes: a crisp two-step halo

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, power);
	float inner = smoothstep(1.0, 0.85, f);
	if (stylized) {
		float aa = max(fwidth(f), 1e-4);
		// the globe edge sits near f = 0.58 on a shell 1.1x its radius
		float band1 = smoothstep(0.55 - aa, 0.55 + aa, f) * (1.0 - smoothstep(0.9 - aa, 0.9 + aa, f));
		float band2 = smoothstep(0.72 - aa, 0.72 + aa, f) * (1.0 - smoothstep(0.82 - aa, 0.82 + aa, f));
		ALBEDO = color * (band1 * 0.35 + band2 * 0.45) * strength;
	} else {
		ALBEDO = color * rim * strength * inner;
	}
}
