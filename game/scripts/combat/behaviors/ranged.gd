extends EnemyBehavior
## Sentinels: keep their distance and lob slow, dodgeable bolts.


func chase(delta: float, ppos: Vector3, dist: float) -> void:
	var want: float = e.def.range * 0.85
	if dist > want:
		e.move_toward_point(ppos, e.def.speed, delta)
	elif dist < 9.0:
		e.move_toward_point(e.global_position + (e.global_position - ppos), e.def.speed * 0.8, delta)
	e.face(ppos, delta)


func attack(player: Node3D, _dist: float) -> void:
	var muzzle: Vector3 = e.global_position + e.dir * 1.8 + e.heading * 0.8
	Sound.play_3d("sentinel_shot", muzzle, -6.0)
	e.world.spawn_enemy_bolt(muzzle, player.global_position + player.global_basis.y * 1.0, e.damage_output(), Color("ff3d9a"))


func hover(t: float) -> float:
	return 1.2 + sin(t * 2.0) * 0.3 if e.type == "sentinel" else 0.0
