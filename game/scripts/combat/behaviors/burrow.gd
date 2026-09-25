extends EnemyBehavior
## Dune Lurkers: dive into the sand, tunnel toward you under a dust trail, then
## burst up under your feet. Surfaced, they bite for a few seconds and can be
## hit; underground they can't.

const ERUPT_WINDUP := 0.8
const ERUPT_RADIUS := 3.0
const SURFACE_TIME := 3.5
const TUNNEL_SPEED := 1.9 # x its walk speed

var phase := "up" # up | diving | under | erupting
var _t := SURFACE_TIME
var _ring: MeshInstance3D
var _target := Vector3.ZERO
var _dust: CPUParticles3D
var _sink := 0.0 # 0 = fully up, 1 = under


func setup(enemy: Enemy) -> void:
	super.setup(enemy)
	_dust = CPUParticles3D.new()
	_dust.amount = 26
	_dust.lifetime = 0.9
	_dust.emitting = false
	_dust.local_coords = false
	_dust.direction = Vector3.UP
	_dust.spread = 50.0
	_dust.initial_velocity_min = 2.0
	_dust.initial_velocity_max = 5.0
	_dust.gravity = Vector3.ZERO
	_dust.scale_amount_min = 0.4
	_dust.scale_amount_max = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = ModelUtil.soft_dot()
	m.albedo_color = Color(0.85, 0.7, 0.45, 0.55)
	q.material = m
	_dust.mesh = q
	e.add_child(_dust)


func busy(delta: float) -> bool:
	if e.state != "chase":
		if phase != "up":
			_surface()
		return false
	match phase:
		"up":
			_t -= delta
			if _t <= 0.0 and e.target:
				phase = "diving"
				_t = 0.5
				Sound.play_3d("burrow", e.global_position, -4.0, 0.1, 20.0)
			return false
		"diving":
			_t -= delta
			_sink = clampf(1.0 - _t / 0.5, 0.0, 1.0)
			e.place_now()
			if _t <= 0.0:
				phase = "under"
				_t = 6.0
				e.set_hittable(false)
				_dust.emitting = true
			return true
		"under":
			_t -= delta
			if e.target:
				var ppos: Vector3 = e.target.global_position
				e.move_toward_point(ppos, e.def.speed * TUNNEL_SPEED, delta)
				e.place_now()
				if e.global_position.distance_to(ppos) < 3.0 or _t <= 0.0:
					_start_eruption(ppos)
			return true
		"erupting":
			_t -= delta * maxf(e.status.speed_mult(), 0.35)
			if _t <= 0.0:
				_erupt()
			return true
	return false


func _start_eruption(at: Vector3) -> void:
	phase = "erupting"
	_t = ERUPT_WINDUP
	_target = at.normalized()
	Sound.play_3d("rumble_short", at, -2.0, 0.05, 20.0)
	_ring = CombatFx.ground_ring(e.world, e.world.gen.surface_point(_target), _target, ERUPT_RADIUS, Color(1.0, 0.7, 0.2, 0.35), ERUPT_WINDUP)


func _erupt() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	e.dir = _target
	_surface()
	e.swing = 1.0
	var center: Vector3 = e.world.gen.surface_point(_target)
	e.world.explosion(center, Color(0.9, 0.72, 0.45), 1.6)
	e.world.shockwave(center, ERUPT_RADIUS, Color(1.0, 0.8, 0.4))
	Sound.play_3d("slam", center, -2.0, 0.08, 22.0)
	var player: Node3D = e.world.player
	if player and not player.dead and player.global_position.distance_to(center) < ERUPT_RADIUS + 0.3:
		e.world.damage_player(e.damage_output(), e)
		player.knockback(player.global_basis.y * 9.0)


func _surface() -> void:
	phase = "up"
	_t = SURFACE_TIME
	_sink = 0.0
	_dust.emitting = false
	e.set_hittable(true)
	if is_instance_valid(_ring):
		_ring.queue_free()
	e.place_now()


func attack(_player: Node3D, _dist: float) -> void:
	if phase != "up":
		return
	e.swing = 1.0
	Sound.play_3d("bite", e.global_position, -4.0)
	e.world.damage_player(e.damage_output() * 0.6, e)


func hover(_t2: float) -> float:
	return -3.2 * _sink if phase != "under" else -3.2


func visible_to_player() -> bool:
	return phase == "up" or phase == "diving"


func cleanup() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	if phase != "up" and is_instance_valid(e):
		phase = "up"
		_sink = 0.0
		if is_instance_valid(_dust):
			_dust.emitting = false
		e.set_hittable(true)


func animate(_delta: float, _engaged: bool) -> bool:
	var t := e.time()
	var wig := sin(t * (10.0 if phase == "under" else 4.0)) * 0.25
	e.pose("Head", Vector3.ZERO, Vector3(-sin(e.swing * PI) * 0.7, 0, wig * 0.4))
	for i in 3:
		e.pose("Seg%d" % i, Vector3.ZERO, Vector3(0, 0, sin(t * 4.0 - i * 0.9) * 0.3))
	return true
