shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.9, 0.6);
uniform float intensity = 4.0;

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

varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }

void fragment() {
	float n = vnoise(normalize(local_pos) * 6.0 + TIME * 0.15) * 0.6 + vnoise(normalize(local_pos) * 17.0 - TIME * 0.2) * 0.4;
	float limb = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = color * intensity * (0.7 + 0.6 * n) * (0.6 + 0.4 * limb);
}
