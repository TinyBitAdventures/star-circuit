extends Node2D
## The Eruption Run: a cutaway of a volcano, from the smoking cone above
## ground, down a winding lava tube through the Crater, the Lava Tubes, the
## Obsidian Galleries and the Magma Chamber to the Deep Mantle, with the
## planet's core glowing at the bottom. Magma rises the whole time and the
## volcano erupts when the timer runs out: dive for crystals in the side
## pockets, ride geysers upward, and climb out before it blows.

const W := 60
const H := 200
const CS := 32
const SURF := 26 # row where the ground outside the volcano starts
const PEAK := 4 # row of the crater rim
const DURATION := 150.0

enum { AIR, ROCK, BASALT, LAVA, CORE }

const ZONES := [
	{"name": "The Crater", "top": PEAK, "col": Color("5a3a30"), "heat": 0.0},
	{"name": "Lava Tubes", "top": 34, "col": Color("4a2a26"), "heat": 1.5},
	{"name": "Obsidian Galleries", "top": 78, "col": Color("2e2436"), "heat": 3.0},
	{"name": "Magma Chamber", "top": 120, "col": Color("4a1c16"), "heat": 5.5},
	{"name": "Deep Mantle", "top": 160, "col": Color("3a1410"), "heat": 8.0},
	{"name": "The Core", "top": 192, "col": Color("ffb347"), "heat": 20.0},
]

## What grows in the pockets of each zone.
const LOOT := [
	[],
	[["obsidian", 0.7, [2, 4]], ["cobalt", 0.3, [2, 3]]],
	[["obsidian", 0.5, [3, 5]], ["lumen", 0.3, [1, 3]], ["fire_opal", 0.08, [1, 1]]],
	[["fire_opal", 0.3, [1, 1]], ["voidshard", 0.35, [1, 2]], ["obsidian", 0.35, [3, 5]]],
	[["core_ember", 0.35, [1, 1]], ["fire_opal", 0.35, [1, 1]], ["exotic", 0.3, [1, 2]]],
]

var cells := PackedByteArray()
var info := {}
var planet := {}
var hud: CanvasLayer
var runner: VolcanoRunner
var deposits: Array = [] # {pos, item, qty, zone, taken, progress}
var geysers: Array = [] # {x, y (cell), t, state: idle|warn|blast, top}
var elapsed := 0.0
var magma_y := 0.0 # pixel y of the magma surface
var heat := 0.0
var rumble := 0.0
var ended := false
var _run_items := {}
var _rng := RandomNumberGenerator.new()
var _tube := FastNoiseLite.new()
var _t := 0.0
var _dark: CanvasModulate
var _magma: Node2D
var _magma_light: PointLight2D
var _fx: Array = []
var _timer_label: Label
var _zone_label: Label
var _depth_label: Label
var _heat_bar: ProgressBar
var _fuel_bar: ProgressBar
var _warned := {}
var _mine_target := -1
var _goal_label: Label
var _briefing := true # the clock waits until you've read what to do
var _brief_t := 0.0
var _brief: CanvasLayer
var _mine_p := 0.0


func _ready() -> void:
	info = Game.volcano
	if info.is_empty():
		info = {"key": "dev:volcano", "seed": 777, "biome": "ember", "star": 0, "planet": 0, "dir": [0, 1, 0]}
		Game.volcano = info
	planet = Galaxy.planet(int(info.get("star", 0)), int(info.get("planet", 0)))
	_rng.seed = int(info.seed)
	_generate()
	_build_backdrop()
	_build_rock()
	_build_lava()
	_build_fg()
	_dark = CanvasModulate.new()
	add_child(_dark)
	runner = VolcanoRunner.new()
	runner.world = self
	runner.position = Vector2(W * CS * 0.5, (PEAK + 1) * CS)
	add_child(runner)
	magma_y = (H - 6) * CS
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "volcano"
	add_child(hud)
	_build_meter()
	UiKit.add_vignette(self, 0.45)
	Game.player_died.connect(_on_died)
	Sound.stop_all_loops()
	Sound.play_music("ember", 2.0)
	Sound.loop_start("rumble", "volcano_rumble_loop", -14.0, "Ambience")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_briefing()


# --------------------------------------------------------------------------
# generation
# --------------------------------------------------------------------------

func idx(x: int, y: int) -> int:
	return y * W + x


func get_cell(x: int, y: int) -> int:
	if x < 0 or x >= W or y >= H:
		return BASALT
	if y < 0:
		return AIR
	return cells[idx(x, y)]


func is_solid(x: int, y: int) -> bool:
	var c := get_cell(x, y)
	return c == ROCK or c == BASALT or c == CORE


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CS), floori(p.y / CS))


func cell_centre(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CS, (c.y + 0.5) * CS)


func zone_of(y: int) -> int:
	var z := 0
	for i in ZONES.size():
		if y >= ZONES[i].top:
			z = i
	return z


func tube_x(y: float) -> float:
	return W * 0.5 + _tube.get_noise_1d(y) * W * 0.28 * clampf((y - PEAK) / 20.0, 0.0, 1.0)


## Half-width of the mountain at a row above ground (for the cone outline).
func cone_half(y: int) -> float:
	return lerpf(4.0, W * 0.5 + 6.0, clampf(float(y - PEAK) / float(SURF - PEAK), 0.0, 1.0))


func _generate() -> void:
	cells.resize(W * H)
	_tube.seed = int(info.seed)
	_tube.frequency = 0.035
	var cav := FastNoiseLite.new()
	cav.seed = int(info.seed) + 5
	cav.frequency = 0.08
	for y in H:
		for x in W:
			var c := ROCK
			if y < PEAK:
				c = AIR
			elif y < SURF and absf(x + 0.5 - W * 0.5) > cone_half(y):
				c = AIR # sky beside the cone
			if y >= ZONES[5].top:
				c = CORE
			elif x == 0 or x == W - 1:
				c = BASALT
			cells[idx(x, y)] = c
	# the main lava tube, winding from the crater to the mantle
	var pa := -1
	var pb := -1
	for y in range(PEAK, ZONES[5].top - 3):
		var cx := tube_x(y)
		var w := 2.2 + 1.2 * sin(y * 0.13) + (1.5 if y < PEAK + 6 else 0.0)
		var a := int(cx - w)
		var b := int(cx + w)
		# every row overlaps the one above by at least two tiles, so the tube
		# never pinches to a corner the runner can't squeeze through
		if pa >= 0:
			a = mini(a, pb - 1)
			b = maxi(b, pa + 1)
		a = clampi(a, 1, W - 2)
		b = clampi(b, 1, W - 2)
		for x in range(a, b + 1):
			cells[idx(x, y)] = AIR
		pa = a
		pb = b
	# pockets off the tube: 3 per zone below the crater
	var id := 0
	for z in range(1, 5):
		var top: int = ZONES[z].top
		var bot: int = ZONES[z + 1].top
		for k in 3:
			var py := _rng.randi_range(top + 4, bot - 6)
			var side := -1 if (k + z) % 2 == 0 else 1
			var px := int(clampf(tube_x(py) + side * _rng.randf_range(10.0, 18.0), 7.0, W - 8.0))
			var rw := _rng.randi_range(5, 8)
			var rh := _rng.randi_range(3, 5)
			for yy in range(py - rh, py + rh + 1):
				for xx in range(px - rw, px + rw + 1):
					var e := pow(float(xx - px) / rw, 2) + pow(float(yy - py) / rh, 2)
					if e < 1.0 + cav.get_noise_2d(xx, yy) * 0.25 and xx > 0 and xx < W - 1:
						cells[idx(xx, yy)] = AIR
			# a side tube back to the main one
			var tx := int(tube_x(py))
			var step := 1 if tx > px else -1
			var yy2 := py
			for xx in range(px, tx + step, step):
				if (xx + z) % 7 == 0:
					yy2 += _rng.randi_range(-1, 1)
				for dy in range(-1, 2):
					cells[idx(clampi(xx, 1, W - 2), clampi(yy2 + dy, PEAK, H - 1))] = AIR
			# floor deposits
			var floor_cells := []
			for xx in range(px - rw, px + rw + 1):
				for yy in range(py, py + rh + 2):
					if get_cell(xx, yy) == AIR and is_solid(xx, yy + 1):
						floor_cells.append(Vector2i(xx, yy))
						break
			floor_cells.shuffle()
			for f in floor_cells.slice(0, mini(floor_cells.size(), 2 + z / 2)):
				var roll := _rng.randf()
				var acc := 0.0
				for l in LOOT[z]:
					acc += float(l[1])
					if roll <= acc:
						deposits.append({"id": id, "pos": cell_centre(f) + Vector2(0, CS * 0.5), "item": l[0], "qty": _rng.randi_range(l[2][0], l[2][1]), "zone": z, "taken": false})
						id += 1
						break
			# deeper pockets have lava pooled in part of their floor
			if z >= 3:
				for xx in range(px - rw + 1, px - rw + 4):
					for yy in range(py + 1, py + rh + 1):
						if get_cell(xx, yy) == AIR and is_solid(xx, yy + 1):
							cells[idx(xx, yy)] = LAVA
							break
	# basalt pillars in the obsidian galleries (decorative, solid)
	for y in range(ZONES[2].top, ZONES[3].top):
		for x in range(1, W - 1):
			if cells[idx(x, y)] == ROCK and (x * 7 + y * 3) % 23 == 0:
				cells[idx(x, y)] = BASALT
	# geysers on the tube floor: find ledges along the main tube
	var last_y := -99
	for y in range(PEAK + 14, ZONES[5].top - 4):
		if y - last_y < 14:
			continue
		for x in range(int(tube_x(y) - 4), int(tube_x(y) + 5)):
			if get_cell(x, y) == AIR and is_solid(x, y + 1) and get_cell(x, y - 3) == AIR:
				var top := y
				while top > PEAK and get_cell(x, top - 1) == AIR and y - top < 12:
					top -= 1
				geysers.append({"x": x, "y": y, "t": _rng.randf_range(0.0, 5.0), "state": "idle", "top": top})
				last_y = y
				break


# --------------------------------------------------------------------------
# frame
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ended:
		_update_fx(delta)
		return
	if _briefing:
		_update_fx(delta)
		if _brief_t > 0.4 and _any_input():
			start_run()
		_brief_t += delta
		return
	_t += delta
	elapsed += delta
	# magma rises slowly at first, then faster
	var f := clampf(elapsed / DURATION, 0.0, 1.0)
	var bottom := (H - 6) * CS
	var top := (PEAK + 2) * CS
	magma_y = lerpf(bottom, top, pow(f, 1.7) * 0.93)
	rumble = clampf(f * f * 1.2, 0.0, 1.0)
	_magma.queue_redraw()
	_magma_light.position = Vector2(runner.position.x, magma_y - 20.0)
	_magma_light.energy = 0.6 + 0.4 * clampf(1.0 - absf(runner.position.y - magma_y) / 600.0, 0.0, 1.0)
	var row := int(runner.position.y / CS)
	var z := zone_of(row)
	var left := DURATION - elapsed
	_timer_label.text = "ERUPTION IN %d:%02d" % [int(left) / 60, int(left) % 60]
	_timer_label.modulate = Color("ff4d4d") if left < 30.0 else (Color("ffb86b") if left < 60.0 else Color.WHITE)
	for mark in [60, 30, 10]:
		if left < mark and not _warned.has(mark):
			_warned[mark] = true
			Game.notify.emit("%d seconds until the eruption!" % mark, Color("ff6b6b"))
			Sound.play("klaxon", -10.0 + (6.0 if mark == 10 else 0.0), 0.0)
	_zone_label.text = ZONES[z].name
	_depth_label.text = "%d m" % int(maxf(0.0, row - PEAK) * 4)
	var dk := clampf(float(row - PEAK) / 120.0, 0.0, 1.0)
	_dark.color = Color(1, 1, 1).lerp(Color(0.28, 0.18, 0.16), dk)
	_update_heat(delta, z)
	_update_geysers(delta)
	_update_mining(delta)
	_update_fx(delta)
	_heat_bar.value = heat
	_fuel_bar.value = runner.fuel * 100.0
	# the rim: climb out
	var prompt := ""
	if row <= PEAK + 1:
		prompt = "[E] Climb out of the crater (%d items in your pack)" % _run_count()
		if Input.is_action_just_pressed("interact") and not Game.ui_open:
			_escape()
			return
	elif _mine_target >= 0:
		var d: Dictionary = deposits[_mine_target]
		prompt = "[E] Hold to mine %s" % Db.item_name(d.item)
	elif drill_p > 0.0:
		prompt = "Drilling..."
	elif drill_msg != "":
		prompt = drill_msg
	hud.set_prompt(prompt, Color("ffb86b"), _mine_p if _mine_target >= 0 else drill_p)
	var up_m := int(maxf(0.0, row - PEAK) * 4)
	if left < 45.0 and row > PEAK + 1:
		_goal_label.text = "GET OUT!  The rim is %d m up" % up_m
		_goal_label.modulate = Color("ff6b6b") if int(_t * 3.0) % 2 == 0 else Color("ffb86b")
	else:
		_goal_label.text = "Haul: %d item%s  ·  Rim: %d m up" % [_run_count(), "" if _run_count() == 1 else "s", up_m]
		_goal_label.modulate = Color("ffd98a")
	if Input.is_action_just_pressed("takeoff") and not Game.ui_open:
		Game.notify.emit("No emergency lift in a volcano: the heat fries the winch. Climb!", Color("ff6b6b"))
	if elapsed >= DURATION:
		_erupt()


## Drilling: rock breaks if you push into it long enough (deeper rock is
## tougher); basalt and the core don't. Returns progress 0..1, or -1 if the
## cell can't be drilled.
var _drill_cell := Vector2i(-99, -99)
var drill_p := 0.0
var drill_msg := ""

func drill(c: Vector2i, delta: float) -> float:
	var t := get_cell(c.x, c.y)
	if t == BASALT or t == CORE or c.y >= ZONES[5].top:
		drill_msg = "Basalt. Too hard to drill." if t == BASALT else ""
		return -1.0
	if t != ROCK:
		return -1.0
	drill_msg = ""
	if c != _drill_cell:
		_drill_cell = c
		drill_p = 0.0
	var z := zone_of(c.y)
	drill_p += delta * sqrt(Game.harvest_speed("mining")) / (0.35 + 0.12 * z)
	if randf() < delta * 14.0:
		_fx.append({"pos": cell_centre(c) + Vector2(randf_range(-10, 10), randf_range(-10, 10)), "vel": Vector2(randf_range(-80, 80), -randf_range(20, 120)), "t": 0.35, "col": ZONES[z].col.lightened(0.4)})
	Sound.loop_start("dig", "drill_loop", -12.0)
	if drill_p >= 1.0:
		drill_p = 0.0
		_drill_cell = Vector2i(-99, -99)
		cells[idx(c.x, c.y)] = AIR
		_rock.queue_redraw()
		Game.drain_energy(0.4)
		Sound.play("rock_break", -6.0, 0.1)
		for i in 8:
			_fx.append({"pos": cell_centre(c), "vel": Vector2(randf_range(-140, 140), -randf_range(60, 200)), "t": 0.5, "col": ZONES[z].col.lightened(0.3)})
		# the deep rock is shot through with volcanic glass
		if z >= 2 and randf() < 0.2:
			var got := Game.add_item("obsidian", 1)
			_run_items["obsidian"] = int(_run_items.get("obsidian", 0)) + got
		Sound.loop_stop("dig", 0.1)
	return drill_p


func stop_drill() -> void:
	if drill_p > 0.0 or _drill_cell != Vector2i(-99, -99):
		Sound.loop_stop("dig", 0.1)
	drill_p = 0.0
	_drill_cell = Vector2i(-99, -99)


func _run_count() -> int:
	var n := 0
	for k in _run_items:
		n += int(_run_items[k])
	return n


func _update_heat(delta: float, z: int) -> void:
	if runner.dead:
		return
	var rate: float = ZONES[z].heat
	# lava pools and the magma surface nearby
	var c := cell_at(runner.position)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if get_cell(c.x + dx, c.y + dy) == LAVA:
				rate += 6.0
	var to_magma := magma_y - runner.position.y
	if to_magma < 300.0:
		rate += (300.0 - to_magma) / 300.0 * 20.0
	if z <= 0:
		rate = -15.0 # the open crater lets the heat out
	if Game.has_upgrade("lava_plating"):
		rate *= 0.5 if rate > 0.0 else 1.0
	heat = clampf(heat + (rate - 2.0) * delta, 0.0, 100.0)
	if heat >= 100.0:
		Game.take_damage(10.0 * delta)
	# touching lava or the magma itself
	var touching := runner.position.y + VolcanoRunner.HALF.y > magma_y
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if get_cell(c.x + dx, c.y + dy) == LAVA and runner.position.distance_to(cell_centre(Vector2i(c.x + dx, c.y + dy))) < CS * 0.9:
				touching = true
	if touching:
		heat = 100.0
		Game.take_damage((12.0 if Game.has_upgrade("lava_plating") else 35.0) * delta)
		if not runner.dead and randf() < delta * 4.0:
			runner.velocity.y = -380.0 # the burn throws you upward
			Sound.play("player_hurt", -10.0, 0.2)


func _update_geysers(delta: float) -> void:
	for g in geysers:
		g.t -= delta
		match g.state:
			"idle":
				if g.t <= 0.0:
					g.state = "warn"
					g.t = 1.2
			"warn":
				if randf() < delta * 20.0:
					_fx.append({"pos": cell_centre(Vector2i(g.x, g.y)) + Vector2(randf_range(-8, 8), 8), "vel": Vector2(0, -randf_range(40, 90)), "t": 0.5, "col": Color(1.0, 0.6, 0.2)})
				if g.t <= 0.0:
					g.state = "blast"
					g.t = 1.3
					if absf(runner.position.y - g.y * CS) < 700.0:
						Sound.play("boost", -6.0, 0.15)
			"blast":
				var gx: float = (g.x + 0.5) * CS
				var top_y: float = g.top * CS
				var bot_y: float = (g.y + 1) * CS
				if absf(runner.position.x - gx) < CS * 0.9 and runner.position.y > top_y - CS * 2 and runner.position.y < bot_y + CS * 0.5 and runner.launched <= 0.0:
					runner.launch(820.0)
					heat = minf(100.0, heat + 8.0)
					Game.take_damage(3.0)
					Game.notify.emit("Riding the geyser!", Color("ffb86b"))
				for k in 3:
					_fx.append({"pos": Vector2(gx + randf_range(-10, 10), bot_y), "vel": Vector2(randf_range(-20, 20), -randf_range(500, 800)), "t": 0.5, "col": Color(1.0, randf_range(0.5, 0.9), 0.3)})
				if g.t <= 0.0:
					g.state = "idle"
					g.t = randf_range(4.0, 7.0)


func _update_mining(delta: float) -> void:
	_mine_target = -1
	var best := 46.0
	for i in deposits.size():
		var d: Dictionary = deposits[i]
		if d.taken:
			continue
		var dist := runner.position.distance_to(d.pos + Vector2(0, -14))
		if dist < best:
			best = dist
			_mine_target = i
	if _mine_target >= 0 and Input.is_action_pressed("interact") and not Game.ui_open:
		_mine_p += delta * Game.harvest_speed("mining") / (1.0 + 0.3 * int(deposits[_mine_target].zone))
		if randf() < delta * 12.0:
			_fx.append({"pos": deposits[_mine_target].pos + Vector2(randf_range(-8, 8), -10), "vel": Vector2(randf_range(-60, 60), -randf_range(40, 120)), "t": 0.4, "col": Db.item_color(deposits[_mine_target].item)})
		Sound.loop_start("dig", "drill_loop", -12.0)
		if _mine_p >= 1.0:
			_mine_p = 0.0
			var d: Dictionary = deposits[_mine_target]
			d.taken = true
			var got := Game.add_item(d.item, int(d.qty))
			_run_items[d.item] = int(_run_items.get(d.item, 0)) + got
			Game.gain_skill_xp("mining", 20.0 + int(d.zone) * 14.0)
			Sound.play("rock_break", -4.0, 0.1)
			if d.item in ["fire_opal", "core_ember"]:
				hud.big(Db.item_name(d.item).to_upper(), "Now get it out before the eruption", Db.item_color(d.item))
			Sound.loop_stop("dig", 0.1)
	else:
		_mine_p = maxf(0.0, _mine_p - delta * 2.0)
		Sound.loop_stop("dig", 0.1)


func _update_fx(delta: float) -> void:
	for f in _fx.duplicate():
		f.t -= delta
		f.pos += f.vel * delta
		f.vel.y += 400.0 * delta
		if f.t <= 0.0:
			_fx.erase(f)
	_fg.queue_redraw()


func _escape() -> void:
	ended = true
	Sound.stop_all_loops()
	Game.gain_xp(150 + _run_count() * 10)
	hud.big("ESCAPED", "Out with %d items, %d seconds to spare" % [_run_count(), int(DURATION - elapsed)], Color("6ee06a"))
	Sound.play("quest_complete", -4.0, 0.0, "UI")
	await get_tree().create_timer(2.2).timeout
	Game.leave_volcano(true)


func _erupt() -> void:
	ended = true
	Sound.stop_all_loops()
	Sound.play("slam", 0.0, 0.0)
	Sound.play("warp", -4.0, 0.0)
	runner.shake = 1.0
	rumble = 1.0
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.5, 0.15, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "color:a", 0.85, 0.4)
	# still inside: blown out of the crater with the ash
	var lost := 0
	for it in _run_items.keys():
		var q := mini(int(ceil(int(_run_items[it]) * 0.5)), Game.count(it))
		if q > 0:
			Game.remove_item(it, q)
			lost += q
	Game.hull = maxf(1.0, Game.hull * 0.4)
	Game.hull_changed.emit()
	hud.big("ERUPTION!", "Blasted out of the crater%s" % ("  ·  %d items lost in the ash" % lost if lost > 0 else ""), Color("ff4d4d"))
	await get_tree().create_timer(2.6).timeout
	Game.leave_volcano(false)


func _on_died() -> void:
	if runner.dead or ended:
		return
	runner.dead = true
	ended = true
	Sound.stop_all_loops()
	Sound.play("death", -2.0, 0.0)
	var lost := 0
	for it in _run_items.keys():
		var q := mini(int(_run_items[it]), Game.count(it))
		if q > 0:
			Game.remove_item(it, q)
			lost += q
	hud.show_death()
	await get_tree().create_timer(3.0).timeout
	Game.hull = Game.max_hull() * 0.5
	Game.energy = maxf(Game.energy, Game.max_energy() * 0.4)
	Game.hull_changed.emit()
	Game.big_notify.emit("REBOOTED", "Recovered at the foot of the volcano%s" % ("  ·  %d items lost to the magma" % lost if lost > 0 else ""), Color("6ee06a"))
	Game.leave_volcano(false)


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
	var sky: Color = Db.BIOMES.get(info.biome, Db.BIOMES.ember).atmo
	bg.draw.connect(func():
		# a dusky, ash-filled sky
		for i in 12:
			var t0 := float(i) / 12.0
			bg.draw_rect(Rect2(-CS * 12, -CS * 12 + (SURF + 12) * CS * t0, (W + 24) * CS, (SURF + 12) * CS / 12.0 + 1.0), sky.darkened(0.55).lerp(Color("3a1a14"), t0))
		var r := RandomNumberGenerator.new()
		r.seed = 9
		for k in 80:
			bg.draw_circle(Vector2(r.randf_range(-CS * 12, (W + 12) * CS), r.randf_range(-CS * 12, PEAK * CS)), r.randf_range(0.8, 1.8), Color(1, 1, 1, 0.3))
		# the ground outside, seen in section, and the deep rock below it
		bg.draw_rect(Rect2(-CS * 12, SURF * CS, (W + 24) * CS, (H - SURF + 4) * CS), Color("1a0e0c"))
		# section bands behind the tunnels: each zone its own tint
		for z in range(1, ZONES.size() - 1):
			var y0: int = maxi(ZONES[z].top, SURF) if z == 1 else ZONES[z].top
			var y1: int = ZONES[z + 1].top
			bg.draw_rect(Rect2(-CS * 12, y0 * CS, (W + 24) * CS, (y1 - y0) * CS), (ZONES[z].col as Color).darkened(0.55))
	)
	bg.queue_redraw()


var _rock: Node2D

func _build_rock() -> void:
	_rock = Node2D.new()
	add_child(_rock)
	_rock.draw.connect(_draw_rock)
	_rock.queue_redraw()


func _hash(x: int, y: int) -> float:
	return float(hash(Vector2i(x, y)) % 1000) / 1000.0


func _draw_rock() -> void:
	for y in H:
		var z := zone_of(y)
		var base: Color = ZONES[z].col
		if y < SURF:
			base = Color("5a3a30").lerp(Color("3a2420"), float(y - PEAK) / float(SURF - PEAK))
		for x in W:
			var t := cells[idx(x, y)]
			if t == AIR or t == LAVA:
				continue
			var r := Rect2(x * CS, y * CS, CS, CS)
			var h := _hash(x, y)
			var col := base
			if t == BASALT:
				col = Color("1c1a22")
			elif t == CORE:
				continue
			_rock.draw_rect(r, col.lightened(h * 0.07).darkened((1.0 - h) * 0.07))
			if not is_solid(x, y - 1) and get_cell(x, y - 1) != LAVA:
				_rock.draw_rect(Rect2(r.position, Vector2(CS, 4)), col.lightened(0.25))
			if not is_solid(x, y + 1):
				_rock.draw_rect(Rect2(r.position + Vector2(0, CS - 4), Vector2(CS, 4)), col.darkened(0.45))
			if not is_solid(x - 1, y):
				_rock.draw_rect(Rect2(r.position, Vector2(3, CS)), col.lightened(0.1))
			if not is_solid(x + 1, y):
				_rock.draw_rect(Rect2(r.position + Vector2(CS - 3, 0), Vector2(3, CS)), col.darkened(0.3))
			if t == BASALT:
				_rock.draw_line(r.position + Vector2(8, 2), r.position + Vector2(8, CS - 2), Color(1, 1, 1, 0.06), 2.0)
				_rock.draw_line(r.position + Vector2(22, 2), r.position + Vector2(22, CS - 2), Color(1, 1, 1, 0.06), 2.0)
			elif z >= 3 and h > 0.8:
				# glowing cracks in the hot rock
				_rock.draw_line(r.position + Vector2(4, 6 + h * 10), r.position + Vector2(CS - 6, 12 + h * 12), Color(1.0, 0.35, 0.1, 0.5), 2.0)
			elif h > 0.85:
				_rock.draw_circle(r.position + Vector2(8 + h * 14, 10), 2.5, col.darkened(0.3))


func _build_lava() -> void:
	var cells_l: Array[Vector2i] = []
	for y in H:
		for x in W:
			if cells[idx(x, y)] == LAVA:
				cells_l.append(Vector2i(x, y))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lava2d.gdshader")
	var pools := Node2D.new()
	pools.z_index = 1
	pools.material = mat
	add_child(pools)
	pools.draw.connect(func():
		for c in cells_l:
			pools.draw_rect(Rect2(c.x * CS, c.y * CS + 6, CS, CS - 6), Color.WHITE)
	)
	pools.queue_redraw()
	var lit := 0
	for c in cells_l:
		if lit < 30 and (c.x + c.y) % 3 == 0:
			var l := PointLight2D.new()
			l.texture = light_tex()
			l.texture_scale = 2.2
			l.color = Color(1.0, 0.45, 0.12)
			l.energy = 0.8
			l.position = cell_centre(c)
			add_child(l)
			lit += 1
	# the core and the rising magma share the lava look
	_magma = Node2D.new()
	_magma.z_index = 3
	_magma.material = mat
	add_child(_magma)
	_magma.draw.connect(func():
		_magma.draw_rect(Rect2(-CS * 12, magma_y, (W + 24) * CS, H * CS - magma_y + CS * 10), Color.WHITE)
	)
	_magma_light = PointLight2D.new()
	_magma_light.texture = light_tex()
	_magma_light.texture_scale = 14.0
	_magma_light.color = Color(1.0, 0.4, 0.1)
	_magma_light.energy = 0.8
	add_child(_magma_light)
	var core := Node2D.new()
	core.z_index = 2
	var cm := CanvasItemMaterial.new()
	cm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	core.material = cm
	add_child(core)
	core.draw.connect(func():
		var c := Vector2(W * CS * 0.5, (H + 30) * CS)
		for k in 8:
			core.draw_circle(c, (40 - k * 3) * CS, Color(1.0, 0.7 + k * 0.03, 0.3 + k * 0.08, 0.12 + k * 0.08))
	)
	core.queue_redraw()


var _fg: Node2D

func _build_fg() -> void:
	_fg = Node2D.new()
	_fg.z_index = 5
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_fg.material = m
	add_child(_fg)
	_fg.draw.connect(_draw_fg)


func _draw_fg() -> void:
	var font := ThemeDB.fallback_font
	# section dividers and names down the left side of the cutaway
	for z in range(0, ZONES.size()):
		var y: float = ZONES[z].top * CS
		if z > 0:
			var x := -CS * 10.0
			while x < (W + 10) * CS:
				_fg.draw_line(Vector2(x, y), Vector2(x + 26, y), Color(1.0, 0.8, 0.6, 0.35), 2.0)
				x += 44.0
		var label: String = ZONES[z].name.to_upper()
		_fg.draw_string(font, Vector2(-CS * 9.5, y + 30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.65, 0.8))
		if z > 0 and z < 5:
			var names := []
			for l in LOOT[z]:
				names.append(Db.item_name(l[0]))
			_fg.draw_string(font, Vector2(-CS * 9.5, y + 54), ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, CS * 9, 14, Color(1.0, 0.85, 0.65, 0.5))
	# deposits: glowing crystals on pocket floors
	for d in deposits:
		if d.taken:
			continue
		var p: Vector2 = d.pos
		var col := Db.item_color(d.item)
		var tw := 0.7 + 0.3 * sin(_t * 3.0 + p.x)
		_fg.draw_circle(p + Vector2(0, -10), 18.0, Color(col, 0.12 * tw))
		for k in 3:
			var bx := p.x - 9 + k * 9
			var hh := 10.0 + (k % 2) * 8.0
			_fg.draw_colored_polygon(PackedVector2Array([Vector2(bx - 4, p.y), Vector2(bx + 4, p.y), Vector2(bx + 1, p.y - hh), Vector2(bx - 1, p.y - hh - 3)]), col.lightened(0.15 * tw))
	# geysers
	for g in geysers:
		var gx: float = (g.x + 0.5) * CS
		var gy: float = (g.y + 1) * CS
		_fg.draw_colored_polygon(PackedVector2Array([Vector2(gx - 12, gy), Vector2(gx + 12, gy), Vector2(gx + 5, gy - 8), Vector2(gx - 5, gy - 8)]), Color("5a2a1a"))
		if g.state == "warn":
			_fg.draw_circle(Vector2(gx, gy - 8), 5.0 + sin(_t * 20.0) * 2.0, Color(1.0, 0.6, 0.2))
		elif g.state == "blast":
			var top_y: float = g.top * CS
			for k in 4:
				var w := 10.0 + k * 5.0
				_fg.draw_rect(Rect2(gx - w * 0.5, top_y, w, gy - top_y), Color(1.0, 0.55 + k * 0.1, 0.2, 0.25 - k * 0.05))
	# magma surface: a bright crust line with bubbles
	var pts := PackedVector2Array()
	for i in 60:
		var x := -CS * 12.0 + i * (W + 24) * CS / 59.0
		pts.append(Vector2(x, magma_y + sin(x * 0.02 + _t * 2.0) * 5.0))
	_fg.draw_polyline(pts, Color(1.0, 0.9, 0.5, 0.9), 4.0)
	for k in 10:
		var bx2 := fmod(k * 197.0 + _t * 40.0 * (1 + k % 3), float((W + 24) * CS)) - CS * 12.0
		var ph := fmod(_t * 0.8 + k * 0.37, 1.0)
		_fg.draw_arc(Vector2(bx2, magma_y - ph * 20.0), 6.0 * (1.0 - ph), PI, TAU, 8, Color(1.0, 0.8, 0.4, 1.0 - ph), 2.0)
	for f in _fx:
		_fg.draw_circle(f.pos, 3.0, Color(f.col, clampf(f.t * 2.0, 0.0, 1.0)))
	# heat shimmer: a faint orange wash near the magma
	if magma_y - runner.position.y < 400.0:
		var a := clampf(1.0 - (magma_y - runner.position.y) / 400.0, 0.0, 1.0) * 0.12
		_fg.draw_rect(Rect2(runner.position - Vector2(1200, 800), Vector2(2400, 1600)), Color(1.0, 0.4, 0.1, a))


func _build_meter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-200, 84)
	top.custom_minimum_size = Vector2(400, 0)
	top.theme = UiKit.theme()
	top.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.03, 0.02, 0.85), Color(1.0, 0.45, 0.2, 0.6), 8, 1, 8))
	layer.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	_timer_label = UiKit.label("ERUPTION IN %d:%02d" % [int(DURATION) / 60, int(DURATION) % 60], 26, Color.WHITE, true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_timer_label)
	_goal_label = UiKit.label("Dive for crystals, then climb back out the rim", 14, Color("ffd98a"))
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_goal_label)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	pc.position = Vector2(-200, 100)
	pc.custom_minimum_size = Vector2(180, 0)
	pc.theme = UiKit.theme()
	layer.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(UiKit.label("DEPTH", 12, UiKit.MUTED, true))
	_depth_label = UiKit.label("0 m", 28, Color("ffb86b"), true)
	v.add_child(_depth_label)
	_zone_label = UiKit.label("", 14, Color("ffd98a"))
	v.add_child(_zone_label)
	v.add_child(UiKit.label("HEAT", 11, UiKit.MUTED, true))
	_heat_bar = ProgressBar.new()
	_heat_bar.max_value = 100.0
	_heat_bar.show_percentage = false
	_heat_bar.custom_minimum_size = Vector2(0, 10)
	_heat_bar.add_theme_stylebox_override("fill", UiKit.box(Color("ff5a2a"), Color("ff5a2a"), 3, 0, 0))
	v.add_child(_heat_bar)
	v.add_child(UiKit.label("JET FUEL", 11, UiKit.MUTED, true))
	_fuel_bar = ProgressBar.new()
	_fuel_bar.max_value = 100.0
	_fuel_bar.show_percentage = false
	_fuel_bar.custom_minimum_size = Vector2(0, 10)
	_fuel_bar.add_theme_stylebox_override("fill", UiKit.box(Color("5ff7ff"), Color("5ff7ff"), 3, 0, 0))
	v.add_child(_fuel_bar)


# --------------------------------------------------------------------------
# the briefing
# --------------------------------------------------------------------------

func _show_briefing() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	var pc := PanelContainer.new()
	pc.theme = UiKit.theme()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(640, 0)
	pc.position = Vector2(-320, -200)
	pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.03, 0.02, 0.94), Color(1.0, 0.45, 0.2, 0.8), 12, 2, 22))
	layer.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	v.add_child(UiKit.label("ERUPTION RUN", 30, Color("ffb86b"), true))
	v.add_child(UiKit.label("%s's volcano blows in %d:%02d. Get in, grab what you can, get out." % [planet.name, int(DURATION) / 60, int(DURATION) % 60], 16, Color.WHITE))
	for line in [
		["Dive", "Run and jetpack down the lava tube. Glowing crystals get richer the deeper you go: Fire Opals from the Obsidian Galleries down, Core Embers in the Deep Mantle."],
		["Mine", "Hold %s at a crystal. Push into rock to drill through it, hold %s to drill down, and jetpack into a ceiling to drill up. Black basalt won't budge." % [Game.key("interact"), Game.key("move_back")]],
		["Escape", "Climb back to the crater rim and press %s before the timer runs out. Geysers throw you upward." % Game.key("interact")],
		["Eruption", "If it blows while you're inside, you're blasted out with 40% hull and half of what you mined is lost in the ash. Heat and lava hurt too, so watch the heat bar."],
	]:
		var r := UiKit.rich("[b][color=#ffb86b]%s[/color][/b]   %s" % [line[0], line[1]], 15)
		r.fit_content = true
		v.add_child(r)
	var go := UiKit.label("Press any key to start the clock", 15, Color("9bd1ff"), true)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(go)
	_brief = layer


func _any_input() -> bool:
	for a in ["move_left", "move_right", "move_forward", "move_back", "jump", "interact", "fire"]:
		if Input.is_action_just_pressed(a):
			return true
	return Input.is_action_just_pressed("ui_accept")


## Start the eruption clock (called when the briefing is dismissed).
func start_run() -> void:
	if not _briefing:
		return
	_briefing = false
	if is_instance_valid(_brief):
		_brief.queue_free()
	Sound.play("klaxon", -14.0, 0.0)
