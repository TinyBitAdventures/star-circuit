extends Node
## Headless multiplayer check against the real Go server (built from ../star-circuit-server):
## join, a scripted second player "Bob" appears on the same planet, chat,
## gifts both ways, crates dropped and picked up (first come first served),
## both flying in the same system, leaving.

var _pid := -1
var _port := 0
var bob: WebSocketPeer
var bob_id := 0
var bob_in: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		_bob_poll()
		t += get_process_delta_time()


func _bob_poll() -> void:
	if bob == null:
		return
	bob.poll()
	while bob.get_available_packet_count() > 0:
		var m = JSON.parse_string(bob.get_packet().get_string_from_utf8())
		if m is Dictionary:
			bob_in.append(m)
			if m.t == "welcome":
				bob_id = int(m.id)


func _bob_send(m: Dictionary) -> void:
	bob.send_text(JSON.stringify(m))


func _bob_got(t: String) -> Dictionary:
	for m in bob_in:
		if m.t == t:
			bob_in.erase(m)
			return m
	return {}


func _bob_wait(t: String, secs := 3.0) -> Dictionary:
	var el := 0.0
	while el < secs:
		var m := _bob_got(t)
		if not m.is_empty():
			return m
		await _wait(0.05)
		el += 0.05
	return {}


func _run() -> void:
	Sound.show_tips = false
	_port = 17000 + randi() % 1000
	# the server lives in its own repo, checked out next to this one
	var dir := OS.get_environment("STAR_CIRCUIT_SERVER_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://").path_join("../../star-circuit-server").simplify_path()
	# build first and run the binary itself, so killing it really stops the server
	var bin := OS.get_cache_dir().path_join("star-circuit-server-test")
	var out := []
	var rc := OS.execute("go", ["-C", dir, "build", "-o", bin, "."], out, true)
	if rc != 0:
		print("[net] server build failed: ", out)
		get_tree().quit()
		return
	_pid = OS.create_process(bin, ["-addr", "127.0.0.1:%d" % _port, "-data", "", "-motd", "Welcome to the test server",
		"-name", "Test Server", "-discovery-port", str(_port + 1)])
	print("[net] server pid=", _pid, " port=", _port)
	Game.new_game("scout", "Austin")
	await _wait(4.0)
	# the server may still be compiling: keep trying for a while
	for i in 30:
		Net.join("127.0.0.1:%d" % _port)
		await _wait(1.0)
		if Net.is_online():
			break
	print("[net] online=", Net.is_online(), " as ", Net.my_name, " id=", Net.my_id, " motd=", Net.server_motd)
	# LAN discovery: the server answers our probe (on its own test port)
	Net.discovery_port = _port + 1
	Net.lan_scan()
	await _wait(Net.LAN_WAIT + 0.3)
	var found := {}
	for k in Net.lan_servers:
		if int(k.get_slice(":", 1)) == _port:
			found = Net.lan_servers[k]
	print("[net] lan: scanning=", Net.lan_scanning, " found=", found.get("name", ""), " address=", found.get("address", ""), " here=", found.get("here", false), " online=", found.get("online", -1), " protocol ok=", found.get("protocol", "") == Net.PROTOCOL)
	var pw := get_tree().current_scene
	# Bob joins and stands next to us
	bob = WebSocketPeer.new()
	bob.connect_to_url("ws://127.0.0.1:%d/ws" % _port)
	await _wait(0.5)
	_bob_send({"t": "hello", "name": "Bob", "robot": "miner", "version": Net.PROTOCOL, "look": {"shell": "#ff8a5b"}})
	await _bob_wait("welcome")
	var me: Vector3 = pw.player.global_position
	var up := me.normalized()
	var side := PlanetGen.align_basis(up).x
	var bob_pos: Vector3 = pw.gen.surface_point((me + side * 4.0).normalized()) + up * 0.1
	for i in 5:
		_bob_send({"t": "state", "scene": "planet", "star": Game.star_index, "planet": Game.planet_index, "pos": Net._arr(bob_pos), "fwd": Net._arr(side), "anim": "walk"})
		await _wait(0.15)
	await _wait(0.5)
	var av: RemotePlayer = pw.net_view.avatars.get(bob_id)
	print("[net] bob avatar=", av != null, " dist from sent pos=", snappedf(av.global_position.distance_to(bob_pos), 0.01) if av else -1.0, " robot=", av.visual.robot_id if av else "", " where=", Net.where_text(bob_id))
	var marks: Array = pw.compass_markers().filter(func(m): return m.label == "Bob")
	var msg := Net.plot_course(bob_id)
	print("[net] friend marks: compass has bob=", marks.size() == 1, " plot: '", msg, "' waypoint=", Game.waypoint.get("kind", ""), " galaxy=", Net.friends_by_star())
	# Bob sees our state too
	var st := await _bob_wait("state")
	print("[net] bob sees us: scene=", st.get("scene", ""), " planet=", st.get("planet", -1), " near=", Net._vec(st.get("pos")).distance_to(me) < 20.0)
	# chat
	_bob_send({"t": "chat", "text": "hi Austin"})
	await _wait(0.4)
	var last: Dictionary = Net.chat_log[Net.chat_log.size() - 1] if not Net.chat_log.is_empty() else {}
	print("[net] chat: ", last.get("name", ""), ": ", last.get("text", ""))
	# Bob gives us ferrite
	var fe0 := Game.count("ferrite")
	_bob_send({"t": "give", "to": Net.my_id, "item": "ferrite", "qty": 7})
	await _wait(0.4)
	print("[net] gift from bob: ferrite ", fe0, " -> ", Game.count("ferrite"))
	# we give Bob some back; upgrades can't be given
	var ok := Net.give(bob_id, "ferrite", 3)
	var g := await _bob_wait("gift")
	print("[net] give to bob: ok=", ok, " bob got ", g.get("qty", 0), " ", g.get("item", ""), " from ", g.get("name", ""), "; ferrite now ", Game.count("ferrite"))
	Game.add_item("drill_mk2", 1, true)
	print("[net] give an upgrade refused=", not Net.give(bob_id, "drill_mk2", 1))
	# giving faster than the server allows: the refused gifts come back
	await _wait(2.5)
	Game.add_item("ferrite", 20, true)
	var fe1 := Game.count("ferrite")
	for i in 12:
		Net.give(bob_id, "ferrite", 1)
	var removed := fe1 - Game.count("ferrite")
	await _wait(0.6)
	var bob_gifts := 0
	for m in bob_in:
		if m.t == "gift":
			bob_gifts += 1
	bob_in = bob_in.filter(func(m): return m.t != "gift")
	print("[net] give flood: sent 12, removed ", removed, ", bob got ", bob_gifts, ", refunded ", Game.count("ferrite") - (fe1 - removed), " ferrite ", fe1, " -> ", Game.count("ferrite"), " kept=", Game.count("ferrite") == fe1 - bob_gifts)
	# we drop a crate; Bob grabs it
	Game.add_item("biofiber", 5, true)
	var dropped := Net.drop_here({"biofiber": 2})
	var da := await _bob_wait("drop_add")
	await _wait(0.3)
	var did := int(da.get("drop", {}).get("id", 0))
	print("[net] drop: ok=", dropped, " biofiber left=", Game.count("biofiber"), " bob sees crate=", did > 0, " local crate=", pw.net_view.crates.has(did))
	_bob_send({"t": "pickup", "id": did})
	var po := await _bob_wait("pickup_ok")
	await _wait(0.3)
	print("[net] bob picked up ", po.get("items", {}), "; local crate gone=", not pw.net_view.crates.has(did))
	# Bob drops a crate beside us and we pick it up with E
	_bob_send({"t": "drop", "star": Game.star_index, "planet": Game.planet_index, "pos": Net._arr(pw.gen.surface_point((me + side * 2.0).normalized())), "items": {"lumen": 3}})
	await _wait(0.5)
	var crate: NetCrate = null
	for id in pw.net_view.crates:
		crate = pw.net_view.crates[id]
	var near: Node = pw.nearest_interactable(crate.global_position, 1.0) if crate else null
	print("[net] bob's crate here=", crate != null, " interactable=", near == crate, " prompt=", crate.interact_info().text if crate else "")
	var lu0 := Game.count("lumen")
	crate.interact(pw.player)
	await _wait(0.5)
	print("[net] picked up: lumen ", lu0, " -> ", Game.count("lumen"), " crates left=", pw.net_view.crates.size())
	# ---- shared fights: Bob in our planet room, fighting the same drone
	var room := "planet:%d:%d" % [Game.star_index, Game.planet_index]
	_bob_send({"t": "state", "scene": "planet", "room": room, "star": Game.star_index, "planet": Game.planet_index, "pos": Net._arr(bob_pos), "fwd": Net._arr(side), "anim": "idle"})
	await _wait(0.3)
	var foe: Enemy = null
	for e in pw.enemies:
		if e.is_alive():
			foe = e
			break
	var hp0: float = foe.hp
	_bob_send({"t": "ev", "room": room, "kind": "hits", "data": {"h": {foe.nid: 10.0}}})
	await _wait(0.3)
	print("[net] shared hit: ", foe.nid, " hp ", snappedf(hp0, 0.1), " -> ", snappedf(foe.hp, 0.1))
	var xp0 := Game.xp
	var k0 := Game.kills
	var kill := {"nid": foe.nid, "type": foe.type, "lvl": foe.level, "elite": foe.elite, "pos": Net._arr(pw.player.global_position)}
	_bob_send({"t": "ev", "room": room, "kind": "kill", "data": kill})
	await _wait(0.3)
	print("[net] shared kill: foe dead=", not foe.is_alive(), " kills ", k0, " -> ", Game.kills, " xp ", xp0, " -> ", Game.xp)
	_bob_send({"t": "ev", "room": room, "kind": "kill", "data": kill})
	await _wait(0.3)
	print("[net] duplicate kill paid again=", Game.kills != k0 + 1)
	# our hits and Bob's finish a drone off together and nobody sends a kill: it still pays, once
	var foe3: Enemy = null
	for e in pw.enemies:
		if is_instance_valid(e) and e.is_alive() and e != foe:
			foe3 = e
			break
	var k1 := Game.kills
	var kill3 := {"nid": foe3.nid, "type": foe3.type, "lvl": foe3.level, "elite": foe3.elite, "pos": Net._arr(pw.player.global_position)}
	foe3.take_hit(1.0)
	_bob_send({"t": "ev", "room": room, "kind": "hits", "data": {"h": {kill3.nid: 999999.0}}})
	await _wait(1.0)
	_bob_send({"t": "ev", "room": room, "kind": "kill", "data": kill3})
	await _wait(0.3)
	print("[net] hit-kill with no kill message: kills ", k1, " -> ", Game.kills, " (want +1)")
	var kf := Game.kills
	var far := kill.duplicate()
	far.nid = "x:far"
	far.pos = Net._arr(pw.player.global_position + up * 500.0)
	_bob_send({"t": "ev", "room": room, "kind": "kill", "data": far})
	await _wait(0.3)
	print("[net] far kill shared=", Game.kills != kf)
	# our hits and kills reach Bob
	var foe2: Enemy = null
	for e in pw.enemies:
		if is_instance_valid(e) and e.is_alive() and e != foe:
			foe2 = e
			break
	bob_in.clear()
	foe2.take_hit(5.0)
	var hits := await _bob_wait("ev")
	foe2.take_hit(999999.0)
	await _wait(0.3)
	var kev := {}
	for m in bob_in:
		if m.t == "ev" and m.kind == "kill":
			kev = m
	print("[net] bob got hits=", hits.get("kind", ""), " ", hits.get("data", {}).get("h", {}), " kill=", kev.get("data", {}).get("nid", "") == foe2.nid)
	# ---- co-op: a drone goes after Bob's robot when he's the one next to it, and can't hurt us from there
	var home_pos: Vector3 = pw.player.global_position
	var e4: Enemy = null
	for e in pw.enemies:
		if is_instance_valid(e) and e.is_alive() and e.state == "idle" and e.def.style == "melee":
			e4 = e
			break
	if e4 == null:
		e4 = pw._spawn_enemy("scrapper", 3, pw.player.global_position.normalized(), -1)
	var eu: Vector3 = e4.global_position.normalized()
	var eb := PlanetGen.align_basis(eu, 0.0)
	# park our robot somewhere quiet: no drone within 70 m
	var park := eu
	for k in 24:
		var cand: Vector3 = (eu + (eb.x * cos(k * 0.9) + eb.z * sin(k * 0.9)) * (140.0 + k * 20.0) / pw.gen.radius).normalized()
		var cp: Vector3 = pw.gen.surface_point(cand)
		var clear := true
		for e in pw.enemies:
			if is_instance_valid(e) and e.is_alive() and e.global_position.distance_to(cp) < 70.0:
				clear = false
		if clear:
			park = cand
			break
	pw.player.global_position = pw.gen.surface_point(park) + park * 0.5
	var hull0 := Game.hull
	for i in 30:
		_bob_send({"t": "state", "scene": "planet", "room": room, "star": Game.star_index, "planet": Game.planet_index,
			"pos": Net._arr(e4.global_position + eb.z * 1.5), "fwd": Net._arr(-eb.z), "anim": "idle"})
		await _wait(0.1)
	print("[net] co-op target: state=", e4.state, " chasing bob=", e4.target is RemotePlayer, " our hull ", snappedf(hull0, 0.1), " -> ", snappedf(Game.hull, 0.1))
	# health reports: Bob's lower value wins here, and ours reach Bob
	var hp4 := e4.hp
	_bob_send({"t": "ev", "room": room, "kind": "hp", "data": {"h": {e4.nid: snappedf(hp4 - 7.0, 0.1)}}})
	await _wait(0.3)
	var hp_low := e4.hp
	_bob_send({"t": "ev", "room": room, "kind": "hp", "data": {"h": {e4.nid: e4.max_hp}}})
	await _wait(0.3)
	print("[net] hp sync: ", snappedf(hp4, 0.1), " -> ", snappedf(hp_low, 0.1), " (want -7), a higher report ignored=", is_equal_approx(e4.hp, hp_low))
	bob_in.clear()
	e4.take_hit(3.0)
	var hpev := {}
	var waited := 0.0
	while hpev.is_empty() and waited < 2.5:
		await _wait(0.1)
		waited += 0.1
		for m in bob_in:
			if m.t == "ev" and m.kind == "hp":
				hpev = m
	print("[net] our hp report reached bob=", hpev.get("data", {}).get("h", {}).has(e4.nid))
	# contested: a drone a friend is fighting doesn't heal on its way home
	e4.remote_t = Time.get_ticks_msec() / 1000.0
	e4.state = "return"
	var hpr := e4.hp
	await _wait(0.5)
	print("[net] contested no heal=", e4.hp <= hpr + 0.01, " (", snappedf(hpr, 0.1), " -> ", snappedf(e4.hp, 0.1), ")")
	pw.player.global_position = home_pos
	# Bob's shots show on his robot here; his grenade bursts but hurts nothing (his game deals it)
	var bav: RemotePlayer = pw.net_view.avatars.get(bob_id)
	var target_e: Enemy = null
	for e in pw.enemies:
		if is_instance_valid(e) and e.is_alive():
			target_e = e
			break
	var thp := target_e.hp
	var fx0 := pw.get_child_count()
	_bob_send({"t": "ev", "room": room, "kind": "shots", "data": {"w": "Cinder", "s": [
		{"k": "rail", "b": Net._arr(bav.global_position + bav.global_basis.z * -20.0)},
		{"k": "lob", "v": Net._arr((target_e.global_position - bav.global_position).normalized() * 30.0)},
		{"k": "lob", "v": Net._arr(bav.global_position.normalized() * 20.0)}]}})
	await _wait(0.15)
	var grenades := pw.get_children().filter(func(c): return c is PlayerGrenade)
	print("[net] bob's shots: fx added=", pw.get_child_count() - fx0, " grenades in flight=", grenades.size(), " all cosmetic=", grenades.all(func(g): return g.cosmetic), " aiming=", bav.visual.aiming)
	await _wait(3.2)
	print("[net] bob's grenade damage here=", snappedf(thp - target_e.hp, 0.1) if is_instance_valid(target_e) else -1.0, " (want 0)")
	# our shots reach Bob
	bob_in.clear()
	pw.player._shoot(pw.player.global_position.normalized())
	var sev := {}
	var shot_wait := 0.0
	while sev.is_empty() and shot_wait < 1.5:
		await _wait(0.1)
		shot_wait += 0.1
		for m in bob_in:
			if m.t == "ev" and m.kind == "shots":
				sev = m
	print("[net] our shots reached bob=", not sev.is_empty(), " ", sev.get("data", {}).get("w", ""), " ", (sev.get("data", {}).get("s", [{}]) as Array)[0].get("k", ""))
	# Titans: a friend's kill only counts if we were there
	var tkind: String = Db.TITANS.get(pw.planet.biome, Db.TITANS.values()[0])
	var pu: Vector3 = pw.player.global_position.normalized()
	var pb := PlanetGen.align_basis(pu, 0.0)
	var t_far: Enemy = pw._spawn_enemy(tkind, 20, (pu + pb.x * 400.0 / pw.gen.radius).normalized(), -1)
	pw.titan = t_far
	Game.titans.erase(pw.planet.key)
	_bob_send({"t": "ev", "room": room, "kind": "kill", "data": {"nid": t_far.nid, "type": tkind, "lvl": 20, "elite": true, "pos": Net._arr(t_far.global_position)}})
	await _wait(0.4)
	var far_rec := Game.titans.has(pw.planet.key)
	var t_near: Enemy = pw._spawn_enemy(tkind, 20, (pu + pb.x * 40.0 / pw.gen.radius).normalized(), -1)
	pw.titan = t_near
	_bob_send({"t": "ev", "room": room, "kind": "kill", "data": {"nid": t_near.nid, "type": tkind, "lvl": 20, "elite": true, "pos": Net._arr(t_near.global_position)}})
	await _wait(0.4)
	print("[net] titan far kill recorded=", far_rec, " (want false), near kill recorded=", Game.titans.has(pw.planet.key), " dead=", not (is_instance_valid(t_far) and t_far.is_alive()) and not (is_instance_valid(t_near) and t_near.is_alive()))
	Game.titans.erase(pw.planet.key)
	# ---- a shared cave
	var cave: Poi = null
	for p in pw.pois:
		if p.type == "cave":
			cave = p
	cave.open_cache()
	await _wait(3.0)
	var dw := get_tree().current_scene
	var croom: String = "dig:" + dw.cave_key
	bob_in.clear()
	for i in 4:
		_bob_send({"t": "state", "scene": "dig", "room": croom, "star": Game.star_index, "planet": Game.planet_index, "pos": [dw.pod.position.x + 64.0, dw.pod.position.y, 0], "fwd": [1, 0, 0], "anim": "drill"})
		await _wait(0.15)
	# Bob arrives second: his tunnels merge into ours and we answer with ours
	bob_in.clear()
	var bob_raw := PackedByteArray()
	bob_raw.resize((dw.W * dw.H + 7) / 8)
	# a shaft from the sky down to (20, SURFACE+8), plus a pocket nobody could reach
	for y in range(dw.SURFACE, dw.SURFACE + 9):
		var si: int = dw.idx(20, y)
		bob_raw[si >> 3] |= (1 << (si & 7))
	var bcell := Vector2i(20, dw.SURFACE + 8)
	var bi: int = dw.idx(bcell.x, bcell.y)
	var lone := Vector2i(-1, -1)
	for y in range(dw.H - 30, dw.SURFACE + 20, -1):
		for x in range(2, dw.W - 2):
			if dw.is_solid(x, y) and dw.get_cell(x, y) != dw.BEDROCK and dw._opens_onto(x, y) == false and not dw._opens_onto(x + 1, y) and not dw._opens_onto(x - 1, y):
				lone = Vector2i(x, y)
				break
		if lone.x >= 0:
			break
	var li: int = dw.idx(lone.x, lone.y)
	bob_raw[li >> 3] |= (1 << (li & 7))
	_bob_send({"t": "ev", "room": croom, "kind": "mask", "data": {"dug": Marshalls.raw_to_base64(bob_raw), "reply": false}})
	var mask := await _bob_wait("ev", 2.0)
	print("[net] cave: bob's tunnel merged=", dw.dug[bi] == 1, " sealed pocket kept=", dw.dug[li] == 0, " we replied with ours=", mask.get("kind", "") == "mask" and not bool(mask.get("data", {}).get("reply", false)) == false)
	# a made-up mask of every tile hollows nothing
	var solid0 := 0
	for i in dw.W * dw.H:
		solid0 += 1 if dw.is_solid(i % dw.W, i / dw.W) else 0
	var all_ones := PackedByteArray()
	all_ones.resize((dw.W * dw.H + 7) / 8)
	all_ones.fill(255)
	_bob_send({"t": "ev", "room": croom, "kind": "mask", "data": {"dug": Marshalls.raw_to_base64(all_ones), "reply": true}})
	await _wait(0.4)
	var solid1 := 0
	for i in dw.W * dw.H:
		solid1 += 1 if dw.is_solid(i % dw.W, i / dw.W) else 0
	print("[net] cave: all-ones mask cleared ", solid0 - solid1, " tiles (want 0)")
	var nv2: NetView2D = null
	for c in dw.get_children():
		if c is NetView2D:
			nv2 = c
	var cell := Vector2i(10, dw.SURFACE + 6)
	var was_dug: int = dw.dug[dw.idx(cell.x, cell.y)]
	_bob_send({"t": "ev", "room": croom, "kind": "dig", "data": {"x": cell.x, "y": cell.y}})
	await _wait(0.3)
	print("[net] cave: bob diver=", nv2 != null and nv2.divers.has(bob_id), " remote dig ", was_dug, " -> ", dw.dug[dw.idx(cell.x, cell.y)])
	bob_in.clear()
	dw.dig_out(Vector2i(12, dw.SURFACE + 6))
	var dev := await _bob_wait("ev")
	print("[net] cave: bob sees our dig=", dev.get("kind", "") == "dig" and int(dev.get("data", {}).get("x", -1)) == 12)
	Game.leave_cave()
	await _wait(4.0)
	# ---- a friend's sea: diving anywhere on this world joins it
	var sea_key := "%s:sea:9,9,9" % Galaxy.planet(Game.star_index, Game.planet_index).key
	for i in 3:
		_bob_send({"t": "state", "scene": "sea", "room": "sea:" + sea_key, "star": Game.star_index, "planet": Game.planet_index, "pos": [400, 300, 0], "fwd": [1, 0, 0]})
		await _wait(0.15)
	Game.enter_sea(Vector3.UP, Galaxy.planet(Game.star_index, Game.planet_index))
	await _wait(3.0)
	var sw0 := get_tree().current_scene
	var cr0 := Game.credits
	_bob_send({"t": "ev", "room": "sea:" + sea_key, "kind": "wreck", "data": {"id": 9999}})
	await _wait(0.4)
	print("[net] sea: joined friend's sea=", Game.sea.get("key", "") == sea_key, " scene=", sw0.name, " wreck share credits ", cr0, " -> ", Game.credits)
	var clam_id := -1
	for o in sw0.objects:
		if o.kind == "clam" and not o.get("open", false):
			clam_id = int(o.id)
			break
	_bob_send({"t": "ev", "room": "sea:" + sea_key, "kind": "clam", "data": {"id": clam_id}})
	await _wait(0.4)
	print("[net] sea: friend's clam saved as opened=", (Game.sea_state(sea_key).opened as Array).has(clam_id))
	Game.leave_sea()
	await _wait(4.0)
	# fly: both in space, Bob 30 m off the first planet
	Game.go_to_space()
	await _wait(4.0)
	var sw := get_tree().current_scene
	var rel := Vector3(30, 5, 0)
	for i in 5:
		_bob_send({"t": "state", "scene": "space", "room": "space:%d" % Game.star_index, "star": Game.star_index, "planet": 0, "pos": Net._arr(rel), "fwd": [0, 0, -1], "anim": "fly"})
		await _wait(0.15)
	await _wait(0.6)
	var sav: RemotePlayer = sw.net_view.avatars.get(bob_id)
	var sk0 := Game.space_kills
	var skill := {"id": "77", "type": "raider", "lvl": 3, "elite": false, "anchor": 0, "pos": Net._arr(sw.player.global_position - Galaxy.orbit_pos(Galaxy.planet(Game.star_index, 0), Game.play_time))}
	_bob_send({"t": "ev", "room": "space:%d" % Game.star_index, "kind": "skill", "data": skill})
	await _wait(0.4)
	_bob_send({"t": "ev", "room": "space:%d" % Game.star_index, "kind": "skill", "data": skill})
	await _wait(0.4)
	print("[net] space shared kill: ", sk0, " -> ", Game.space_kills, " (repeat ignored)")
	var expect := Galaxy.orbit_pos(Galaxy.planet(Game.star_index, 0), Game.play_time) + rel
	Game.waypoint = {"kind": "friend", "id": bob_id, "star": Game.star_index, "name": "Bob"}
	print("[net] friend waypoint in space: off by ", snappedf(sw.waypoint_pos().distance_to(sav.global_position), 0.1) if sav else -1.0)
	Game.waypoint = {}
	print("[net] space: scene=", sw.name, " bob flying=", sav != null, " off by ", snappedf(sav.global_position.distance_to(expect), 0.1) if sav else -1.0, " where=", Net.where_text(bob_id))
	# Bob leaves, then we do
	bob.close()
	await _wait(0.8)
	print("[net] bob left: players=", Net.players.size(), " avatars=", sw.net_view.avatars.size())
	Net.leave()
	await _wait(0.3)
	print("[net] left: status=", Net.status)
	OS.kill(_pid)
	get_tree().quit()
