class_name ModelUtil
extends RefCounted
## Helpers for the Blender-exported .glb models.

static var _cache := {}
static var _soft_dot: GradientTexture2D


## Round, soft-edged sprite for particles (instead of hard squares).
static func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.75))
		_soft_dot = GradientTexture2D.new()
		_soft_dot.gradient = g
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(1.0, 0.5)
		_soft_dot.width = 64
		_soft_dot.height = 64
	return _soft_dot


static func scene(path: String) -> PackedScene:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


static func instance(path: String) -> Node3D:
	return scene(path).instantiate()


## Re-colour every surface whose material is named `mat_name`.
static func tint(root: Node, mat_name: String, color: Color) -> void:
	for mi in _mesh_instances(root):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m and m.resource_name == mat_name and m is StandardMaterial3D:
				var dup: StandardMaterial3D = m.duplicate()
				dup.albedo_color = color
				if dup.emission_enabled:
					dup.emission = color
				mi.set_surface_override_material(i, dup)


static func _mesh_instances(root: Node) -> Array:
	var out := []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out


## Flatten a model into [{mesh, xform}] relative to the model root, applying
## an optional tint to materials named `tint_name`.
static func flatten(path: String, tint_name := "", tint_color := Color.WHITE) -> Array:
	var inst := instance(path)
	var parts := []
	for mi in _mesh_instances(inst):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != inst:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var mesh: Mesh = mi.mesh
		if tint_name != "":
			mesh = mesh.duplicate()
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m and m.resource_name == tint_name and m is StandardMaterial3D:
					var dup: StandardMaterial3D = m.duplicate()
					dup.albedo_color = tint_color
					mesh.surface_set_material(i, dup)
		parts.append({"mesh": mesh, "xform": xf})
	inst.free()
	return parts


## Build MultiMeshInstance3Ds that draw `path` at every transform in `xforms`.
static func multimesh(parent: Node3D, path: String, xforms: Array, tint_name := "", tint_color := Color.WHITE, shadows := true) -> void:
	if xforms.is_empty():
		return
	for p in flatten(path, tint_name, tint_color):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = p.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * p.xform)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)



## Soft rim light on every material of a model (the Spore-ish glow edge).
static func add_rim(root: Node, amount := 0.35, tint := 0.4) -> void:
	for mi in _mesh_instances(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			var owned := m != null
			if m == null:
				m = mesh.surface_get_material(i)
			if not (m is StandardMaterial3D):
				continue
			var sm: StandardMaterial3D = m if owned else m.duplicate()
			sm.rim_enabled = true
			sm.rim = amount
			sm.rim_tint = tint
			if not owned:
				mi.set_surface_override_material(i, sm)
