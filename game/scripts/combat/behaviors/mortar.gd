extends EnemyBehavior
## Smelters: armoured furnaces that keep their distance and lob molten shells
## onto where you're heading. After a few shots they overheat and vent: that's
## the window, because the rest of the time their plating shrugs off most damage.

const SHOTS_PER_VENT := 3
const VENT_TIME := 3.5
const ARMOUR := 0.35 # damage taken while closed up
const EXPOSED := 1.6 # damage taken while venting

var _shots := 0
var _vent := -1.0
var _steam: Array[CPUParticles3D] = []


func setup(enemy: Enemy) -> void:
	super.setup(enemy)
	for i in 2:
		var c := e.part("ChimneyCap%d" % i)
		if c == null:
			continue
		var p := CPUParticles3D.new()
		p.amount = 24
		p.lifetime = 1.2
		p.emitting = false
		p.direction = Vector3(0, 0, 1)
		p.spread = 15.0
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 5.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 0.8)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = ModelUtil.soft_dot()
		m.albedo_color = Color(0.95, 0.95, 1.0, 0.45)
		q.material = m
		p.mesh = q
		c.add_child(p)
		_steam.append(p)


func venting() -> bool:
	return _vent >= 0.0


func busy(delta: float) -> bool:
	if _vent < 0.0:
		return false
	_vent -= delta
	if _vent < 0.0:
		for p in _steam:
			p.emitting = false
	return true


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	if dist > 24.0:
		e.move_toward_point(ppos, e.def.speed, delta)
	elif dist < 12.0:
		e.move_toward_point(e.global_position + (e.global_position - ppos), e.def.speed, delta)
	e.face(ppos, delta * 0.5)


func attack(player: Node3D, _dist: float) -> void:
	# lead the target a little: where you'll be when it lands
	var flight := 1.3
	var lead: Vector3 = player.velocity * flight * 0.7 if "velocity" in player else Vector3.ZERO
	var target: Vector3 = (player.global_position + lead).normalized()
	var muzzle: Vector3 = e.global_position + e.dir * 3.2
	MortarShell.fire(e.world, muzzle, target, e.damage_output(), 3.2, flight)
	Sound.play_3d("mortar_launch", muzzle, -2.0, 0.08, 26.0)
	e.swing = 1.0
	_shots += 1
	if _shots % SHOTS_PER_VENT == 0:
		_vent = VENT_TIME
		for p in _steam:
			p.emitting = true
		Sound.play_3d("steam_vent", e.global_position, -2.0, 0.05, 22.0)
		e.world.floating_text(e.global_position + e.dir * 4.2, "VENTING", Color("ffb86b"), true)


func on_hit(amount: float, _kind: String, _from: Vector3) -> float:
	return amount * (EXPOSED if _vent >= 0.0 else ARMOUR)


func cleanup() -> void:
	_vent = -1.0
	for p in _steam:
		if is_instance_valid(p):
			p.emitting = false


func animate(_delta: float, _engaged: bool) -> bool:
	var core := e.part("Core")
	if core:
		core.scale = Vector3.ONE * (1.35 if _vent >= 0.0 else 1.0 + 0.05 * sin(e.time() * 3.0))
	e.pose("Cannon", Vector3.ZERO, Vector3(-sin(e.swing * PI) * 0.4, 0, 0))
	e.pose("Torso", Vector3.ZERO, Vector3(0, 0, sin(e.time() * 40.0) * 0.02 if _vent >= 0.0 else 0.0))
	return true
