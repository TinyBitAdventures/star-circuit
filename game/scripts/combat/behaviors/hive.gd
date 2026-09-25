extends EnemyBehavior
## Spore Hives: rooted in place, breeding Sporelings (up to four at a time) and
## puffing out a sticky spore cloud that slows anything close. Kill the hive and
## its brood withers. Fire does double damage.

const CLOUD_RADIUS := 5.5
const CLOUD_WINDUP := 1.0
const MAX_BROOD := 4

var brood: Array[Enemy] = []
var _breed := 1.5
var _cloud := -1.0
var _ring: MeshInstance3D


func busy(delta: float) -> bool:
	if e.state == "chase":
		brood = brood.filter(func(b): return is_instance_valid(b) and b.is_alive())
		_breed -= delta
		if _breed <= 0.0 and brood.size() < MAX_BROOD:
			_breed = 4.0
			_spawn_sporeling()
	if _cloud >= 0.0:
		_cloud -= delta
		if _cloud < 0.0:
			_puff()
	return false


func _spawn_sporeling() -> void:
	var b := PlanetGen.align_basis(e.dir, randf() * TAU)
	var d: Vector3 = (e.dir + b.z * 2.5 / e.world.gen.radius).normalized()
	var s: Enemy = e.world._spawn_enemy("sporeling", e.level, d, -1)
	s.nid = "" # brood are local and short-lived
	s.aggro()
	brood.append(s)
	Sound.play_3d("spore_puff", e.global_position, -6.0, 0.1, 18.0)


func chase(delta: float, ppos: Vector3, _dist: float) -> void:
	e.face(ppos, delta * 0.3)


func attack(_player: Node3D, dist: float) -> void:
	if dist > CLOUD_RADIUS + 4.0 or _cloud >= 0.0:
		return
	_cloud = CLOUD_WINDUP
	Sound.play_3d("hive_pulse", e.global_position, -2.0, 0.05, 22.0)
	_ring = CombatFx.ground_ring(e.world, e.world.gen.surface_point(e.dir), e.dir, CLOUD_RADIUS, Color(0.7, 1.0, 0.35, 0.3), CLOUD_WINDUP)


func _puff() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	var center: Vector3 = e.world.gen.surface_point(e.dir)
	e.world.shockwave(center, CLOUD_RADIUS, Color(0.7, 1.0, 0.4))
	Sound.play_3d("spore_puff", center, 0.0, 0.05, 24.0)
	var p: Node3D = e.world.player
	if p and not p.dead and p.global_position.distance_to(center) < CLOUD_RADIUS + 0.3:
		e.world.damage_player(e.damage_output() * 0.5, e, "chill", 3.5, 2.0)


func on_death() -> void:
	for b in brood:
		if is_instance_valid(b) and b.is_alive():
			b.self_destruct()
	brood.clear()


func cleanup() -> void:
	_cloud = -1.0
	if is_instance_valid(_ring):
		_ring.queue_free()


func animate(_delta: float, _engaged: bool) -> bool:
	var t := e.time()
	var breathe := 1.0 + sin(t * 2.2) * 0.05 + (0.12 if _cloud >= 0.0 else 0.0)
	var torso := e.part("Torso")
	if torso:
		torso.scale = Vector3(breathe, breathe, 1.0 + (breathe - 1.0) * 1.5)
	return true
