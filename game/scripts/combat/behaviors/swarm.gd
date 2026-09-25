extends EnemyBehavior
## Cinder Mites: come in packs, scuttle straight at you, and when they reach you
## a short fuse hisses before they burst into flame. Killing one pops it too, so
## shoot them before they're close.

const FUSE := 0.45
const BURST_RADIUS := 2.6

var _fuse := -1.0


func busy(delta: float) -> bool:
	if _fuse < 0.0:
		return false
	_fuse -= delta * maxf(e.status.speed_mult(), 0.35)
	e.model().scale = Vector3.ONE * e.def.scale * (1.0 + 0.25 * absf(sin(_fuse * 40.0)))
	if _fuse < 0.0:
		_detonate()
	return true


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	# a jinking run so they're harder to pick off
	var to := ppos - e.global_position
	var side := to.cross(e.dir).normalized() * sin(e.time() * 6.0 + float(e.camp_id)) * 3.0
	if dist > 1.2:
		e.move_toward_point(ppos + (side if dist > 4.0 else Vector3.ZERO), e.def.speed, delta)
	else:
		e.face(ppos, delta)


func attack(_player: Node3D, _dist: float) -> void:
	if _fuse >= 0.0:
		return
	_fuse = FUSE
	Sound.play_3d("fuse", e.global_position, -4.0, 0.1)


func _detonate() -> void:
	var center: Vector3 = e.world.gen.surface_point(e.dir)
	var p: Node3D = e.world.player
	if p and not p.dead and p.global_position.distance_to(center) < BURST_RADIUS + 0.3:
		e.world.damage_player(e.damage_output(), e, "burn", 3.0, e.damage_output() * 0.25)
	_burst(center, BURST_RADIUS)
	e.self_destruct()


## Shot down: it still bursts, just smaller.
func on_death() -> void:
	if _fuse >= 0.0 and _fuse < FUSE:
		return
	_burst(e.world.gen.surface_point(e.dir), 1.8)


func _burst(center: Vector3, r: float) -> void:
	e.world.explosion(center + e.dir * 0.5, Color(1.0, 0.45, 0.1), r * 0.6)
	Sound.play_3d("fire_burst", center, -4.0, 0.1, 20.0)
	HazardPatch.spawn(e.world, e.dir, r * 0.8, 3.0, e.damage_output() * 0.2)


func hover(t: float) -> float:
	return 0.12 + absf(sin(t * 14.0)) * 0.06


func cleanup() -> void:
	_fuse = -1.0


func animate(_delta: float, engaged: bool) -> bool:
	var t := e.time()
	var sp := 26.0 if engaged else 10.0
	for i in 3:
		var w := sin(t * sp + i * 2.1) * 0.5
		e.pose("LegL%d" % i, Vector3.ZERO, Vector3(0, 0, w))
		e.pose("LegR%d" % i, Vector3.ZERO, Vector3(0, 0, -w))
	var glow := e.part("Glow")
	if glow:
		glow.scale = Vector3.ONE * (1.0 + 0.2 * sin(t * (30.0 if _fuse >= 0.0 else 5.0)))
	return true
