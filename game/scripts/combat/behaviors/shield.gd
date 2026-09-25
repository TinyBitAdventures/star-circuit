extends EnemyBehavior
## Frost Wardens: a curved shield soaks everything from the front, so flank it
## (they turn slowly), punch through with Rail, or melt it with fire. They fire
## chilling ice bolts, and now and then pulse a frost nova around themselves.

const FRONT_DOT := 0.35 # cos of the half-angle the shield covers (about 70 degrees)
const NOVA_RADIUS := 5.5
const NOVA_WINDUP := 0.9

var _shots := 0
var _nova_t := -1.0
var _ring: MeshInstance3D


func setup(enemy: Enemy) -> void:
	super.setup(enemy)
	# the shield is a see-through energy dish, bright at the rim
	var sh := e.part("Shield") as MeshInstance3D
	if sh:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.35, 0.75, 1.0, 0.22)
		sh.material_override = m
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func busy(delta: float) -> bool:
	if _nova_t < 0.0:
		return false
	_nova_t -= delta * maxf(e.status.speed_mult(), 0.35)
	if _nova_t < 0.0:
		_nova()
	return true


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	var want: float = e.def.range * 0.7
	if dist > want:
		e.move_toward_point(ppos, e.def.speed, delta)
	# slow to turn: that's the opening
	e.face(ppos, delta * 0.22)


func attack(player: Node3D, dist: float) -> void:
	_shots += 1
	if _shots % 4 == 0 and dist < NOVA_RADIUS + 3.0:
		_nova_t = NOVA_WINDUP
		Sound.play_3d("telegraph", e.global_position, -4.0, 0.1, 20.0)
		_ring = CombatFx.ground_ring(e.world, e.world.gen.surface_point(e.dir), e.dir, NOVA_RADIUS, Color(0.5, 0.85, 1.0, 0.35), NOVA_WINDUP)
		return
	var muzzle: Vector3 = e.global_position + e.dir * 2.4 + e.heading * 1.0
	Sound.play_3d("ice_shot", muzzle, -5.0)
	e.world.spawn_enemy_bolt(muzzle, player.global_position + player.global_basis.y * 1.0, e.damage_output(), Color("7fe3ff"), "chill", 3.0, 1.0)


func _nova() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	var center: Vector3 = e.world.gen.surface_point(e.dir)
	e.world.shockwave(center, NOVA_RADIUS, Color(0.6, 0.9, 1.0))
	Sound.play_3d("freeze", center, -2.0, 0.05, 22.0)
	var player: Node3D = e.world.player
	if player and not player.dead and player.global_position.distance_to(center) < NOVA_RADIUS + 0.3:
		e.world.damage_player(e.damage_output() * 0.6, e, "chill", 4.0, 2.0)


## Blocks shots from the front, unless they pierce (Rail) or burn through (fire).
func on_hit(amount: float, kind: String, from: Vector3) -> float:
	if from == Vector3.INF or kind == "pierce" or kind == "fire":
		return amount
	var to: Vector3 = from - e.global_position
	to -= e.dir * to.dot(e.dir)
	if to.length() < 0.01:
		return amount
	if to.normalized().dot(e.heading) > FRONT_DOT:
		Sound.play_3d("shield_block", e.global_position, -6.0, 0.1)
		return 0.0
	return amount * 1.25 # caught from the side or behind


func cleanup() -> void:
	_nova_t = -1.0
	if is_instance_valid(_ring):
		_ring.queue_free()


func animate(_delta: float, engaged: bool) -> bool:
	var t := e.time()
	var walk := sin(t * 5.0) * (0.3 if engaged else 0.12)
	e.pose("LegL", Vector3.ZERO, Vector3(walk, 0, 0))
	e.pose("LegR", Vector3.ZERO, Vector3(-walk, 0, 0))
	var brace := 0.4 if _nova_t >= 0.0 else 0.0
	e.pose("ArmL", Vector3.ZERO, Vector3(-0.2 - brace, 0, 0))
	e.pose("Torso", Vector3.ZERO, Vector3(-sin(e.swing * PI) * 0.15, 0, 0))
	return true
