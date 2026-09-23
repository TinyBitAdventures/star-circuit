extends Node
## Headless check of the Deep Sea: dive in from the planet, swim down,
## cut rock, scan, open a clam, get crushed in the Abyss, surface.

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
	Game.new_game("miner", "Sea")
	await _wait(4.0)
	var pw := get_tree().current_scene
	var gen: PlanetGen = pw.gen
	print("[sea] planet=", pw.planet.name, " sea_r=", snappedf(gen.sea_radius(), 0.1))
	# find the deepest ocean spot among a sample of directions
	var best := Vector3.ZERO
	var best_d := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 3000:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var depth := gen.sea_radius() - gen.surface_radius(d)
		if depth > best_d:
			best_d = depth
			best = d
	print("[sea] deepest ocean found=", snappedf(best_d, 0.1), " m")
	var p = pw.player
	p.global_position = best * (gen.sea_radius() - 3.0)
	await _wait(1.5)
	print("[sea] 3D underwater music=", Sound._music_current)
	print("[sea] in_liquid=", p.in_liquid, " swim_depth=", snappedf(p.swim_depth, 0.1), " uw=", snappedf(p._uw, 0.01), " fog=", snappedf(pw.env.fog_density, 0.001))
	Input.action_press("descend")
	await _wait(1.5)
	Input.action_release("descend")
	print("[sea] after diving swim_depth=", snappedf(p.swim_depth, 0.1))
	Game.enter_sea(p.global_position.normalized(), pw.planet)
	await _wait(3.0)
	var w := get_tree().current_scene
	print("[sea] music=", Sound._music_current, " stream=", Sound._music_active.stream, " playing=", Sound._music_active.playing)
	print("[sea] scene=", w.name, " objects=", w.objects.size(), " fauna=", w.fauna.size(), " kinds=", _kinds(w.objects))
	var d: SeaDiver = w.diver
	# swim straight down the trench
	Input.action_press("move_back")
	await _wait(4.0)
	Input.action_release("move_back")
	print("[sea] depth after swim=", Game.max_sea_depth, " m")
	# scan near a fish school
	for f in w.fauna:
		if f.kind == "fish":
			d.position = f.pos
			break
	await _wait(0.2)
	w._scan()
	print("[sea] scanned=", Game.scanned.filter(func(k): return ":sea:" in k), " quest=", Game.current_quest().get("id"))
	# cut some rock sideways
	var before: float = Game.skills.mining.xp
	var c: Vector2i = w.cell_at(d.position)
	for x in range(c.x, 0, -1):
		if w.is_solid(x - 1, c.y):
			d.position = w.cell_centre(Vector2i(x, c.y))
			break
	Input.action_press("move_left")
	await _wait(2.5)
	Input.action_release("move_left")
	print("[sea] dug cells=", Array(w.dug).count(1), " mining xp ", before, "->", Game.skills.mining.xp)
	# open a clam
	for o in w.objects:
		if o.kind == "clam":
			w._use(o)
			print("[sea] clam open=", o.open, " pearls=", Game.count("sea_pearl"))
			break
	# the Abyss hurts without a pressure hull
	var h0 := Game.hull
	d.position = Vector2(w.trench_x(150) * w.CS, 150 * w.CS)
	await _wait(1.5)
	print("[sea] abyss hull ", snappedf(h0, 0.1), " -> ", snappedf(Game.hull, 0.1), " depth=", Game.max_sea_depth)
	Game.upgrades.append("pressure_hull")
	var h1 := Game.hull
	await _wait(1.0)
	print("[sea] with pressure hull ", snappedf(h1, 0.1), " -> ", snappedf(Game.hull, 0.1))
	w._exit()
	await _wait(4.0)
	var back := get_tree().current_scene
	print("[sea] back on ", back.name, " player in_liquid=", back.player.in_liquid)
	get_tree().quit()


func _kinds(objs: Array) -> Dictionary:
	var k := {}
	for o in objs:
		k[o.kind] = int(k.get(o.kind, 0)) + 1
	return k
