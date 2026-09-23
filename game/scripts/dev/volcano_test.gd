extends Node
## Headless check of the Eruption Run: the vent appears on a volcanic
## world, the run generates, mining works, geysers launch, heat and magma
## rise, escaping keeps loot, and an eruption costs half of it.

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
	Game.new_game("miner", "Vol")
	await _wait(3.0)
	# find a volcanic world
	var target := Vector2i(-1, -1)
	for s in Galaxy.stars.size():
		for p in Galaxy.star(s).planets:
			if Db.BIOMES[p.biome].get("lava", false) and not p.has("moon_of") and target.x < 0:
				target = Vector2i(s, p.index)
	Game.go_to_planet(target.x, target.y)
	await _wait(5.0)
	var pw := get_tree().current_scene
	var vent: Poi = null
	for p in pw.pois:
		if p.type == "volcano":
			vent = p
	var vents: Array = pw.pois.filter(func(p): return p.type == "volcano")
	var near := INF
	for v in vents:
		near = minf(near, v.global_position.distance_to(pw.player.global_position))
	var on_compass: int = pw.compass_markers().filter(func(m): return m.label == "Volcanic Vent").size()
	print("[vol] vents=", vents.size(), " nearest to landing=", int(near), "m  on compass=", on_compass)
	Game.quest_index = Db.QUESTS.map(func(q): return q.id).find("fire")
	Game.quest_accepted = false
	Game.accept_quest()
	pw._qt_t = 0.0
	print("[vol] fire quest star -> ", pw.quest_target().get("label", "none"), " · nearest volcanic world=", Game.nearest_volcanic_world().get("name", "?"))
	print("[vol] world=", pw.planet.name, " (", pw.planet.biome, ") vent=", vent != null, " info=", vent.cache_info().text if vent else "")
	vent.open_cache()
	await _wait(3.0)
	var w := get_tree().current_scene
	print("[vol] scene=", w.name, " deposits=", w.deposits.size(), " geysers=", w.geysers.size(), " by zone=", _zones(w))
	var r: VolcanoRunner = w.runner
	# mine a deep deposit
	var deep := {}
	for d in w.deposits:
		if int(d.zone) >= 3:
			deep = d
			break
	r.position = deep.pos + Vector2(0, -16)
	Input.action_press("interact")
	await _wait(4.0)
	Input.action_release("interact")
	print("[vol] mined ", deep.item, " taken=", deep.taken, " hold=", Game.count(deep.item), " heat=", snappedf(w.heat, 0.1))
	# a geyser launches you
	var g: Dictionary = w.geysers[0]
	r.position = Vector2((g.x + 0.5) * w.CS, (g.y + 0.5) * w.CS)
	g.state = "warn"
	g.t = 0.1
	await _wait(0.4)
	print("[vol] geyser: launched=", r.launched > 0.0, " vy=", snappedf(r.velocity.y, 1))
	# magma rises
	var m0: float = w.magma_y
	w.elapsed = 100.0
	await _wait(0.2)
	print("[vol] magma ", int(m0 / w.CS), " -> ", int(w.magma_y / w.CS), " rows (rim at ", w.PEAK, ")")
	# escape with loot
	var had := Game.count(deep.item)
	r.position = Vector2(w.W * w.CS * 0.5, (w.PEAK + 1) * w.CS)
	await _wait(0.2)
	w._escape()
	await _wait(5.0)
	print("[vol] escaped: scene=", get_tree().current_scene.name, " kept ", deep.item, " ", had, "->", Game.count(deep.item), " runs=", Game.volcano_runs)
	# second run: stay too long
	var pw2 := get_tree().current_scene
	for p in pw2.pois:
		if p.type == "volcano":
			p.open_cache()
	await _wait(3.0)
	var w2 := get_tree().current_scene
	for d in w2.deposits:
		if not d.taken:
			w2.runner.position = d.pos + Vector2(0, -16)
			w2._run_items[d.item] = int(d.qty)
			Game.add_item(d.item, int(d.qty), true, true)
			var before := Game.count(d.item)
			w2.elapsed = w2.DURATION + 1.0
			await _wait(4.0)
			print("[vol] erupted: scene=", get_tree().current_scene.name, " ", d.item, " ", before, "->", Game.count(d.item), " hull=", snappedf(Game.hull, 0.1), " runs=", Game.volcano_runs)
			break
	get_tree().quit()


func _zones(w) -> Dictionary:
	var z := {}
	for d in w.deposits:
		z[d.zone] = int(z.get(d.zone, 0)) + 1
	return z
