extends EnemyBehavior
## Thornbacks: circle at mid range, paint a lane on the ground, then charge down
## it. A charge that misses leaves it stunned and taking extra damage.

const WINDUP := 1.0
const CHARGE_SPEED := 26.0
const CHARGE_LEN := 30.0
const LANE_W := 3.2
const STUN := 2.2

var phase := "" # "" | windup | charging | stunned
var _t := 0.0
var _lane_dir := Vector3.ZERO # tangent at the start
var _travelled := 0.0
var _hit := false
var _lane: MeshInstance3D


func busy(delta: float) -> bool:
	match phase:
		"windup":
			_t -= delta * maxf(e.status.speed_mult(), 0.35)
			e.face(e.global_position + _lane_dir, delta)
			if _t <= 0.0:
				phase = "charging"
				_travelled = 0.0
				_hit = false
				Sound.play_3d("charge_roar", e.global_position, -2.0, 0.05, 24.0)
			return true
		"charging":
			var step := CHARGE_SPEED * delta * maxf(e.status.speed_mult(), 0.35)
			var d0 := e.dir
			e.heading = (_lane_dir - e.dir * _lane_dir.dot(e.dir)).normalized()
			e.dir = (e.dir + e.heading * step / e.world.gen.radius).normalized()
			_lane_dir = e.heading
			_travelled += step
			e.place_now()
			var player: Node3D = e.world.player
			if not _hit and player and not player.dead and e.global_position.distance_to(player.global_position) < 2.6:
				_hit = true
				e.world.damage_player(e.damage_output(), e)
				player.knockback(e.heading * 16.0 + player.global_basis.y * 6.0)
				e.world.shake_near(e.global_position, 0.5)
			# the lane ends, or it runs into a slope it can't climb
			var climb: float = e.world.gen.surface_radius(e.dir) - e.world.gen.surface_radius(d0)
			if _travelled >= CHARGE_LEN or climb > step * 0.9:
				_end_charge()
			return true
		"stunned":
			_t -= delta
			if _t <= 0.0:
				phase = ""
			return true
	return false


func _end_charge() -> void:
	if is_instance_valid(_lane):
		_lane.queue_free()
	if _hit:
		phase = ""
		return
	# missed: dazed, horn stuck in the dirt
	phase = "stunned"
	_t = STUN
	e.world.floating_text(e.global_position + e.dir * 3.0, "STUNNED", Color("ffd23f"), true)
	e.world.shockwave(e.global_position, 2.5, Color(0.8, 0.9, 0.4))
	Sound.play_3d("slam", e.global_position, -6.0, 0.1, 18.0)


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	# hold at charging distance, sidling round the player
	if dist > 20.0:
		e.move_toward_point(ppos, e.def.speed, delta)
	elif dist < 9.0:
		e.move_toward_point(e.global_position + (e.global_position - ppos), e.def.speed, delta)
	else:
		var to := (ppos - e.global_position)
		var side := to.cross(e.dir).normalized()
		e.move_toward_point(e.global_position + side * 4.0, e.def.speed * 0.6, delta)
	e.face(ppos, delta)


func attack(player: Node3D, dist: float) -> void:
	if dist < 6.0:
		# too close to charge: a quick horn toss
		e.swing = 1.0
		Sound.play_3d("saw_swipe", e.global_position, -6.0)
		e.world.damage_player(e.damage_output() * 0.5, e)
		return
	var to: Vector3 = player.global_position - e.global_position
	_lane_dir = (to - e.dir * to.dot(e.dir)).normalized()
	phase = "windup"
	_t = WINDUP
	Sound.play_3d("telegraph", e.global_position, -4.0, 0.0, 22.0)
	_lane = CombatFx.ground_lane(e.world, e.dir, _lane_dir, CHARGE_LEN, LANE_W, Color(1.0, 0.85, 0.1, 0.35), WINDUP)


func on_hit(amount: float, _kind: String, _from: Vector3) -> float:
	return amount * (1.6 if phase == "stunned" else 1.0)


func cleanup() -> void:
	phase = ""
	if is_instance_valid(_lane):
		_lane.queue_free()


func animate(_delta: float, engaged: bool) -> bool:
	var t := e.time()
	var gait := 7.0 if phase == "" else (18.0 if phase == "charging" else 0.0)
	var amp := 0.5 if (engaged or phase == "charging") else 0.25
	var w := sin(t * gait) * amp
	e.pose("LegFL", Vector3.ZERO, Vector3(w, 0, 0))
	e.pose("LegBR", Vector3.ZERO, Vector3(w, 0, 0))
	e.pose("LegFR", Vector3.ZERO, Vector3(-w, 0, 0))
	e.pose("LegBL", Vector3.ZERO, Vector3(-w, 0, 0))
	var head_dip := 0.0
	if phase == "windup":
		head_dip = 0.35 + sin(t * 30.0) * 0.05
	elif phase == "charging":
		head_dip = 0.4
	elif phase == "stunned":
		head_dip = 0.7 + sin(t * 3.0) * 0.1
	e.pose("Head", Vector3.ZERO, Vector3(head_dip - sin(e.swing * PI) * 0.6, 0, 0))
	e.pose("Torso", Vector3.ZERO, Vector3(0, 0, sin(t * 2.5) * 0.25 if phase == "stunned" else 0.0))
	return true
