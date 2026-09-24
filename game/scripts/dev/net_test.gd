extends Node
## Headless multiplayer check against the real Go server (go run in server/):
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
	var dir := ProjectSettings.globalize_path("res://").path_join("../server").simplify_path()
	# build first and run the binary itself, so killing it really stops the server
	var bin := OS.get_cache_dir().path_join("star-circuit-server-test")
	var out := []
	var rc := OS.execute("go", ["-C", dir, "build", "-o", bin, "."], out, true)
	if rc != 0:
		print("[net] server build failed: ", out)
		get_tree().quit()
		return
	_pid = OS.create_process(bin, ["-addr", "127.0.0.1:%d" % _port, "-data", "", "-motd", "Welcome to the test server"])
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
	# fly: both in space, Bob 30 m off the first planet
	Game.go_to_space()
	await _wait(4.0)
	var sw := get_tree().current_scene
	var rel := Vector3(30, 5, 0)
	for i in 5:
		_bob_send({"t": "state", "scene": "space", "star": Game.star_index, "planet": 0, "pos": Net._arr(rel), "fwd": [0, 0, -1], "anim": "fly"})
		await _wait(0.15)
	await _wait(0.6)
	var sav: RemotePlayer = sw.net_view.avatars.get(bob_id)
	var expect := Galaxy.orbit_pos(Galaxy.planet(Game.star_index, 0), Game.play_time) + rel
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
