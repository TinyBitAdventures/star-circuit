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
	# the cone is solid: a ray from 25 m out toward the centre stops at its flank
	var up: Vector3 = vent.dir
	var side: Vector3 = vent.global_basis.x.normalized()
	var from: Vector3 = vent.global_position + up * 3.0 + side * 25.0
	var hit: Dictionary = pw.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, vent.global_position + up * 3.0))
	var hit_d: float = (hit.position - vent.global_position).length() if hit else -1.0
	print("[vol] cone solid=", not hit.is_empty(), " hit at ", snappedf(hit_d, 0.1), " m from centre")
	# walk up to the doorway: standing on the ground in front of it brings up the prompt
	var door: Vector3 = vent.entrance()
	pw.player.place_at((door + (door - vent.global_position).normalized() * 1.5).normalized(), pw.gen)
	await _wait(0.6)
	var t: Node = pw.nearest_interactable(pw.player.global_position, 4.2)
	var gap := door.distance_to(pw.player.global_position)
	print("[vol] door reach: player ", snappedf(gap, 0.1), " m from door, target=", t.interact_info().text if t else "none")
	if t:
		t.interact(pw.player)
	else:
		vent.open_cache()
	await _wait(3.0)
	var w := get_tree().current_scene
	print("[vol] scene=", w.name, " deposits=", w.deposits.size(), " geysers=", w.geysers.size(), " by zone=", _zones(w))
	var r: VolcanoRunner = w.runner
	# the clock waits for the briefing
	await _wait(1.5)
	print("[vol] briefing up=", w._briefing, " clock held=", w.elapsed == 0.0)
	w.start_run()
	# the tube never pinches: each row shares at least 2 open tiles with the next
	var worst := 99
	for y in range(w.PEAK, w.ZONES[5].top - 4):
		var cx := int(w.tube_x(y))
		var shared := 0
		for x in range(cx - 8, cx + 9):
			if not w.is_solid(x, y) and not w.is_solid(x, y + 1):
				shared += 1
		worst = mini(worst, shared)
	print("[vol] tube: narrowest row-to-row opening=", worst, " tiles")
	# drilling: push right into rock in the Lava Tubes
	var rock_c := Vector2i(-1, -1)
	for y in range(w.ZONES[1].top + 2, w.ZONES[2].top):
		for x in range(3, w.W - 4):
			if w.get_cell(x, y) == w.ROCK and not w.is_solid(x - 1, y) and not w.is_solid(x - 1, y - 1) and w.is_solid(x - 1, y + 1):
				rock_c = Vector2i(x, y)
				break
		if rock_c.x >= 0:
			break
	r.position = w.cell_centre(Vector2i(rock_c.x - 1, rock_c.y)) + Vector2(-2, 2)
	r.velocity = Vector2.ZERO
	Input.action_press("move_right")
	await _wait(2.0)
	Input.action_release("move_right")
	print("[vol] drill sideways at ", rock_c, ": rock gone=", not w.is_solid(rock_c.x, rock_c.y))
	# and straight down
	await _wait(0.3)
	var below: Vector2i = w.cell_at(r.position + Vector2(0, VolcanoRunner.HALF.y + 4.0))
	var was_solid: bool = w.is_solid(below.x, below.y)
	Input.action_press("move_back")
	await _wait(2.0)
	Input.action_release("move_back")
	print("[vol] drill down at ", below, ": was solid=", was_solid, " now open=", not w.is_solid(below.x, below.y), " basalt refused=", w.drill(Vector2i(0, 40), 0.1) < 0.0)
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
	var lava_near := 0
	for d in w.deposits:
		var dc: Vector2i = w.cell_at(d.pos - Vector2(0, w.CS * 0.5))
		for dx in range(-1, 2):
			if w.get_cell(dc.x + dx, dc.y) == w.LAVA:
				lava_near += 1
	print("[vol] crystals with lava beside them=", lava_near)
	print("[vol] mined ", deep.item, " taken=", deep.taken, " hold=", Game.count(deep.item), " heat=", snappedf(w.heat, 0.1))
	# a save mid-run leaves the haul in the volcano (quitting now forfeits it)
	Game.save_game()
	var sd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.slot_path(Game.slot)))
	print("[vol] mid-run save: hold ", deep.item, "=", Game.count(deep.item), " saved=", int(sd.inventory.get(deep.item, 0)), " haul=", Game.volcano.get("haul", {}))
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
	w2.start_run()
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
