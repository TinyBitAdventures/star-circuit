extends EnemyBehavior
## Titans: world bosses. Each kind cycles through its attacks, then kneels with
## its core exposed for a few seconds: its armour turns aside most damage the
## rest of the time. At half health it enrages (faster, harder) and calls in
## the world's signature enemies to help.
##   colossus: stomps, boulder barrages, ground-splitting lanes
##   wyrm: burrows (can't be hit), erupts under you, spits burning shells
##   sentinel: floats high, calls lightning storms, sprays chilling bolts

const ARMOUR := 0.35
const EXPOSED := 1.8
const EXPOSE_TIME := 3.5

const CYCLES := {
	"colossus": ["stomp", "barrage", "lanes", "expose"],
	"wyrm": ["dive", "spit", "dive", "expose"],
	"sentinel": ["storm", "fan", "storm", "expose"],
}

var kind := "colossus"
var enraged := false
var exposed := 0.0
var _step := 0
var _hold := 0.0 # seconds the current attack roots it in place
var _under := 0.0 # wyrm: seconds left tunnelling
var _sink := 0.0


func setup(enemy: Enemy) -> void:
	super.setup(enemy)
	kind = e.def.get("titan", "colossus")


func busy(delta: float) -> bool:
	exposed = maxf(0.0, exposed - delta)
	if not enraged and e.hp <= e.max_hp * 0.5 and e.state == "chase":
		_enrage()
	if _under > 0.0:
		_under -= delta
		_tunnel(delta)
		return true
	if _hold > 0.0:
		_hold -= delta
		_sink = move_toward(_sink, 0.0, delta * 2.0)
		return true
	_sink = move_toward(_sink, 0.0, delta * 2.0)
	return false


func _enrage() -> void:
	enraged = true
	e.world.floating_text(e.global_position + e.dir * 12.0, "ENRAGED", Color("ff4d4d"), true)
	Sound.play_3d("charge_roar", e.global_position, 2.0, 0.0, 60.0)
	e.world.shake_near(e.global_position, 1.0)
	var foe: String = Db.BIOME_FOES.get(e.world.planet.biome, "scrapper")
	if foe == "hive":
		foe = "sporeling"
	for i in 2:
		var b := PlanetGen.align_basis(e.dir, float(i) * PI + 0.7)
		var d: Vector3 = (e.dir + b.z * 12.0 / e.world.gen.radius).normalized()
		var add: Enemy = e.world._spawn_enemy(foe, e.level - 2, d, -1)
		add.nid = ""
		add.aggro()


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	if kind == "sentinel":
		var up: Vector3 = ppos.normalized()
		var b := PlanetGen.align_basis(up, e.time() * 0.25)
		var spot: Vector3 = e.world.gen.surface_point((up + b.z * 16.0 / e.world.gen.radius).normalized())
		e.move_toward_point(spot, e.def.speed, delta)
		e.face(ppos, delta)
		return
	if dist > 14.0:
		e.move_toward_point(ppos, e.def.speed, delta)
	e.face(ppos, delta * 0.6)


func attack(player: Node3D, _dist: float) -> void:
	var cycle: Array = CYCLES[kind]
	var what: String = cycle[_step % cycle.size()]
	_step += 1
	var pd: Vector3 = player.global_position.normalized()
	var dmg := e.damage_output()
	var w: Node3D = e.world
	match what:
		"stomp":
			_hold = 1.8
			e.swing = 1.0
			TelegraphBlast.ring(w, e.dir, 9.0, 1.2, dmg)
			if enraged:
				TelegraphBlast.ring(w, e.dir, 17.0, 1.9, dmg * 0.8)
			Sound.play_3d("telegraph", e.global_position, 0.0, 0.0, 50.0)
		"barrage":
			_hold = 1.2
			for i in (7 if enraged else 5):
				var b := PlanetGen.align_basis(pd, randf() * TAU)
				var off: Vector3 = b.z * (0.0 if i == 0 else randf_range(3.0, 8.0)) / w.gen.radius
				MortarShell.fire(w, e.global_position + e.dir * 10.0, (pd + off).normalized(), dmg * 0.6, 3.0, 1.3 + i * 0.12)
			Sound.play_3d("mortar_launch", e.global_position, 0.0, 0.05, 50.0)
		"lanes":
			_hold = 1.9
			var to: Vector3 = player.global_position - e.global_position
			var fwd: Vector3 = (to - e.dir * to.dot(e.dir)).normalized()
			var spread := [-0.45, 0.0, 0.45] if not enraged else [-0.7, -0.35, 0.0, 0.35, 0.7]
			for a in spread:
				TelegraphBlast.lane(w, e.dir, fwd.rotated(e.dir, a), 42.0, 3.6, 1.4, dmg * 0.9)
			Sound.play_3d("telegraph", e.global_position, 0.0, 0.0, 50.0)
		"dive":
			_under = 2.6
			e.set_hittable(false)
			Sound.play_3d("burrow", e.global_position, 2.0, 0.05, 50.0)
		"spit":
			_hold = 1.4
			for i in (6 if enraged else 4):
				var b2 := PlanetGen.align_basis(pd, randf() * TAU)
				MortarShell.fire(w, e.global_position + e.dir * 6.0, (pd + b2.z * randf_range(0.0, 6.0) / w.gen.radius).normalized(), dmg * 0.6, 3.2, 1.2 + i * 0.15)
			Sound.play_3d("fire_burst", e.global_position, 0.0, 0.05, 50.0)
		"storm":
			_hold = 1.0
			var n := 8 if enraged else 5
			for i in n:
				var off2 := Vector3.ZERO
				if i > 0:
					var b3 := PlanetGen.align_basis(pd, float(i) / (n - 1) * TAU)
					off2 = b3.z * 5.5 / w.gen.radius
				SkyStrike.call_down(w, (pd + off2).normalized(), dmg * 0.8, 2.6, 1.1 + i * 0.12)
			Sound.play_3d("screech", e.global_position, 2.0, 0.0, 60.0)
		"fan":
			_hold = 1.0
			var muzzle: Vector3 = e.global_position
			var target: Vector3 = player.global_position + player.global_basis.y
			var side: Vector3 = (target - muzzle).cross(e.dir).normalized()
			for i in 7:
				w.spawn_enemy_bolt(muzzle, target + side * (i - 3) * 2.5, dmg * 0.5, Color("7fe3ff"), "chill", 3.0, 1.0)
			Sound.play_3d("ice_shot", muzzle, 0.0, 0.0, 50.0)
		"expose":
			_hold = EXPOSE_TIME
			exposed = EXPOSE_TIME
			_sink = 1.0
			w.floating_text(e.global_position + e.dir * 10.0, "CORE EXPOSED", Color("ffd23f"), true)
			Sound.play_3d("steam_vent", e.global_position, 2.0, 0.0, 50.0)


## Wyrm: tunnel toward the player, then erupt under them.
func _tunnel(delta: float) -> void:
	var p: Node3D = e.world.player
	if p and not p.dead:
		e.move_toward_point(p.global_position, e.def.speed * 3.5, delta)
	e.place_now()
	if _under <= 0.0:
		var at: Vector3 = p.global_position.normalized() if p else e.dir
		var dmg := e.damage_output()
		TelegraphBlast.ring(e.world, at, 6.5, 0.9, dmg * 1.2, Color(1.0, 0.45, 0.1), "burn")
		if enraged:
			for i in 2:
				var b := PlanetGen.align_basis(at, float(i) * PI + randf())
				TelegraphBlast.ring(e.world, (at + b.z * 9.0 / e.world.gen.radius).normalized(), 5.0, 1.2, dmg, Color(1.0, 0.45, 0.1), "burn")
		HazardPatch.spawn(e.world, at, 4.0, 5.0, dmg * 0.25)
		e.dir = at
		_hold = 1.4
		e.set_hittable(true)
		e.world.explosion(e.world.gen.surface_point(at), Color(1.0, 0.5, 0.15), 3.0)


func on_hit(amount: float, _kind: String, _from: Vector3) -> float:
	return amount * (EXPOSED if exposed > 0.0 else ARMOUR)


func hover(t: float) -> float:
	if kind == "sentinel":
		return lerpf(9.0 + sin(t * 0.8) * 0.8, 2.5, _sink)
	if kind == "wyrm":
		return -12.0 if _under > 0.0 else -1.5 * _sink
	return -1.2 * _sink


func visible_to_player() -> bool:
	return _under <= 0.0


func cleanup() -> void:
	_under = 0.0
	_hold = 0.0
	exposed = 0.0
	if is_instance_valid(e):
		e.set_hittable(e.state != "dead")


func animate(_delta: float, engaged: bool) -> bool:
	var t := e.time()
	var core := e.part("Core")
	if core:
		core.scale = Vector3.ONE * (1.5 + 0.2 * sin(t * 10.0) if exposed > 0.0 else 1.0 + 0.06 * sin(t * 2.0))
	match kind:
		"colossus":
			var walk := sin(t * 2.5) * (0.35 if engaged and _hold <= 0.0 else 0.05)
			var raise := 2.2 if _hold > 0.0 and exposed <= 0.0 else 0.0
			e.pose("ArmL", Vector3.ZERO, Vector3(-walk * 0.5 - raise + sin(e.swing * PI) * 2.0, 0, 0))
			e.pose("ArmR", Vector3.ZERO, Vector3(walk * 0.5 - raise + sin(e.swing * PI) * 2.0, 0, 0))
			e.pose("LegL", Vector3.ZERO, Vector3(walk, 0, 0))
			e.pose("LegR", Vector3.ZERO, Vector3(-walk, 0, 0))
			e.pose("Torso", Vector3.ZERO, Vector3(0.45 if exposed > 0.0 else 0.0, 0, 0))
		"wyrm":
			for i in 5:
				e.pose("Seg%d" % i, Vector3.ZERO, Vector3(0, 0, sin(t * 2.0 - i * 0.8) * 0.25))
			e.pose("Head", Vector3.ZERO, Vector3(-0.5 if exposed > 0.0 else sin(t) * 0.1, 0, 0))
		"sentinel":
			var r1 := e.part("Ring1")
			if r1:
				r1.rotation.z = t * (1.6 if enraged else 0.8)
			var r2 := e.part("Ring2")
			if r2:
				r2.rotation.y = -t * (1.2 if enraged else 0.6)
	return true
