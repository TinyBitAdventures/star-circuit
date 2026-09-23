extends Node
## Headless: new system features + the full Relight-the-Circuit loop + the Heart.

func _ready() -> void:
	_go.call_deferred()


func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	var s0: Dictionary = Galaxy.star(0)
	print("[end] integrity: star0=%s planets=%s biomes=%s star3=%s belt=%d station=%s wants=%s" % [s0.name, s0.planets.slice(0, 4).map(func(p): return p.name), s0.planets.slice(0, 4).map(func(p): return p.biome), Galaxy.star(3).name, int(s0.belt.radius), s0.station.name, s0.station.demand])
	var leg := []
	for st in Galaxy.stars:
		if st.has("legendary"):
			leg.append("%s(%s, %.0f ly)" % [st.name, st.legendary, st.pos.length()])
	var moons := 0
	var giants := 0
	for st in Galaxy.stars:
		giants += 1 if st.has("giant") else 0
		for p in st.planets:
			moons += 1 if p.has("moon_of") else 0
	print("[end] legendary: ", leg, "  moons=", moons, " giants=", giants)
	Game.new_game("scout", "E")
	await _w(4.0)
	Game.go_to_space()
	await _w(4.5)
	var s := get_tree().current_scene
	Game.invulnerable = true
	print("[end] home space: planets=%d giant=%s derelicts=%d relay lit=%s objects=%d" % [s.planets.size(), s.giant != null, s.derelicts.size(), Game.relay_lit(0), s.system_objects().size()])
	# skim the giant
	var sp = s.player
	sp.set_physics_process(false)
	var p0 := Game.count("plasma") + Game.count("cryo_ice")
	sp.global_position = s.giant.global_position + Vector3(0, 0, s.giant_r * 1.15)
	await _w(3.0)
	print("[end] skimming: fuel ", p0, "->", Game.count("plasma") + Game.count("cryo_ice"))
	# system map + waypoint
	s.hud.toggle_panel("sysmap")
	await _w(0.3)
	Game.waypoint = {"kind": "relay", "id": 0, "star": 0, "name": "Circuit Relay"}
	s.hud.close_panel()
	print("[end] waypoint pos finite=", s.waypoint_pos().is_finite(), " marker=", s.threat_markers(sp.camera).filter(func(t): return t.get("waypoint", false)).size())
	# flare
	s._flare_t = 0.0
	sp.global_position = Vector3(0, 0, 700)
	var h0 := Game.hull
	Game.invulnerable = false
	await _w(9.5)
	print("[end] flare state=", s._flare_state, " sheltered=", s._sheltered(sp.global_position))
	await _w(3.0)
	print("[end] flare hull ", int(h0), "->", int(Game.hull))
	Game.invulnerable = true
	# board the derelict
	var d0: Node3D = s.derelicts[0].node
	sp.set_physics_process(true)
	sp.global_position = d0.global_position + Vector3(0, 0, 40)
	await _w(0.4)
	print("[end] derelict prompt: ", s.hud.prompt_label.text)
	s.space_interactable(sp.global_position).action.call()
	await _w(3.5)
	var g := get_tree().current_scene
	var ped: RelicPedestal = null
	for n in g._interactables:
		if n is RelicPedestal:
			ped = n
	print("[end] derelict interior: ", g.name, " theme=", g.theme, " pedestal=", ped != null, " item=", ped.item if ped else "")
	ped.interact(g.player)
	print("[end] crystal=", Game.count("resonance_crystal"), " boarded=", Game.boarded)
	Game.leave_chamber()
	await _w(4.0)
	s = get_tree().current_scene
	print("[end] back in space: ", s.name, " near derelict=", int(s.player.global_position.distance_to(s.derelicts[0].node.global_position)))
	# warp to star 3 and relight its relay
	Game.star_index = 3
	Game.arrived_by_warp = true
	Game.go_to_space()
	await _w(4.5)
	s = get_tree().current_scene
	sp = s.player
	print("[end] star3 relay lit=", Game.relay_lit(3), " guards=", s.relay_guards_alive())
	sp.global_position = s.relay.global_position + Vector3(0, 0, 50)
	await _w(0.3)
	print("[end] relay prompt (guarded): ", s.space_interactable(sp.global_position).text)
	for e in s.relay_guards:
		if is_instance_valid(e) and e.is_alive():
			e.take_hit(999999.0)
	Game.add_item("relay_coupler", 1, true, true)
	print("[end] relay prompt (clear): ", s.space_interactable(sp.global_position).text)
	s.space_interactable(sp.global_position).action.call()
	print("[end] lit relays=", Game.lit_relays)
	# galaxy map relay jump offer
	s.hud.toggle_panel("sysmap")
	s.hud.toggle_panel("map")
	await _w(0.3)
	s.hud.galaxy_map.selected = 0
	s.hud.galaxy_map._refresh_info()
	await _w(0.2)
	var btns := []
	for c in s.hud.galaxy_map._info.get_children():
		if c is Button:
			btns.append(c.text)
	print("[end] galaxy map buttons for home: ", btns)
	s.hud.close_panel()
	# the Heart
	var forge := -1
	for st in Galaxy.stars:
		if st.get("legendary", "") == "forge":
			forge = st.index
	Game.star_index = forge
	Game.arrived_by_warp = true
	Game.go_to_space()
	await _w(4.5)
	s = get_tree().current_scene
	sp = s.player
	var heart: SpaceEnemy = s.heart
	sp.global_position = heart.global_position + Vector3(0, 0, 200)
	await _w(1.5)
	var hp0 := heart.hp
	heart.take_hit(5000.0)
	print("[end] heart shielded while pylons live: hp ", int(hp0), "->", int(heart.hp), "  pylons=", s.pylons.size(), " heart state=", heart.state)
	for p in s.pylons:
		p.take_hit(99999.0)
	await _w(0.3)
	heart.take_hit(99999999.0)
	await _w(3.5)
	print("[end] heart defeated=", Game.heart_defeated, " panel=", s.hud.current_panel, " quest=", Game.current_quest().get("id", "done"))
	# legendary landing
	var lp: Dictionary = Galaxy.star(forge).planets.filter(func(p): return p.get("legendary", false))[0]
	Game.land_dir = Vector3(0.2, 0.9, 0.3).normalized()
	Game.go_to_planet(forge, lp.index)
	await _w(6.0)
	var w := get_tree().current_scene
	print("[end] landed on ", w.planet.name, " biome=", w.planet.biome, " legend shards=", Game.count("legend_shard"))
	get_tree().quit()
