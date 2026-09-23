// Flora material with wind sway. Height above the model base drives bend.
shader_type spatial;
render_mode diffuse_lambert_wrap;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float base_height = 0.0; // part origin height inside the model
uniform float strength = 0.06;

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	float h = max(0.0, base_height + VERTEX.y);
	float t = TIME * 1.1 + dot(inst, vec3(0.05, 0.03, 0.04));
	float gust = sin(TIME * 0.35 + dot(inst, vec3(0.011, 0.017, 0.013))) * 0.5 + 0.5;
	float bend = (sin(t) + 0.35 * sin(t * 2.7)) * strength * (0.4 + 0.6 * gust) * h * h * 0.1;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission * emission_energy;
	RIM = 0.3;
	RIM_TINT = 0.5;
}
