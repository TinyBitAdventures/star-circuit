extends EnemyBehavior
## Storm Kites: glide in wide circles overhead and call lightning down on you
## (a ring warns first). Every third call is a triple strike around you. The
## strikes shock you, so you take more damage for a moment.

const ORBIT := 11.0

var _calls := 0


func chase(delta: float, ppos: Vector3, _dist: float) -> void:
	var up: Vector3 = ppos.normalized()
	var b := PlanetGen.align_basis(up, e.time() * 0.45 + float(e.camp_id))
	var spot: Vector3 = e.world.gen.surface_point((up + b.z * ORBIT / e.world.gen.radius).normalized())
	e.move_toward_point(spot, e.def.speed, delta)
	e.face(spot, delta)


func attack(player: Node3D, _dist: float) -> void:
	_calls += 1
	Sound.play_3d("screech", e.global_position, -4.0, 0.1, 26.0)
	var pd: Vector3 = player.global_position.normalized()
	if _calls % 3 == 0:
		var b := PlanetGen.align_basis(pd, randf() * TAU)
		for i in 3:
			var a := float(i) / 3.0 * TAU
			var off: Vector3 = (b.x * cos(a) + b.z * sin(a)) * 3.5 / e.world.gen.radius
			SkyStrike.call_down(e.world, (pd + off).normalized(), e.damage_output() * 0.8, 2.4, 1.1 + i * 0.25)
	else:
		SkyStrike.call_down(e.world, pd, e.damage_output(), 2.4, 1.1)


func hover(t: float) -> float:
	return 6.0 + sin(t * 1.4) * 0.6


func animate(_delta: float, engaged: bool) -> bool:
	var t := e.time()
	var flap := sin(t * (3.0 if engaged else 1.6)) * 0.25
	e.pose("WingL", Vector3.ZERO, Vector3(0, flap, 0))
	e.pose("WingR", Vector3.ZERO, Vector3(0, -flap, 0))
	for i in 4:
		e.pose("Tail%d" % i, Vector3.ZERO, Vector3(sin(t * 3.0 - i * 0.8) * 0.35, 0, 0))
	var coil := e.part("Coil")
	if coil:
		coil.rotation.z = t * 4.0
	# bank into the turn
	e.pose("Torso", Vector3.ZERO, Vector3(0.15, 0, 0.35 if engaged else 0.0))
	return true
