extends Node
## Headless check of combat: statuses (burn, chill, freeze, shock) on drones and
## on the player, and the drone behaviours (melee, ranged, slam).


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## A point on the surface this many metres from the player, off to one side.
func _near(w: Node3D, metres: float, side := 0.0) -> Vector3:
	var up: Vector3 = w.player.global_position.normalized()
	var b := PlanetGen.align_basis(up, side)
	return (up + b.z * metres / w.gen.radius).normalized()


func _clear(w: Node3D) -> void:
	for e in w.enemies.duplicate():
		w.enemies.erase(e)
		e.queue_free()


func _run() -> void:
	Sound.show_tips = false
	Game.new_game("miner", "Combat")
	await _wait(4.0)
	var w := get_tree().current_scene
	_clear(w)
	await _wait(0.2)
	Game.invulnerable = true

	# burn: 10 a second for 3 seconds
	var a: Enemy = w._spawn_enemy("brute", 5, _near(w, 30.0), 900)
	var hp0 := a.hp
	a.apply_status("burn", 3.0, 10.0)
	await _wait(3.3)
	print("[combat] burn: hp %d -> %d (want about -30) burning=%s" % [hp0, a.hp, a.status.burning()])

	# shock: +25% damage taken
	a.apply_status("shock", 2.0)
	var h1 := a.hp
	a.take_hit(40.0)
	print("[combat] shock: took %d from a 40 hit (want 50)" % int(h1 - a.hp))
	_clear(w)
	await _wait(0.2)

	# chill slows, a fourth stack freezes, then a short immunity
	var fast: Enemy = w._spawn_enemy("scrapper", 3, _near(w, 18.0, 0.0), 901)
	var slow: Enemy = w._spawn_enemy("scrapper", 3, _near(w, 18.0, PI), 902)
	fast.aggro()
	slow.aggro()
	slow.apply_status("chill", 5.0, 3.0)
	var f0 := fast.global_position
	var s0 := slow.global_position
	await _wait(1.0)
	var fd := fast.global_position.distance_to(f0)
	var sd := slow.global_position.distance_to(s0)
	print("[combat] chill x%d: moved %.1f vs %.1f m (ratio %.2f, want about %.2f)" % [slow.status.chill, sd, fd, sd / maxf(fd, 0.01), slow.status.speed_mult()])
	var got := slow.apply_status("chill", 5.0, 1.0)
	var p0 := slow.global_position
	await _wait(1.0)
	print("[combat] freeze: got=%s frozen=%s moved %.2f m while frozen" % [got, slow.status.frozen(), slow.global_position.distance_to(p0)])
	await _wait(0.8)
	var again := slow.apply_status("chill", 5.0, 4.0)
	print("[combat] thawed: frozen=%s refreeze right away=%s" % [slow.status.frozen(), again == "freeze"])
	# leashing clears it all
	slow.apply_status("burn", 5.0, 1.0)
	slow._leash()
	print("[combat] leash clears: any=%s" % slow.status.any())
	_clear(w)
	await _wait(0.2)

	# the player: chilled, frozen (briefly), burning
	var pl: Node3D = w.player
	Game.invulnerable = false
	Game.hull = Game.max_hull()
	w.damage_player(1.0, null, "chill", 4.0, 2.0)
	print("[combat] player chill: stacks=%d speed x%.2f hud='%s'" % [pl.status.chill, pl.status.speed_mult(), w.hud.effects_label.text])
	w.damage_player(1.0, null, "chill", 4.0, 2.0)
	var frozen_for: float = pl.status.frozen_t
	print("[combat] player freeze: frozen=%s for %.2fs (drones get %.1fs)" % [pl.status.frozen(), frozen_for, Status.FREEZE_TIME])
	await _wait(1.3)
	print("[combat] player thawed=%s" % (not pl.status.frozen()))
	var hull0 := Game.hull
	w.damage_player(0.0, null, "burn", 2.0, 10.0)
	await _wait(2.3)
	print("[combat] player burn: hull %d -> %d (want about -20) hud visible=%s" % [hull0, Game.hull, w.hud.effects_label.visible])

	# the three drones still fight the way they did
	Game.hull = Game.max_hull()
	var sc: Enemy = w._spawn_enemy("scrapper", 1, _near(w, 5.0), 910)
	sc.aggro()
	await _wait(2.5)
	print("[combat] scrapper melee: hull %d -> %d" % [Game.max_hull(), Game.hull])
	_clear(w)
	Game.hull = Game.max_hull()
	var se: Enemy = w._spawn_enemy("sentinel", 1, _near(w, 14.0), 911)
	se.aggro()
	await _wait(4.0)
	print("[combat] sentinel bolts: hull %d -> %d" % [Game.max_hull(), Game.hull])
	_clear(w)
	Game.hull = Game.max_hull()
	var br: Enemy = w._spawn_enemy("brute", 1, _near(w, 3.0), 912)
	br.aggro()
	var raised := false
	for i in 40:
		await _wait(0.1)
		raised = raised or br.behavior.raised()
	print("[combat] brute slam: raised=%s hull %d -> %d" % [raised, Game.max_hull(), Game.hull])
	_clear(w)
	await _biome_foes(w)
	await _biome_foes_2()
	get_tree().quit()


func _biome_foes(w: Node3D) -> void:
	var pl: Node3D = w.player
	# Thornback: stand in the lane and get run over
	Game.hull = Game.max_hull()
	var tb: Enemy = w._spawn_enemy("thornback", 2, _near(w, 14.0), 920)
	tb.aggro()
	var phases := {}
	for i in 60:
		await _wait(0.1)
		phases[tb.behavior.phase] = true
	print("[combat] thornback charge: phases=%s hull %d -> %d" % [phases.keys(), Game.max_hull(), Game.hull])
	# ...and sidestep the next one: it ends up stunned and takes extra damage
	tb.behavior.phase = ""
	tb._atk_cd = 0.0
	var stunned := false
	for i in 60:
		await _wait(0.05)
		if tb.behavior.phase == "windup" and tb.behavior._t < 0.15:
			var up: Vector3 = pl.global_position.normalized()
			pl.global_position = w.gen.surface_point((up + tb.global_basis.x * 12.0 / w.gen.radius).normalized()) + up * 0.5
		if tb.behavior.phase == "stunned":
			stunned = true
			break
	var h0 := tb.hp
	tb.take_hit(50.0)
	print("[combat] thornback dodged: stunned=%s took %d from 50 (want 80)" % [stunned, int(h0 - tb.hp)])
	_clear(w)
	await _wait(0.2)

	# Dune Lurker: dives (can't be hit), tunnels over, erupts under you
	Game.hull = Game.max_hull()
	var lk: Enemy = w._spawn_enemy("lurker", 2, _near(w, 12.0), 921)
	lk.aggro()
	var hits: Array = []
	var log_hit := func(a: float): hits.append("%s:%d" % [lk.behavior.phase, int(a)])
	Game.player_damaged.connect(log_hit)
	var seen := {}
	var unhittable := false
	for i in 120:
		await _wait(0.1)
		seen[lk.behavior.phase] = true
		if lk.behavior.phase == "under" and lk.collision_layer == 0:
			unhittable = true
		if seen.has("erupting") and lk.behavior.phase == "up":
			break
	Game.player_damaged.disconnect(log_hit)
	print("[combat] lurker: phases=%s unhittable under=%s hull %d -> %d hits=%s" % [seen.keys(), unhittable, Game.max_hull(), Game.hull, hits])
	_clear(w)
	await _wait(0.2)

	# Frost Warden: shield from the front, open from behind; Rail and fire get through; can't be chilled
	var wd: Enemy = w._spawn_enemy("warden", 3, _near(w, 30.0), 922)
	await _wait(0.2)
	var front: Vector3 = wd.global_position + wd.heading * 10.0
	var back: Vector3 = wd.global_position - wd.heading * 10.0
	var hp1 := wd.hp
	wd.take_hit(100.0, false, "kinetic", front)
	var f_dmg := hp1 - wd.hp
	hp1 = wd.hp
	wd.hp = wd.max_hp
	hp1 = wd.hp
	wd.take_hit(100.0, false, "kinetic", back)
	var b_dmg := hp1 - wd.hp
	hp1 = wd.hp
	wd.hp = wd.max_hp
	hp1 = wd.hp
	wd.take_hit(100.0, false, "pierce", front)
	var p_dmg := hp1 - wd.hp
	hp1 = wd.hp
	wd.hp = wd.max_hp
	hp1 = wd.hp
	wd.take_hit(100.0, false, "fire", front)
	var fire_dmg := hp1 - wd.hp
	print("[combat] warden shield: front=%d back=%d rail=%d fire=%d chill=%s" % [f_dmg, b_dmg, p_dmg, fire_dmg, "resisted" if wd.apply_status("chill", 3.0, 4.0) == "" else "took"])
	# its bolts chill you
	Game.hull = Game.max_hull()
	pl.status.clear()
	wd.hp = wd.max_hp
	wd.aggro()
	var chilled := false
	var trace := []
	for i in 140:
		await _wait(0.1)
		if i % 10 == 0:
			trace.append("%s d=%d cd=%.1f" % [wd.state, int(wd.global_position.distance_to(pl.global_position)), wd._atk_cd])
		if pl.status.chill > 0 or pl.status.frozen():
			chilled = true
			break
	print("[combat] warden trace ", trace)
	print("[combat] warden bolts chill the player=%s" % chilled)
	# up close, every fourth attack is a frost nova
	pl.status.clear()
	pl.place_at((wd.dir + (pl.global_position.normalized() - wd.dir).normalized() * 3.0 / w.gen.radius).normalized(), w.gen)
	wd.behavior._shots = 3
	wd._atk_cd = 0.0
	var nova_seen := false
	for i in 40:
		await _wait(0.05)
		nova_seen = nova_seen or wd.behavior._nova_t >= 0.0
		if nova_seen and wd.behavior._nova_t < 0.0:
			break
	print("[combat] warden nova: seen=%s player chill=%d frozen=%s" % [nova_seen, pl.status.chill, pl.status.frozen()])
	_clear(w)

	# signature camps turn up on their own worlds (never on the home world)
	var planets := {}
	for b in Db.BIOME_FOES:
		planets[b] = Vector2i(-1, -1)
	for si in range(1, Galaxy.stars.size()):
		for p in Galaxy.star(si).planets:
			if planets.has(p.biome) and planets[p.biome].x < 0 and not p.has("moon_of"):
				planets[p.biome] = Vector2i(si, p.index)
	var counts := {}
	for b in planets:
		var at: Vector2i = planets[b]
		Game.go_to_planet(at.x, at.y)
		await _wait(5.0)
		var world2 := get_tree().current_scene
		var foe: String = Db.BIOME_FOES[b]
		counts[b] = "%d %s of %d" % [world2.enemies.filter(func(e): return e.type == foe).size(), foe, world2.enemies.size()]
	print("[combat] signature camps: ", counts)



func _count(w: Node3D, node_class: String) -> int:
	return w.get_children().filter(func(c): return c.get_class() == "Node3D" and c.get_script() and c.get_script().get_global_name() == node_class).size()


func _biome_foes_2() -> void:
	Game.go_to_planet(0, 0)
	await _wait(4.5)
	var w := get_tree().current_scene
	_clear(w)
	await _wait(0.2)
	var pl: Node3D = w.player
	Game.invulnerable = false
	pl.status.clear()

	# Cinder Mites: rush in, fuse, burst into flame; their own burst pays nothing
	Game.hull = Game.max_hull()
	var k0 := Game.kills
	var mites: Array = []
	for i in 3:
		mites.append(w._spawn_enemy("mite", 2, _near(w, 9.0, i * 2.0), 930))
	mites[0].aggro()
	var patch_seen := false
	for i in 60:
		await _wait(0.1)
		patch_seen = patch_seen or _count(w, "HazardPatch") > 0
		if mites.all(func(m): return not is_instance_valid(m) or not m.is_alive()):
			break
	print("[combat] mites: all burst=%s kills +%d (want 0) hull %d -> %d burning=%s patch=%s" % [mites.all(func(m): return not is_instance_valid(m) or not m.is_alive()), Game.kills - k0, Game.max_hull(), Game.hull, pl.status.burning(), patch_seen])
	var shot: Enemy = w._spawn_enemy("mite", 2, _near(w, 20.0), 931)
	await _wait(0.1)
	var patches := _count(w, "HazardPatch")
	shot.take_hit(999.0)
	await _wait(0.1)
	print("[combat] mite shot down: kills +%d pops a patch=%s" % [Game.kills - k0, _count(w, "HazardPatch") > patches])
	_clear(w)
	await _wait(3.5)

	# Smelter: armour, then a venting window; mortar shells land where you are
	Game.hull = Game.max_hull()
	pl.status.clear()
	var sm: Enemy = w._spawn_enemy("smelter", 2, _near(w, 18.0), 932)
	await _wait(0.2)
	var h := sm.hp
	sm.take_hit(50.0)
	var closed := (h - sm.hp) * 2.0
	sm.behavior._vent = 1.0
	h = sm.hp
	sm.take_hit(50.0)
	var open := (h - sm.hp) * 2.0
	sm.behavior._vent = -1.0
	sm.hp = sm.max_hp
	sm.aggro()
	var vented := false
	var hull0 := Game.hull
	for i in 120:
		await _wait(0.1)
		vented = vented or sm.behavior.venting()
		if vented and Game.hull < hull0:
			break
	print("[combat] smelter: armour took %d of 100, venting took %d; vented=%s hull %d -> %d" % [closed, open, vented, hull0, Game.hull])
	_clear(w)
	await _wait(0.5)

	# Storm Kite: flies high, calls lightning that shocks you
	Game.hull = Game.max_hull()
	pl.status.clear()
	var kt: Enemy = w._spawn_enemy("kite", 2, _near(w, 14.0), 933)
	kt.aggro()
	var shocked := false
	var height := 0.0
	for i in 80:
		await _wait(0.1)
		height = maxf(height, kt.global_position.length() - w.gen.surface_radius(kt.dir))
		if pl.status.shocked():
			shocked = true
			break
	print("[combat] kite: flies %.1f m up, strike shocked the player=%s hull %d -> %d" % [height, shocked, Game.max_hull(), Game.hull])
	_clear(w)
	await _wait(0.5)

	# Refractor: reflects while glowing, takes hits otherwise
	Game.hull = Game.max_hull()
	var rf: Enemy = w._spawn_enemy("refractor", 2, _near(w, 16.0), 934)
	await _wait(0.2)
	rf.behavior._glow = 1.5
	h = rf.hp
	var hull1 := Game.hull
	rf.take_hit(60.0, false, "kinetic", pl.global_position)
	var glow_dmg := h - rf.hp
	await _wait(1.2)
	var reflected := Game.hull < hull1
	rf.behavior._glow = 0.0
	h = rf.hp
	rf.take_hit(60.0, false, "kinetic", pl.global_position)
	print("[combat] refractor: glowing took %d (want 0), reflection hit me=%s; dim took %d" % [glow_dmg, reflected, h - rf.hp])
	_clear(w)

	# Void Stalker: cloaked, a scan reveals and exposes it, then it pounces
	Game.hull = Game.max_hull()
	var st: Enemy = w._spawn_enemy("stalker", 2, _near(w, 15.0), 935)
	await _wait(0.3)
	var hidden_at_start: bool = not st.behavior.visible_to_player()
	w.scan(pl.global_position, 30.0)
	print("[combat] bestiary: stalker logged by scan=%s traits='%s' milestone metric=%d" % [Game.bestiary.get("stalker", {}).get("scanned", false), Db.foe_traits("stalker"), Game.metric("bestiary")])
	h = st.hp
	st.take_hit(40.0)
	var exposed_dmg := h - st.hp
	st.hp = st.max_hp
	var leapt := false
	hull0 = Game.hull
	for i in 60:
		await _wait(0.05)
		leapt = leapt or st.behavior.phase == "leap"
		if leapt and st.behavior.phase == "recover":
			break
	print("[combat] stalker: cloaked=%s scan exposed hit took %d of 40 (want 60) pounced=%s hull %d -> %d" % [hidden_at_start, exposed_dmg, leapt, hull0, Game.hull])
	_clear(w)
	await _wait(0.3)

	# Spore Hive: breeds sporelings, puffs a slowing cloud, brood withers when it dies
	Game.hull = Game.max_hull()
	pl.status.clear()
	var hv: Enemy = w._spawn_enemy("hive", 2, _near(w, 7.0), 936)
	hv.aggro()
	var chilled := false
	for i in 90:
		await _wait(0.1)
		chilled = chilled or pl.status.chill > 0 or pl.status.frozen()
	var brood: int = hv.behavior.brood.filter(func(b): return is_instance_valid(b) and b.is_alive()).size()
	var k1 := Game.kills
	hv.take_hit(99999.0, false, "fire")
	await _wait(0.4)
	var alive: int = w.enemies.filter(func(e): return e.type == "sporeling" and e.is_alive()).size()
	print("[combat] bestiary: hive kills=%d scanned=%s" % [int(Game.bestiary.get("hive", {}).get("kills", 0)), Game.bestiary.get("hive", {}).get("scanned", false)])
	print("[combat] hive: brood=%d spore cloud chilled=%s; killed: kills +%d brood left=%d" % [brood, chilled, Game.kills - k1, alive])
	_clear(w)
