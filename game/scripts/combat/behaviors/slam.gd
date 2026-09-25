extends EnemyBehavior
## Brutes: raise both arms, a red ring grows on the ground, then SLAM.

const RADIUS := 4.6
const WINDUP := 0.95

var _timer := -1.0
var _telegraph: MeshInstance3D


func busy(delta: float) -> bool:
	if _timer < 0.0:
		return false
	_timer -= delta * maxf(e.status.speed_mult(), 0.35)
	if _timer < 0.0:
		_resolve()
	return true


func attack(_player: Node3D, _dist: float) -> void:
	_timer = WINDUP
	Sound.play_3d("telegraph", e.global_position, -4.0, 0.0, 20.0)
	_telegraph = CombatFx.ground_ring(e.world, e.world.gen.surface_point(e.dir), e.dir, RADIUS, Color(1, 0.1, 0.05, 0.35), WINDUP - 0.05)


func _resolve() -> void:
	e.swing = 1.0
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	var center: Vector3 = e.world.gen.surface_point(e.dir)
	e.world.shockwave(center, RADIUS, Color(1.0, 0.4, 0.2))
	Sound.play_3d("slam", center, 0.0, 0.05, 24.0)
	var player: Node3D = e.world.player
	if player and not player.dead and player.global_position.distance_to(center) < RADIUS + 0.2:
		e.world.damage_player(e.damage_output(), e)
		player.knockback((player.global_position - center).normalized() * 7.0 + player.global_basis.y * 5.0)


func cleanup() -> void:
	_timer = -1.0
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()


func raised() -> bool:
	return _timer >= 0.0
