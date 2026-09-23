class_name HarvestFx
extends Node3D
## The robot's working tool: a beam from its hand to whatever it's
## gathering, plus the effects at the far end. Mining cuts with a hot
## laser (sparks, rock chips, dust), botany pulls with a green tractor
## (leaves), siphoning draws a golden stream back to the robot.

var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _chips: CPUParticles3D
var _stream: CPUParticles3D
var _hand_glow: MeshInstance3D
var _t := 0.0
var _active := false

const COLORS := {"mining": Color(1.0, 0.55, 0.2), "botany": Color(0.45, 1.0, 0.45), "siphoning": Color(1.0, 0.85, 0.3)}


func _ready() -> void:
	top_level = true
	_beam_mat = _additive(Color.WHITE)
	_beam = _cylinder(0.09, _beam_mat)
	_core_mat = _additive(Color.WHITE)
	_core = _cylinder(0.03, _core_mat)
	_hand_glow = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	s.radial_segments = 12
	s.rings = 6
	s.material = _additive(Color.WHITE)
	_hand_glow.mesh = s
	add_child(_hand_glow)
	_light = OmniLight3D.new()
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_sparks = _particles(48, 0.4, Vector3(0, -12, 0), 0.022, 0.1, true)
	_chips = _particles(12, 0.8, Vector3(0, -14, 0), 0.08, 0.1, false)
	_stream = _particles(36, 0.6, Vector3.ZERO, 0.035, 0.07, false)
	_stream.scale_amount_min = 0.6
	_stream.scale_amount_max = 1.2
	# stream motes are shaded flat so leaf-green and gold read as colour
	var sm: StandardMaterial3D = _stream.mesh.surface_get_material(0)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_set_visible(false)


func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _cylinder(radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 1.0
	c.radial_segments = 8
	c.rings = 1
	c.material = mat
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _particles(n: int, life: float, grav: Vector3, s0: float, s1: float, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.gravity = grav
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	var m: PrimitiveMesh
	if glow:
		var sm := SphereMesh.new()
		sm.radius = s0
		sm.height = s0 * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		m = sm
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * s1
		m = bm
	var mat := StandardMaterial3D.new()
	if glow:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	add_child(p)
	return p


func _set_visible(v: bool) -> void:
	_beam.visible = v
	_core.visible = v
	_hand_glow.visible = v


## Called every frame by the player while it's gathering (or not).
func update(active: bool, skill: String, from: Vector3, to: Vector3, progress: float, item_color: Color, delta: float) -> void:
	_t += delta
	if not active:
		if _active:
			_active = false
			_set_visible(false)
			_sparks.emitting = false
			_chips.emitting = false
			_stream.emitting = false
		_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 8.0)
		return
	_active = true
	_set_visible(true)
	var col: Color = COLORS.get(skill, Color.WHITE)
	var d := to - from
	var len := d.length()
	if len < 0.05:
		return
	var dir := d / len
	# a wobbling beam: thicker and brighter as the work nears done
	var flick := 0.8 + 0.2 * sin(_t * 47.0) + 0.1 * sin(_t * 71.0)
	var w := (0.7 + progress * 0.6) * flick
	var b := _basis_along(dir)
	_beam.global_transform = Transform3D(b * Basis.from_scale(Vector3(w, len, w)), from + d * 0.5)
	_core.global_transform = Transform3D(b * Basis.from_scale(Vector3(w, len, w)), from + d * 0.5)
	var up := to.normalized() # planets are centred on the origin
	_sparks.gravity = -up * 12.0
	_chips.gravity = -up * 14.0
	_beam_mat.albedo_color = Color(col, 0.28 if skill == "mining" else 0.2)
	_core_mat.albedo_color = Color(col.lerp(Color.WHITE, 0.6), 0.9 if skill == "mining" else 0.55)
	_hand_glow.global_position = from
	(_hand_glow.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(col, 0.6 * flick)
	_light.global_position = to - dir * 0.4
	_light.light_color = col
	_light.light_energy = (1.2 + progress * 1.5) * flick
	match skill:
		"mining":
			_sparks.global_position = to - dir * 0.3
			_sparks.direction = -dir
			_sparks.color = col.lerp(Color(1, 1, 0.8), 0.5)
			_sparks.emitting = true
			_chips.global_position = to - dir * 0.3
			_chips.direction = -dir + Vector3.UP * 0.5
			_chips.color = item_color.darkened(0.2)
			_chips.emitting = true
			_stream.emitting = false
		"botany":
			# leaves and fibres drawn back toward the robot
			_stream.global_position = to
			_stream.direction = -dir
			_stream.spread = 25.0
			_stream.gravity = Vector3.ZERO
			_stream.initial_velocity_min = len / 0.6
			_stream.initial_velocity_max = len / 0.5
			_stream.color = item_color.lerp(Color("4fd84a"), 0.5)
			_stream.emitting = true
			_sparks.emitting = false
			_chips.emitting = false
		_:
			_stream.global_position = to
			_stream.direction = -dir
			_stream.spread = 8.0
			_stream.gravity = Vector3.ZERO
			_stream.initial_velocity_min = len / 0.6
			_stream.initial_velocity_max = len / 0.55
			_stream.color = Color(1.0, 0.8, 0.25)
			_stream.emitting = true
			_sparks.emitting = false
			_chips.emitting = false


func _basis_along(dir: Vector3) -> Basis:
	var up := dir
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


## The finishing flourish: the node bursts and a few glowing orbs of
## whatever it held fly into the robot.
static func burst(world: Node3D, at: Vector3, col: Color, skill: String, target: Node3D) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = 26
	p.lifetime = 0.9
	p.local_coords = false
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = -at.normalized() * (14.0 if skill == "mining" else 3.0)
	var m := BoxMesh.new()
	m.size = Vector3.ONE * (0.16 if skill == "mining" else 0.1)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	p.color = col
	world.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	for i in 4:
		var orb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.14
		s.height = 0.28
		s.radial_segments = 8
		s.rings = 4
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.albedo_color = col.lerp(Color.WHITE, 0.35)
		s.material = om
		orb.mesh = s
		world.add_child(orb)
		var start := at + Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 1.2), randf_range(-0.6, 0.6))
		orb.global_position = at
		var tw := orb.create_tween()
		tw.tween_property(orb, "global_position", start, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.05 * i)
		tw.tween_method(func(k: float):
			if is_instance_valid(target):
				orb.global_position = start.lerp(target.global_position + target.global_basis.y * 1.0, k * k)
				orb.scale = Vector3.ONE * (1.0 - k * 0.6)
		, 0.0, 1.0, 0.35)
		tw.tween_callback(func():
			Sound.play("pickup", -16.0, 0.15, "SFX", 0.02)
			orb.queue_free()
		)
