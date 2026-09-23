class_name AsteroidBelt
extends Node3D
## A star system's asteroid belt: minable rocks (scattered + dense clusters),
## a haze of tiny decorative rocks, and sometimes a comet.

var world: Node3D
var data: Dictionary
var comet: Asteroid
var _comet_tail: CPUParticles3D
var _comet_angle := 0.0
var _comet_orbit := 0.0


func build(w: Node3D, belt: Dictionary) -> void:
	world = w
	data = belt
	rotation.x = belt.tilt
	var rng := RandomNumberGenerator.new()
	rng.seed = int(belt.seed)
	var r: float = belt.radius
	var width: float = belt.width
	# minable rocks: 3 dense clusters + scattered
	var clusters := []
	for i in 3:
		clusters.append(rng.randf() * TAU)
	for i in int(belt.count):
		var a: float
		if i % 3 != 0:
			a = clusters[i % 3] + rng.randf_range(-0.18, 0.18)
		else:
			a = rng.randf() * TAU
		var rr := r + rng.randf_range(-width, width) * 0.5
		var pos := Vector3(cos(a) * rr, rng.randf_range(-width, width) * 0.12, sin(a) * rr)
		var t := _pick(rng, belt.mix)
		var size := rng.randf_range(2.5, 9.0) * (1.25 if t == "metallic" else 1.0)
		world.spawn_asteroid(t, size, to_global(pos), 0)
	# decorative dust rocks (non-minable) for density
	var xforms := []
	for i in 1400:
		var a2 := rng.randf() * TAU
		var rr2 := r + rng.randf_range(-width, width) * 0.7
		var s := rng.randf_range(0.3, 1.6)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)).scaled(Vector3.ONE * s)
		xforms.append(Transform3D(b, Vector3(cos(a2) * rr2, rng.randf_range(-width, width) * 0.15, sin(a2) * rr2)))
	ModelUtil.multimesh(self, "res://assets/models/prop_boulder.glb", xforms, "", Color.WHITE, false)
	if belt.comet:
		_make_comet(rng)


func _pick(rng: RandomNumberGenerator, mix: Dictionary) -> String:
	var total := 0
	for k in mix:
		total += int(mix[k])
	var roll := rng.randi() % maxi(1, total)
	for k in mix:
		roll -= int(mix[k])
		if roll < 0:
			return k
	return "rocky"


func _make_comet(rng: RandomNumberGenerator) -> void:
	_comet_orbit = data.radius * rng.randf_range(1.4, 1.9)
	_comet_angle = rng.randf() * TAU
	comet = world.spawn_asteroid("comet", rng.randf_range(9.0, 12.0), _comet_pos(), 0)
	comet.spin *= 0.3
	_comet_tail = CPUParticles3D.new()
	_comet_tail.amount = 260
	_comet_tail.lifetime = 5.0
	_comet_tail.local_coords = false
	_comet_tail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_comet_tail.emission_sphere_radius = 6.0
	_comet_tail.spread = 12.0
	_comet_tail.initial_velocity_min = 20.0
	_comet_tail.initial_velocity_max = 40.0
	_comet_tail.gravity = Vector3.ZERO
	_comet_tail.scale_amount_min = 2.0
	_comet_tail.scale_amount_max = 6.0
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = ModelUtil.soft_dot()
	q.material = m
	_comet_tail.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 0.95, 1.0, 0.9))
	g.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
	_comet_tail.color_ramp = g
	world.add_child(_comet_tail)
	var label := Label3D.new()
	label.text = "Comet"
	label.font = UiKit.body_font()
	label.font_size = 26
	label.outline_size = 8
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = CombatFx.hdr(Color("9be8ff"), 1.5)
	label.position.y = 16.0
	comet.add_child(label)


func _comet_pos() -> Vector3:
	return Vector3(cos(_comet_angle) * _comet_orbit, sin(_comet_angle * 2.0) * 60.0, sin(_comet_angle) * _comet_orbit * 0.7)


func _process(delta: float) -> void:
	if is_instance_valid(comet):
		_comet_angle += delta * 0.004
		comet.position = _comet_pos()
		# the tail always streams away from the star
		_comet_tail.global_position = comet.global_position
		_comet_tail.direction = comet.global_position.normalized()
		_comet_tail.emitting = true
	elif _comet_tail:
		_comet_tail.emitting = false
