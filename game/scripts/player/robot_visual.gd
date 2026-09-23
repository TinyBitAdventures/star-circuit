class_name RobotVisual
extends Node3D

signal step
## Procedural animation for the Blender robots (no skeleton needed: the
## exported parts are named joints).

var move_amount := 0.0 # 0..1 walk blend
var airborne := false
var jetting := false
var working := false # harvesting / crafting
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


## Non-player robots (townsfolk): any model with the standard joint names.
func setup_model(path: String, tint := Color(-1, 0, 0)) -> void:
	robot_id = ""
	_load_model(path)
	if tint.r >= 0.0:
		ModelUtil.tint(model, "Accent", tint)


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
	elif working:
		_pose("ArmL", Vector3.ZERO, Vector3(-0.9 + sin(_t * 18.0) * 0.25, 0, 0))
		_pose("ArmR", Vector3.ZERO, Vector3(-1.3 + sin(_t * 22.0 + 1.0) * 0.35, 0, 0))
		_pose("LegL", Vector3.ZERO, Vector3.ZERO)
		_pose("LegR", Vector3.ZERO, Vector3.ZERO)
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
