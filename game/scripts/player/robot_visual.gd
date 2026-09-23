class_name RobotVisual
extends Node3D

signal step
## Procedural animation for the Blender robots (no skeleton needed: the
## exported parts are named joints).

var move_amount := 0.0 # 0..1 walk blend
var airborne := false
var jetting := false
var working := false # harvesting / crafting
var swimming := false
var work_skill := "" # mining / botany / siphoning: picks the working pose
var work_progress := 0.0
var flying := false # space flight pose
var boost := false
var aiming := false
var sprinting := false
var _sprint_amt := 0.0
var _walk_phase := 0.0
var model: Node3D
var robot_id := ""

var _parts := {}
var _rest := {}
var _t := 0.0
var _flames: Array[CPUParticles3D] = []
var _last_step_sign := 0.0


func setup(id: String) -> void:
	robot_id = id
	_load_model(Db.ROBOTS[id].model)
	_add_flames()
	ModelUtil.add_rim(model, 0.35)


## Non-player robots (townsfolk): any model with the standard joint names.
func setup_model(path: String, tint := Color(-1, 0, 0)) -> void:
	robot_id = ""
	_load_model(path)
	if tint.r >= 0.0:
		ModelUtil.tint(model, "Accent", tint)
	ModelUtil.add_rim(model, 0.3)


func _load_model(path: String) -> void:
	if model:
		model.queue_free()
	model = ModelUtil.instance(path)
	add_child(model)
	_parts.clear()
	_rest.clear()
	for n in ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR", "Thruster", "Halo", "Antenna"]:
		var node := model.find_child(n, true, false) as Node3D
		if node:
			_parts[n] = node
			_rest[n] = node.transform


func _add_flames() -> void:
	_flames.clear()
	var thr: Node3D = _parts.get("Thruster")
	if thr == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = ModelUtil.soft_dot()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	quad.material = mat
	var grad := Gradient.new()
	var col: Color = Db.ROBOTS[robot_id].color
	grad.set_color(0, Color(1, 1, 0.9, 1))
	grad.set_color(1, Color(col.r, col.g, col.b, 0))
	grad.add_point(0.35, Color(col.lightened(0.3), 0.9))
	for x in [-0.14, 0.14]:
		var p := CPUParticles3D.new()
		p.mesh = quad
		p.amount = 28
		p.lifetime = 0.35
		p.emitting = false
		p.local_coords = false
		p.direction = Vector3.DOWN
		p.spread = 8.0
		p.initial_velocity_min = 5.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.3
		p.color_ramp = grad
		p.position = Vector3(x, -0.45, 0)
		thr.add_child(p)
		_flames.append(p)


func _process(delta: float) -> void:
	if model == null:
		return
	_t += delta
	_sprint_amt = lerpf(_sprint_amt, 1.0 if sprinting else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	# stride speeds up with pace, so a sprint reads as a sprint
	_walk_phase += delta * (9.0 + 6.0 * _sprint_amt) * maxf(move_amount, 0.3)
	var walk_phase := _walk_phase
	var swing := sin(walk_phase) * (0.7 + 0.45 * _sprint_amt) * move_amount
	var sgn := signf(sin(walk_phase))
	if sgn != _last_step_sign and move_amount > 0.35 and not airborne and not flying and not working:
		step.emit()
	_last_step_sign = sgn
	var bob := absf(sin(walk_phase)) * 0.06 * move_amount
	var idle := sin(_t * 2.0) * 0.025

	_pose("Torso", Vector3(0, bob + idle, 0), Vector3((0.12 * move_amount + 0.28 * _sprint_amt) if not flying else 0.0, 0, 0))
	_pose("Head", Vector3.ZERO, Vector3(sin(_t * 0.7) * 0.05, sin(_t * 0.5) * 0.25 * (1.0 - move_amount), 0))
	if flying:
		_pose("ArmL", Vector3.ZERO, Vector3(-0.9, 0, -0.35))
		_pose("ArmR", Vector3.ZERO, Vector3(-0.9, 0, 0.35))
		_pose("LegL", Vector3.ZERO, Vector3(-0.6, 0, 0))
		_pose("LegR", Vector3.ZERO, Vector3(-0.6, 0, 0))
	elif aiming:
		_pose("ArmL", Vector3.ZERO, Vector3(swing * 0.5, 0, -0.08))
		_pose("ArmR", Vector3.ZERO, Vector3(-1.5, 0, 0.1))
		_pose("LegL", Vector3.ZERO, Vector3(-swing * 0.8, 0, 0))
		_pose("LegR", Vector3.ZERO, Vector3(swing * 0.8, 0, 0))
	elif swimming and not working:
		# a lazy breaststroke with a flutter kick
		var st := _t * 3.2
		_pose("Torso", Vector3(0, idle, 0), Vector3(0.35 * move_amount + 0.1, 0, sin(st) * 0.05))
		_pose("ArmL", Vector3.ZERO, Vector3(-1.2 + sin(st) * 0.9, 0, -0.4 - cos(st) * 0.5))
		_pose("ArmR", Vector3.ZERO, Vector3(-1.2 + sin(st) * 0.9, 0, 0.4 + cos(st) * 0.5))
		_pose("LegL", Vector3.ZERO, Vector3(sin(_t * 7.0) * 0.4, 0, 0))
		_pose("LegR", Vector3.ZERO, Vector3(-sin(_t * 7.0) * 0.4, 0, 0))
	elif working:
		match work_skill:
			"mining":
				# tool arm locked on target, bucking with the cutter's recoil; off arm braces
				var kick := sin(_t * 31.0) * 0.06 + sin(_t * 13.0) * 0.04
				_pose("Torso", Vector3(0, idle, 0), Vector3(0.22 + kick * 0.5, 0, sin(_t * 23.0) * 0.02))
				_pose("ArmR", Vector3.ZERO, Vector3(-1.5 + kick, 0, 0.12))
				_pose("ArmL", Vector3.ZERO, Vector3(-1.1 + kick * 0.5, 0, -0.35))
				_pose("LegL", Vector3.ZERO, Vector3(-0.3, 0, -0.08))
				_pose("LegR", Vector3.ZERO, Vector3(0.25, 0, 0.08))
				_pose("Head", Vector3.ZERO, Vector3(0.18, 0, 0))
			"botany":
				# both hands out, coaxing the plant loose
				var sway := sin(_t * 3.5) * 0.12
				_pose("Torso", Vector3(0, idle, 0), Vector3(0.15, sway * 0.3, 0))
				_pose("ArmR", Vector3.ZERO, Vector3(-1.35 + sway, 0, 0.25))
				_pose("ArmL", Vector3.ZERO, Vector3(-1.35 - sway, 0, -0.25))
				_pose("LegL", Vector3.ZERO, Vector3.ZERO)
				_pose("LegR", Vector3.ZERO, Vector3.ZERO)
			_:
				# siphoning: arms raised wide, drinking in the light
				var pulse := sin(_t * 5.0) * 0.08
				_pose("Torso", Vector3(0, idle + 0.03 * work_progress, 0), Vector3(-0.08, 0, 0))
				_pose("ArmR", Vector3.ZERO, Vector3(-1.9 + pulse, 0, 0.55))
				_pose("ArmL", Vector3.ZERO, Vector3(-1.9 + pulse, 0, -0.55))
				_pose("LegL", Vector3.ZERO, Vector3.ZERO)
				_pose("LegR", Vector3.ZERO, Vector3.ZERO)
				_pose("Head", Vector3.ZERO, Vector3(-0.15, 0, 0))
	elif airborne:
		_pose("ArmL", Vector3.ZERO, Vector3(0.3, 0, -0.5))
		_pose("ArmR", Vector3.ZERO, Vector3(0.3, 0, 0.5))
		_pose("LegL", Vector3.ZERO, Vector3(0.35, 0, 0))
		_pose("LegR", Vector3.ZERO, Vector3(-0.2, 0, 0))
	else:
		_pose("ArmL", Vector3.ZERO, Vector3(swing, 0, -0.08))
		_pose("ArmR", Vector3.ZERO, Vector3(-swing, 0, 0.08))
		_pose("LegL", Vector3.ZERO, Vector3(-swing * 0.8, 0, 0))
		_pose("LegR", Vector3.ZERO, Vector3(swing * 0.8, 0, 0))
	if _parts.has("Halo"):
		_parts.Halo.rotation.z = _t * 1.5
	for f in _flames:
		f.emitting = jetting or flying
		f.scale_amount_max = 0.55 if flying and not boost else 1.3
		f.scale_amount_min = 0.3 if flying and not boost else 0.8
		f.initial_velocity_min = 9.0 if boost else 5.0
		f.initial_velocity_max = 12.0 if boost else 7.0


func _pose(part: String, offset: Vector3, rot: Vector3) -> void:
	var n: Node3D = _parts.get(part)
	if n == null:
		return
	var rest: Transform3D = _rest[part]
	var target := Transform3D(rest.basis * Basis.from_euler(rot), rest.origin + offset)
	n.transform = n.transform.interpolate_with(target, 0.25)



# --------------------------------------------------------------------------
# customisation
# --------------------------------------------------------------------------

## Rebuild the model with the player's parts, paint and finish.
func apply_look(look: Dictionary) -> void:
	if robot_id == "":
		return
	setup(robot_id)
	# remember the robot's factory colours so new parts match when unpainted
	var base := {"Shell": _find_color("Shell", Color("e6e8ec")), "Accent": _find_color("Accent", Color("18c2b0"))}
	var head_id: String = look.get("head", "default")
	if head_id != "default":
		_swap_part("Head", Game.cosmetic("head", head_id).model)
	var top_id: String = look.get("top", "none")
	if top_id != "none":
		_add_topper(Game.cosmetic("top", top_id).model)
	var pack_id: String = look.get("pack", "default")
	if pack_id != "default":
		_swap_part("Thruster", Game.cosmetic("pack", pack_id).model)
	var shell: Color = Color(look.shell) if look.has("shell") else base.Shell
	var accent: Color = Color(look.accent) if look.has("accent") else base.Accent
	var glow: Color = Color(look.glow) if look.has("glow") else Color(-1, 0, 0)
	var flame: Color = Color(look.flame) if look.has("flame") else Color(-1, 0, 0)
	_paint(shell, accent, glow, look.get("finish", "standard"))
	if flame.r >= 0.0:
		_tint_flames(flame)
	ModelUtil.add_rim(model, 0.35)


func _find_color(mat_name: String, fallback: Color) -> Color:
	for mi in ModelUtil._mesh_instances(model):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m is StandardMaterial3D and m.resource_name == mat_name:
				return (m as StandardMaterial3D).albedo_color
	return fallback


## Replace a joint's own geometry (keeping the joint so it still animates).
func _swap_part(joint: String, path: String) -> void:
	var n: Node3D = _parts.get(joint)
	if n == null:
		return
	if n is MeshInstance3D:
		(n as MeshInstance3D).mesh = null
	for c in n.get_children():
		if c is CPUParticles3D:
			continue
		if c is Node3D:
			(c as Node3D).visible = false
	var inst := ModelUtil.instance(path)
	inst.name = "Custom" + joint
	n.add_child(inst)


## Sit a topper on the highest point of whatever head is fitted.
func _add_topper(path: String) -> void:
	var head: Node3D = _parts.get("Head")
	if head == null:
		return
	var box := AABB()
	var first := true
	for mi in ModelUtil._mesh_instances(head):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var xf: Transform3D = head.global_transform.affine_inverse() * mi.global_transform if head.is_inside_tree() else _relative(head, mi)
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var inst := ModelUtil.instance(path)
	inst.name = "CustomTop"
	head.add_child(inst)
	var c := box.get_center()
	inst.position = Vector3(c.x, box.end.y - 0.04, c.z) if not first else Vector3(0, 0.5, 0)


func _relative(ancestor: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _paint(shell: Color, accent: Color, glow: Color, finish: String) -> void:
	for mi in ModelUtil._mesh_instances(model):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if not (m is StandardMaterial3D):
				continue
			var sm := m as StandardMaterial3D
			var role := ""
			if sm.resource_name == "Shell":
				role = "shell"
			elif sm.resource_name == "Accent":
				role = "accent"
			elif sm.emission_enabled and not sm.resource_name.begins_with("ThrusterGlow") and not sm.resource_name.begins_with("Engine"):
				role = "glow"
			if role == "" or (role == "glow" and glow.r < 0.0):
				continue
			var d: StandardMaterial3D = sm.duplicate()
			match role:
				"shell":
					d.albedo_color = shell
				"accent":
					d.albedo_color = accent
				"glow":
					d.albedo_color = glow
					d.emission = glow
			if role != "glow":
				match finish:
					"matte":
						d.metallic = 0.0
						d.roughness = 0.95
					"chrome":
						d.metallic = 1.0
						d.roughness = 0.12
						d.albedo_color = d.albedo_color.lightened(0.25)
					"gold":
						if role == "shell":
							d.albedo_color = Color("e8b93a")
						d.metallic = 1.0
						d.roughness = 0.22
					"neon":
						if role == "accent":
							d.emission_enabled = true
							d.emission = accent
							d.emission_energy_multiplier = 2.2
			mi.set_surface_override_material(i, d)


func _tint_flames(c: Color) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 0.95, 1))
	grad.set_color(1, Color(c.r, c.g, c.b, 0))
	grad.add_point(0.35, Color(c.lightened(0.2), 0.9))
	for f in _flames:
		f.color_ramp = grad



## Where the tool arm's hand is, for beams and effects.
func hand_position() -> Vector3:
	var arm: Node3D = _parts.get("ArmR")
	if arm == null:
		return global_position + global_basis.y * 1.2
	return arm.global_transform * Vector3(0, -0.62, 0)
