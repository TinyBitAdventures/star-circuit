extends Node
## Headless: does an aggroed Brute camp actually close in and slam?

func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("miner", "T")
	await get_tree().create_timer(4.0).timeout
	Game.land_dir = Vector3(0.3, 0.8, 0.2).normalized()
	Game.go_to_planet(0, 2)
	await get_tree().create_timer(5.0).timeout
	var w := get_tree().current_scene
	var b: Enemy = null
	for c in w.enemies:
		if c.elite:
			b = c
			break
	print("[brute] elites=", w.enemies.filter(func(e): return e.elite).size(), " total=", w.enemies.size())
	var p = w.player
	var bd: Vector3 = b.home_dir
	p.place_at((bd + PlanetGen.align_basis(bd).x * 12.0 / w.gen.radius).normalized(), w.gen)
	Game.invulnerable = false
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		print("[brute] t=%.1f state=%s dist=%.1f slam=%.2f hull=%d sea=%s h=%.4f" % [i * 0.5, b.state, b.global_position.distance_to(p.global_position), (1.0 if b.behavior.raised() else -1.0), Game.hull, w.gen.sea, w.gen.height(b.dir)])
	get_tree().quit()
