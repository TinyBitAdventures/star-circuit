extends Node
## Headless check of the orbit view: probe down to a gem, reel it in.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _run() -> void:
	Game.new_game("miner", "O")
	await get_tree().create_timer(3.0).timeout
	var info := Game.orbit_info("planet", 0, 0)
	print("[orbit] gems on Cradle=", Game.world_gems(info).size(), " left=", Game.gems_left(info))
	var gi := Game.orbit_info("giant", 0, -1)
	print("[orbit] giant=", gi.name, " gems=", Game.world_gems(gi).size())
	Game.add_item("deep_probe", 3, true)
	Game.enter_orbit(info, Vector3(0, 0, 900))
	await get_tree().create_timer(2.5).timeout
	var w := get_tree().current_scene
	print("[orbit] scene=", w.name, " gems=", w.gems.size(), " rocks=", w.rocks.size(), " ores=", w.ores.size())
	w._scan()
	# line the ship up over the first gem (compensating for the planet's spin) and drop straight down
	var g: Dictionary = w.gems[0]
	for attempt in 3:
		w.rocks.clear() # the test is about the gem, not dodging
		var local_angle: float = (g.pos as Vector2).angle()
		var dist: float = w.R * 1.24 + 18.0 - (g.pos as Vector2).length()
		var travel_t: float = dist / w.PROBE_SPEED
		w.ship_angle = local_angle + w.rot + w.SPIN * travel_t
		w._launch()
		var t := 0.0
		while w.probe_state != "" and t < 12.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		print("[orbit] attempt ", attempt, " state=", w.probe_state, " heat=", snappedf(w.probe_heat, 0.1), " gem held=", Game.count(info.gem), " probes=", Game.count("deep_probe"))
		if Game.count(info.gem) > 0:
			break
	print("[orbit] gems_taken=", Game.gems_taken, " left=", Game.gems_left(info), " types=", Game.gem_types())
	# a probe dropped straight into the core should be lost
	var before := Game.count("deep_probe")
	w.rocks.clear()
	for gg in w.gems:
		gg.taken = true
	for oo in w.ores:
		oo.taken = true
	w._launch()
	var t2 := 0.0
	while w.probe_state != "" and t2 < 15.0:
		await get_tree().process_frame
		t2 += get_process_delta_time()
	print("[orbit] core dive: probes ", before, " -> ", Game.count("deep_probe"))
	# the Crown of Worlds
	for gk in Game.GEM_KINDS:
		Game.add_item(gk, 1, true)
	Game.skills.engineering.level = 45
	Game.skill_tiers["engineering"] = 1
	var e0 := Game.max_energy()
	Game.check_milestones(false)
	var r: Dictionary = {}
	for rr in Db.RECIPES:
		if rr.id == "crown_of_worlds":
			r = rr
	print("[orbit] gem types=", Game.gem_types(), " gem_hunter=", Game.milestones.has("gem_hunter"), " can craft crown=", Game.can_craft(r))
	Game.craft("crown_of_worlds")
	print("[orbit] crown=", Game.has_upgrade("crown_of_worlds"), " energy ", e0, " -> ", Game.max_energy(), " gems left=", Game.gem_types())
	w._leave()
	await get_tree().create_timer(3.0).timeout
	print("[orbit] back in: ", get_tree().current_scene.name)
	get_tree().quit()
