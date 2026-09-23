extends Node
## Renders a tour of the game to PNGs in res://../shots/. Run windowed:
##   godot --path . res://scenes/dev_shots.tscn

var out_dir := ""
var n := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = ProjectSettings.globalize_path("res://").path_join("../shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	n += 1
	var path := out_dir.path_join("%02d_%s.png" % [n, label])
	img.save_png(path)
	print("[shots] ", path)


func _scene() -> Node:
	return get_tree().current_scene


func _run() -> void:
	var which: String = OS.get_environment("SHOTS")
	if which == "":
		which = "all"
	if which == "portraits":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		await _wait(2.0)
		var mm := _scene()
		mm._show_select()
		mm.select_box.visible = false
		for i in 4:
			mm._select(i)
			await _wait(2.4)
			await shot("portrait_%d" % i)
		get_tree().quit()
		return
	if which == "volcano":
		await _volcano_tour()
		get_tree().quit()
		return
	if which == "warp":
		await _warp_tour()
		get_tree().quit()
		return
	if which == "home":
		await _home_tour()
		get_tree().quit()
		return
	if which == "select":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		await _wait(2.0)
		var m := _scene()
		m._show_select()
		for i in 4:
			m._select(i)
			await _wait(1.8)
			await shot("select_%d" % i)
		get_tree().quit()
		return
	if which == "atmo":
		await _atmo_tour()
		get_tree().quit()
		return
	if which == "shadow":
		await _shadow_tour()
		get_tree().quit()
		return
	if which == "sea":
		await _sea_tour()
		get_tree().quit()
		return
	if which == "mine":
		await _mine_tour()
		get_tree().quit()
		return
	if which == "orbit":
		await _orbit_tour()
		get_tree().quit()
		return
	if which == "polish":
		await _polish_tour()
		get_tree().quit()
		return
	if which == "circuit":
		await _circuit_tour()
		get_tree().quit()
		return
	if which == "deep":
		await _deep_tour()
		get_tree().quit()
		return
	if which == "gfx":
		await _gfx_tour()
		get_tree().quit()
		return
	if which == "outfit":
		await _outfit_tour()
		get_tree().quit()
		return
	if which == "station":
		await _station_tour()
		get_tree().quit()
		return
	if which == "spacefight":
		await _spacefight_tour()
		get_tree().quit()
		return
	if which == "belt":
		await _belt_tour()
		get_tree().quit()
		return
	if which == "town":
		await _town_tour()
		get_tree().quit()
		return
	if which == "sky":
		await _sky_tour()
		get_tree().quit()
		return
	if which == "depth":
		await _depth_tour()
		get_tree().quit()
		return
	if which == "combat":
		await _combat_tour()
		get_tree().quit()
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(2.5)
	await shot("menu")
	var m := _scene()
	m._show_select()
	await _wait(1.6)
	await shot("select_scout")
	m._select(1)
	await _wait(1.6)
	await shot("select_miner")
	m._select(3)
	await _wait(1.6)
	await shot("select_siphon")
	Game.new_game(OS.get_environment("ROBOT") if OS.get_environment("ROBOT") != "" else "engineer", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await shot("planet_arrive")
	var p = w.player
	p.cam_pitch = -0.15
	p.cam_yaw = PI
	await _wait(0.6)
	await shot("planet_behind")
	p.cam_yaw = PI * 0.5
	p.spring.spring_length = 14.0
	p.cam_pitch = -0.5
	await _wait(0.6)
	await shot("planet_wide")
	# walk away from the outpost and look around
	p.cam_yaw = 0.8
	p.cam_pitch = -0.2
	p.spring.spring_length = 7.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(4.0)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _wait(0.8)
	await shot("planet_explore")
	w.scan(p.global_position, 90.0)
	await _wait(0.5)
	await shot("planet_scan")
	# jetpack high
	Input.action_press("jump")
	await _wait(2.5)
	Input.action_release("jump")
	p.cam_pitch = -0.9
	p.spring.spring_length = 16.0
	await _wait(0.3)
	await shot("planet_jetpack")
	await _wait(2.0)
	p.cam_pitch = -0.3
	p.spring.spring_length = 7.0
	Game.add_item("ferrite", 20)
	Game.add_item("plasma", 10)
	Game.add_item("biofiber", 8)
	Game.add_item("cobalt", 5)
	for panel in ["crafting", "inventory", "skills", "quests", "dialog"]:
		w.hud.toggle_panel(panel)
		await _wait(0.3)
		await shot("panel_" + panel)
	w.hud.close_panel()
	# night
	Game.play_time += 360.0
	await _wait(0.5)
	await shot("planet_night")
	Game.play_time -= 360.0
	p._start_launch()
	await _wait(5.0)
	var s := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await shot("space_launch")
	# swing around to look at the system
	s.player.look_at(Vector3.ZERO, Vector3.UP)
	s.player.snap_camera()
	await _wait(0.5)
	await shot("space_star")
	var p1 = s.planets[1]
	s.player.global_position = p1.node.global_position + Vector3(20, 10, 45)
	s.player.look_at(p1.node.global_position, Vector3.UP)
	s.player.snap_camera()
	await _wait(0.5)
	await shot("space_planet")
	s.hud.toggle_panel("map")
	await _wait(0.4)
	await shot("galaxy_map")
	s.hud.close_panel()
	for idx in [1, 2, 3]:
		s = _scene()
		s.land(s.planets[idx], s.planets[idx].node.global_position + Vector3(0, 60, 10))
		await _wait(5.0)
		w = _scene()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		w.player.cam_pitch = -0.25
		await _wait(0.5)
		await shot("world_" + w.planet.biome)
		Game.play_time += 0.0
		w.player._start_launch()
		await _wait(4.5)
	# visit a volcanic / fungal world elsewhere if any
	for si in range(1, Galaxy.stars.size()):
		var st: Dictionary = Galaxy.star(si)
		for pl in st.planets:
			if pl.biome in ["ember", "bloom"] and not has_meta(pl.biome):
				set_meta(pl.biome, true)
				Game.star_index = si
				Game.land_dir = Vector3(0.3, 0.8, 0.2).normalized()
				Game.go_to_planet(si, pl.index)
				await _wait(5.0)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				await shot("world_" + pl.biome)
		if has_meta("ember") and has_meta("bloom"):
			break
	print("[shots] done")
	get_tree().quit()


func _combat_tour() -> void:
	Game.new_game(OS.get_environment("ROBOT") if OS.get_environment("ROBOT") != "" else "miner", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	var e: Enemy = w.enemies[0]
	for c in w.enemies:
		if c.global_position.distance_to(p.global_position) < e.global_position.distance_to(p.global_position):
			e = c
	var ed: Vector3 = e.home_dir
	var pd: Vector3 = (ed + (p.global_position.normalized() - ed).normalized() * 16.0 / w.gen.radius).normalized()
	p.place_at(pd, w.gen)
	await _wait(0.3)
	# point the camera at the camp
	var to: Vector3 = e.global_position - p.global_position
	var up: Vector3 = p.global_position.normalized()
	to = (to - up * to.dot(up)).normalized()
	p.ref_fwd = to
	p.cam_yaw = 0.0
	p.cam_pitch = -0.12
	await _wait(1.0)
	await shot("combat_approach")
	await _wait(1.2)
	for i in 6:
		p._shoot(p._aim_ray(), up)
		p._fire_pose = 0.6
		await _wait(0.12)
	await shot("combat_firing")
	await _wait(1.2)
	await shot("combat_melee")
	p.ability_cd = 0.0
	Game.energy = Game.max_energy()
	p._use_ability(p.global_position.normalized())
	await _wait(0.15)
	await shot("combat_ability")
	# brute on a harder world
	Game.land_dir = Vector3(0.3, 0.8, 0.2).normalized()
	Game.go_to_planet(0, 2)
	await _wait(5.5)
	w = _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p = w.player
	var b: Enemy = null
	for c in w.enemies:
		if c.elite:
			b = c
			break
	if b:
		var bd: Vector3 = b.home_dir
		var pb: Vector3 = (bd + PlanetGen.align_basis(bd).x * 5.0 / w.gen.radius).normalized()
		p.place_at(pb, w.gen)
		up = p.global_position.normalized()
		var tb: Vector3 = b.global_position - p.global_position
		p.ref_fwd = (tb - up * tb.dot(up)).normalized()
		p.cam_yaw = 0.25
		p.cam_pitch = -0.2
		p.spring.spring_length = 10.0
		Game.invulnerable = true
		b.aggro()
		await _wait(3.2)
		await shot("combat_brute")
		await _wait(0.6)
		await shot("combat_brute2")
	Game.invulnerable = false
	Game.take_damage(99999.0)
	await _wait(1.0)
	await shot("combat_death")
	await _wait(4.5)
	w.hud.toggle_panel("inventory")
	await _wait(0.3)
	await shot("combat_inventory")


func _look_at_from(w, p, target: Vector3, dist: float, pitch := -0.15, arm := 9.0) -> void:
	var td: Vector3 = target.normalized()
	var b := PlanetGen.align_basis(td)
	p.place_at((td + b.x * dist / w.gen.radius).normalized(), w.gen)
	var up: Vector3 = p.global_position.normalized()
	var to: Vector3 = target - p.global_position
	p.ref_fwd = (to - up * to.dot(up)).normalized()
	p.cam_yaw = 0.0
	p.cam_pitch = pitch
	p.spring.spring_length = arm
	await _wait(0.8)


func _depth_tour() -> void:
	Game.new_game("scout", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	await shot("depth_arrive_compass")
	for poi in w.pois:
		poi.revealed = true
	await _wait(0.3)
	await shot("depth_compass_revealed")
	var done := {}
	for poi in w.pois:
		if done.has(poi.type):
			continue
		done[poi.type] = true
		await _look_at_from(w, p, poi.global_position, 20.0 if poi.type != "monolith" else 26.0, -0.05 if poi.type == "monolith" else -0.2)
		await shot("depth_poi_" + poi.type)
	# lore popup
	var mono: Poi = null
	for poi in w.pois:
		if poi.type == "monolith":
			mono = poi
	if mono:
		mono.open_cache()
		await _wait(0.5)
		await shot("depth_lore")
		w.hud.close_panel()
	w.hud.toggle_panel("quests")
	await _wait(0.3)
	await shot("depth_codex")
	w.hud.close_panel()
	# night sky with sister planets
	p.cam_pitch = 0.45
	p.spring.spring_length = 6.0
	Game.play_time = 360.0
	await _wait(0.6)
	await shot("depth_night_sky")
	Game.play_time = 0.0
	# storm
	w.weather._phase = 260.0 * 0.25 - Game.play_time
	w.weather.storm = 1.0
	p.cam_pitch = -0.1
	await _wait(1.5)
	await shot("depth_rainstorm")
	# ringed crystal world with floating islands
	Game.land_dir = Vector3(0.2, 0.3, 1.0).normalized()
	Game.go_to_planet(0, 3)
	await _wait(6.0)
	w = _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p = w.player
	for e in w.enemies:
		e.set_physics_process(false)
	p.cam_pitch = 0.35
	p.spring.spring_length = 8.0
	await _wait(0.8)
	await shot("depth_rings_islands_day")
	Game.play_time = 360.0
	await _wait(0.8)
	await shot("depth_rings_islands_night")
	Game.play_time = 0.0
	w.weather.storm = 1.0
	w.weather._phase = 260.0 * 0.25
	p.cam_pitch = -0.15
	await _wait(1.5)
	await shot("depth_crystal_squall")
	# desert craters from orbit
	p._start_launch()
	await _wait(5.5)
	var s := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var pl = s.planets[1]
	s.player.set_physics_process(false)
	s.player.global_position = pl.node.global_position + Vector3(0.2, 0.9, 0.5).normalized() * pl.radius * 3.2
	s.player.look_at(pl.node.global_position, Vector3.UP)
	s.player.snap_camera()
	await _wait(0.6)
	await shot("depth_craters_orbit")


## Find a surface spot + time of day where `target` sits ~elev radians above
## the horizon at night, then frame it.
func _frame_sky(w, target_fn: Callable, elev := 0.3) -> void:
	var p = w.player
	var best := {}
	var best_score := INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 3000:
		var a := rng.randf() * TAU
		var z := rng.randf_range(-0.9, 0.9)
		var r := sqrt(1.0 - z * z)
		var up := Vector3(r * cos(a), z, r * sin(a))
		var ta := rng.randf() * TAU
		var sun := Vector3(cos(ta) * 0.93, 0.28, sin(ta) * 0.93).normalized()
		if up.dot(sun) > -0.35:
			continue
		if w.gen.has_liquid() and w.gen.height(up) < w.gen.sea + 0.004:
			continue
		var tgt: Vector3 = target_fn.call(ta)
		var to: Vector3 = (tgt - up * w.gen.surface_radius(up)).normalized()
		var e := asin(clampf(to.dot(up), -1.0, 1.0))
		var score := absf(e - elev)
		if score < best_score:
			best_score = score
			best = {"up": up, "ta": ta, "tgt": tgt}
	Game.play_time = (best.ta - PI * 0.5) * w.DAY_LENGTH / TAU
	await _wait(0.2)
	p.place_at(best.up, w.gen)
	var upv: Vector3 = p.global_position.normalized()
	var tgt2: Vector3 = target_fn.call(best.ta)
	var to2: Vector3 = tgt2 - p.global_position
	p.ref_fwd = (to2 - upv * to2.dot(upv)).normalized()
	p.cam_yaw = 0.0
	p.cam_pitch = clampf(asin(to2.normalized().dot(upv)), -1.0, 0.6)
	p.spring.spring_length = 5.0
	await _wait(1.0)


func _sky_tour() -> void:
	Game.new_game("scout", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	# a sister planet in the night sky
	var body: Node3D = w.sky_bodies[0]
	await _frame_sky(w, func(ta):
		w._sky_pivot.rotation.y = -(ta - PI * 0.5) + w._sky_offset
		return w._sky_pivot.global_transform * body.position
	)
	await shot("sky_sister_planet_night")
	# ringed world: the ring arc across the sky
	Game.land_dir = Vector3(0.2, 0.3, 1.0).normalized()
	Game.go_to_planet(0, 3)
	await _wait(6.0)
	w = _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for e in w.enemies:
		e.set_physics_process(false)
	var ring: MeshInstance3D = w.ring_node
	var rp: Vector3 = ring.global_transform * Vector3(w.gen.radius * 3.2, 0, 0)
	await _frame_sky(w, func(_ta): return rp, 0.35)
	await shot("sky_ring_night")
	# daytime version of the same view
	Game.play_time += w.DAY_LENGTH * 0.5
	await _wait(1.0)
	await shot("sky_ring_day")
	# floating islands
	var up: Vector3 = w.player.global_position.normalized()
	var best_d := INF
	var isl := Vector3.ZERO
	for c in w.get_children():
		if c is StaticBody3D:
			for cs in c.get_children():
				if cs is CollisionShape3D and cs.shape is CylinderShape3D and (cs.shape as CylinderShape3D).height < 5.0 and (cs.shape as CylinderShape3D).radius > 3.0:
					var d: float = cs.global_position.distance_to(w.player.global_position)
					if d < best_d:
						best_d = d
						isl = cs.global_position
	if isl != Vector3.ZERO:
		var id: Vector3 = isl.normalized()
		var b := PlanetGen.align_basis(id)
		w.player.place_at((id + b.x * 30.0 / w.gen.radius).normalized(), w.gen)
		var upv: Vector3 = w.player.global_position.normalized()
		var to: Vector3 = isl - w.player.global_position
		w.player.ref_fwd = (to - upv * to.dot(upv)).normalized()
		w.player.cam_yaw = 0.0
		w.player.cam_pitch = clampf(asin(to.normalized().dot(upv)), -0.5, 0.6)
		w.player.spring.spring_length = 6.0
		Game.play_time = 0.0
		await _wait(1.0)
		await shot("sky_floating_island")


func _town_tour() -> void:
	Game.new_game("miner", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	var p = w.player
	var t: Town = w.town
	# wide view of the Cradle from the edge of town
	await _look_at_from(w, p, t.centre, 30.0, -0.35, 16.0)
	await _wait(2.0)
	await shot("town_cradle_wide")
	for npc in t.npcs:
		if npc.role in ["merchant", "trainer", "board"]:
			await _look_at_from(w, p, npc.global_position, 6.0, -0.1, 6.0)
			await shot("town_" + npc.role)
	for npc in t.npcs:
		if npc.role == "folk":
			await _look_at_from(w, p, npc.global_position, 4.0, -0.05, 5.0)
			npc._bubble_t = 0.0
			await _wait(1.2)
			await shot("town_folk_chatter")
			break
	Game.add_item("ferrite", 30, true)
	Game.add_item("biofiber", 12, true)
	Game.add_item("cobalt", 6, true)
	Game.add_credits(320, true)
	Game.skills.mining.level = 22
	var tp: Dictionary = w.town_planet()
	w.hud.open_town_panel("trade", tp)
	await _wait(0.4)
	await shot("panel_trade_buy")
	w.hud._trade_tab = "sell"
	w.hud._rebuild_town_panel()
	await _wait(0.3)
	await shot("panel_trade_sell")
	w.hud.close_panel()
	w.hud.open_town_panel("trainer", tp)
	await _wait(0.3)
	await shot("panel_trainer")
	w.hud.close_panel()
	w.hud.open_town_panel("board", tp)
	await _wait(0.3)
	for o in Game.board_offers(tp).slice(0, 2):
		Game.accept_bounty(o)
	w.hud._rebuild_town_panel()
	await _wait(0.3)
	await shot("panel_board")
	w.hud.close_panel()
	await _wait(0.5)
	await shot("hud_contracts")
	# fly to a sister world with a hub and dock there
	p._start_launch()
	await _wait(5.5)
	var sp := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var target = sp.planets[1]
	sp.player.global_position = target.node.global_position + Vector3(0.2, 0.3, 1.0).normalized() * target.radius * 2.6
	sp.player.look_at(target.node.global_position, Vector3.UP)
	sp.player.snap_camera()
	await _wait(0.8)
	await shot("space_dock_prompt")
	sp.land_at_town(target)
	await _wait(7.0)
	w = _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _look_at_from(w, w.player, w.town.centre, 28.0, -0.3, 14.0)
	await _wait(2.0)
	await shot("town_second_hub")


func _belt_tour() -> void:
	Game.new_game("miner", "Tester")
	await _wait(5.0)
	Game.last_hit_time = -100.0
	_scene().player._start_launch()
	await _wait(5.5)
	var s := _scene()
	var sp = s.player
	# wide view of the belt from above its plane
	var br: float = s.star.belt.radius
	sp.global_position = Vector3(br * 0.75, 90, br * 0.55)
	sp.look_at(Vector3(br * 1.0, 0, br * 0.1), Vector3.UP)
	sp.snap_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(1.0)
	await shot("belt_overview")
	# fly up to a big rock and mine it
	var rock: Asteroid = null
	for a in s.asteroids:
		if a.generation == 0 and a.type in ["rocky", "icy"] and a.size > 6.0:
			rock = a
			break
	sp.global_position = rock.global_position + Vector3(6, 4, rock.size + 22.0)
	sp.look_at(rock.global_position, Vector3.UP)
	sp.velocity = Vector3.ZERO
	sp.snap_camera()
	await _wait(0.6)
	sp._scan_cd = 0.0
	Game.energy = Game.max_energy()
	s.scan_space(sp.global_position, 520.0)
	await _wait(1.6)
	await shot("belt_scan_labels")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var hp0 := rock.hp
	Input.action_press("fire")
	await _wait(1.2)
	print("[belt] captured=", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, " hp ", int(hp0), "->", int(rock.hp), " beam=", sp._beam.visible)
	await shot("belt_laser")
	await _wait(6.0)
	Input.action_release("fire")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[belt] rock alive=", is_instance_valid(rock), " asteroids=", s.asteroids.size())
	await _wait(0.4)
	await shot("belt_shards")
	# the comet
	var c: Asteroid = s.belt.comet
	if c:
		sp.global_position = c.global_position + (c.global_position.normalized().cross(Vector3.UP).normalized() * 70.0) + Vector3(0, 20, 0)
		sp.look_at(c.global_position, Vector3.UP)
		sp.snap_camera()
		await _wait(2.5)
		await shot("belt_comet")


func _spacefight_tour() -> void:
	Game.new_game("scout", "Tester")
	await _wait(5.0)
	Game.last_hit_time = -100.0
	_scene().player._start_launch()
	await _wait(5.5)
	var s := _scene()
	var sp = s.player
	Game.invulnerable = true
	sp.velocity = Vector3.ZERO
	# a raider wing + gunship dead ahead, a swarm behind (off-screen arrows)
	var ahead: Vector3 = sp.global_position - sp.global_basis.z * 140.0
	var wing := []
	for t in ["raider", "raider", "gunship"]:
		var e: SpaceEnemy = s._spawn_pirate(t, 3, ahead + Vector3(randf_range(-30, 30), randf_range(-12, 12), randf_range(-20, 20)), ahead)
		e.aggro()
		wing.append(e)
	var behind: Vector3 = sp.global_position + sp.global_basis.z * 200.0
	for i in 3:
		s._spawn_pirate("swarmer", 3, behind + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)), behind).aggro()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(1.5)
	sp.look_at(wing[0].global_position, Vector3.UP)
	sp.snap_camera()
	await _wait(0.2)
	await shot("space_engage")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for i in 25:
		if is_instance_valid(wing[0]) and wing[0].is_alive():
			sp.look_at(wing[0].global_position, Vector3.UP)
		Input.action_press("fire")
		await _wait(0.05)
	await shot("space_cannons")
	Input.action_release("fire")
	sp._missile_cd = 0.0
	Game.energy = Game.max_energy()
	var tgt: SpaceEnemy = null
	for e in wing:
		if is_instance_valid(e) and e.is_alive():
			tgt = e
	if tgt:
		sp.look_at(tgt.global_position, Vector3.UP)
		sp._launch_missiles(tgt)
		await _wait(0.35)
		await shot("space_missiles")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(1.5)
	await shot("space_melee")
	# the flagship
	for e in s.space_enemies.duplicate():
		e.queue_free()
	s.space_enemies.clear()
	var m: SpaceEnemy = s._spawn_pirate("marauder", 6, sp.global_position - sp.global_basis.z * 170.0, sp.global_position)
	m.aggro()
	await _wait(2.5)
	sp.look_at(m.global_position, Vector3.UP)
	sp.snap_camera()
	await _wait(0.3)
	await shot("space_marauder")
	s._ambush()
	await _wait(0.8)
	await shot("space_ambush")


func _station_tour() -> void:
	Game.new_game("miner", "Tester")
	await _wait(5.0)
	var w := _scene()
	var p = w.player
	for e in w.enemies:
		e.set_physics_process(false)
	# sprint on open ground
	var d: Vector3 = w._find_land(Vector3(0.6, 0.5, 0.6).normalized())
	p.place_at(d, w.gen)
	p.cam_yaw = 2.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(0.5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(1.6)
	await shot("planet_sprint")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	Game.add_item("ferrite", 60, true)
	Game.add_item("cobalt", 25, true)
	Game.add_item("nickel", 30, true)
	Game.add_item("biofiber", 20, true)
	Game.last_hit_time = -100.0
	p._start_launch()
	await _wait(5.5)
	var s := _scene()
	var sp = s.player
	var st: OrbitalStation = s.station
	sp.global_position = st.global_position + Vector3(60, 18, 70)
	sp.look_at(st.global_position, Vector3.UP)
	sp.snap_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _wait(1.0)
	await shot("station_approach")
	sp.global_position = st.global_position + Vector3(0, 6, 36)
	sp.look_at(st.global_position, Vector3.UP)
	sp.snap_camera()
	await _wait(0.6)
	await shot("station_dock_prompt")
	s.hud.open_station_panel(Game.star_index)
	await _wait(0.4)
	await shot("station_sell")
	for tab in ["buy", "services", "contracts"]:
		s.hud._station_tab = tab
		s.hud._rebuild_town_panel()
		await _wait(0.3)
		await shot("station_" + tab)
	s.hud._station_tab = "sell"
	s.hud.close_panel()


func _outfit_tour() -> void:
	var looks := [
		{"robot": "scout", "look": {"head": "dome", "top": "flower", "pack": "wings", "shell": "ff7eb6", "accent": "f4f4f2", "glow": "ffd23f", "flame": "ff7eb6", "finish": "standard"}},
		{"robot": "miner", "look": {"head": "crest", "top": "horns", "pack": "rockets", "shell": "2a2d36", "accent": "e0453a", "glow": "e0453a", "flame": "ff9f43", "finish": "matte"}},
		{"robot": "engineer", "look": {"head": "mono", "top": "tophat", "pack": "ring", "shell": "39a0ff", "accent": "ffd23f", "glow": "6ee06a", "flame": "39a0ff", "finish": "neon"}},
		{"robot": "siphon", "look": {"head": "box", "top": "crown", "pack": "rockets", "shell": "f4f4f2", "accent": "b06bff", "glow": "b06bff", "flame": "b06bff", "finish": "gold"}},
	]
	Game.new_game("engineer", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.add_credits(5000, true)
	Game.add_item("scatter_mod", 1)
	w.hud.open_outfitter()
	await _wait(0.6)
	await shot("outfit_paint_default")
	var i := 0
	for L in looks:
		Game.robot_id = L.robot
		Game.appearance = L.look.duplicate()
		for slot in ["head", "top", "pack", "finish"]:
			Game.owned_cosmetics.append("%s:%s" % [slot, L.look[slot]])
		Game.appearance_changed.emit()
		w.hud._outfit_tab = ["paint", "parts", "parts", "loadout"][i]
		w.hud._preview_fly = i == 2
		w.hud._rebuild_town_panel()
		await _wait(0.8)
		await shot("outfit_%s" % L.robot)
		i += 1
	w.hud.close_panel()
	# the engineer look in the world, walking and flying
	Game.robot_id = "engineer"
	Game.appearance = looks[2].look.duplicate()
	Game.appearance_changed.emit()
	var p = w.player
	p.visual.setup("engineer")
	p.visual.apply_look(Game.appearance)
	p.cam_yaw = PI
	p.cam_pitch = -0.1
	p.spring.spring_length = 5.0
	await _wait(1.0)
	await shot("outfit_in_world")


## Fixed views used to compare graphics changes before/after.
func _gfx_view(w, dir: Vector3, yaw: float, pitch: float, arm: float, t: float, label: String) -> void:
	Game.play_time = t
	w.player.place_at(w._find_land(dir.normalized()), w.gen)
	w.player.cam_yaw = yaw
	w.player.cam_pitch = pitch
	w.player.spring.spring_length = arm
	await _wait(1.8)
	await shot(label)


func _gfx_tour() -> void:
	var tag: String = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "x"
	Game.new_game("scout", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	w.hud.visible = false
	w.hud.root.visible = false
	await _gfx_view(w, Vector3(0.5, 0.35, 0.8), 0.6, -0.12, 7.0, 40.0, tag + "_verdant_meadow")
	await _gfx_view(w, Vector3(0.1, 0.25, 1.0), 2.2, -0.3, 10.0, 40.0, tag + "_verdant_shore")
	await _gfx_view(w, Vector3(0.5, 0.35, 0.8), 3.4, 0.25, 6.0, 180.0, tag + "_verdant_sky")
	for pi in [2, 3, 1]:
		Game.land_dir = Vector3(0.3, 0.5, 0.8).normalized()
		Game.go_to_planet(0, pi)
		await _wait(6.0)
		w = _scene()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		for e in w.enemies:
			e.set_physics_process(false)
		w.hud.visible = false
		w.hud.root.visible = false
		await _gfx_view(w, Vector3(0.3, 0.5, 0.8), 1.0, -0.15, 8.0, 60.0, "%s_%s" % [tag, w.planet.biome])
	Game.last_hit_time = -100.0
	w.player._start_launch()
	await _wait(6.0)
	var s := _scene()
	s.hud.visible = false
	s.hud.root.visible = false
	var pl = s.planets[0]
	s.player.set_physics_process(false)
	s.player.global_position = pl.node.global_position + Vector3(0.4, 0.3, 1.0).normalized() * pl.radius * 2.4
	s.player.look_at(pl.node.global_position, Vector3.UP)
	s.player.snap_camera()
	await _wait(1.0)
	await shot(tag + "_orbit")


func _deep_tour() -> void:
	Game.new_game("engineer", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	var cave: Poi = null
	for p in w.pois:
		if p.type == "cave":
			cave = p
	await _look_at_from(w, w.player, cave.global_position, 22.0, -0.45, 12.0)
	await _wait(1.0)
	await shot("deep_cave_mouth")
	Game.skills.mining.level = 60
	Game.skill_tiers["mining"] = 3
	cave.open_cache()
	await _wait(3.5)
	var d := _scene()
	await shot("deep_lift")
	var pod: DigPod = d.pod
	Input.action_press("move_back")
	await _wait(5.0)
	Input.action_release("move_back")
	Input.action_press("move_left")
	await _wait(1.5)
	Input.action_release("move_left")
	await shot("deep_topsoil_tunnel")
	for band in [[45, "stone"], [80, "deepstone"], [110, "crystal"], [135, "magma"]]:
		var y: int = band[0]
		# carve a little pocket so the pod has somewhere to sit
		var cx := 12
		for yy in range(y - 2, y + 2):
			for xx in range(cx - 3, cx + 4):
				if d.get_cell(xx, yy) != d.BEDROCK:
					d.cells[d.idx(xx, yy)] = d.AIR
					d.redraw_cell(Vector2i(xx, yy))
		pod.position = d.cell_centre(Vector2i(cx, y))
		pod.velocity = Vector2.ZERO
		Input.action_press("move_back")
		await _wait(1.2)
		Input.action_release("move_back")
		await shot("deep_" + band[1])
	# a chamber from the outside
	var ch: Dictionary = d.chambers[2]
	pod.position = ch.centre + Vector2(-80, -10)
	await _wait(1.0)
	await shot("deep_chamber_outside")
	# every grotto theme
	var seen := {}
	for c in d.chambers:
		if seen.has(c.theme):
			continue
		seen[c.theme] = true
		Game.cave["chamber"] = c
		Game.cave["pod"] = [c.centre.x, c.centre.y]
		get_tree().change_scene_to_file("res://scenes/grotto.tscn")
		await _wait(3.0)
		var g := _scene()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		g.player.cam_pitch = -0.18
		await _wait(1.5)
		await shot("grotto_" + c.theme)


func _space_look(s, target: Vector3, off: Vector3) -> void:
	var sp = s.player
	sp.set_physics_process(false)
	sp.global_position = target + off
	sp.look_at(target, Vector3.UP)
	sp.snap_camera()
	await _wait(0.8)


func _circuit_tour() -> void:
	Game.new_game("scout", "Tester")
	await _wait(4.0)
	Game.go_to_space()
	await _wait(4.5)
	var s := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	await _space_look(s, s.giant.global_position, Vector3(0.3, 0.25, 1.0).normalized() * s.giant_r * 2.6)
	await shot("circuit_gas_giant")
	await _space_look(s, s.relay.global_position + Vector3(0, 19, 0), Vector3(40, 10, 70))
	await shot("circuit_relay_lit")
	await _space_look(s, s.derelicts[0].node.global_position, Vector3(30, 15, 60))
	await shot("circuit_derelict")
	var moon = null
	for p in s.planets:
		if Galaxy.is_moon(p.data):
			moon = p
	if moon:
		await _space_look(s, moon.node.global_position, Vector3(10, 8, 35))
		await shot("circuit_moon")
	s.hud.toggle_panel("sysmap")
	Game.waypoint = {"kind": "giant", "id": 0, "star": 0, "name": s.star.giant.name}
	await _wait(0.6)
	await shot("circuit_system_map")
	s.hud.close_panel()
	await _space_look(s, s.station.global_position, Vector3(0, 30, 160))
	await _wait(0.3)
	await shot("circuit_waypoint_hud")
	# a dark relay under guard
	Game.star_index = 3
	Game.arrived_by_warp = true
	Game.go_to_space()
	await _wait(4.5)
	s = _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _space_look(s, s.relay.global_position + Vector3(0, 19, 0), Vector3(50, 10, 80))
	await _wait(1.0)
	await shot("circuit_relay_dark")
	s.hud.toggle_panel("sysmap")
	s.hud.toggle_panel("map")
	await _wait(0.5)
	await shot("circuit_galaxy_map")
	s.hud.close_panel()
	# the Heart
	var forge := -1
	for st in Galaxy.stars:
		if st.get("legendary", "") == "forge":
			forge = st.index
	Game.star_index = forge
	Game.arrived_by_warp = true
	Game.go_to_space()
	await _wait(4.5)
	s = _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _space_look(s, s.heart.global_position, Vector3(60, 40, 230))
	await _wait(1.5)
	await shot("circuit_heart")
	# the three edge worlds from the ground
	for leg in ["forge", "tempest", "abyss"]:
		for st in Galaxy.stars:
			if st.get("legendary", "") == leg:
				var lp: Dictionary = st.planets.filter(func(p): return p.get("legendary", false))[0]
				Game.land_dir = Vector3(0.3, 0.6, 0.7).normalized()
				Game.go_to_planet(st.index, lp.index)
				await _wait(6.5)
				var w := _scene()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				for e in w.enemies:
					e.set_physics_process(false)
				w.player.cam_pitch = -0.08
				w.player.spring.spring_length = 9.0
				await _wait(1.5)
				await shot("edge_" + leg)



func _polish_tour() -> void:
	Sound.show_tips = true
	Sound.seen_tips = []
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(2.5)
	var m := _scene()
	await shot("pol_menu")
	m._show_overlay("load")
	await _wait(0.8)
	await shot("pol_load")
	m._show_overlay("settings")
	await _wait(0.8)
	await shot("pol_settings_menu")
	Game.new_game("scout", "Tester")
	await _wait(8.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	await shot("pol_tip_landing")
	# quest guidance: accept the first quest and look at the compass
	Game.accept_quest()
	await _wait(1.5)
	await shot("pol_quest_star")
	# fake some collection progress
	for pi in 3:
		var pl: Dictionary = Galaxy.planet(0, pi)
		Game.visited_planets.append(pl.key)
		for v in 3:
			var k := "%s:fauna:%d" % [pl.key, v]
			Game.record_scan(k, Galaxy.species_name(pl.seed, "fauna%d" % v) + " (fauna)")
		Game.note_world_species(pl.key, pl.name, pl.biome, 6)
	Game.kills = 30
	Game.check_milestones()
	await _wait(1.5)
	await shot("pol_milestone")
	var hud = w.hud
	for t in 3:
		hud._codex_tab = t
		hud.toggle_panel("quests")
		await _wait(0.6)
		await shot("pol_codex_%d" % t)
		hud.toggle_panel("quests")
		await _wait(0.2)
	hud.toggle_panel("settings")
	await _wait(0.6)
	await shot("pol_settings_pause")
	hud.toggle_panel("settings")
	# the Deep: lava + survey map
	var cave: Poi = null
	for p in w.pois:
		if p.type == "cave":
			cave = p
	Game.skills.mining.level = 60
	Game.skill_tiers["mining"] = 3
	cave.open_cache()
	await _wait(3.5)
	var d := _scene()
	var pod: DigPod = d.pod
	Input.action_press("move_back")
	await _wait(6.0)
	Input.action_release("move_back")
	await shot("pol_dig_tip_minimap")
	# find a lava pool and sit next to it
	var best := Vector2i(-1, -1)
	for y in range(100, d.H):
		for x in d.W:
			if d.get_cell(x, y) == d.LAVA and best.x < 0:
				best = Vector2i(x, y)
	if best.x >= 0:
		var cx := clampi(best.x + 3, 3, d.W - 4)
		for yy in range(best.y - 3, best.y + 1):
			for xx in range(cx - 2, cx + 3):
				if d.get_cell(xx, yy) != d.BEDROCK and d.get_cell(xx, yy) != d.LAVA:
					d.cells[d.idx(xx, yy)] = d.AIR
					d.dug[d.idx(xx, yy)] = 1
					d.redraw_cell(Vector2i(xx, yy))
		Game.upgrades.append("lava_plating")
		pod.position = d.cell_centre(Vector2i(cx, best.y - 1))
		pod.velocity = Vector2.ZERO
		await _wait(2.0)
		await shot("pol_dig_lava")



func _orbit_tour() -> void:
	Sound.show_tips = true
	Sound.seen_tips = []
	Game.new_game("scout", "Tester")
	await _wait(4.0)
	Game.add_item("deep_probe", 4, true)
	# space: the orbit prompt next to Cradle
	Game.planet_index = 0
	Game.go_to_space()
	await _wait(4.0)
	var sw := _scene()
	var p0: Dictionary = sw.planets[0]
	sw.player.global_position = p0.node.global_position + Vector3(0, 0, p0.radius * 1.6)
	sw.player.look_at(p0.node.global_position)
	await _wait(1.5)
	await shot("orb_space_prompt")
	for spec in [["planet", 0, 0], ["planet", 0, 3], ["giant", 0, -1]]:
		var info := Game.orbit_info(spec[0], spec[1], spec[2])
		Game.enter_orbit(info, Vector3(0, 0, 900))
		await _wait(3.2)
		var w := _scene()
		await shot("orb_%s_arrive" % info.biome)
		w._scan()
		await _wait(0.8)
		await shot("orb_%s_scanned" % info.biome)
		# drop toward the first gem
		var g: Dictionary = w.gems[0]
		var dist: float = w.R * 1.24 + 18.0 - (g.pos as Vector2).length()
		w.ship_angle = (g.pos as Vector2).angle() + w.rot + w.SPIN * dist / w.PROBE_SPEED
		w._launch()
		await _wait(dist / w.PROBE_SPEED * 0.6)
		await shot("orb_%s_probe" % info.biome)
		while w.probe_state == "down":
			await get_tree().process_frame
		await _wait(0.25)
		await shot("orb_%s_reel" % info.biome)
		while w.probe_state != "":
			await get_tree().process_frame
		await _wait(0.4)
		await shot("orb_%s_got" % info.biome)
		w._leave()
		await _wait(3.0)



func _mine_tour() -> void:
	Game.new_game("miner", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	for s in ["mining", "botany", "siphoning"]:
		Game.skills[s].level = 60
	var p = w.player
	for skill in ["mining", "botany", "siphoning"]:
		var node: ResourceNode = null
		for n in w._nodes:
			if is_instance_valid(n) and n.def.skill == skill:
				node = n
				break
		if node == null:
			continue
		await _look_at_from(w, p, node.global_position, 2.6, -0.2, 5.0)
		p.cam_yaw = 0.9
		Input.action_press("interact")
		await _wait(0.9)
		await shot("mine_%s_work" % skill)
		await _wait(0.5)
		await shot("mine_%s_late" % skill)
		var t := 0.0
		while is_instance_valid(node) and not node._dying and t < 8.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		await _wait(0.12)
		await shot("mine_%s_burst" % skill)
		Input.action_release("interact")
		await _wait(0.6)



func _sea_tour() -> void:
	Sound.show_tips = false
	Game.new_game("scout", "Tester")
	await _wait(5.0)
	var w := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	var gen: PlanetGen = w.gen
	var best := Vector3.ZERO
	var best_d := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	for i in 4000:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var depth := gen.sea_radius() - gen.surface_radius(d)
		if depth > best_d:
			best_d = depth
			best = d
	var p = w.player
	# at the shore looking out, then just under the surface, then deep
	p.global_position = best * (gen.sea_radius() - 1.2)
	p.cam_pitch = -0.1
	await _wait(1.5)
	await shot("sea3d_surface")
	p.global_position = best * (gen.sea_radius() - 4.0)
	p.cam_pitch = 0.05
	await _wait(1.5)
	await shot("sea3d_under")
	p.global_position = best * (gen.sea_radius() - best_d + 2.0)
	p.cam_pitch = -0.35
	Input.action_press("descend")
	await _wait(1.5)
	Input.action_release("descend")
	await shot("sea3d_deep_prompt")
	Game.enter_sea(p.global_position.normalized(), w.planet)
	await _wait(3.5)
	var s := _scene()
	var d: SeaDiver = s.diver
	await shot("sea2d_surface")
	for band in [[18, "sunlit"], [60, "twilight"], [110, "midnight"], [160, "abyss"]]:
		var y: int = band[0]
		d.position = Vector2(s.trench_x(y) * s.CS, y * s.CS)
		Game.upgrades.append("pressure_hull")
		# frame something interesting nearby if there is one
		for o in s.objects:
			if o.kind in ["kelp", "wreck", "vent", "clam"] and absf(o.pos.y / s.CS - y) < 12 and (o.kind != "kelp" or y < 40):
				d.position = o.pos + Vector2(-90, -60)
				if o.kind == "wreck":
					break
		for f in s.fauna:
			if f.kind in ["angler", "leviathan", "jelly"] and absf(f.pos.y / s.CS - y) < 25:
				f.pos = d.position + Vector2(160, 30)
				break
		await _wait(1.2)
		s._scan()
		await _wait(0.5)
		await shot("sea2d_" + band[1])



func _shadow_tour() -> void:
	Sound.show_tips = false
	var tag := OS.get_environment("TAG")
	for q in [0, 1, 2]:
		Sound.gfx_quality = q
		Sound.apply_gfx()
		Game.new_game("scout", "Tester")
		Game.star_index = 0
		Game.planet_index = 1
		Game.go_to_planet(0, 1)
		await _wait(6.0)
		var w := _scene()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.invulnerable = true
		for e in w.enemies:
			e.set_physics_process(false)
		# late afternoon so shadows are long
		Game.play_time = w.DAY_LENGTH * 0.18
		var p = w.player
		p.cam_pitch = -0.35
		p.cam_yaw = 2.6
		await _wait(1.5)
		await shot("shadow_q%d%s" % [q, tag])
		if q == 1:
			p.cam_yaw = 0.2
			p.cam_pitch = -0.08
			await _wait(1.0)
			await shot("shadow_q%d_view%s" % [q, tag])



func _atmo_tour() -> void:
	Sound.show_tips = false
	Sound.gfx_quality = 1
	# [planet, time of day (fraction), label, look toward sun]
	for spec in [[0, 0.24, "verdant_dusk", true], [1, 0.0, "dune_noon", false], [2, 0.55, "frost_night", false], [3, 0.26, "prism_sunset", true]]:
		Game.new_game("scout", "Tester")
		Game.go_to_planet(0, spec[0])
		await _wait(6.0)
		var w := _scene()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Game.invulnerable = true
		for e in w.enemies:
			e.set_physics_process(false)
		Game.play_time = w.DAY_LENGTH * float(spec[1])
		var p = w.player
		p.cam_pitch = -0.05
		await _wait(0.5)
		if spec[3]:
			# swing the camera to face the sun
			var up: Vector3 = p.global_position.normalized()
			var sd: Vector3 = w.sun_dir
			var flat := (sd - up * sd.dot(up)).normalized()
			var basef: Vector3 = p.ref_fwd
			p.cam_yaw = basef.signed_angle_to(flat, up)
			p.cam_pitch = 0.05
		await _wait(1.5)
		await shot("atmo_" + spec[2])



func _home_tour() -> void:
	Sound.show_tips = false
	Game.new_game("scout", "Tester")
	await _wait(4.0)
	for g in ["gem_verdant", "gem_dune", "gem_frost", "gem_giant"]:
		Game.add_item(g, 1, true)
	Game.vault = {"cobalt": 42, "lumen": 12, "fossil": 2, "gem_prism": 1, "biofiber": 60}
	Game.add_item("ancient_relic", 1, true)
	Game.add_item("ferrite", 30, true)
	Game.add_item("plasma", 12, true)
	for i in 23:
		Game.scanned.append("0:0:fake:%d" % i)
	Game.milestones = ["wanderer", "naturalist", "scrapper"]
	Game.visited_towns.append("0:0")
	Game._order_t = 0.0
	Game._update_orders(0.1)
	Game.send_mail("Tutor Vess", "Your Journeyman papers", "Word travels fast between trainers. Here's a little something for the road.", {"repair_kit": 2}, 120)
	Game.open_home()
	await _wait(1.5)
	var home: Node = null
	for c in get_tree().root.get_children():
		if c.has_method("leave"):
			home = c
	home._avatar_x = home._vs().x * 0.36
	await _wait(0.6)
	await shot("home_room")
	home._avatar_x = home._vs().x * 0.72
	await _wait(0.6)
	await shot("home_room_trophy")
	home._open_panel("vault")
	await _wait(0.5)
	await shot("home_vault")
	home._open_panel("inbox")
	await _wait(0.5)
	await shot("home_inbox_order")
	home._sel_mail = int(Game.inbox[Game.inbox.size() - 1].id)
	home._rebuild()
	await _wait(0.5)
	await shot("home_inbox_welcome")
	home._open_panel("trophy")
	await _wait(0.5)
	await shot("home_trophy")
	home._close_panel()
	# part 2: workers, decor, a wing
	Game.add_credits(20000, true)
	for id in ["lamp", "globe", "charging_pod", "arcade", "aquarium", "neon_home", "clock", "string_lights", "poster", "holo_fish", "star_chart", "crystal", "cactus"]:
		Game.decor_buy(id)
	var place := {"f0": "lamp", "f1": "globe", "f3": "charging_pod", "f4": "arcade", "w0": "neon_home", "w1": "clock", "w2": "string_lights", "w3": "poster", "w4": "holo_fish"}
	for k in place:
		Game.decor_place(k, place[k])
	Game.wing_buy()
	Game.wing_buy()
	Game.lit_relays = [0, 3, 5, 9, 12]
	Game.decor_place("f5", "aquarium")
	Game.decor_place("f6", "crystal")
	Game.decor_place("w5", "star_chart")
	for i in 2:
		Game.worker_compile()
	Game.visited_planets.append("0:1")
	Game.job_start(int(Game.workers[1].id), "gather", "0:1", 15)
	home._build_layout()
	home._avatar_x = 990.0
	home.scroll = 990.0 - home._vs().x * 0.5
	await _wait(1.0)
	await shot("home_dispatch_room")
	home._open_panel("dispatch")
	await _wait(0.5)
	await shot("home_dispatch_panel")
	home._open_panel("decor")
	await _wait(0.5)
	await shot("home_decor_panel")
	home._close_panel()
	Game.theme_buy("sunset")
	home._avatar_x = 2000.0
	await _wait(1.5)
	await shot("home_sunset")
	home._avatar_x = 2900.0
	await _wait(2.5)
	await shot("home_observatory")
	home._avatar_x = 3900.0
	await _wait(2.5)
	await shot("home_garden")



func _warp_tour() -> void:
	Sound.show_tips = false
	Game.new_game("scout", "Tester")
	await _wait(3.0)
	Game.visited_stars = [0, 1, 2]
	Game.interdictions = 1
	Game.go_to_space()
	await _wait(3.0)
	Game.start_warp(3, false)
	await _wait(1.8)
	var w := _scene()
	w.interdicted = true
	w.duration = 60.0
	w._plan_waves()
	await shot("warp_tunnel")
	w.elapsed = 13.0
	await _wait(3.5)
	await shot("warp_raiders_arrive")
	Input.action_press("fire")
	for k in 16:
		if not w.enemies.is_empty():
			var e: Dictionary = w.enemies[0]
			Input.warp_mouse(w.camera.unproject_position(e.pos))
		await _wait(0.1)
	await shot("warp_firefight")
	Input.action_release("fire")
	w.elapsed = 21.5
	await _wait(2.2)
	await shot("warp_mines")
	w.elapsed = 35.5
	await _wait(3.0)
	Input.action_press("fire")
	await _wait(0.6)
	await shot("warp_gunship")
	Input.action_release("fire")
	# a calm relay jump for the colours
	Game.start_warp(0, true)
	await _wait(2.5)
	await shot("warp_relay")



func _volcano_tour() -> void:
	Sound.show_tips = false
	Game.new_game("scout", "Tester")
	await _wait(3.0)
	var target := Vector2i(-1, -1)
	for s in Galaxy.stars.size():
		for p in Galaxy.star(s).planets:
			if Db.BIOMES[p.biome].get("lava", false) and not p.has("moon_of") and target.x < 0:
				target = Vector2i(s, p.index)
	Game.go_to_planet(target.x, target.y)
	await _wait(6.0)
	var pw := _scene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.invulnerable = true
	for e in pw.enemies:
		e.set_physics_process(false)
	var vent: Poi = null
	for p in pw.pois:
		if p.type == "volcano":
			vent = p
	await _look_at_from(pw, pw.player, vent.global_position, 40.0, -0.25, 14.0)
	await _wait(1.0)
	await shot("vol_vent_3d")
	vent.open_cache()
	await _wait(3.5)
	var w := _scene()
	var r: VolcanoRunner = w.runner
	await shot("vol_crater")
	for z in [1, 2, 3, 4]:
		for d in w.deposits:
			if int(d.zone) == z:
				r.position = d.pos + Vector2(-60, -20)
				break
		if z == 4:
			w.elapsed = 128.0
		await _wait(1.6)
		await shot("vol_zone_%d" % z)
	# a geyser mid-blast
	var g: Dictionary = w.geysers[2]
	w.elapsed = 40.0
	r.position = Vector2((g.x + 3.5) * w.CS, (g.y - 1) * w.CS)
	g.state = "blast"
	g.t = 1.3
	await _wait(0.5)
	await shot("vol_geyser")
	# zoomed out cutaway overview
	r.set_physics_process(false)
	var cam: Camera2D = r._cam
	cam.zoom = Vector2(0.16, 0.16)
	cam.position_smoothing_enabled = false
	r.position = Vector2(w.W * w.CS * 0.5, w.H * w.CS * 0.46)
	w.elapsed = 60.0
	await _wait(1.0)
	await shot("vol_cutaway")
