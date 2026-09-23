class_name Weather
extends Node3D
## Per-biome weather around the player: snow, dust, ash, spores, rain,
## glitter. Storms roll in on a cycle, thicken the fog and raise the wind.

const STORM_PERIOD := 260.0

var world: Node3D
var kind := ""
var storm := 0.0 # 0..1
var _light: CPUParticles3D
var _heavy: CPUParticles3D
var _phase := 0.0
var _was_storm := false
var _base_fog := 0.0

const KINDS := {
	"frost": {"name": "Blizzard", "color": Color(1, 1, 1, 0.9), "size": 0.14, "fall": 3.0, "drift": 2.0, "streak": false, "hazard": 0.6},
	"dune": {"name": "Sandstorm", "color": Color(0.95, 0.78, 0.5, 0.6), "size": 0.08, "fall": 0.4, "drift": 12.0, "streak": false, "hazard": 0.8},
	"ember": {"name": "Ash storm", "color": Color(1.0, 0.45, 0.15, 1.0), "size": 0.09, "fall": -0.6, "drift": 1.5, "streak": false, "hazard": 1.0, "glow": true},
	"bloom": {"name": "Spore bloom", "color": Color(0.8, 1.0, 0.6, 0.9), "size": 0.12, "fall": -0.3, "drift": 1.0, "streak": false, "hazard": 0.0, "glow": true},
	"verdant": {"name": "Rain shower", "color": Color(0.7, 0.8, 1.0, 0.55), "size": 0.05, "fall": 22.0, "drift": 1.0, "streak": true, "hazard": 0.0},
	"prism": {"name": "Crystal squall", "color": Color(0.9, 0.7, 1.0, 0.9), "size": 0.07, "fall": 1.2, "drift": 3.0, "streak": false, "hazard": 0.3, "glow": true},
}


func setup(w: Node3D, biome: String, seed_: int) -> void:
	world = w
	kind = biome
	_phase = float(seed_ % 1000) / 1000.0 * STORM_PERIOD
	_base_fog = w.env.fog_density
	var k: Dictionary = KINDS.get(kind, KINDS.verdant)
	_light = _emitter(k, 160)
	_heavy = _emitter(k, 900)
	_heavy.emitting = false
	if kind == "verdant":
		_light.emitting = false # rain only during showers


func _emitter(k: Dictionary, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(40, 16, 40)
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.initial_velocity_min = absf(k.fall) * 0.8
	p.initial_velocity_max = absf(k.fall) * 1.2 + 0.2
	p.gravity = Vector3.ZERO
	var mesh := QuadMesh.new()
	mesh.size = Vector2(k.size, k.size * (8.0 if k.streak else 1.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if k.streak else BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = k.color * (Color(2, 2, 2, 1) if k.get("glow", false) else Color.WHITE)
	if not k.streak:
		m.albedo_texture = ModelUtil.soft_dot()
	m.disable_fog = true
	mesh.material = m
	p.mesh = mesh
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	add_child(p)
	return p


func _process(delta: float) -> void:
	var player: Node3D = world.player
	if player == null:
		return
	var up := player.global_position.normalized()
	global_transform = Transform3D(PlanetGen.align_basis(up), player.global_position + up * 6.0)
	var k: Dictionary = KINDS.get(kind, KINDS.verdant)
	# particles fall along local "down" and drift sideways with the wind
	var t := Game.play_time + _phase
	var wind: Vector3 = PlanetGen.align_basis(up).x.rotated(up, sin(t * 0.05) * 2.0) * k.drift
	var fall: Vector3 = -up * float(k.fall)
	for p in [_light, _heavy]:
		p.gravity = (fall + wind) * 0.35
		p.direction = (global_basis.inverse() * (fall + wind)).normalized()
	# storm cycle: ~20% of the time
	var s := sin(t * TAU / STORM_PERIOD)
	var target := smoothstep(0.55, 0.8, s)
	storm = move_toward(storm, target, delta * 0.15)
	var is_storm := storm > 0.4
	_heavy.emitting = is_storm
	if kind == "verdant":
		_light.emitting = storm > 0.1
	world.env.fog_density = _base_fog * (1.0 + storm * 3.0)
	Sound.loop_set("ambience", lerpf(-12.0, -2.0, storm) if kind != "verdant" else lerpf(-14.0, -6.0, storm), 1.0 + storm * 0.15)
	if is_storm != _was_storm:
		_was_storm = is_storm
		if is_storm:
			var msg: String = k.name + " rolling in" + ("  -  hazard: energy drain" if k.hazard > 0.0 else "")
			Game.notify.emit(msg, Color("ffb86b") if k.hazard > 0.0 else Color("9bd1ff"))
		else:
			Game.notify.emit(k.name + " passing", Color("9bd1ff"))
	if is_storm and k.hazard > 0.0 and not (kind == "ember" and Game.has_upgrade("lava_plating")):
		Game.drain_energy(k.hazard * delta)
