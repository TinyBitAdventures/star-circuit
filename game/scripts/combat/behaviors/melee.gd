extends EnemyBehavior
## Scrappers: close in and saw at you.


func attack(_player: Node3D, _dist: float) -> void:
	e.swing = 1.0
	Sound.play_3d("saw_swipe", e.global_position, -6.0)
	e.world.damage_player(e.damage_output(), e)


func hover(t: float) -> float:
	return 0.3 + sin(t * 4.0) * 0.15 if e.type == "scrapper" else 0.0
