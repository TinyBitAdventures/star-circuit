extends Node2D
## The Deep Sea: a side-on slice of a world's ocean. Swim down through the
## Sunlit, Twilight and Midnight zones into the Abyss; cut ore out of the
## rock, harvest kelp, open pearl clams, loot a wreck, siphon hot vents,
## and scan the fish, jellies, anglers and leviathans that live here.

const W := 64
const H := 190
const CS := 32
const SURF := 4 # rows of sky above the water line
const M_PER_ROW := 1.5

enum { WATER, ROCK, BEDROCK }
const ORE0 := 16

const ZONES := [
	{"name": "Sunlit Zone", "top": SURF, "hard": 0.35},
	{"name": "Twilight Zone", "top": 40, "hard": 0.55},
	{"name": "Midnight Zone", "top": 90, "hard": 0.8},
	{"name": "The Abyss", "top": 140, "hard": 1.05},
]

const ORES := [
	{"item": "nickel", "zones": [0, 1], "qty": [1, 3], "chance": 0.05, "req": 1},
	{"item": "cobalt", "zones": [0, 2], "qty": [1, 3], "chance": 0.035, "req": 15},
	{"item": "lumen", "zones": [1, 2], "qty": [1, 2], "chance": 0.03, "req": 30},
	{"item": "stardust", "zones": [2, 3], "qty": [1, 2], "chance": 0.015, "req": 20},
	{"item": "voidshard", "zones": [2, 3], "qty": [1, 2], "chance": 0.025, "req": 55},
	{"item": "exotic", "zones": [3, 3], "qty": [1, 1], "chance": 0.012, "req": 40},
]

## species index -> [kind, zone, size]
const SPECIES := [
	["fish", 0, 1.0], ["fish", 0, 0.8], ["fish", 1, 1.2], ["jelly", 1, 1.0],
	["fish", 2, 0.9], ["angler", 2, 1.6], ["leviathan", 3, 9.0], ["jelly", 3, 1.4],
]

var cells := PackedByteArray()
var dug := PackedByteArray()
var info := {}
var planet := {}
var key := ""
var hud: CanvasLayer
var diver: SeaDiver
var palette: Array = []
var water_col := Color("2a6f97")
var objects: Array = [] # {kind, pos, id, ...}
var fauna: Array = [] # {kind, sp, pos, vel, t, ...}
var _chunks := {}
var _run_items := {}
var _t := 0.0
var _dark: CanvasModulate
var _depth_label: Label
var _zone_label: Label
var _press_label: Label
var _scan_cd := 0.0
var _scan_fx := 0.0
var _reveal := 0.0
var _press_warn := 0.0
var _dug_since_save := 0
var _bite_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _fx: Array = []
var _whale_t := 6.0
var _process_delta := 0.0


func _ready() -> void:
	info = Game.sea
	if info.is_empty():
		# launched directly (dev): dive off the home world
		var p0: Dictionary = Galaxy.planet(0, 0)
		info = {"key": "0:0:sea:dev", "seed": 4321, "biome": p0.biome, "star": 0, "planet": 0, "dir": [0, 1, 0], "pos": []}
		Game.sea = info
	key = info.key
	planet = Galaxy.planet(int(info.star), int(info.planet))
	var b: Dictionary = Db.BIOMES[info.biome]
	water_col = b.water
	water_col.a = 1.0
	_make_palette()
	_generate(int(info.seed))
	_load_state()
	_build_backdrop()
	for cy in ceili(float(H) / 16):
		for cx in ceili(float(W) / 16):
			_make_chunk(Vector2i(cx, cy))
	_build_fg()
	_spawn_fauna()
	_dark = CanvasModulate.new()
	add_child(_dark)
	diver = SeaDiver.new()
	diver.world = self
	diver.position = Vector2(W * CS * 0.5, (SURF + 1) * CS)
	add_child(diver)
	_build_snow()
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "sea"
	add_child(hud)
	_build_depth_meter()
	UiKit.add_vignette(self, 0.45)
	Game.player_died.connect(_on_died)
	Sound.stop_all_loops()
	Sound.play_music("ocean", 2.0)
	Sound.loop_start("sea_amb", "ocean_loop", -8.0, "Ambience")
	Sound.play("splash", -4.0, 0.05)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_location_banner("The Deep Sea", "Beneath the waves of %s" % planet.name)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			Game.tip("first_sea", "Swim with WASD (%s up, %s down), boost with %s. Push into rock to cut it. %s scans nearby creatures, %s harvests kelp, opens clams and loots wrecks. Below about 200 m the Abyss crushes an unprotected hull: fabricate a Pressure Hull first." % [Game.key("jump"), Game.key("descend"), Game.key("sprint"), Game.key("scan"), Game.key("interact")])
	)


# --------------------------------------------------------------------------
# generation
# --------------------------------------------------------------------------

func _make_palette() -> void:
	var b: Dictionary = Db.BIOMES[info.biome]
	var rock: Color = b.colors.rock
	palette = [
		(b.colors.beach as Color).lerp(rock, 0.45),
		rock.lerp(Color("41505e"), 0.5),
		Color("2b3242").lerp(rock, 0.15),
		Color("1b1a24"),
	]


func zone_of(y: int) -> int:
	var z := 0
	for i in ZONES.size():
		if y >= ZONES[i].top:
			z = i
	return z


func idx(x: int, y: int) -> int:
	return y * W + x


func get_cell(x: int, y: int) -> int:
	if x < 0 or x >= W or y >= H:
		return BEDROCK
	if y < 0:
		return WATER
	return cells[idx(x, y)]


func is_solid(x: int, y: int) -> bool:
	return get_cell(x, y) != WATER


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CS), floori(p.y / CS))


func cell_centre(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CS, (c.y + 0.5) * CS)


func trench_x(y: float) -> float:
	return W * 0.5 + _trench.get_noise_1d(y * 1.0) * W * 0.3


var _trench := FastNoiseLite.new()


func _generate(seed_: int) -> void:
	_rng.seed = seed_
	cells.resize(W * H)
	dug.resize(W * H)
	dug.fill(0)
	var cav := FastNoiseLite.new()
	cav.seed = seed_
	cav.frequency = 0.055
	cav.fractal_octaves = 3
	_trench.seed = seed_ + 3
	_trench.frequency = 0.02
	var shelf := FastNoiseLite.new()
	shelf.seed = seed_ + 7
	shelf.frequency = 0.08
	for y in H:
		var z := zone_of(y)
		for x in W:
			var c := WATER
			if y >= H - 2 or x == 0 or x == W - 1:
				c = BEDROCK
			elif y >= SURF:
				var edge := float(mini(x, W - 1 - x))
				# continental shelves: rock creeps in from the sides as you go down
				var shelf_w := minf(3.0 + float(y - SURF) * 0.22, 11.0) + shelf.get_noise_1d(y * 2.0) * 3.0
				var solid := edge < shelf_w
				# below the sunlit zone the ocean becomes a maze of caves
				if y > 30:
					var n := cav.get_noise_2d(x * 1.1, y * 0.8)
					solid = solid or n < -0.16 - (0.0 if z < 3 else 0.06)
				# the trench always runs from top to bottom
				var tr := absf(x - trench_x(y))
				if tr < 3.2 + 1.5 * sin(y * 0.11):
					solid = false
				if solid:
					c = ROCK
			cells[idx(x, y)] = c
	# a floor for the trench
	for x in range(1, W - 1):
		for y in range(H - 5, H - 2):
			cells[idx(x, y)] = ROCK
	# ore on rock faces
	for y in range(SURF, H - 2):
		var z := zone_of(y)
		for x in range(1, W - 1):
			if cells[idx(x, y)] != ROCK:
				continue
			for oi in ORES.size():
				var o: Dictionary = ORES[oi]
				if z >= o.zones[0] and z <= o.zones[1] and _rng.randf() < o.chance * 0.6:
					cells[idx(x, y)] = ORE0 + oi
					break
	_place_objects()


## Cells with rock underneath and water here: floors for kelp, clams, vents.
func _floor_spots(y0: int, y1: int) -> Array:
	var out := []
	for y in range(maxi(y0, SURF + 1), mini(y1, H - 3)):
		for x in range(1, W - 1):
			if cells[idx(x, y)] == WATER and cells[idx(x, y + 1)] != WATER and cells[idx(x, y - 1)] == WATER:
				out.append(Vector2i(x, y))
	return out


func _place_objects() -> void:
	objects.clear()
	var id := 0
	# kelp forests and coral in the light
	for s in _floor_spots(SURF, ZONES[1].top + 10):
		var r := _rng.randf()
		if r < 0.3:
			objects.append({"kind": "kelp", "id": id, "pos": cell_centre(s) + Vector2(0, CS * 0.5), "h": _rng.randf_range(60, 150), "cut": false})
		elif r < 0.5:
			objects.append({"kind": "coral", "id": id, "pos": cell_centre(s) + Vector2(0, CS * 0.5), "hue": _rng.randf(), "s": _rng.randf_range(0.7, 1.3)})
		id += 1
	# clams and glow plants lower down
	var mids := _floor_spots(ZONES[1].top, ZONES[3].top)
	mids.shuffle()
	for i in mini(mids.size(), 14):
		objects.append({"kind": "clam", "id": id, "pos": cell_centre(mids[i]) + Vector2(0, CS * 0.3), "open": false})
		id += 1
	for s in _floor_spots(ZONES[2].top, H):
		if _rng.randf() < 0.18:
			objects.append({"kind": "glow", "id": id, "pos": cell_centre(s) + Vector2(0, CS * 0.5), "hue": _rng.randf_range(0.45, 0.8), "h": _rng.randf_range(16, 40)})
			id += 1
	# hydrothermal vents deep down
	var deeps := _floor_spots(ZONES[2].top + 20, H)
	deeps.shuffle()
	for i in mini(deeps.size(), 6):
		objects.append({"kind": "vent", "id": id, "pos": cell_centre(deeps[i]) + Vector2(0, CS * 0.5), "cd": 0.0})
		id += 1
	# one wreck in the midnight zone, on the widest bit of floor
	var best := Vector2i(-1, -1)
	var best_w := 0
	for s in _floor_spots(ZONES[2].top, ZONES[3].top):
		var w := 0
		while s.x + w < W - 1 and cells[idx(s.x + w, s.y)] == WATER and cells[idx(s.x + w, s.y + 1)] != WATER:
			w += 1
		if w > best_w:
			best_w = w
			best = s
	if best.x >= 0:
		objects.append({"kind": "wreck", "id": 9999, "pos": cell_centre(best) + Vector2(best_w * CS * 0.5 - CS * 0.5, CS * 0.5), "w": clampi(best_w, 3, 8)})


func _load_state() -> void:
	var st := Game.sea_state(key)
	if st.dug != "":
		var raw := Marshalls.base64_to_raw(st.dug)
		for i in mini(raw.size() * 8, W * H):
			if raw[i >> 3] & (1 << (i & 7)):
				dug[i] = 1
				cells[i] = WATER
	for o in objects:
		if o.kind == "clam" and (st.opened as Array).has(o.id):
			o.open = true
		if o.kind == "wreck" and st.wreck:
			o["looted"] = true


func save_state() -> void:
	var raw := PackedByteArray()
	raw.resize((W * H + 7) / 8)
	for i in W * H:
		if dug[i]:
			raw[i >> 3] |= (1 << (i & 7))
	Game.sea_state(key).dug = Marshalls.raw_to_base64(raw)


# --------------------------------------------------------------------------
# fauna
# --------------------------------------------------------------------------

func species_key(sp: int) -> String:
	return "%s:sea:%d" % [planet.key, sp]


func species_name(sp: int) -> String:
	return Galaxy.species_name(int(planet.seed), "sea%d" % sp)


func species_color(sp: int) -> Color:
	var h := fmod(float(hash(species_key(sp)) % 1000) / 1000.0, 1.0)
	return Color.from_hsv(h, 0.55, 1.0)


func _open_spot(zone: int) -> Vector2:
	for tries in 60:
		var y := _rng.randi_range(maxi(ZONES[zone].top + 2, SURF + 2), (ZONES[zone + 1].top - 2) if zone + 1 < ZONES.size() else H - 8)
		var x := _rng.randi_range(2, W - 3)
		if not is_solid(x, y):
			return cell_centre(Vector2i(x, y))
	return Vector2(trench_x(ZONES[zone].top + 10) * CS, (ZONES[zone].top + 10) * CS)


func _spawn_fauna() -> void:
	fauna.clear()
	for sp in SPECIES.size():
		var s: Array = SPECIES[sp]
		match s[0]:
			"fish":
				for school in 2:
					var c := _open_spot(s[1])
					for i in _rng.randi_range(6, 10):
						fauna.append({"kind": "fish", "sp": sp, "pos": c + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-30, 30)),
							"vel": Vector2.RIGHT.rotated(_rng.randf() * TAU) * 40.0, "t": _rng.randf() * 10.0, "home": c, "size": s[2]})
			"jelly":
				for i in 5:
					fauna.append({"kind": "jelly", "sp": sp, "pos": _open_spot(s[1]), "vel": Vector2.ZERO, "t": _rng.randf() * 10.0, "size": s[2]})
			"angler":
				for i in 3:
					var p := _open_spot(s[1])
					fauna.append({"kind": "angler", "sp": sp, "pos": p, "vel": Vector2.ZERO, "t": _rng.randf() * 10.0, "home": p, "size": s[2]})
			"leviathan":
				var p := _open_spot(s[1])
				fauna.append({"kind": "leviathan", "sp": sp, "pos": p, "vel": Vector2(30, 0), "t": 0.0, "size": s[2]})


func _update_fauna(delta: float) -> void:
	var dp := diver.position
	for f in fauna:
		f.t += delta
		match f.kind:
			"fish":
				# loose school around a wandering home, scattering from the diver
				f.home += Vector2(sin(f.t * 0.2 + f.sp), cos(f.t * 0.17)) * 8.0 * delta
				var to_home: Vector2 = f.home - f.pos
				f.vel += to_home * 0.6 * delta + Vector2(sin(f.t * 2.3), cos(f.t * 1.9)) * 20.0 * delta
				var away: Vector2 = f.pos - dp
				if away.length() < 90.0:
					f.vel += away.normalized() * 260.0 * delta
				if f.vel.length() > 110.0:
					f.vel = f.vel.normalized() * 110.0
			"jelly":
				# pulse upward, sink slowly
				var pulse := maxf(0.0, sin(f.t * 1.6))
				f.vel = Vector2(sin(f.t * 0.3) * 8.0, -pulse * 28.0 + 10.0)
				if (f.pos as Vector2).distance_to(dp) < 22.0 * f.size and not diver.dead:
					if _bite_cd <= 0.0:
						_bite_cd = 1.0
						diver.hurt(8.0, f.pos)
						Game.notify.emit("Stung by a jelly!", Color("ff8fd8"))
						Sound.play("jelly_sting", -3.0, 0.15)
			"angler":
				var d := dp - (f.pos as Vector2)
				if d.length() < 260.0 and not diver.dead:
					f.vel = f.vel.lerp(d.normalized() * 115.0, clampf(delta * 1.5, 0.0, 1.0))
					if d.length() < 26.0 and _bite_cd <= 0.0:
						_bite_cd = 1.2
						diver.hurt(15.0, f.pos)
						Game.notify.emit("An angler bites!", Color("ff6b6b"))
						Sound.play("hit", -2.0, 0.1)
				else:
					var h: Vector2 = f.home - f.pos
					f.vel = f.vel.lerp(h.limit_length(30.0) + Vector2(sin(f.t * 0.4), cos(f.t * 0.3)) * 15.0, clampf(delta, 0.0, 1.0))
			"leviathan":
				# cruises back and forth across the abyss
				if f.pos.x > W * CS - 200.0:
					f.vel.x = -absf(f.vel.x)
				elif f.pos.x < 200.0:
					f.vel.x = absf(f.vel.x)
				f.vel.y = sin(f.t * 0.15) * 10.0
		var np: Vector2 = f.pos + f.vel * delta
		# swim around rock rather than through it (the leviathan is too big to care)
		var c := cell_at(np)
		if f.kind != "leviathan" and is_solid(c.x, c.y):
			f.vel = -f.vel * 0.5
		else:
			f.pos = np


# --------------------------------------------------------------------------
# frame
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_process_delta = delta
	_bite_cd = maxf(0.0, _bite_cd - delta)
	_scan_cd = maxf(0.0, _scan_cd - delta)
	_scan_fx = maxf(0.0, _scan_fx - delta)
	_reveal = maxf(0.0, _reveal - delta)
	var row := diver.position.y / CS
	var depth := int(maxf(0.0, row - SURF) * M_PER_ROW)
	var z := zone_of(int(row))
	Game.record_sea_depth(depth)
	_depth_label.text = "%d m" % depth
	_zone_label.text = ZONES[z].name
	# the music darkens once the light is gone
	Sound.play_music("abyss" if z >= 2 else "ocean", 4.0)
	_whale_t -= _process_delta
	if _whale_t <= 0.0:
		_whale_t = randf_range(14.0, 26.0)
		for f in fauna:
			if f.kind == "leviathan":
				var d := (f.pos as Vector2).distance_to(diver.position)
				if d < 1600.0:
					Sound.play("whale_call", lerpf(-2.0, -20.0, d / 1600.0), 0.08)
	# light fades fast with depth
	var dk := clampf((row - SURF) / 110.0, 0.0, 1.0)
	_dark.color = Color(1, 1, 1).lerp(Color(0.05, 0.06, 0.1), pow(dk, 0.8))
	diver.set_light(dk)
	_update_fauna(delta)
	_hazards(delta, z)
	for f in _fx.duplicate():
		f.t -= delta
		f.pos += f.vel * delta
		if f.t <= 0.0:
			_fx.erase(f)
	_fg.queue_redraw()
	_life.queue_redraw()
	# input
	if not Game.ui_open:
		if Input.is_action_just_pressed("scan"):
			_scan()
		if Input.is_action_just_pressed("use_cell"):
			Game.use_energy_cell()
		if Input.is_action_just_pressed("repair"):
			Game.use_repair_kit()
		if Input.is_action_just_pressed("takeoff"):
			_emergency_surface()
	_update_prompt()


func _hazards(delta: float, z: int) -> void:
	if diver.dead:
		return
	_press_warn = maxf(0.0, _press_warn - delta)
	if z >= 3 and not Game.has_upgrade("pressure_hull"):
		Game.take_damage(6.0 * delta)
		_press_label.text = "PRESSURE! Hull failing"
		_press_label.modulate = Color("ff6b6b")
		if _press_warn <= 0.0:
			_press_warn = 4.0
			Game.notify.emit("The Abyss is crushing your hull. Fabricate a Pressure Hull, or head up!", Color("ff6b6b"))
			Sound.play("klaxon", -10.0, 0.0)
	else:
		_press_label.text = "Pressure hull OK" if Game.has_upgrade("pressure_hull") else ("Pressure: safe" if z < 3 else "")
		_press_label.modulate = UiKit.MUTED
	for o in objects:
		if o.kind == "vent" and diver.position.distance_to(o.pos + Vector2(0, -30)) < 34.0:
			Game.take_damage(10.0 * delta)


func _update_prompt() -> void:
	var txt := ""
	var col := Color("9bd1ff")
	if diver.position.y < (SURF + 1.5) * CS:
		txt = "[E] Surface and swim ashore"
		if Input.is_action_just_pressed("interact") and not Game.ui_open:
			_exit()
			return
	var o := _nearest_object()
	if not o.is_empty():
		match o.kind:
			"kelp":
				txt = "[E] Harvest kelp"
				col = Color("6ee06a")
			"clam":
				txt = "[E] Pry open the clam"
				col = Color("f3eef8")
			"wreck":
				txt = "[E] Search the wreck"
				col = Color("ffd98a")
			"vent":
				txt = "[E] Siphon the vent" if o.cd <= 0.0 else "Vent recharging..."
				col = Color("ffcf3f")
		if Input.is_action_just_pressed("interact") and not Game.ui_open:
			_use(o)
	if txt == "" and diver.dig_msg != "":
		txt = diver.dig_msg
		col = Color("ff9f43")
	hud.set_prompt(txt, col, diver.dig_progress)


func _nearest_object() -> Dictionary:
	var best := {}
	var bd := 0.0 # must be inside an object's reach
	for o in objects:
		match o.kind:
			"kelp":
				if o.cut:
					continue
			"clam":
				if o.open:
					continue
			"wreck":
				if o.get("looted", false):
					continue
			"coral", "glow":
				continue
		var p: Vector2 = o.pos
		var reach := 56.0
		if o.kind == "wreck":
			reach = 40.0 + float(o.w) * CS * 0.5
		elif o.kind == "kelp":
			p = o.pos + Vector2(0, -o.h * 0.5)
			reach = 30.0 + o.h * 0.4
		var score := diver.position.distance_to(p) - reach
		if score < bd:
			bd = score
			best = o
	return best


func _use(o: Dictionary) -> void:
	match o.kind:
		"kelp":
			o.cut = true
			var got := Game.add_item("kelp", _rng.randi_range(2, 4))
			_run_items["kelp"] = int(_run_items.get("kelp", 0)) + got
			Game.gain_skill_xp("botany", 14)
			Sound.play("plant_snap", -4.0, 0.1)
			_burst(o.pos + Vector2(0, -o.h * 0.5), Color("4fbf6a"), 12)
		"clam":
			o.open = true
			Game.sea_state(key).opened.append(o.id)
			Sound.play("bubble_pop", -6.0, 0.1)
			if _rng.randf() < 0.65:
				Game.add_item("sea_pearl", 1)
				Game.notify.emit("A pearl!", Color("f3eef8"))
				Sound.play("coin", -4.0, 0.0, "UI")
				_burst(o.pos, Color("f3eef8"), 14)
			else:
				Game.notify.emit("Empty. The clam looks relieved.", UiKit.MUTED)
			Game.gain_skill_xp("exploration", 20)
		"wreck":
			o["looted"] = true
			Game.sea_state(key).wreck = true
			var cr := _rng.randi_range(180, 320)
			Game.add_credits(cr)
			Game.add_item("ancient_relic", 1, true)
			Game.add_item("deep_probe", 1, true)
			Game.gain_skill_xp("exploration", 120)
			hud.big("WRECK SALVAGED", "+%d credits  ·  Ancient Relic  ·  Deep Probe" % cr, Color("ffd98a"))
			Sound.play("quest_complete", -4.0, 0.0, "UI")
		"vent":
			if o.cd > 0.0:
				return
			o.cd = 40.0
			var got2 := Game.add_item("plasma", _rng.randi_range(2, 4))
			_run_items["plasma"] = int(_run_items.get("plasma", 0)) + got2
			Game.gain_skill_xp("siphoning", 30)
			Sound.play("siphon_done", -4.0, 0.0)
			_burst(o.pos + Vector2(0, -20), Color("ffcf3f"), 16)
			var ov: Dictionary = o
			get_tree().create_timer(40.0).timeout.connect(func(): ov.cd = 0.0)


func _scan() -> void:
	if _scan_cd > 0.0:
		return
	if not Game.spend_energy(5.0):
		Game.notify.emit("Not enough energy to scan.", Color("ff6b6b"))
		return
	_scan_cd = 2.5
	_scan_fx = 1.0
	_reveal = 8.0
	Sound.play("sonar_ping", -3.0, 0.0)
	var seen := {}
	for f in fauna:
		if (f.pos as Vector2).distance_to(diver.position) < 300.0 + (200.0 if f.kind == "leviathan" else 0.0):
			seen[f.sp] = true
	var new := 0
	for sp in seen:
		if Game.record_sea_scan(species_key(sp), "%s (sea %s)" % [species_name(sp), SPECIES[sp][0]]):
			new += 1
	if seen.is_empty():
		Game.notify.emit("Nothing alive in range. Ore veins highlighted.", UiKit.MUTED)


func dig_block_reason(p: Vector2i) -> String:
	var c := get_cell(p.x, p.y)
	if c == BEDROCK:
		return "Bedrock. Nothing cuts that."
	if c >= ORE0 and Game.skill_level("mining") < int(ORES[c - ORE0].req):
		return "%s vein needs Mining %d." % [Db.item_name(ORES[c - ORE0].item), ORES[c - ORE0].req]
	return ""


func hardness(p: Vector2i) -> float:
	var c := get_cell(p.x, p.y)
	var h: float = ZONES[zone_of(p.y)].hard
	return h * (1.25 if c >= ORE0 else 1.0)


func dig_out(p: Vector2i) -> void:
	var c := get_cell(p.x, p.y)
	cells[idx(p.x, p.y)] = WATER
	dug[idx(p.x, p.y)] = 1
	_redraw_cell(p)
	_burst(cell_centre(p), palette[zone_of(p.y)], 10)
	Game.drain_energy(0.3)
	if c >= ORE0:
		var o: Dictionary = ORES[c - ORE0]
		var got := Game.add_item(o.item, _rng.randi_range(o.qty[0], o.qty[1]))
		_run_items[o.item] = int(_run_items.get(o.item, 0)) + got
		Game.gain_skill_xp("mining", 15.0 + zone_of(p.y) * 10.0)
		Sound.play("rock_break", -6.0, 0.1)
	_dug_since_save += 1
	if _dug_since_save >= 20:
		_dug_since_save = 0
		save_state()


func _burst(p: Vector2, col: Color, n: int) -> void:
	for i in n:
		_fx.append({"pos": p, "vel": Vector2.from_angle(randf() * TAU) * randf_range(30, 120), "t": randf_range(0.4, 0.9), "col": col})


func _exit() -> void:
	save_state()
	Sound.stop_all_loops()
	Game.leave_sea()


func _emergency_surface() -> void:
	if diver.position.y < (SURF + 3) * CS:
		return
	if Game.spend_energy(30.0):
		Game.notify.emit("Emergency ascent: 30 energy", Color("ffd98a"))
	else:
		var lost := _lose_run_items(0.4)
		Game.notify.emit("Emergency ascent without power: %d items left behind" % lost, Color("ff6b6b"))
	diver.position = Vector2(W * CS * 0.5, (SURF + 1) * CS)
	diver.velocity = Vector2.ZERO
	save_state()


func _lose_run_items(frac: float) -> int:
	var lost := 0
	for it in _run_items.keys():
		var q := mini(int(floor(int(_run_items[it]) * frac)), Game.count(it))
		if q > 0:
			Game.remove_item(it, q)
			lost += q
			_run_items[it] = int(_run_items[it]) - q
	return lost


func _on_died() -> void:
	if diver.dead:
		return
	diver.dead = true
	var lost := _lose_run_items(0.5)
	hud.show_death()
	Sound.play("death", -2.0, 0.0)
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	diver.position = Vector2(W * CS * 0.5, (SURF + 1) * CS)
	diver.velocity = Vector2.ZERO
	diver.dead = false
	Game.hull = Game.max_hull() * 0.6
	Game.energy = maxf(Game.energy, Game.max_energy() * 0.4)
	Game.hull_changed.emit()
	Game.energy_changed.emit(Game.energy, Game.max_energy())
	hud.hide_death()
	Game.big_notify.emit("REBOOTED", "Floated back to the surface%s" % ("  ·  %d items lost" % lost if lost > 0 else ""), Color("6ee06a"))


# --------------------------------------------------------------------------
# drawing
# --------------------------------------------------------------------------

var _ltex: GradientTexture2D
func light_tex() -> GradientTexture2D:
	if _ltex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_ltex = GradientTexture2D.new()
		_ltex.gradient = g
		_ltex.fill = GradientTexture2D.FILL_RADIAL
		_ltex.fill_from = Vector2(0.5, 0.5)
		_ltex.fill_to = Vector2(1.0, 0.5)
		_ltex.width = 256
		_ltex.height = 256
	return _ltex


func _build_backdrop() -> void:
	var bg := Node2D.new()
	bg.z_index = -10
	add_child(bg)
	var sky: Color = Db.BIOMES[info.biome].atmo
	bg.draw.connect(func():
		bg.draw_rect(Rect2(-CS * 12, -CS * 20, CS * (W + 24), CS * (20 + SURF)), sky.lightened(0.1))
		bg.draw_circle(Vector2(W * CS * 0.8, CS * 0.5), 60.0, Color(1.0, 0.97, 0.85, 0.9))
		# water darkens through the zones
		var top := water_col.lightened(0.15)
		var stops := [[SURF, top], [ZONES[1].top, water_col.darkened(0.35)], [ZONES[2].top, Color("0b1a33")], [ZONES[3].top, Color("050912")], [H, Color("020306")]]
		for i in stops.size() - 1:
			var y0: int = stops[i][0]
			var y1: int = stops[i + 1][0]
			var steps := 12
			for k in steps:
				var t0 := float(k) / steps
				var col: Color = (stops[i][1] as Color).lerp(stops[i + 1][1], t0)
				var ya := (y0 + (y1 - y0) * t0) * CS
				var yb := (y0 + (y1 - y0) * (t0 + 1.0 / steps)) * CS
				bg.draw_rect(Rect2(-CS * 12, ya, CS * (W + 24), yb - ya + 1.0), col)
	)
	bg.queue_redraw()


func _make_chunk(c: Vector2i) -> void:
	var n := Node2D.new()
	add_child(n)
	n.draw.connect(func(): _draw_chunk(n, c))
	_chunks[c] = n
	n.queue_redraw()


func _redraw_cell(p: Vector2i) -> void:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var q := Vector2i((p.x + dx) / 16, (p.y + dy) / 16)
			if _chunks.has(q):
				_chunks[q].queue_redraw()


func _hash(x: int, y: int) -> float:
	return float(hash(Vector2i(x, y)) % 1000) / 1000.0


func _draw_chunk(n: Node2D, c: Vector2i) -> void:
	for y in range(c.y * 16, mini(H, (c.y + 1) * 16)):
		for x in range(c.x * 16, mini(W, (c.x + 1) * 16)):
			var t := cells[idx(x, y)]
			if t == WATER:
				continue
			var r := Rect2(x * CS, y * CS, CS, CS)
			var h := _hash(x, y)
			var z := zone_of(y)
			var base: Color = palette[z] if t != BEDROCK else Color("0d0c12")
			n.draw_rect(r, base.lightened(h * 0.08).darkened((1.0 - h) * 0.08))
			if not is_solid(x, y - 1):
				# sandy tops in the light, silt below
				n.draw_rect(Rect2(r.position, Vector2(CS, 5)), (Db.BIOMES[info.biome].colors.beach as Color).darkened(0.1 + z * 0.25))
			if not is_solid(x, y + 1):
				n.draw_rect(Rect2(r.position + Vector2(0, CS - 4), Vector2(CS, 4)), base.darkened(0.45))
			if not is_solid(x - 1, y):
				n.draw_rect(Rect2(r.position, Vector2(3, CS)), base.lightened(0.1))
			if not is_solid(x + 1, y):
				n.draw_rect(Rect2(r.position + Vector2(CS - 3, 0), Vector2(3, CS)), base.darkened(0.3))
			if t >= ORE0:
				var col := Db.item_color(ORES[t - ORE0].item)
				for k in 3:
					var p := r.position + Vector2(6 + fmod(h * 97.0 * (k + 1), 20.0), 6 + fmod(h * 53.0 * (k + 2), 20.0))
					var s := 3.0 + fmod(h * 13.0 * (k + 1), 3.0)
					n.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)
			elif h > 0.75:
				n.draw_circle(r.position + Vector2(8 + h * 14, 10 + (1.0 - h) * 12), 2.5, base.darkened(0.3))


var _fg: Node2D # plants, clams, wreck, vents: lit by the world
var _life: Node2D # glowing things drawn unshaded: jellies, lures, glow plants, fx


func _build_fg() -> void:
	_fg = Node2D.new()
	_fg.z_index = 2
	_fg.draw.connect(_draw_fg)
	add_child(_fg)
	_life = Node2D.new()
	_life.z_index = 4
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_life.material = m
	_life.draw.connect(_draw_life)
	add_child(_life)


func _visible_rect() -> Rect2:
	var vs := get_viewport_rect().size / 1.25
	return Rect2(diver.position - vs * 0.6, vs * 1.2)


func _draw_fg() -> void:
	var view := _visible_rect()
	var sway := sin(_t * 1.2)
	# the water surface with a little chop
	var pts := PackedVector2Array()
	var y0 := SURF * CS
	for i in 80:
		var x := -CS * 10 + i * (W + 20) * CS / 79.0
		pts.append(Vector2(x, y0 + sin(x * 0.02 + _t * 1.6) * 4.0))
	_fg.draw_polyline(pts, Color(0.85, 0.97, 1.0, 0.8), 3.0)
	# sun shafts slanting down through the sunlit zone
	if view.position.y < ZONES[1].top * CS:
		for k in 7:
			var x := fmod(k * 311.0 + sin(_t * 0.2 + k) * 40.0, float(W * CS))
			var w := 40.0 + 30.0 * sin(k * 1.7)
			_fg.draw_colored_polygon(PackedVector2Array([Vector2(x, y0), Vector2(x + w, y0), Vector2(x + w + 180, ZONES[1].top * CS), Vector2(x + 180, ZONES[1].top * CS)]), Color(0.8, 0.95, 1.0, 0.05))
	for o in objects:
		var p: Vector2 = o.pos
		if not view.grow(200).has_point(p):
			continue
		match o.kind:
			"kelp":
				if o.cut:
					_fg.draw_line(p, p + Vector2(0, -10), Color("2f7a3f"), 4.0)
					continue
				var segs := 8
				var prev := p
				for i in range(1, segs + 1):
					var t := float(i) / segs
					var q := p + Vector2(sin(_t * 1.3 + p.x * 0.01 + t * 2.0) * 16.0 * t, -o.h * t)
					_fg.draw_line(prev, q, Color("3d9c52").lerp(Color("7fd66f"), t), 5.0 - t * 2.0)
					if i % 2 == 0:
						_fg.draw_circle(q + Vector2(5, 0), 3.5, Color("58b862"))
					prev = q
			"coral":
				var cc := Color.from_hsv(o.hue, 0.55, 0.95)
				for b in 5:
					var a := -PI * 0.5 + (b - 2) * 0.35
					var e: Vector2 = p + Vector2.from_angle(a) * 22.0 * float(o.s)
					_fg.draw_line(p, e, cc, 4.0)
					_fg.draw_circle(e, 4.0 * o.s, cc.lightened(0.2))
			"clam":
				var cl := Color("b9a5c9")
				if o.open:
					_fg.draw_colored_polygon(PackedVector2Array([p + Vector2(-12, 0), p + Vector2(12, 0), p + Vector2(10, -12), p + Vector2(-10, -12)]), cl.darkened(0.3))
				else:
					var breathe := sin(_t * 2.0 + p.x) * 1.5
					_fg.draw_colored_polygon(PackedVector2Array([p + Vector2(-13, 0), p + Vector2(13, 0), p + Vector2(8, -8 - breathe), p + Vector2(-8, -8 - breathe)]), cl)
					_fg.draw_line(p + Vector2(-12, -2), p + Vector2(12, -2), cl.darkened(0.4), 2.0)
			"vent":
				_fg.draw_colored_polygon(PackedVector2Array([p + Vector2(-16, 0), p + Vector2(16, 0), p + Vector2(7, -26), p + Vector2(-7, -26)]), Color("3a2c2a"))
				_fg.draw_circle(p + Vector2(0, -26), 6.0, Color("ff8a3d") if o.cd <= 0.0 else Color("6a3a2a"))
			"wreck":
				var ww: float = float(o.w) * CS
				var hull := PackedVector2Array([p + Vector2(-ww * 0.5, 0), p + Vector2(ww * 0.5, 0), p + Vector2(ww * 0.55, -40), p + Vector2(-ww * 0.4, -52)])
				_fg.draw_colored_polygon(hull, Color("3b3a40"))
				_fg.draw_polyline(hull + PackedVector2Array([hull[0]]), Color("5c5a66"), 2.0)
				_fg.draw_line(p + Vector2(-ww * 0.1, -46), p + Vector2(-ww * 0.05, -120), Color("4a4850"), 5.0)
				for k in 3:
					_fg.draw_circle(p + Vector2(-ww * 0.25 + k * ww * 0.22, -26), 6.0, Color("1a1a20"))
				if not o.get("looted", false):
					_fg.draw_rect(Rect2(p + Vector2(ww * 0.2, -16), Vector2(22, 16)), Color("8a6a3a"))
					_fg.draw_rect(Rect2(p + Vector2(ww * 0.2, -16), Vector2(22, 4)), Color("c9a24a"))
	# fish and anglers' bodies
	for f in fauna:
		if not view.grow(300).has_point(f.pos):
			continue
		var col := species_color(f.sp)
		var dir := signf(f.vel.x) if absf(f.vel.x) > 1.0 else 1.0
		match f.kind:
			"fish":
				var s: float = 7.0 * f.size
				var tail := sin(f.t * 14.0) * 3.0
				_fg.draw_colored_polygon(PackedVector2Array([f.pos + Vector2(s * dir, 0), f.pos + Vector2(0, -s * 0.55), f.pos + Vector2(-s * dir, 0), f.pos + Vector2(0, s * 0.55)]), col)
				_fg.draw_colored_polygon(PackedVector2Array([f.pos + Vector2(-s * dir, 0), f.pos + Vector2(-s * 1.7 * dir, -s * 0.5 + tail), f.pos + Vector2(-s * 1.7 * dir, s * 0.5 + tail)]), col.darkened(0.2))
			"angler":
				var s2: float = 11.0 * f.size
				_fg.draw_circle(f.pos, s2, Color("2a2230"))
				# teeth
				for k in 4:
					var tp: Vector2 = f.pos + Vector2(dir * s2 * 0.7, -4 + k * 3)
					_fg.draw_line(tp, tp + Vector2(dir * 5, 1), Color("e8e0d0"), 1.5)
				_fg.draw_colored_polygon(PackedVector2Array([f.pos + Vector2(-s2 * dir, 0), f.pos + Vector2(-s2 * 1.7 * dir, -s2 * 0.6), f.pos + Vector2(-s2 * 1.7 * dir, s2 * 0.6)]), Color("241c2a"))
				_fg.draw_line(f.pos + Vector2(dir * 4, -s2), f.pos + Vector2(dir * s2 * 1.3, -s2 * 1.7), Color("3a3040"), 2.0)
			"leviathan":
				var L: float = 26.0 * f.size
				var body := PackedVector2Array()
				for k in 17:
					var t := float(k) / 16.0
					var wv := sin(f.t * 1.2 - t * 5.0) * 12.0
					body.append(f.pos + Vector2(dir * (L * 0.5 - t * L), -L * 0.12 * sin(t * PI) + wv))
				for k in 16:
					var t := 1.0 - float(k) / 15.0
					var wv := sin(f.t * 1.2 - t * 5.0) * 12.0
					body.append(f.pos + Vector2(dir * (L * 0.5 - t * L), L * 0.1 * sin(t * PI) + wv))
				_fg.draw_colored_polygon(body, Color("1c2a3a"))


func _draw_life() -> void:
	var view := _visible_rect()
	for o in objects:
		var p: Vector2 = o.pos
		if not view.grow(200).has_point(p):
			continue
		if o.kind == "glow":
			var gc := Color.from_hsv(o.hue, 0.6, 1.0)
			_life.draw_line(p, p + Vector2(sin(_t + p.x) * 4.0, -o.h), gc.darkened(0.3), 2.0)
			_life.draw_circle(p + Vector2(sin(_t + p.x) * 4.0, -o.h), 4.0 + sin(_t * 2.0 + p.x) * 1.0, gc)
			_life.draw_circle(p + Vector2(sin(_t + p.x) * 4.0, -o.h), 10.0, Color(gc, 0.12))
		elif o.kind == "vent" and o.cd <= 0.0:
			for k in 4:
				var ph := fmod(_t * 0.8 + k * 0.25, 1.0)
				_life.draw_circle(p + Vector2(sin(ph * 9.0 + k) * 6.0, -30 - ph * 90.0), 6.0 + ph * 10.0, Color(1.0, 0.6, 0.3, 0.25 * (1.0 - ph)))
		elif o.kind == "clam" and not o.open and _reveal > 0.0:
			_life.draw_circle(p + Vector2(0, -5), 3.0, Color(1, 1, 1, 0.8))
	for f in fauna:
		if not view.grow(300).has_point(f.pos):
			continue
		var col := species_color(f.sp)
		var dir := signf(f.vel.x) if absf(f.vel.x) > 1.0 else 1.0
		match f.kind:
			"jelly":
				var s: float = 12.0 * f.size
				var pulse := 1.0 + maxf(0.0, sin(f.t * 1.6)) * 0.2
				_life.draw_circle(f.pos, s * 2.2, Color(col, 0.08))
				var bell := PackedVector2Array()
				for k in 13:
					var a := PI + PI * k / 12.0
					bell.append(f.pos + Vector2(cos(a) * s * pulse, sin(a) * s / pulse))
				_life.draw_colored_polygon(bell, Color(col, 0.55))
				for k in 5:
					var tx: float = f.pos.x - s + k * s * 0.5
					_life.draw_line(Vector2(tx, f.pos.y), Vector2(tx + sin(f.t * 3.0 + k) * 5.0, f.pos.y + s * 2.4), Color(col, 0.45), 1.5)
			"angler":
				var s2: float = 11.0 * f.size
				var lure: Vector2 = f.pos + Vector2(dir * s2 * 1.3, -s2 * 1.7)
				_life.draw_circle(lure, 14.0, Color(0.6, 1.0, 0.8, 0.12))
				_life.draw_circle(lure, 3.5 + sin(f.t * 4.0), Color(0.75, 1.0, 0.85))
				_life.draw_circle(f.pos + Vector2(dir * s2 * 0.35, -s2 * 0.3), 2.0, Color(1.0, 0.9, 0.5))
			"fish":
				if f.sp == 4: # lanternfish glow
					_life.draw_circle(f.pos, 2.5, col.lightened(0.5))
			"leviathan":
				var L: float = 26.0 * f.size
				for k in 9:
					var t := float(k) / 8.0
					var wv := sin(f.t * 1.2 - t * 5.0) * 12.0
					var sp: Vector2 = f.pos + Vector2(dir * (L * 0.5 - t * L), wv - 4.0)
					_life.draw_circle(sp, 4.0, Color(0.5, 0.9, 1.0, 0.8))
				_life.draw_circle(f.pos + Vector2(dir * L * 0.4, -6), 5.0, Color(0.9, 1.0, 0.7))
	# revealed ore glints after a scan
	if _reveal > 0.0:
		var a := minf(_reveal, 1.0)
		var c0 := cell_at(view.position)
		var c1 := cell_at(view.end)
		for y in range(maxi(c0.y, 0), mini(c1.y + 1, H)):
			for x in range(maxi(c0.x, 0), mini(c1.x + 1, W)):
				var t := cells[idx(x, y)]
				if t >= ORE0:
					_life.draw_circle(cell_centre(Vector2i(x, y)), 6.0 + sin(_t * 6.0 + x) * 2.0, Color(Db.item_color(ORES[t - ORE0].item), 0.5 * a))
	if _scan_fx > 0.0:
		var r := (1.0 - _scan_fx) * 320.0
		_life.draw_arc(diver.position, r, 0.0, TAU, 64, Color(0.5, 0.95, 1.0, _scan_fx * 0.7), 3.0)
	for f in _fx:
		_life.draw_circle(f.pos, 2.5, Color(f.col, clampf(f.t * 1.6, 0.0, 1.0)))


func _build_snow() -> void:
	# marine snow drifting past the diver
	var p := CPUParticles2D.new()
	p.amount = 90
	p.lifetime = 8.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(900, 600)
	p.direction = Vector2(0.2, 1)
	p.spread = 20.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 18.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color = Color(0.85, 0.95, 1.0, 0.35)
	p.local_coords = false
	p.preprocess = 8.0
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	p.material = m
	diver.add_child(p)


func _build_depth_meter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	pc.position = Vector2(-190, 120)
	pc.custom_minimum_size = Vector2(170, 0)
	pc.theme = UiKit.theme()
	layer.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(UiKit.label("DEPTH", 12, UiKit.MUTED, true))
	_depth_label = UiKit.label("0 m", 30, Color("7fd8ff"), true)
	v.add_child(_depth_label)
	_zone_label = UiKit.label("", 14, UiKit.ACCENT)
	v.add_child(_zone_label)
	_press_label = UiKit.label("", 12, UiKit.MUTED)
	v.add_child(_press_label)
	v.add_child(UiKit.label("T  emergency ascent", 12, UiKit.MUTED))
