extends EnemyBehavior
## Sporelings: slow puffballs a Spore Hive breeds. They drift at you and burst
## against you in a cloud of sticky spores that slows you down.


func attack(_player: Node3D, _dist: float) -> void:
	e.swing = 1.0
	Sound.play_3d("spore_puff", e.global_position, -6.0, 0.15)
	e.world.damage_player(e.damage_output(), e, "chill", 2.5, 1.0)


func hover(t: float) -> float:
	return 1.0 + sin(t * 2.5) * 0.3


func animate(_delta: float, _engaged: bool) -> bool:
	var torso := e.part("Torso")
	if torso:
		torso.rotation.z = e.time() * 1.5
		torso.scale = Vector3.ONE * (1.0 + sin(e.swing * PI) * 0.4)
	return true
