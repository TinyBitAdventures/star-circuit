class_name ArtStyle
## Art styles (Settings > Display > Art style):
##   0 Classic      the original smooth lighting
##   1 Illustrative banded "toon" light, cool shadows, warm rims, painted terrain
##   2 Storybook    Illustrative, bolder colour, plus ink outlines
## Shaders get a TOON variant generated at runtime (the source gains
## `#define TOON` and a shared light() function), so the originals stay
## untouched and Classic renders exactly as before.

const TOON_SHADERS := ["res://shaders/terrain.gdshader", "res://shaders/sway.gdshader", "res://shaders/grass.gdshader"]

const TOON_LIGHT := """

// ---- ArtStyle toon lighting (appended at runtime) ----
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sh = smoothstep(0.25, 0.6, ATTENUATION);
#ifdef TOON_SOFT
	float d = (smoothstep(-0.12, 0.12, ndl) * 0.65 + smoothstep(0.3, 0.55, ndl) * 0.35) * sh;
#else
	float d = (smoothstep(-0.03, 0.05, ndl) * 0.6 + smoothstep(0.4, 0.5, ndl) * 0.4) * sh;
#endif
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * d;
	if (LIGHT_IS_DIRECTIONAL) {
		// shade is cool, never grey
		DIFFUSE_LIGHT += vec3(0.16, 0.2, 0.38) * length(lc) * 0.3 * (1.0 - d);
		// a warm rim on the side facing the light
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * smoothstep(-0.2, 0.3, ndl);
		DIFFUSE_LIGHT += lc * vec3(1.0, 0.85, 0.65) * rim * 0.45;
	}
	float spec = smoothstep(0.93, 0.97, dot(reflect(-LIGHT, NORMAL), VIEW));
	SPECULAR_LIGHT += lc * spec * 0.12 * sh;
}
"""

static var _variants := {}
static var _outline_shader: Shader


static func style() -> int:
	return Sound.art_style


static func toon_shader(path: String) -> Shader:
	if _variants.has(path):
		return _variants[path]
	var src: Shader = load(path)
	var lines := src.code.split("\n")
	var out := PackedStringArray()
	var done := false
	for l in lines:
		if l.begins_with("render_mode"):
			l = l.replace("diffuse_lambert_wrap, ", "").replace(", diffuse_lambert_wrap", "").replace("diffuse_lambert_wrap", "diffuse_burley")
		out.append(l)
		if not done and l.begins_with("shader_type"):
			out.append("#define TOON")
			done = true
	var sh := Shader.new()
	sh.code = "\n".join(out) + TOON_LIGHT
	_variants[path] = sh
	return sh


## Restyle every material under `root` for the current style (both ways).
static func apply(root: Node) -> void:
	for n in _walk(root):
		apply_node(n)


static func apply_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var toon := style() >= 1
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		if gi.material_override:
			_style_material(gi.material_override, toon)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				if m:
					_style_material(m, toon)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			for i in mm.mesh.get_surface_count():
				var m2: Material = mm.mesh.surface_get_material(i)
				if m2:
					_style_material(m2, toon)


static func _style_material(m: Material, toon: bool) -> void:
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return
		sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if toon else BaseMaterial3D.DIFFUSE_BURLEY
		sm.specular_mode = BaseMaterial3D.SPECULAR_TOON if toon else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	elif m is ShaderMaterial:
		var shm := m as ShaderMaterial
		if shm.shader == null:
			return
		var orig: String = shm.get_meta("orig_shader", shm.shader.resource_path)
		if not orig in TOON_SHADERS:
			return
		shm.set_meta("orig_shader", orig)
		shm.shader = toon_shader(orig) if toon else load(orig)
		if toon:
			shm.set_shader_parameter("paint", 1.8 if style() == 2 else 1.0)


static func _walk(root: Node) -> Array:
	var out := [root]
	var i := 0
	while i < out.size():
		out.append_array(out[i].get_children())
		i += 1
	return out


## World-level look: colour grade and ambient, and ink outlines for Storybook.
static func apply_env(env: Environment, camera: Camera3D) -> void:
	var s := style()
	env.adjustment_enabled = s >= 1
	env.adjustment_saturation = [1.0, 1.03, 1.1][s]
	env.adjustment_contrast = [1.0, 1.04, 1.08][s]
	env.adjustment_brightness = [1.0, 1.02, 1.03][s]
	if camera:
		var ol: Node = camera.get_node_or_null("InkOutline")
		if s == 2 and ol == null:
			camera.add_child(_outline_quad())
		elif s != 2 and ol:
			ol.queue_free()


static func _outline_quad() -> MeshInstance3D:
	if _outline_shader == null:
		_outline_shader = load("res://shaders/ink_outline.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "InkOutline"
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.flip_faces = true
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _outline_shader
	mi.material_override = m
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0, -1)
	return mi
