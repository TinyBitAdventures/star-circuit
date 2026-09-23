extends Node
## Headless check of hyperspace: an interdicted first warp (waves spawn,
## kills pay out, hits land, the jump ends in the destination system) and
## a calm relay jump.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	Game.new_game("scout", "Warp")
	await _wait(3.0)
	Game.go_to_space()
	await _wait(3.0)
	Game.start_warp(3, false)
	await _wait(2.0)
	var w := get_tree().current_scene
	print("[warp] scene=", w.name, " star now=", Game.star_index, " interdicted=", w.interdicted, " duration=", w.duration, " waves=", w.waves.size())
	await _wait(5.0)
	print("[warp] t=", snappedf(w.elapsed, 0.1), " enemies=", w.enemies.size(), " types=", w.enemies.map(func(e): return e.type))
	var cr := Game.credits
	var sk := Game.space_kills
	for e in w.enemies.duplicate():
		w._hit_enemy(e, 99999.0)
	print("[warp] killed: kills=", w.kills, " space_kills ", sk, "->", Game.space_kills, " credits ", cr, "->", Game.credits)
	var h0 := Game.hull
	w._add_shot(w.player.position + Vector3(0, 0.6, -10), Vector3(0, 0, 60), 7.0, true, Color.RED)
	await _wait(0.5)
	print("[warp] hostile bolt: hull ", snappedf(h0, 0.1), "->", snappedf(Game.hull, 0.1))
	# skip to the end, clearing later waves as they come
	while not w.ended:
		for e in w.enemies.duplicate():
			w._hit_enemy(e, 99999.0)
		for m in w.mines.duplicate():
			m.hp = 0.0
		await get_tree().process_frame
		w.elapsed = maxf(w.elapsed, w.duration - 0.5) if w.waves.is_empty() else w.elapsed + 0.5
	await _wait(3.5)
	print("[warp] arrived: scene=", get_tree().current_scene.name, " star=", Game.star_index, " (", Galaxy.star(Game.star_index).name, ") interdictions=", Game.interdictions, " kills=", Game.space_kills)
	# a calm relay jump home
	Game.start_warp(0, true)
	await _wait(1.5)
	var w2 := get_tree().current_scene
	print("[warp] relay jump interdicted=", w2.interdicted, " duration=", w2.duration)
	if w2.interdicted:
		w2.elapsed = w2.duration
	await _wait(10.0)
	print("[warp] relay arrived: scene=", get_tree().current_scene.name, " star=", Game.star_index)
	get_tree().quit()
