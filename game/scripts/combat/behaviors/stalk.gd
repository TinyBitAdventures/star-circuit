extends EnemyBehavior
## Void Stalkers: all but invisible until they're close, until you hit them, or
## until you scan (Q), which lights them up and leaves them exposed. When they
## see an opening they crouch and pounce, then melt back into the dark.

const REVEAL_DIST := 6.0
const POUNCE_WINDUP := 0.5
const POUNCE_TIME := 0.35

var revealed := 0.0 # seconds left fully visible
var exposed := 0.0 # seconds left taking extra damage (after a scan)
var phase := "" # "" | crouch | leap | recover
var _t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _cloaked := false


func setup(enemy: Enemy) -> void:
	super.setup(enemy)
	_set_cloak(true)


func _set_cloak(on: bool) -> void:
	if on == _cloaked:
		return
	_cloaked = on
	e.set_ghost(on, 0.07)
	Sound.play_3d("cloak", e.global_position, -8.0, 0.1, 16.0)


func on_scanned() -> void:
	revealed = 6.0
	exposed = 6.0
	_set_cloak(false)
	e.world.floating_text(e.global_position + e.dir * 2.6, "REVEALED", Color("b06bff"), true)
	if e.state == "idle":
		e.aggro()


func busy(delta: float) -> bool:
	revealed = maxf(0.0, revealed - delta)
	exposed = maxf(0.0, exposed - delta)
	var player: Node3D = e.world.player
	var near: bool = player != null and not player.dead and e.global_position.distance_to(player.global_position) < REVEAL_DIST
	_set_cloak(revealed <= 0.0 and not near and phase == "")
	match phase:
		"crouch":
			_t -= delta * maxf(e.status.speed_mult(), 0.35)
			if _t <= 0.0:
				phase = "leap"
				_t = POUNCE_TIME
				_from = e.dir
				_to = player.global_position.normalized() if player else e.dir
				Sound.play_3d("pounce", e.global_position, -2.0, 0.08, 20.0)
			return true
		"leap":
			_t -= delta
			var k := 1.0 - clampf(_t / POUNCE_TIME, 0.0, 1.0)
			e.dir = _from.slerp(_to, k).normalized()
			e.place_now()
			e.global_position += e.dir * sin(k * PI) * 2.5
			if _t <= 0.0:
				_land()
			return true
		"recover":
			_t -= delta
			if _t <= 0.0:
				phase = ""
			return true
	return false


func _land() -> void:
	phase = "recover"
	_t = 0.8
	e.swing = 1.0
	var p: Node3D = e.world.player
	if p and not p.dead and p.global_position.distance_to(e.global_position) < 3.0:
		e.world.damage_player(e.damage_output() * 1.4, e)
		p.knockback((p.global_position - e.global_position).normalized() * 8.0 + p.global_basis.y * 4.0)
	e.world.shockwave(e.global_position, 2.0, Color(0.6, 0.4, 1.0))


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	# circle in from the side while cloaked
	var to := ppos - e.global_position
	var side := to.cross(e.dir).normalized() * (4.0 if dist > 8.0 else 0.0)
	e.move_toward_point(ppos + side, e.def.speed, delta)
	e.face(ppos, delta)


func attack(_player: Node3D, dist: float) -> void:
	if dist > 3.0:
		phase = "crouch"
		_t = POUNCE_WINDUP
		revealed = maxf(revealed, 1.5)
		return
	e.swing = 1.0
	Sound.play_3d("saw_swipe", e.global_position, -6.0)
	e.world.damage_player(e.damage_output() * 0.7, e)


func on_hit(amount: float, _kind: String, _from: Vector3) -> float:
	revealed = maxf(revealed, 2.5)
	return amount * (1.5 if exposed > 0.0 else 1.0)


func visible_to_player() -> bool:
	return not _cloaked


func cleanup() -> void:
	phase = ""
	if is_instance_valid(e):
		_set_cloak(false)


func animate(_delta: float, engaged: bool) -> bool:
	var t := e.time()
	var w := sin(t * (12.0 if engaged else 5.0)) * 0.45
	e.pose("LegFL", Vector3.ZERO, Vector3(w, 0, 0))
	e.pose("LegBR", Vector3.ZERO, Vector3(w, 0, 0))
	e.pose("LegFR", Vector3.ZERO, Vector3(-w, 0, 0))
	e.pose("LegBL", Vector3.ZERO, Vector3(-w, 0, 0))
	var crouch := 0.35 if phase == "crouch" else (-0.3 if phase == "leap" else 0.0)
	e.pose("Torso", Vector3(0, 0, -crouch * 0.6), Vector3(crouch, 0, 0))
	e.pose("Tail", Vector3.ZERO, Vector3(sin(t * 3.0) * 0.3, 0, 0))
	return true
