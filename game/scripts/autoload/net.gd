extends Node
## Multiplayer client. Everyone keeps their own save; the server (a small Go
## program in server/) shares who is where, chat, item gifts and crates
## dropped on planets. Scenes read `players` and `drops` to draw other robots
## and crates (see scripts/net/net_view.gd), and call give / drop_here /
## pickup / say.

signal status_changed
signal chat_received(line: Dictionary)
signal players_changed
signal drops_changed
signal look_changed(id: int)
## Something happened in the room we're in (a tile dug, a clam opened, a kill...).
signal room_event(from_id: int, from_name: String, kind: String, data: Dictionary)
## LAN discovery found a server or finished a scan.
signal lan_changed

const PROTOCOL := "4"
const DEFAULT_PORT := 7777
const SEND_RATE := 0.1 # seconds between position updates
const CFG_PATH := "user://multiplayer.cfg"
const MAX_QTY := 9999 # the most of one item a gift or crate can carry (the server's limit)
const MAX_CRATE_KINDS := 20

var status := "offline" # offline | connecting | online
var address := ""
var last_error := ""
var my_id := 0
var my_name := ""
var server_motd := ""
var server_protocol := "" # set when a server turned us away for speaking another protocol
var players := {} # id -> {name, robot, look, state: {scene, star, planet, label, pos, fwd, anim}, t}
var drops := {} # id -> {id, star, planet, pos: Vector3, items: {item: qty}, by}
var chat_log: Array = [] # {name, text, color}

## Servers on the local network, from the last scan: "ip:port" -> {name, address,
## online, max, password, protocol, version, here (on this computer)}.
var lan_servers := {}
var lan_scanning := false
var discovery_port := 7777 # the server's LAN discovery port (tests use their own)
var _lan: PacketPeerUDP
var _lan_t := 0.0
const LAN_PROBE := "STARCIRCUIT?"
const LAN_WAIT := 1.5 # seconds to listen for answers

var saved_address := ""
var saved_password := ""
var auto_join := false # join the last server when a game starts

## Dropped connections retry on their own, waiting longer each time. A refusal
## (wrong password, other version, server full) or leaving on purpose doesn't.
var reconnect_in := 0.0 # seconds until the next try (0 = not waiting)
var _retry_n := 0
var _refused := false
var _auto_pending := false
const RETRY_WAITS := [2.0, 4.0, 8.0, 15.0, 30.0]
const MAX_RETRIES := 12

var _ws: WebSocketPeer
var _password := ""
var _hello_sent := false
var _send_t := 0.0
var _ping_t := 0.0
var room := "" # the shared space we're in, from the scene's net_state()
var _hits := {} # enemy net id -> damage not yet sent (batched with the state tick)
var _shots: Array = [] # our shots since the last state tick, drawn on friends' screens
const MAX_SHOTS := 6 # per tick: enough to read as firing, not every pellet


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps talking while the Homespace pauses the world
	Game.appearance_changed.connect(send_look)
	# the server knows us by the name we joined with: rejoin under the new one
	Game.name_changed.connect(func():
		if is_online():
			join(address, _password))
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		saved_address = String(cfg.get_value("server", "address", ""))
		saved_password = String(cfg.get_value("server", "password", ""))
		auto_join = bool(cfg.get_value("server", "auto_join", false))
	_auto_pending = auto_join and saved_address != "" and not Game.is_dev_run()


## Ask the local network who's hosting. Answers arrive over the next moment
## (lan_changed fires as each one comes in, and when the scan ends).
func lan_scan() -> void:
	if _lan:
		_lan.close()
	lan_servers.clear()
	_lan = PacketPeerUDP.new()
	_lan.set_broadcast_enabled(true)
	if _lan.bind(0) != OK:
		_lan = null
		lan_scanning = false
		lan_changed.emit()
		return
	var probe := LAN_PROBE.to_utf8_buffer()
	var targets := ["255.255.255.255", "127.0.0.1"]
	for a in _private_addresses():
		var q := a.split(".")
		targets.append("%s.%s.%s.255" % [q[0], q[1], q[2]]) # this subnet (a /24 is the usual home network)
	for t in targets:
		_lan.set_dest_address(t, discovery_port)
		_lan.put_packet(probe)
	_lan_t = LAN_WAIT
	lan_scanning = true
	lan_changed.emit()


static func _private_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var q := a.split(".")
		if q.size() != 4:
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or (q[0] == "172" and int(q[1]) >= 16 and int(q[1]) <= 31):
			out.append(a)
	return out


func _poll_lan(delta: float) -> void:
	var changed := false
	while _lan.get_available_packet_count() > 0:
		var bytes := _lan.get_packet()
		var ip := _lan.get_packet_ip()
		if bytes.size() > 2048:
			continue
		var r = JSON.parse_string(bytes.get_string_from_utf8())
		if not r is Dictionary or String(r.get("game", "")) != "Star Circuit":
			continue
		var port := clampi(int(r.get("port", DEFAULT_PORT)), 1, 65535)
		# our own server answers on loopback and on our LAN address: list it once
		var here := ip == "127.0.0.1" or ip in IP.get_local_addresses()
		if here:
			ip = "127.0.0.1"
		var key := "%s:%d" % [ip, port]
		var host := ip if port == DEFAULT_PORT else key
		lan_servers[key] = {"name": String(r.get("name", "Star Circuit server")).left(40), "address": ("wss://" + key) if bool(r.get("tls", false)) else host,
			"online": int(r.get("online", 0)), "max": int(r.get("max_players", 0)), "password": bool(r.get("password", false)),
			"protocol": String(r.get("protocol", "")), "version": String(r.get("version", "")), "here": here}
		changed = true
	_lan_t -= delta
	if _lan_t <= 0.0:
		_lan.close()
		_lan = null
		lan_scanning = false
		changed = true
	if changed:
		lan_changed.emit()


## "newer" when a server (protocol p) is ahead of this game, "older" when it's behind, "" when they match.
static func protocol_gap(p: String) -> String:
	if p == "" or p == PROTOCOL:
		return ""
	return "newer" if p.to_int() > PROTOCOL.to_int() else "older"


## What to tell a player whose game and server don't match.
func version_advice(p: String) -> String:
	if protocol_gap(p) == "newer":
		if Updater.has_update():
			return "This server needs a newer Star Circuit. Version %s is out: update and you can join." % Updater.latest
		return "This server needs a newer Star Circuit than yours (v%s). Update the game to join." % Updater.current_version()
	return "This server runs an older version than your game. Ask the host to update the Star Circuit server."


func set_auto_join(on: bool) -> void:
	auto_join = on
	if Game.is_dev_run():
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("server", "auto_join", on)
	cfg.save(CFG_PATH)


## Stop trying to get back onto a server that dropped us.
func stop_reconnecting() -> void:
	reconnect_in = 0.0
	_retry_n = 0
	status_changed.emit()


func is_online() -> bool:
	return status == "online"


## Turn what the player typed into a socket URL: "192.168.1.20",
## "play.example.com:7777", "ws://host:port/ws" or "wss://domain".
static func url_for(addr: String) -> String:
	addr = addr.strip_edges()
	if addr == "":
		return ""
	var scheme := "ws://"
	for pre in [["wss://", "wss://"], ["ws://", "ws://"], ["https://", "wss://"], ["http://", "ws://"]]:
		if addr.begins_with(pre[0]):
			scheme = pre[1]
			addr = addr.substr(pre[0].length())
			break
	var host := addr
	var path := "/ws"
	var slash := addr.find("/")
	if slash >= 0:
		host = addr.substr(0, slash)
		path = addr.substr(slash)
		if path == "/":
			path = "/ws"
	# a bare host gets the default port, unless it's a secure address (443 behind a proxy)
	var has_port := host.contains("]:") if host.begins_with("[") else host.contains(":")
	if not has_port and scheme == "ws://":
		host += ":%d" % DEFAULT_PORT
	return scheme + host + path


func join(addr: String, password := "", retry := false) -> void:
	var tries := _retry_n
	leave(false)
	if retry:
		_retry_n = tries
	_refused = false
	var url := url_for(addr)
	if url == "":
		last_error = "Enter a server address."
		status_changed.emit()
		return
	address = addr.strip_edges()
	_password = password
	last_error = ""
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	if err != OK:
		last_error = "Couldn't reach %s." % url
		_ws = null
		status_changed.emit()
		return
	_hello_sent = false
	status = "connecting"
	status_changed.emit()
	if not Game.is_dev_run():
		var cfg := ConfigFile.new()
		cfg.set_value("server", "address", address)
		cfg.set_value("server", "password", password)
		cfg.set_value("server", "auto_join", auto_join)
		cfg.save(CFG_PATH)
		saved_address = address
		saved_password = password


func leave(announce := true) -> void:
	if _ws:
		_ws.close(1000, "bye")
		_ws = null
	var was := status
	status = "offline"
	reconnect_in = 0.0
	_retry_n = 0
	players.clear()
	drops.clear()
	my_id = 0
	if announce and was != "offline":
		_system("You left the server.")
	status_changed.emit()
	players_changed.emit()
	drops_changed.emit()


func _process(delta: float) -> void:
	if _lan:
		_poll_lan(delta)
	if _auto_pending and Game.in_game:
		_auto_pending = false
		if status == "offline":
			join(saved_address, saved_password)
	if reconnect_in > 0.0 and _ws == null:
		reconnect_in -= delta
		if reconnect_in <= 0.0:
			reconnect_in = 0.0
			join(address, _password, true)
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_hello_sent = true
			_send({"t": "hello", "name": Game.player_name, "robot": Game.robot_id, "look": Game.appearance,
				"version": PROTOCOL, "game": Updater.current_version(), "password": _password})
		while _ws and _ws.get_available_packet_count() > 0:
			var txt := _ws.get_packet().get_string_from_utf8()
			var m = JSON.parse_string(txt)
			if m is Dictionary:
				_on_msg(m)
		if status == "online":
			_send_t -= delta
			if _send_t <= 0.0:
				_send_t = SEND_RATE
				_send_state()
			_ping_t -= delta
			if _ping_t <= 0.0:
				_ping_t = 5.0
				_send({"t": "ping"})
	elif st == WebSocketPeer.STATE_CLOSED:
		var reason := _ws.get_close_reason()
		_ws = null
		if last_error == "":
			last_error = "Couldn't connect to %s." % address if status == "connecting" else ("Disconnected%s." % ((": " + reason) if reason != "" and reason != "bye" else ""))
		var was := status
		status = "offline"
		players.clear()
		drops.clear()
		# lost the server (not refused): try again, a little later each time
		if not _refused and address != "" and (was == "online" or _retry_n > 0) and _retry_n < MAX_RETRIES:
			reconnect_in = RETRY_WAITS[mini(_retry_n, RETRY_WAITS.size() - 1)]
			_retry_n += 1
			if was == "online":
				last_error = "Lost the connection to %s. Reconnecting..." % address
		if was == "online":
			_system(last_error)
			Game.notify.emit(last_error, Color("ff8a6b"))
		status_changed.emit()
		players_changed.emit()
		drops_changed.emit()


func _send(m: Dictionary) -> bool:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return _ws.send_text(JSON.stringify(m)) == OK
	return false


func _socket_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


## Another player's look, kept only if it's the shape we expect.
static func _look(v) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			if k is String and v[k] is String and (v[k] as String).length() <= 40:
				out[k] = v[k]
	return out


static func _vec(a) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _on_msg(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"welcome":
			my_id = int(m.id)
			my_name = String(m.name)
			server_motd = String(m.get("motd", ""))
			players.clear()
			for p in m.get("players", []):
				_add_player(p)
				if p.get("state") is Dictionary:
					_set_state(int(p.id), p.state)
			drops.clear()
			for d in m.get("drops", []):
				_add_drop(d)
			status = "online"
			if _retry_n > 0:
				_retry_n = 0
				Game.notify.emit("Reconnected to %s" % address, Color("6ee06a"))
			_system("Connected to %s as %s. %d other%s online." % [address, my_name, players.size(), "" if players.size() == 1 else "s"])
			if server_motd != "":
				_system(server_motd)
			Game.notify.emit("Joined %s" % address, Color("6ee06a"))
			status_changed.emit()
			players_changed.emit()
			drops_changed.emit()
		"join":
			_add_player(m)
			_system("%s joined." % m.name)
			Game.notify.emit("%s joined the game" % m.name, Color("9bd1ff"))
			players_changed.emit()
		"leave":
			var id := int(m.id)
			if players.has(id):
				_system("%s left." % players[id].name)
				players.erase(id)
				players_changed.emit()
		"state":
			var id := int(m.id)
			var was_where := where_text(id)
			_set_state(id, m)
			if where_text(id) != was_where:
				players_changed.emit()
		"look":
			var id := int(m.id)
			if players.has(id):
				players[id].look = _look(m.get("look"))
				look_changed.emit(id)
		"chat":
			var line := {"name": String(m.name), "text": String(m.text), "color": Color("e6f1ff") if int(m.id) != my_id else Color("9bd1ff")}
			chat_log.append(line)
			if chat_log.size() > 80:
				chat_log.pop_front()
			if int(m.id) != my_id:
				Game.notify.emit("%s: %s" % [line.name, line.text], Color("c3d9ff"))
			chat_received.emit(line)
		"gift":
			var item := String(m.item)
			var qty := clampi(int(m.qty), 1, 9999)
			if can_share(item):
				Game.add_item(item, qty, true, true)
				Game.notify.emit("%s gave you %d %s" % [m.name, qty, Db.item_name(item)], Color("ffd23f"))
				Sound.ui("coin", -4.0)
				_system("%s gave you %d %s." % [m.name, qty, Db.item_name(item)])
		"give_ok":
			Game.notify.emit("Sent %d %s to %s" % [int(m.qty), Db.item_name(String(m.item)), m.name], Color("6ee06a"))
			_system("You gave %s %d %s." % [m.name, int(m.qty), Db.item_name(String(m.item))])
		"give_fail":
			# the server refused the gift: the items come back
			var item := String(m.get("item", ""))
			var q := int(m.get("qty", 0))
			if can_share(item) and q >= 1:
				Game.add_item(item, mini(q, 9999), true, true)
			Game.notify.emit(String(m.get("text", "The gift couldn't be delivered.")), Color("ff8a6b"))
		"drop_add":
			_add_drop(m.get("drop", {}))
			drops_changed.emit()
		"drop_remove":
			drops.erase(int(m.id))
			drops_changed.emit()
		"drop_fail":
			_restore(m.get("items", {}))
			Game.notify.emit(String(m.get("text", "Couldn't drop that.")), Color("ff8a6b"))
		"pickup_ok":
			var got: Array[String] = []
			var items: Dictionary = m.get("items", {})
			for item in items:
				if can_share(item):
					var q := clampi(int(items[item]), 1, 9999)
					Game.add_item(item, q, true, true)
					got.append("%d %s" % [q, Db.item_name(item)])
			Sound.ui("pickup", -2.0)
			Game.notify.emit("Picked up %s%s" % [", ".join(got), ("  (left by %s)" % m.name) if String(m.get("name", "")) != "" else ""], Color("ffd23f"))
		"pickup_fail":
			Game.notify.emit("Someone got to that crate first.", UiKit.MUTED)
		"ev":
			var data = m.get("data", {})
			if String(m.get("room", "")) == room and data is Dictionary:
				room_event.emit(int(m.id), String(m.get("name", "")), String(m.get("kind", "")), data)
		"error":
			_refused = true
			last_error = String(m.get("text", "The server refused the connection."))
			server_protocol = String(m.get("version", "")).left(8)
			if server_protocol != "" and server_protocol != PROTOCOL:
				last_error = version_advice(server_protocol)
			Game.notify.emit(last_error, Color("ff8a6b"))


func _add_player(p: Dictionary) -> void:
	var id := int(p.get("id", 0))
	if id == 0 or id == my_id:
		return
	players[id] = {"name": String(p.get("name", "Unit")), "robot": String(p.get("robot", "scout")), "look": _look(p.get("look")), "state": {}, "t": 0.0}


func _set_state(id: int, m: Dictionary) -> void:
	if not players.has(id):
		return
	players[id].state = {
		"scene": String(m.get("scene", "away")), "star": int(m.get("star", -1)), "planet": int(m.get("planet", -1)),
		"label": String(m.get("label", "")), "pos": _vec(m.get("pos")), "fwd": _vec(m.get("fwd")), "anim": String(m.get("anim", "")),
		"anchor": int(m.get("planet", -1)), "room": String(m.get("room", "")),
	}
	players[id].t = Time.get_ticks_msec() / 1000.0


func _add_drop(d: Dictionary) -> void:
	if not d.has("id"):
		return
	var items := {}
	var raw: Dictionary = d.get("items", {})
	for k in raw:
		if can_share(k):
			items[k] = clampi(int(raw[k]), 1, 9999)
	if items.is_empty():
		return
	drops[int(d.id)] = {"id": int(d.id), "star": int(d.star), "planet": int(d.planet), "pos": _vec(d.pos), "items": items, "by": String(d.get("by", ""))}


func _system(text: String) -> void:
	var line := {"name": "", "text": text, "color": UiKit.MUTED}
	chat_log.append(line)
	if chat_log.size() > 80:
		chat_log.pop_front()
	chat_received.emit(line)


func where_text(id: int) -> String:
	if not players.has(id):
		return ""
	var st: Dictionary = players[id].state
	if st.is_empty() or int(st.get("star", -1)) < 0:
		return "Somewhere out there"
	var star := Galaxy.star(int(st.star))
	var here := ""
	var pl := int(st.get("planet", -1))
	if st.scene == "planet" and pl >= 0:
		here = Galaxy.planet(int(st.star), pl).name
	elif st.scene == "space":
		here = "Flying in the %s system" % star.name
	else:
		here = String(st.get("label", "Busy"))
		if pl >= 0:
			here += " on %s" % Galaxy.planet(int(st.star), pl).name
	if st.scene == "planet":
		here += ", %s system" % star.name
	return here


# --------------------------------------------------------------------------
# what the game calls
# --------------------------------------------------------------------------

## Upgrades are part of your frame; everything else can change hands.
static func can_share(item: String) -> bool:
	return Db.ITEMS.has(item) and String(Db.ITEMS[item].kind) != "upgrade"


func say(text: String) -> void:
	text = text.strip_edges().left(200)
	if text != "" and is_online():
		_send({"t": "chat", "text": text})


## Items leave the hold only once the message is on its way; the server
## answers give_fail (items back) for anything it won't deliver.
func give(to_id: int, item: String, qty: int) -> bool:
	if not is_online() or not players.has(to_id) or not can_share(item):
		return false
	qty = mini(mini(qty, Game.count(item)), MAX_QTY)
	if qty <= 0:
		return false
	if not _socket_open() or not _send({"t": "give", "to": to_id, "item": item, "qty": qty}):
		Game.notify.emit("Not connected to the server. Nothing was sent.", Color("ff8a6b"))
		return false
	Game.remove_item(item, qty)
	return true


## Drop items in a crate where you stand (planets only).
func drop_here(items: Dictionary) -> bool:
	var sc := get_tree().current_scene
	if not is_online() or sc == null or not sc.has_method("drop_point"):
		return false
	var clean := {}
	for k in items:
		var q := mini(mini(int(items[k]), Game.count(k)), MAX_QTY)
		if can_share(k) and q > 0 and clean.size() < MAX_CRATE_KINDS:
			clean[k] = q
	if clean.is_empty():
		return false
	var p: Vector3 = sc.drop_point()
	if not _socket_open() or not _send({"t": "drop", "star": Game.star_index, "planet": Game.planet_index, "pos": _arr(p), "items": clean}):
		Game.notify.emit("Not connected to the server. Nothing was dropped.", Color("ff8a6b"))
		return false
	for k in clean:
		Game.remove_item(k, clean[k])
	Sound.ui("craft", -6.0)
	return true


func pickup(id: int) -> void:
	if is_online() and drops.has(id):
		_send({"t": "pickup", "id": id})


func send_look() -> void:
	if is_online():
		_send({"t": "look", "look": Game.appearance})


func _restore(items) -> void:
	if not items is Dictionary:
		return
	for k in items:
		var q := int(items[k]) if (items[k] is int or items[k] is float) else 0
		if k is String and can_share(k) and q >= 1:
			Game.add_item(k, mini(q, MAX_QTY), true, true)


## Where am I? Scenes that host other players provide net_state(); everything
## else (caves, the sea, volcanoes, orbit, hyperspace) reports "away".
const AWAY_LABELS := {"Dig": "Digging in a cave", "Grotto": "Exploring a grotto", "Sea": "Diving the Deep Sea",
	"Volcano": "Running a volcano", "Orbit": "Probing from orbit", "Hyperspace": "In hyperspace"}

func _send_state() -> void:
	var sc := get_tree().current_scene
	var m := {"t": "state", "star": Game.star_index, "planet": Game.planet_index, "scene": "away", "label": "Busy"}
	if sc and sc.has_method("net_state") and not Game.in_home:
		m.merge(sc.net_state(), true)
	elif Game.in_home:
		m.label = "In their Homespace"
	elif sc:
		m.label = AWAY_LABELS.get(String(sc.name), "Busy")
	room = String(m.get("room", ""))
	if m.has("pos") and m.pos is Vector3:
		m.pos = _arr(m.pos)
	if m.has("fwd") and m.fwd is Vector3:
		m.fwd = _arr(m.fwd)
	_send(m)
	if not _hits.is_empty() and room != "":
		send_event("hits", {"h": _hits})
		_hits = {}
	if not _shots.is_empty() and room != "":
		send_event("shots", {"w": String(Game.weapon_def().name), "s": _shots})
	_shots = []


# --------------------------------------------------------------------------
# rooms: shared caves, seas and fights
# --------------------------------------------------------------------------

## Tell everyone in our room that something happened.
func send_event(kind: String, data: Dictionary) -> void:
	if is_online() and room != "":
		_send({"t": "ev", "room": room, "kind": kind, "data": data})


## Where a friend is: {star, planet (-1 when flying), scene, name}, or {} if unknown.
func friend_spot(id: int) -> Dictionary:
	if not players.has(id):
		return {}
	var st: Dictionary = players[id].state
	if st.is_empty() or int(st.get("star", -1)) < 0:
		return {}
	var pl := int(st.get("planet", -1)) if String(st.get("scene", "")) != "space" else -1
	return {"star": int(st.star), "planet": pl, "scene": String(st.get("scene", "")), "name": String(players[id].name)}


## Friends at each star: star index -> [names].
func friends_by_star() -> Dictionary:
	var out := {}
	for id in players:
		var f := friend_spot(id)
		if not f.is_empty():
			if not out.has(f.star):
				out[f.star] = []
			out[f.star].append(f.name)
	return out


## Set a course for a friend: a waypoint that follows them round this system, or
## the star they're at (the galaxy map opens on it). Returns what to tell the player.
func plot_course(id: int) -> String:
	var f := friend_spot(id)
	if f.is_empty():
		return "Can't tell where they are right now."
	Game.waypoint = {"kind": "friend", "id": id, "star": f.star, "name": f.name}
	if f.star != Game.star_index:
		return "%s is in the %s system, %.0f ly away. Open the galaxy map to warp there." % [f.name, Galaxy.star(f.star).name, Galaxy.distance(Game.star_index, f.star)]
	if f.planet >= 0 and f.scene != "space":
		if f.planet == Game.planet_index and Game.in_game and get_tree().current_scene and get_tree().current_scene.has_method("compass_markers"):
			return "%s is on this world: follow the blue mark on your compass." % f.name
		return "Course set for %s on %s. Take off and follow the marker." % [f.name, Galaxy.planet(f.star, f.planet).name]
	return "Course set for %s. Follow the marker." % f.name


## Players currently sharing our room.
func room_peers() -> Array:
	var out := []
	if room == "":
		return out
	for id in players:
		if String(players[id].state.get("room", "")) == room:
			out.append(id)
	return out


## One of our shots, for friends in the room to see: {k: hit|rail|arc|beam|lob, b: end point
## (or v: a grenade's velocity), a: space anchor}. Sent with the next state tick.
func queue_shot(shot: Dictionary) -> void:
	if is_online() and room != "" and _shots.size() < MAX_SHOTS and not room_peers().is_empty():
		_shots.append(shot)


## Damage we did to a shared enemy, sent in one batch per state tick.
func queue_hit(nid: String, amount: float) -> void:
	if is_online() and nid != "":
		_hits[nid] = snappedf(float(_hits.get(nid, 0.0)) + amount, 0.1)


## The room of a friend already in a mini game of this kind on a world ("sea:").
func friend_room(prefix: String, star: int, planet: int) -> String:
	if not is_online():
		return ""
	for id in players:
		var st: Dictionary = players[id].state
		var r := String(st.get("room", ""))
		if r.begins_with(prefix) and int(st.get("star", -1)) == star and int(st.get("planet", -1)) == planet:
			return r
	return ""
