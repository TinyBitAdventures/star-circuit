extends Node
## Headless end-to-end smoke test. Run:
##   godot --headless --path . res://scenes/dev_smoke.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		_detach.call_deferred()
	else:
		_run()


func _detach() -> void:
	var root := get_tree().root
	get_tree().current_scene = null
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _scene() -> Node:
	return get_tree().current_scene


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	Game.new_game("miner", "Smoke")
	await _wait(4.0)
	var w := _scene()
	print("[smoke] scene=", w.name, " planet=", w.planet.name, " biome=", w.planet.biome, " nodes=", w._nodes.size(), " critters=", w._critters.size())
	var p = w.player
	print("[smoke] player pos r=", p.global_position.length(), " surface r=", w.gen.surface_radius(p.global_position.normalized()), " on_floor=", p.is_on_floor())
	# walk forward for a bit
	Input.action_press("move_forward")
	await _wait(2.0)
	Input.action_release("move_forward")
	print("[smoke] after walk r=", p.global_position.length(), " surface r=", w.gen.surface_radius(p.global_position.normalized()), " on_floor=", p.is_on_floor())
	# jetpack
	Input.action_press("jump")
	await _wait(1.5)
	print("[smoke] jetpack alt=", p.global_position.length() - w.gen.surface_radius(p.global_position.normalized()), " energy=", Game.energy)
	Input.action_release("jump")
	await _wait(2.0)
	# quest + harvest
	Game.accept_quest()
	var mined := 0
	for n in w._nodes.duplicate():
		if n.node_type == "ferrite" and mined < 4:
			n.interact(p)
			mined += 1
	await _wait(0.5)
	print("[smoke] inv=", Game.inventory, " mining=", Game.skills.mining, " quest=", Game.quest_index, " prog=", Game.quest_progress)
	await _wait(3.5)
	print("[smoke] quest now=", Game.quest_index, " accepted=", Game.quest_accepted)
	Game.add_item("ferrite", 12)
	Game.add_item("biofiber", 6)
	Game.add_item("plasma", 8)
	for i in 4:
		Game.craft("alloy")
	Game.craft("energy_cell")
	Game.craft("drill_mk2")
	print("[smoke] after craft inv=", Game.inventory, " upgrades=", Game.upgrades, " eng=", Game.skills.engineering)
	w.scan(p.global_position, 120.0)
	print("[smoke] scanned=", Game.scanned)
	# ---- combat ----
	print("[smoke] enemies=", w.enemies.size(), " danger=", w.danger_level, " hull=", Game.hull, "/", Game.max_hull(), " dmg=", Game.weapon_damage())
	var e: Enemy = w.enemies[0]
	for cand in w.enemies:
		if cand.global_position.distance_to(p.global_position) < e.global_position.distance_to(p.global_position):
			e = cand
	var near_dir: Vector3 = (e.global_position.normalized() * 1.0 + (p.global_position.normalized() - e.global_position.normalized()).normalized() * 12.0 / w.gen.radius).normalized()
	p.place_at(near_dir, w.gen)
	await _wait(3.0)
	print("[smoke] enemy ", e.type, " lvl ", e.level, " state=", e.state, " dist=", e.global_position.distance_to(p.global_position), " player hull=", Game.hull)
	var k0 := Game.kills
	var scrap0 := Game.count("scrap")
	while is_instance_valid(e) and e.is_alive():
		e.take_hit(Game.weapon_damage())
		await get_tree().physics_frame
	print("[smoke] kills ", k0, "->", Game.kills, " scrap ", scrap0, "->", Game.count("scrap"), " combat skill=", Game.skills.combat)
	# ability (miner: slam) near remaining camp members
	p.ability_cd = 0.0
	Game.energy = Game.max_energy()
	p._use_ability(p.global_position.normalized())
	await _wait(0.5)
	print("[smoke] after ability kills=", Game.kills, " ability_cd=", p.ability_cd)
	# bolt path: fire one sentinel bolt at the player
	w.spawn_enemy_bolt(p.global_position + p.global_basis.y * 1.0 + p.global_basis.z * -8.0, p.global_position + p.global_basis.y * 1.0, 5.0, Color.RED)
	await _wait(0.8)
	print("[smoke] after bolt hull=", Game.hull)
	# death + respawn
	Game.invulnerable = false
	Game.take_damage(99999.0)
	await _wait(0.5)
	print("[smoke] dead=", p.dead)
	await _wait(4.5)
	print("[smoke] respawned dead=", p.dead, " hull=", Game.hull)
	# ---- towns + economy ----
	print("[smoke] town=", w.town != null, " name=", w.planet.town.get("name", ""), " npcs=", w.town.npcs.size() if w.town else 0)
	var tp: Dictionary = w.town_planet()
	var c0 := Game.credits
	Game.add_item("cobalt", 5, true)
	Game.sell("ferrite", 4, tp)
	Game.sell("cobalt", 5, tp)
	print("[smoke] sold: credits ", c0, "->", Game.credits, " ferrite sells ", Game.sell_price("ferrite", tp), " cobalt sells ", Game.sell_price("cobalt", tp))
	var stock := Game.trader_stock(tp)
	Game.add_credits(500, true)
	var cells0 := Game.count("energy_cell")
	Game.buy("energy_cell", 2, tp)
	print("[smoke] stock lines=", stock.size(), " bought cells ", cells0, "->", Game.count("energy_cell"), " credits=", Game.credits)
	Game.skills.mining.level = 25
	Game.gain_skill_xp("mining", 500)
	print("[smoke] mining capped at ", Game.skills.mining.level, " cap=", Game.skill_cap("mining"))
	Game.train("mining", tp.town.max_tier)
	Game.gain_skill_xp("mining", 500)
	print("[smoke] after training cap=", Game.skill_cap("mining"), " level=", Game.skills.mining.level, " tier=", Game.skill_tier("mining"))
	var offers := Game.board_offers(tp)
	for o in offers:
		Game.accept_bounty(o)
	print("[smoke] offers=", offers.map(func(o): return "%s(%s x%d)" % [o.title, o.type, o.n]))
	for b in Game.bounties:
		match b.type:
			"deliver": Game.add_item(b.item, b.n, true)
			"kill": Game._bounty_event("kill", b.n)
			"scan": Game._bounty_event("scan", b.n)
			"loot": Game._bounty_event("loot", b.n)
	var cr := Game.credits
	for b in Game.bounties.duplicate():
		Game.turn_in_bounty(b)
	print("[smoke] bounties turned in: credits ", cr, "->", Game.credits, " remaining=", Game.bounties.size())
	# save/load round trip keeps quest by id
	var qid: String = Game.current_quest().get("id", "")
	Game.save_game()
	var summary := Game.save_summary()
	print("[smoke] saved quest_id=", summary.get("quest_id", "?"), " (current ", qid, ") credits=", summary.get("credits", -1))
	# fire through the real input path
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.last_hit_time = -100.0
	# open every panel
	for panel in ["inventory", "crafting", "skills", "quests", "help", "pause", "dialog"]:
		w.hud.toggle_panel(panel)
		await get_tree().process_frame
	w.hud.close_panel()
	# take off
	p._start_launch()
	await _wait(5.0)
	var s := _scene()
	print("[smoke] scene=", s.name, " star=", s.star.name, " planets=", s.planets.size(), " player=", s.player.global_position)
	# ---- space mining ----
	var types := {}
	for ast in s.asteroids:
		types[ast.type] = types.get(ast.type, 0) + 1
	print("[smoke] belt r=", int(s.star.belt.radius), " asteroids=", s.asteroids.size(), " types=", types, " comet=", s.belt.comet != null)
	var rock: Asteroid = null
	for ast in s.asteroids:
		if ast.type == "rocky" and ast.size > 5.0 and ast.generation == 0:
			rock = ast
			break
	var sp = s.player
	sp.global_position = rock.global_position + Vector3(0, 0, rock.size + 25.0)
	sp.look_at(rock.global_position, Vector3.UP)
	sp.velocity = Vector3.ZERO
	sp.snap_camera()
	await _wait(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var hp0: float = rock.hp
	Input.action_press("fire")
	await _wait(2.0)
	print("[smoke] laser: rock hp ", int(hp0), "->", int(rock.hp) if is_instance_valid(rock) else -1, " beam=", sp._beam.visible, " energy=", int(Game.energy))
	Input.action_release("fire")
	var n0 := Game.count("nickel")
	var count0: int = s.asteroids.size()
	if is_instance_valid(rock):
		var rp: Vector3 = rock.global_position
		rock.mine(99999.0)
		await get_tree().process_frame
		print("[smoke] broke rock: asteroids ", count0, "->", s.asteroids.size(), " (fragments)")
		sp.global_position = rp
		sp.velocity = Vector3.ZERO
		await _wait(2.5)
	print("[smoke] shards collected: nickel ", n0, "->", Game.count("nickel"), " mining xp=", Game.skills.mining)
	# ---- space combat ----
	print("[smoke] pirates in system=", s.space_enemies.size(), " danger=", s.danger)
	Game.invulnerable = false
	Game.hull = Game.max_hull()
	var h0 := Game.hull
	var raider: SpaceEnemy = s._spawn_pirate("raider", 2, sp.global_position - sp.global_basis.z * 150.0, sp.global_position)
	raider.aggro()
	await _wait(4.0)
	print("[smoke] raider state=", raider.state, " dist=", int(raider.global_position.distance_to(sp.global_position)), " player hull ", int(h0), "->", int(Game.hull))
	var k1 := Game.kills
	var scrap1 := Game.count("scrap")
	var cr1 := Game.credits
	while is_instance_valid(raider) and raider.is_alive():
		raider.take_hit(Game.space_weapon_damage())
		await get_tree().physics_frame
	sp.global_position = raider.global_position if is_instance_valid(raider) else sp.global_position
	await _wait(2.0)
	print("[smoke] raider down: kills ", k1, "->", Game.kills, " credits ", cr1, "->", Game.credits, " scrap ", scrap1, "->", Game.count("scrap"))
	var gun: SpaceEnemy = s._spawn_pirate("gunship", 2, sp.global_position - sp.global_basis.z * 120.0, sp.global_position)
	var ghp: float = gun.hp
	Game.energy = Game.max_energy()
	sp._missile_cd = 0.0
	sp._launch_missiles(gun)
	await _wait(3.0)
	print("[smoke] missile: gunship hp ", int(ghp), "->", int(gun.hp) if is_instance_valid(gun) else -1)
	Game.take_damage(99999.0)
	await _wait(0.3)
	print("[smoke] ship destroyed dead=", sp.dead)
	await _wait(4.5)
	print("[smoke] ship rebooted dead=", sp.dead, " hull=", int(Game.hull))
	# ---- cargo + orbital station ----
	var st: OrbitalStation = s.station
	print("[smoke] station=", st.data.name, " wants=", st.data.demand, " surplus=", st.data.surplus, " dist from planet0=", int(st.global_position.distance_to(s.planets[0].node.global_position)))
	print("[smoke] cargo ", Game.cargo_used(), "/", Game.cargo_cap())
	var room := Game.cargo_free()
	var added := Game.add_item("ferrite", room + 25)
	print("[smoke] filled hold: added ", added, " of ", room + 25, " -> ", Game.cargo_used(), "/", Game.cargo_cap(), " more=", Game.add_item("nickel", 5))
	var cr0 := Game.credits
	var want: String = st.data.demand[0]
	Game.remove_item("ferrite", 10)
	Game.add_item(want, 10)
	print("[smoke] ", want, " sells here for ", Game.station_sell_price(want, Game.star_index), " vs town-ish ", int(Db.VALUES[want] * 0.6))
	Game.station_sell_all(Game.star_index)
	print("[smoke] sold all: credits ", cr0, "->", Game.credits, " cargo ", Game.cargo_used(), "/", Game.cargo_cap(), " quest=", Game.current_quest().get("id", ""))
	Game.station_buy("energy_cell", 2, Game.star_index)
	Game.hull = Game.max_hull() * 0.5
	var rc := Game.repair_cost()
	Game.buy_repair()
	print("[smoke] repair cost ", rc, " hull now ", int(Game.hull), "/", int(Game.max_hull()))
	sp.global_position = st.global_position + Vector3(0, 0, 30)
	await _wait(0.3)
	print("[smoke] dock prompt: ", s.hud.prompt_label.text)
	Game.add_item("cobalt", 20)
	var shards0 := 0
	Game.invulnerable = false
	Game.take_damage(99999.0)
	await _wait(0.3)
	print("[smoke] after ship loss cobalt=", Game.count("cobalt"), " (spilled into space)")
	await _wait(4.5)
	Game.invulnerable = true
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	s.hud.toggle_panel("map")
	await get_tree().process_frame
	s.hud.close_panel()
	# land on planet 2
	s.land(s.planets[1], s.planets[1].node.global_position + Vector3(0, 40, 0))
	await _wait(5.0)
	w = _scene()
	print("[smoke] landed on ", w.planet.name, " biome=", w.planet.biome, " nodes=", w._nodes.size(), " visited=", Game.visited_planets)
	# warp
	Game.add_item("warp_cell", 1)
	Game.star_index = 3
	Game.arrived_by_warp = true
	Game.record_warp(3)
	Game.go_to_space()
	await _wait(5.0)
	s = _scene()
	print("[smoke] warped to ", s.star.name, " planets=", s.planets.size())
	Game.save_game()
	print("[smoke] save exists=", Game.has_save(), " level=", Game.level, " xp=", Game.xp)
	print("[smoke] DONE in %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()
