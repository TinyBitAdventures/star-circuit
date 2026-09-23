extends Node2D
## Orbit view: a side-on cutaway of a world with your ship circling above
## the sky. Drop a tethered Deep Probe through crust, mantle and core to
## pull out the world's gems (1-3 per world, gone once taken) and ore.

const PROBE_SPEED := 115.0
const PROBE_DIVE := 200.0
const PROBE_SLOW := 45.0
const PROBE_STEER := 80.0
const REEL_SPEED := 300.0
const ORBIT_DRIFT := 0.1
const ORBIT_STEER := 0.55
const SPIN := 0.045 # planet rotation, rad/s
const LAUNCH_ENERGY := 8.0

# layer boundaries as fractions of the radius
const CRUST := 0.86
const MANTLE := 0.55
const CORE := 0.26

var info := {}
var hud: CanvasLayer
var gems: Array = [] # {idx, pos (planet-local), item, taken}
var ores: Array = [] # {pos, item, qty, taken}
var rocks: Array = [] # {pos, r, poly (local PackedVector2Array)}
var centre := Vector2.ZERO
var R := 300.0
var rot := 0.0
var ship_angle := -PI * 0.5
var scanned := false
var _t := 0.0
var _stars: Array = []
var _sea := false
var _cols := {}
var _giant := false
var _accent := Color.WHITE
var _glow := Color.WHITE

# probe state: "" (docked), "down", "reel"
var probe_state := ""
var probe_pos := Vector2.ZERO
var probe_hull := 100.0
var probe_heat := 0.0
var probe_cargo := {} # {"kind": "gem"/"ore", "ref": Dictionary}
var _heat_warned := false
var _trail: Array = []
var _fx: Array = [] # {pos, vel, t, col}
var _flash := 0.0

var _bg: Node2D
var _planet: ColorRect
var _pmat: ShaderMaterial
var _panel_title: Label
var _panel_lines: Label
var _bars: Control


func _ready() -> void:
	info = Game.orbit
	if info.is_empty():
		# launched directly (dev): orbit the home world
		info = Game.orbit_info("planet", 0, 0)
		info["return"] = [0, 0, 0]
		Game.orbit = info
	_giant = info.kind == "giant"
	_accent = Color(Game.appearance.accent) if Game.appearance.has("accent") else Game.robot().color
	_glow = Color(Game.appearance.glow) if Game.appearance.has("glow") else Color("5ff7ff")
	_build_layers()
	_layout()
	_generate()
	_apply_colours()
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "orbit"
	add_child(hud)
	_build_panel()
	UiKit.add_vignette(self, 0.35)
	Sound.stop_all_loops()
	Sound.play_music("space", 2.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().size_changed.connect(_layout)
	hud.show_location_banner(info.name, ("Gas giant" if _giant else Db.BIOMES[info.biome].name + " world") + "  ·  holding orbit")
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			Game.tip("first_orbit", "Drop a Deep Probe with %s. Steer it with %s/%s, dive with %s, brake with %s. Scan with %s to find the gems. Stay out of the core and don't let it overheat. Press %s again to reel it in, and %s to leave orbit." % [Game.key("jump"), Game.key("move_left"), Game.key("move_right"), Game.key("move_back"), Game.key("move_forward"), Game.key("scan"), Game.key("jump"), Game.key("takeoff")])
	)


func _layout() -> void:
	var vs := get_viewport_rect().size
	centre = Vector2(vs.x * 0.5, vs.y * 0.5)
	R = minf(vs.x, vs.y) * 0.29
	if _planet:
		var ext := 1.4
		_planet.position = centre - Vector2.ONE * R * ext
		_planet.size = Vector2.ONE * R * ext * 2.0
		_pmat.set_shader_parameter("extent", ext)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_stars.clear()
	for i in 220:
		_stars.append([Vector2(rng.randf() * vs.x, rng.randf() * vs.y), rng.randf_range(0.6, 1.8), rng.randf()])


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info.seed) ^ 0x5eed
	if _giant:
		var h: float = info.hue
		_cols = {"surface": Color.from_hsv(h, 0.4, 0.85), "low": Color.from_hsv(fmod(h + 0.06, 1.0), 0.55, 0.7), "peak": Color.from_hsv(h, 0.15, 1.0),
			"crust": Color.from_hsv(h, 0.5, 0.55), "mantle": Color.from_hsv(fmod(h + 0.6, 1.0), 0.45, 0.35),
			"core": Color("ffcf6b"), "atmo": Color.from_hsv(h, 0.35, 1.0)}
	else:
		var b: Dictionary = Db.BIOMES[info.biome]
		var c: Dictionary = b.colors
		_sea = float(b.sea) >= 0.0
		_cols = {"surface": c.mid, "low": c.low, "high": c.high, "peak": c.peak, "water": c.deep, "crust": (c.rock as Color),
			"mantle": (c.rock as Color).darkened(0.5).lerp(Color("4a2418"), 0.5), "core": Color("ffb347"), "atmo": b.atmo}
	# gems
	gems.clear()
	var taken: Array = Game.gems_taken.get(info.key, [])
	for g in Game.world_gems(info):
		var rr: float = R * (1.0 - float(g.depth) * 0.85)
		gems.append({"idx": g.idx, "pos": Vector2.from_angle(g.angle) * rr, "item": info.gem, "taken": taken.has(g.idx)})
	# ore pockets (refill every visit)
	var pool: Array = []
	if _giant:
		pool = ["plasma", "cryo_ice", "stardust"]
	else:
		for n in Db.BIOMES[info.biome].nodes:
			var it: String = Db.NODES[n].item
			if it != "plasma" and not pool.has(it):
				pool.append(it)
		pool.append_array(["stardust", "voidshard"])
	ores.clear()
	for i in rng.randi_range(7, 10):
		var a := rng.randf() * TAU
		var rr := R * rng.randf_range(0.42, 0.92)
		var it: String = pool[rng.randi() % pool.size()]
		var deep := rr < R * 0.6
		ores.append({"pos": Vector2.from_angle(a) * rr, "item": it, "qty": rng.randi_range(2, 4) + (2 if deep else 0), "taken": false})
	# faultstone: dense rock that crushes probes
	rocks.clear()
	for i in rng.randi_range(9, 14):
		var a := rng.randf() * TAU
		var rr := R * rng.randf_range(0.35, 0.8)
		var size := rng.randf_range(12.0, 26.0) * R / 300.0
		var poly := PackedVector2Array()
		for k in 9:
			poly.append(Vector2.from_angle(TAU * k / 9.0) * size * rng.randf_range(0.75, 1.15))
		var p := Vector2.from_angle(a) * rr
		# keep clear of gems so every gem is reachable
		var ok := true
		for g in gems:
			if p.distance_to(g.pos) < size + 34.0:
				ok = false
		if ok:
			rocks.append({"pos": p, "r": size, "poly": poly})


# --------------------------------------------------------------------------
# frame
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	rot = fmod(rot + SPIN * delta, TAU)
	_flash = maxf(0.0, _flash - delta * 2.0)
	var ui := Game.ui_open
	var steer := 0.0 if ui else Input.get_axis("move_left", "move_right")
	# the ship drifts along its orbit; A/D speed it up or back it off while docked
	if probe_state == "":
		ship_angle += (ORBIT_DRIFT + steer * ORBIT_STEER) * delta
	else:
		ship_angle += ORBIT_DRIFT * 0.35 * delta
	if not ui:
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("interact"):
			if probe_state == "":
				_launch()
			elif probe_state == "down":
				_start_reel()
		if Input.is_action_just_pressed("scan"):
			_scan()
		if Input.is_action_just_pressed("takeoff"):
			_leave()
			return
		if Input.is_action_just_pressed("use_cell"):
			Game.use_energy_cell()
	match probe_state:
		"down":
			_probe_down(delta, steer, ui)
		"reel":
			_probe_reel(delta)
	for f in _fx.duplicate():
		f.t -= delta
		f.pos += f.vel * delta
		f.vel *= 0.96
		if f.t <= 0.0:
			_fx.erase(f)
	_update_panel()
	_update_prompt()
	queue_redraw()


func ship_pos() -> Vector2:
	return centre + Vector2.from_angle(ship_angle) * (R * 1.24 + 18.0)


func _to_local(p: Vector2) -> Vector2:
	return (p - centre).rotated(-rot)


func _to_screen(lp: Vector2) -> Vector2:
	return centre + lp.rotated(rot)


func _launch() -> void:
	if Game.count("deep_probe") <= 0:
		Game.notify.emit("No Deep Probes. Fabricate them (Alloy, Nickel-Iron, Solar Plasma).", Color("ff6b6b"))
		Sound.ui("ui_error", -4.0)
		return
	if not Game.spend_energy(LAUNCH_ENERGY):
		Game.notify.emit("Not enough energy to launch a probe.", Color("ff6b6b"))
		Sound.ui("ui_error", -4.0)
		return
	probe_state = "down"
	probe_pos = ship_pos()
	probe_hull = 100.0
	probe_heat = 0.0
	probe_cargo = {}
	_heat_warned = false
	_trail.clear()
	Sound.play("turret_deploy", -4.0, 0.05)
	Sound.loop_start("probe", "thruster_loop", -14.0)


func _start_reel() -> void:
	probe_state = "reel"
	Sound.loop_stop("probe", 0.2)
	Sound.loop_start("reel", "siphon_loop", -12.0)


func _probe_down(delta: float, steer: float, ui: bool) -> void:
	var to_c := (centre - probe_pos)
	var down := to_c.normalized()
	var side := Vector2(-down.y, down.x)
	var speed := PROBE_SPEED
	if not ui and Input.is_action_pressed("move_back"):
		speed = PROBE_DIVE
	elif not ui and Input.is_action_pressed("move_forward"):
		speed = PROBE_SLOW
	probe_pos += (down * speed - side * steer * PROBE_STEER) * delta
	_trail.append(probe_pos)
	if _trail.size() > 60:
		_trail.pop_front()
	var lp := _to_local(probe_pos)
	var r := lp.length()
	# heat builds in the outer core
	var heat_rate := 34.0 * (0.5 if Game.has_upgrade("lava_plating") else 1.0)
	if r < R * MANTLE:
		probe_heat += heat_rate * delta
		if probe_heat > 65.0 and not _heat_warned:
			_heat_warned = true
			Sound.play("low_energy", -6.0, 0.0)
			Game.notify.emit("Probe overheating! Reel it in (%s)." % Game.key("jump"), Color("ff7a3d"))
	else:
		probe_heat = maxf(0.0, probe_heat - 12.0 * delta)
		_heat_warned = probe_heat > 50.0 and _heat_warned
	if r < R * CORE:
		_lose_probe("The probe melted in the core.")
		return
	if probe_heat >= 100.0:
		_lose_probe("The probe cooked in the outer core.")
		return
	# faultstone
	for k in rocks:
		if lp.distance_to(k.pos) < float(k.r) + 5.0:
			probe_hull -= 40.0
			_flash = 1.0
			_burst(probe_pos, Color("c9ced6"), 10)
			Sound.play("hit", -4.0, 0.1)
			var out := (lp - (k.pos as Vector2)).normalized()
			probe_pos = _to_screen(k.pos + out * (float(k.r) + 12.0))
			if probe_hull <= 0.0:
				_lose_probe("Faultstone crushed the probe.")
				return
			Game.notify.emit("Faultstone! Probe hull %d%%" % int(probe_hull), Color("ffb86b"))
			break
	# grab things
	for g in gems:
		if not g.taken and lp.distance_to(g.pos) < 20.0:
			g.taken = true
			probe_cargo = {"kind": "gem", "ref": g}
			_burst(probe_pos, Db.item_color(g.item), 18)
			Sound.play("pickup", -2.0, 0.0)
			Game.notify.emit("Gem locked in the probe's claws! Reeling in...", Db.item_color(g.item))
			_start_reel()
			return
	for o in ores:
		if not o.taken and lp.distance_to(o.pos) < 15.0:
			o.taken = true
			probe_cargo = {"kind": "ore", "ref": o}
			_burst(probe_pos, Db.item_color(o.item), 10)
			Sound.play("rock_break", -6.0, 0.1)
			_start_reel()
			return
	# drifted back out into space: reel it in
	if r > R * 1.3:
		_start_reel()


func _probe_reel(delta: float) -> void:
	var sp := ship_pos()
	var d := sp - probe_pos
	var step := REEL_SPEED * delta
	probe_heat = maxf(0.0, probe_heat - 20.0 * delta)
	if d.length() <= step:
		_dock_probe()
		return
	probe_pos += d.normalized() * step
	if probe_cargo.get("kind", "") == "gem":
		_trail.append(probe_pos)
		if _trail.size() > 60:
			_trail.pop_front()


func _dock_probe() -> void:
	probe_state = ""
	_trail.clear()
	Sound.loop_stop("reel", 0.2)
	Sound.loop_stop("probe", 0.2)
	match probe_cargo.get("kind", ""):
		"gem":
			var g: Dictionary = probe_cargo.ref
			Game.take_gem(info, int(g.idx))
			Sound.play("quest_complete", -2.0, 0.0, "UI")
			_burst(ship_pos(), Db.item_color(g.item), 26)
		"ore":
			var o: Dictionary = probe_cargo.ref
			var got := Game.add_item(o.item, int(o.qty))
			if got > 0:
				Game.gain_skill_xp("mining", 20.0)
				Sound.play("coin", -8.0, 0.1, "UI")
	probe_cargo = {}


func _lose_probe(why: String) -> void:
	probe_state = ""
	Sound.loop_stop("probe", 0.2)
	Sound.loop_stop("reel", 0.2)
	Sound.play("enemy_die", -4.0, 0.1)
	_burst(probe_pos, Color("ff7a3d"), 24)
	_flash = 1.0
	Game.remove_item("deep_probe", 1)
	# anything it was carrying drops back where it was
	if probe_cargo.get("kind", "") != "":
		probe_cargo.ref.taken = false
	probe_cargo = {}
	_trail.clear()
	Game.notify.emit("%s  %d probe%s left." % [why, Game.count("deep_probe"), "" if Game.count("deep_probe") == 1 else "s"], Color("ff6b6b"))


func _scan() -> void:
	if scanned:
		Game.notify.emit("Core already charted: %d gem%s left here." % [_gems_left(), "" if _gems_left() == 1 else "s"], Color("9bd1ff"))
		return
	if not Game.spend_energy(5.0):
		return
	scanned = true
	Sound.play("scan", -4.0, 0.0)
	Game.gain_skill_xp("exploration", 25)
	var n := _gems_left()
	Game.notify.emit(("Deep scan: %d gem%s in the core" % [n, "" if n == 1 else "s"]) if n > 0 else "Deep scan: this core has been picked clean. Ore pockets remain.", Color("9bd1ff"))
	if not Game.gems_taken.has(info.key):
		Game.gems_taken[info.key] = [] # charted


func _gems_left() -> int:
	var n := 0
	for g in gems:
		if not g.taken:
			n += 1
	return n


func _leave() -> void:
	if probe_state != "":
		Game.notify.emit("Reel the probe in first (%s)." % Game.key("jump"), Color("ffb86b"))
		return
	Sound.stop_all_loops()
	Game.leave_orbit()


func _burst(p: Vector2, col: Color, n: int) -> void:
	for i in n:
		_fx.append({"pos": p, "vel": Vector2.from_angle(randf() * TAU) * randf_range(40, 170), "t": randf_range(0.4, 0.9), "col": col})


# --------------------------------------------------------------------------
# HUD bits
# --------------------------------------------------------------------------

func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pc.position = Vector2(20, 236)
	pc.custom_minimum_size = Vector2(300, 0)
	pc.theme = UiKit.theme()
	layer.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(UiKit.label("DEEP PROBE", 12, UiKit.MUTED, true))
	_panel_title = UiKit.label(info.name, 20, Db.item_color(info.gem), true)
	v.add_child(_panel_title)
	_panel_lines = UiKit.label("", 14)
	v.add_child(_panel_lines)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(270, 34)
	_bars.draw.connect(func():
		if probe_state == "":
			return
		var font := ThemeDB.fallback_font
		_bars.draw_string(font, Vector2(0, 11), "HULL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.MUTED)
		_bars.draw_rect(Rect2(44, 3, 220, 8), Color(1, 1, 1, 0.1))
		_bars.draw_rect(Rect2(44, 3, 220 * probe_hull / 100.0, 8), Color("6ee06a"))
		_bars.draw_string(font, Vector2(0, 29), "HEAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.MUTED)
		_bars.draw_rect(Rect2(44, 21, 220, 8), Color(1, 1, 1, 0.1))
		_bars.draw_rect(Rect2(44, 21, 220 * clampf(probe_heat / 100.0, 0.0, 1.0), 8), Color("ffb347").lerp(Color("ff3b3b"), clampf(probe_heat / 100.0, 0.0, 1.0)))
	)
	v.add_child(_bars)


func _update_panel() -> void:
	var total := gems.size()
	var gl := "Gems: %d / %d left" % [_gems_left(), total] if scanned or Game.gems_taken.has(info.key) else "Gems: unknown  (scan with %s)" % Game.key("scan")
	var held := Game.count(info.gem)
	_panel_lines.text = "%s\n%s held: %d\nDeep Probes: %d\nDifferent gems collected: %d / 10" % [gl, Db.item_name(info.gem), held, Game.count("deep_probe"), Game.gem_types()]
	_bars.queue_redraw()


func _update_prompt() -> void:
	var txt := ""
	match probe_state:
		"":
			txt = "[%s] Launch probe   ·   A/D move along orbit   ·   [%s] Deep scan   ·   [%s] Leave orbit" % [Sound.key_name("jump"), Sound.key_name("scan"), Sound.key_name("takeoff")]
			if Game.count("deep_probe") <= 0:
				txt = "No Deep Probes left. Fabricate more (C).   ·   [%s] Leave orbit" % Sound.key_name("takeoff")
		"down":
			txt = "A/D steer   ·   S dive   ·   W brake   ·   [%s] Reel in" % Sound.key_name("jump")
		"reel":
			txt = "Reeling in..."
	hud.set_prompt(txt, Color("9bd1ff"), 0.0)


# --------------------------------------------------------------------------
# drawing
# --------------------------------------------------------------------------

func _build_layers() -> void:
	_bg = Node2D.new()
	_bg.z_index = -2
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	_planet = ColorRect.new()
	_planet.z_index = -1
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pmat = ShaderMaterial.new()
	_pmat.shader = preload("res://shaders/orbit_planet.gdshader")
	_planet.material = _pmat
	add_child(_planet)


func _apply_colours() -> void:
	_pmat.set_shader_parameter("giant", _giant)
	_pmat.set_shader_parameter("sea", _sea)
	_pmat.set_shader_parameter("seed", float(int(info.seed) % 1000))
	for k in ["surface", "low", "peak", "water", "crust", "mantle", "atmo"]:
		if _cols.has(k):
			_pmat.set_shader_parameter("c_" + k, _cols[k])
	var vs := get_viewport_rect().size
	var sun := Vector2(vs.x * 0.08, vs.y * 0.1)
	_pmat.set_shader_parameter("sun_dir", (sun - centre).normalized())


func _draw_bg() -> void:
	var vs := get_viewport_rect().size
	_bg.draw_rect(Rect2(Vector2.ZERO, vs), Color("04060c"))
	# a faint nebula wash
	for k in 5:
		_bg.draw_circle(Vector2(vs.x * (0.78 + k * 0.03), vs.y * (0.25 + k * 0.1)), 220.0 - k * 25.0, Color(0.35, 0.2, 0.55, 0.035))
	for s in _stars:
		var tw := 0.55 + 0.45 * sin(_t * 1.5 + float(s[2]) * 40.0)
		_bg.draw_circle(s[0], s[1], Color(1, 1, 1, 0.3 + 0.45 * tw * float(s[2])))
	# the sun, far off to the upper left
	var sun := Vector2(vs.x * 0.08, vs.y * 0.1)
	for k in 7:
		_bg.draw_circle(sun, 26.0 + k * 24.0, Color(1.0, 0.85, 0.55, 0.045))
	_bg.draw_circle(sun, 20.0, Color(1.0, 0.96, 0.82))
	if info.get("rings", false):
		_draw_rings(_bg, false)


func _draw() -> void:
	var vs := get_viewport_rect().size
	_bg.queue_redraw()
	_pmat.set_shader_parameter("rot", rot)
	if info.get("rings", false):
		_draw_rings(self, true)
	_draw_interior()
	# orbit path + ship
	draw_arc(centre, R * 1.24 + 18.0, 0.0, TAU, 160, Color(0.6, 0.85, 1.0, 0.08), 1.0, true)
	_draw_probe()
	_draw_ship()
	for f in _fx:
		draw_circle(f.pos, 2.5 * clampf(f.t * 2.0, 0.2, 1.0), Color(f.col, clampf(f.t * 1.6, 0.0, 1.0)))
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.4, 0.2, _flash * 0.12))


func _draw_interior() -> void:
	# faultstone
	for k in rocks:
		var poly := PackedVector2Array()
		for p in k.poly:
			poly.append(_to_screen(k.pos + p))
		draw_colored_polygon(poly, Color("24232c"))
		var hi := PackedVector2Array()
		for p in k.poly:
			hi.append(_to_screen(k.pos + p * 0.55 + Vector2(-2, -2).rotated(-rot)))
		draw_colored_polygon(hi, Color("34333f"))
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color("5c5a70"), 1.5, true)
	# ore pockets: little crystal clusters
	for o in ores:
		if o.taken:
			continue
		var sp := _to_screen(o.pos)
		var col := Db.item_color(o.item)
		draw_circle(sp, 9.0, Color(col, 0.12))
		for j in 3:
			var off := Vector2.from_angle(j * 2.1 + float(o.qty)) * 4.5
			draw_colored_polygon(_diamond(sp + off, 3.2), col)
			draw_colored_polygon(_diamond(sp + off + Vector2(-0.8, -1.0), 1.4), col.lightened(0.6))
	# gems: faint shimmer until scanned, then a bright faceted stone
	var reveal := scanned or Game.gems_taken.has(info.key)
	for g in gems:
		if g.taken:
			continue
		var sp := _to_screen(g.pos)
		var col := Db.item_color(g.item)
		if reveal:
			for k in 5:
				draw_circle(sp, 10.0 + k * 5.0 + sin(_t * 3.0) * 1.5, Color(col, 0.06))
			draw_colored_polygon(_diamond(sp, 11.0), col.darkened(0.2))
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -13.2), sp + Vector2(11, 0), sp]), col)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -13.2), sp + Vector2(-11, 0), sp]), col.lightened(0.35))
			draw_colored_polygon(_diamond(sp + Vector2(-3, -4), 2.6), Color(1, 1, 1, 0.85))
			var tw := maxf(0.0, sin(_t * 4.0 + float(g.idx) * 2.0))
			draw_line(sp + Vector2(-10, 0) * tw, sp + Vector2(10, 0) * tw, Color(1, 1, 1, 0.7 * tw), 1.5)
			draw_line(sp + Vector2(0, -14) * tw, sp + Vector2(0, 14) * tw, Color(1, 1, 1, 0.7 * tw), 1.5)
		else:
			var a := 0.14 + 0.1 * sin(_t * 2.0 + float(g.idx))
			draw_circle(sp, 8.0, Color(1, 1, 1, a))
			draw_circle(sp, 3.0, Color(1, 1, 1, a * 1.5))


func _diamond(p: Vector2, s: float) -> PackedVector2Array:
	return PackedVector2Array([p + Vector2(0, -s * 1.2), p + Vector2(s, 0), p + Vector2(0, s * 1.2), p + Vector2(-s, 0)])


func _draw_rings(ci: CanvasItem, front: bool) -> void:
	# rings seen nearly edge-on: a thin ellipse, back half behind the planet
	var col := Color((_cols.atmo as Color).lightened(0.35), 0.55)
	var pts := PackedVector2Array()
	for i in 97:
		var a := PI * i / 96.0 + (PI if not front else 0.0)
		pts.append(centre + Vector2(cos(a) * R * 1.9, sin(a) * R * 0.16))
	ci.draw_polyline(pts, col, 5.0, true)
	ci.draw_polyline(pts, Color(col, 0.25), 11.0, true)


func _draw_ship() -> void:
	var sp := ship_pos()
	var fwd := Vector2.from_angle(ship_angle + PI * 0.5)
	var out := Vector2.from_angle(ship_angle)
	var side := Vector2(-fwd.y, fwd.x)
	var body := PackedVector2Array([sp + fwd * 16.0, sp - fwd * 10.0 + side * 9.0, sp - fwd * 6.0, sp - fwd * 10.0 - side * 9.0])
	draw_colored_polygon(body, Color("e6e8ec"))
	draw_colored_polygon(PackedVector2Array([sp + fwd * 6.0, sp - fwd * 4.0 + side * 4.0, sp - fwd * 4.0 - side * 4.0]), _accent)
	var flame := 6.0 + sin(_t * 30.0) * 2.0
	draw_colored_polygon(PackedVector2Array([sp - fwd * 8.0 + side * 3.0, sp - fwd * (8.0 + flame), sp - fwd * 8.0 - side * 3.0]), _glow)
	# docking arm pointing down at the world when a probe is out
	if probe_state == "":
		draw_circle(sp - out * 9.0, 3.0, Color("9bd1ff") if Game.count("deep_probe") > 0 else Color("555a66"))


func _draw_probe() -> void:
	if probe_state == "":
		return
	var sp := ship_pos()
	# tether
	var tcol := Color(0.6, 0.85, 1.0, 0.55)
	draw_line(sp, probe_pos, tcol, 1.5, true)
	if _trail.size() > 1:
		draw_polyline(PackedVector2Array(_trail), Color(_glow, 0.25), 2.0, true)
	var heat := clampf(probe_heat / 100.0, 0.0, 1.0)
	var body := Color("c9ced6").lerp(Color("ff5a2a"), heat)
	draw_circle(probe_pos, 7.0, body)
	draw_circle(probe_pos, 3.0, _glow if probe_state == "down" else Color.WHITE)
	# a halo that brightens as it heats
	if heat > 0.2:
		draw_circle(probe_pos, 12.0 + heat * 8.0, Color(1.0, 0.45, 0.1, heat * 0.25))
	if probe_cargo.get("kind", "") == "gem":
		draw_colored_polygon(_diamond(probe_pos + Vector2(0, 11), 6.0), Db.item_color(probe_cargo.ref.item))
