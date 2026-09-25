extends EnemyBehavior
## Refractors: floating crystal clusters. Every few seconds their facets flare
## and, while they glow, anything you shoot at them is thrown back at you. They
## blink to a new spot now and then and fire fans of crystal shards.

const GLOW_EVERY := 5.0
const GLOW_TIME := 2.2
const BLINK_EVERY := 7.0

var _cycle := 2.5
var _glow := 0.0
var _blink := BLINK_EVERY
var _reflect_cd := 0.0


func glowing() -> bool:
	return _glow > 0.0


func busy(delta: float) -> bool:
	_reflect_cd = maxf(0.0, _reflect_cd - delta)
	if _glow > 0.0:
		_glow -= delta
	elif e.state == "chase":
		_cycle -= delta
		if _cycle <= 0.0:
			_cycle = GLOW_EVERY
			_glow = GLOW_TIME
			Sound.play_3d("reflect", e.global_position, -6.0, 0.05, 20.0)
	if e.state == "chase":
		_blink -= delta
		if _blink <= 0.0:
			_blink = BLINK_EVERY * randf_range(0.8, 1.2)
			_do_blink()
	return false


func _do_blink() -> void:
	var player: Node3D = e.world.player
	if player == null or player.dead:
		return
	var pd: Vector3 = player.global_position.normalized()
	var b := PlanetGen.align_basis(pd, randf() * TAU)
	var to: Vector3 = (pd + b.z * randf_range(9.0, 15.0) / e.world.gen.radius).normalized()
	e.world.explosion(e.global_position, Color(0.8, 0.75, 1.0), 0.8)
	Sound.play_3d("blink", e.global_position, -4.0, 0.05, 22.0)
	e.dir = to
	e.place_now()
	e.world.explosion(e.global_position, Color(0.8, 0.75, 1.0), 0.8)


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	if dist > 18.0:
		e.move_toward_point(ppos, e.def.speed, delta)
	elif dist < 9.0:
		e.move_toward_point(e.global_position + (e.global_position - ppos), e.def.speed, delta)
	e.face(ppos, delta)


func attack(player: Node3D, _dist: float) -> void:
	var muzzle: Vector3 = e.global_position + e.dir * 0.4
	var target: Vector3 = player.global_position + player.global_basis.y * 1.0
	var side: Vector3 = (target - muzzle).cross(e.dir).normalized()
	Sound.play_3d("crystal_shot", muzzle, -5.0, 0.08)
	for i in 3:
		e.world.spawn_enemy_bolt(muzzle, target + side * (i - 1) * 2.2, e.damage_output() * 0.6, Color("c9b8ff"))


## While the facets glow, shots come straight back.
func on_hit(amount: float, _kind: String, from: Vector3) -> float:
	if _glow <= 0.0:
		return amount
	if _reflect_cd <= 0.0 and from != Vector3.INF:
		_reflect_cd = 0.25
		e.world.spawn_enemy_bolt(e.global_position, from + e.dir * 1.0, minf(amount * 0.5, e.damage_output() * 1.5), Color("ffffff"))
		e.world.floating_text(e.global_position + e.dir * 2.6, "REFLECTED", Color("c9b8ff"), false)
		Sound.play_3d("reflect", e.global_position, -8.0, 0.1)
	return 0.0


func hover(t: float) -> float:
	return 2.2 + sin(t * 1.7) * 0.35


func cleanup() -> void:
	_glow = 0.0


func animate(_delta: float, _engaged: bool) -> bool:
	var t := e.time()
	var torso := e.part("Torso")
	if torso:
		torso.rotation.z = t * (2.5 if _glow > 0.0 else 0.6)
	var flare := 1.0 + (0.35 if _glow > 0.0 else 0.0) + 0.05 * sin(t * 6.0)
	for i in 6:
		var p := e.part("Prism%d" % i)
		if p:
			p.scale = Vector3.ONE * flare
	return true
