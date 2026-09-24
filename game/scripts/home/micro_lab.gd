extends Control
## The Micro Lab: a bowl of primordial soup under the microscope. Each
## ingredient becomes a strain of cells swimming in the broth. Steer a
## tiny probe (WASD), zap a cell to tag it, then zap a cell of a different
## strain to fuse the two. Fused cells divide on their own; corruption
## phages hunt them. Reach critical mass before the culture goes off.
## Faster cultures grade higher: Stable, Refined, Pristine.
##
## Runs inside the Homespace (the tree is paused, so this processes always).
## The simulation is stepped in fixed slices so it plays the same at any
## frame rate; tests call step() directly with autoplay on.

signal closed(result: Dictionary)

const ARENA := 500.0 # logical dish radius
const RAY_RANGE := 320.0
const RAY_CD := 0.2
const TAG_TIME := 2.6
const FUSE_TIME := 0.45
const BASE_CELLS := 12
const MERGED_R := 30.0
const SPLIT_MIN := 12.0
const SPLIT_MAX := 17.0
const DIVIDE_TIME := 0.7
const INFECT_TIME := 2.4
const PHAGE_SPEED := 85.0
const PHAGE_MAX := 12
const PHAGE_R := 16.0
const PROBE_ACCEL := 1500.0
const PROBE_DRAG := 3.2 # the soup is thick
const PRISTINE_AT := 0.45 # stability left when critical mass is reached
const REFINED_AT := 0.2
const MOVE_WORDS := {"drift": "drifts", "dart": "darts", "blink": "blinks", "swarm": "swarms", "armor": "armoured, zap twice"}


class Cell:
	var p := Vector2.ZERO
	var v := Vector2.ZERO
	var r := 20.0
	var strain := 0 # index into strains, -1 for a merged cell
	var col := Color.WHITE
	var col2 := Color.WHITE # merged: the second parent's colour
	var move := "drift"
	var speed := 80.0
	var hp := 1
	var sd := 0.0
	var fade := 0.0
	var dash_t := 0.0
	var blink_t := 0.0
	var split_t := 0.0
	var div := -1.0 # merged: dividing progress 0..1, -1 when not dividing
	var div_dir := Vector2.RIGHT
	var infected := 0.0
	var fusing := false
	var dead := false


class Phage:
	var p := Vector2.ZERO
	var v := Vector2.ZERO
	var host: Cell = null
	var angle := 0.0 # where it sits on the host
	var fade := 0.0
	var dead := false


class Fusion:
	var a: Cell
	var b: Cell
	var t := 0.0


class Fx:
	var p := Vector2.ZERO
	var v := Vector2.ZERO
	var t := 0.0
	var life := 0.5
	var r := 4.0
	var col := Color.WHITE
	var ring := false
	var text := ""


var recipe_id := ""
var recipe: Dictionary = {}
var strains: Array[String] = []
var cells: Array[Cell] = []
var phages: Array[Phage] = []
var fusions: Array[Fusion] = []
var fx: Array[Fx] = []
var beams: Array = [] # [from, to, t]

var probe_p := Vector2(0, 220)
var probe_v := Vector2.ZERO
var aim := Vector2.UP
var tag: Cell = null
var tag_t := 0.0
var stability := 100.0
var time_total := 100.0
var mass := 14
var merges := 0
var phages_zapped := 0
var phase := "play" # play | result
var grade := -1
var result: Dictionary = {}
var autoplay := false
var bot_error := 0.0 # autoplay aim wobble (radians), to model a less precise player
var bot_rate := 0.0 # autoplay: least seconds between shots (a human needs time to aim)
var _bot_cd := 0.0
var manual := false # tests drive step() themselves
var elapsed := 0.0

var rng := RandomNumberGenerator.new()
var _t := 0.0
var _cd := 0.0
var _stir_t := 0.0
var _stir_dir := 1.0
var _stir_angle := 0.0
var _next_stir := 18.0
var _phage_t := 6.0
var _respawn_t := 0.0
var _bubble_t := 0.0
var _abandon_t := 0.0
var _result_t := 0.0
var _heat := 0.0

var _bg: ColorRect
var _mat: ShaderMaterial
var _view: Control
var _c := Vector2.ZERO
var _s := 1.0
var _glow := Color("5ff7ff")
var _accent := Color("ffb347")


func setup(id: String, seed_ := -1) -> void:
	recipe_id = id
	recipe = Db.lab_recipe(id)
	rng.seed = seed_ if seed_ >= 0 else randi()
	strains.clear()
	for k in recipe.in:
		strains.append(String(k))
	time_total = float(recipe.time)
	stability = time_total
	mass = int(recipe.mass)
	for i in BASE_CELLS:
		var c := _spawn_cell(_fewest_strain(), Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, ARENA * 0.8))
		c.fade = 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Game.appearance.has("glow"):
		_glow = Color(Game.appearance.glow)
	if Game.appearance.has("accent"):
		_accent = Color(Game.appearance.accent)
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/soup.gdshader")
	# the broth takes its colour from what went in
	var mix := Color(0, 0, 0)
	for sname in strains:
		mix += Db.item_color(sname)
	mix /= maxf(1.0, strains.size())
	_mat.set_shader_parameter("broth_a", Color("a8702a").lerp(mix, 0.3))
	_mat.set_shader_parameter("broth_b", Color("3c4a1a").lerp(mix.darkened(0.6), 0.3))
	_bg.material = _mat
	add_child(_bg)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_layout()


func _layout() -> void:
	# a Control under a CanvasLayer doesn't always pick up the viewport size, so set it
	var vs := get_viewport_rect().size
	if size != vs:
		position = Vector2.ZERO
		size = vs
	var rad := minf(vs.x * 0.34, vs.y * 0.41)
	_c = Vector2(vs.x * 0.5, vs.y * 0.52)
	_s = rad / ARENA
	if _mat:
		_mat.set_shader_parameter("rect_size", vs)
		_mat.set_shader_parameter("center", _c)
		_mat.set_shader_parameter("radius", rad)


func _S(p: Vector2) -> Vector2:
	return _c + p * _s


func _process(delta: float) -> void:
	_layout()
	if not manual:
		if not autoplay and phase == "play":
			_read_input(delta)
		step(delta)
	if _mat:
		_mat.set_shader_parameter("t", _t)
		_mat.set_shader_parameter("swirl", _stir_angle)
		_mat.set_shader_parameter("heat", _heat)
	_view.queue_redraw()


var _in_move := Vector2.ZERO
var _in_fire := false


func _read_input(_delta: float) -> void:
	_in_move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	var m := (_view.get_local_mouse_position() - _c) / _s
	if m.distance_to(probe_p) > 4.0:
		aim = (m - probe_p).normalized()
	_in_fire = Input.is_action_pressed("fire") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if phase == "result":
		if _result_t > 0.8 and (event.is_action("interact") or event.is_action("pause") or event.is_action("ui_accept") or event is InputEventMouseButton):
			_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action("pause") or event.is_action("home"):
		if _abandon_t > 0.0:
			_end(-1)
		else:
			_abandon_t = 2.5
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if phase == "result" and _result_t > 0.8 and event is InputEventMouseButton and event.is_pressed():
		accept_event()
		_close()


func _close() -> void:
	closed.emit(result)


# --------------------------------------------------------------------------
# simulation
# --------------------------------------------------------------------------

## Advance the dish by dt seconds in fixed slices (frame-rate independent).
func step(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.25)
	var n := maxi(1, int(ceil(dt / (1.0 / 60.0))))
	var h := dt / n
	for i in n:
		_tick(h)


func _tick(h: float) -> void:
	_t += h
	_tick_fx(h)
	if phase != "play":
		_result_t += h
		_heat = move_toward(_heat, 0.0 if grade >= 0 else 1.0, h)
		return
	elapsed += h
	_abandon_t = maxf(0.0, _abandon_t - h)
	stability -= h
	_heat = clampf(1.0 - stability / (time_total * 0.25), 0.0, 1.0)
	if stability <= 0.0:
		stability = 0.0
		_end(-1)
		return
	_tick_stir(h)
	if autoplay:
		_bot_cd -= h
		_bot()
	_tick_probe(h)
	_tick_cells(h)
	_tick_fusions(h)
	_tick_phages(h)
	_tick_spawns(h)
	_cd = maxf(0.0, _cd - h)
	if _in_fire and _cd <= 0.0:
		fire(aim)
	if tag:
		tag_t -= h
		if tag_t <= 0.0 or tag.dead or tag.fusing:
			tag = null
	if merged_count() >= mass:
		var frac := stability / time_total
		_end(2 if frac >= PRISTINE_AT else (1 if frac >= REFINED_AT else 0))


func _stir_amt() -> float:
	return sin(PI * clampf(1.0 - _stir_t / 4.5, 0.0, 1.0)) if _stir_t > 0.0 else 0.0


func _tick_stir(h: float) -> void:
	_next_stir -= h
	if _next_stir <= 0.0:
		_next_stir = rng.randf_range(16.0, 24.0)
		_stir_t = 4.5
		_stir_dir = -1.0 if rng.randf() < 0.5 else 1.0
		_text(Vector2(0, -ARENA * 0.55), "The soup swirls!", Color("ffe9a8"))
		_sfx("lab_stir", -6.0)
	_stir_t = maxf(0.0, _stir_t - h)
	_stir_angle += _stir_dir * (0.04 + _stir_amt() * 0.7) * h


func _flow(p: Vector2) -> Vector2:
	var k := 14.0 + _stir_amt() * 150.0
	var tang := Vector2(-p.y, p.x) / ARENA * _stir_dir
	return tang * k + Vector2(sin(p.y * 0.01 + _t * 0.4), cos(p.x * 0.012 - _t * 0.3)) * 10.0


func _tick_probe(h: float) -> void:
	probe_v += _in_move.limit_length(1.0) * PROBE_ACCEL * h
	probe_v *= exp(-PROBE_DRAG * h)
	probe_p += (probe_v + _flow(probe_p) * 0.3) * h
	var lim := ARENA - 18.0
	if probe_p.length() > lim:
		var nrm := probe_p.normalized()
		probe_p = nrm * lim
		if probe_v.dot(nrm) > 0.0:
			probe_v -= nrm * probe_v.dot(nrm) * 1.5
	if probe_v.length() > 120.0 and rng.randf() < h * 14.0:
		var b := _fx(probe_p - probe_v.normalized() * 14.0, -probe_v * 0.1, rng.randf_range(2.0, 4.0), Color(1, 1, 1, 0.5), 0.6)
		b.ring = true


func _tick_cells(h: float) -> void:
	# swarms pull toward their own kind
	var centres := {}
	for c in cells:
		if c.move == "swarm" and not c.dead:
			var acc: Array = centres.get(c.strain, [Vector2.ZERO, 0])
			centres[c.strain] = [acc[0] + c.p, int(acc[1]) + 1]
	var merged_now := merged_count()
	for c in cells:
		if c.dead or c.fusing:
			continue
		c.fade = minf(1.0, c.fade + h * 2.0)
		var wander := Vector2.from_angle(c.sd * 10.0 + _t * (0.5 + fmod(c.sd, 0.5)) + sin(_t * 0.9 + c.sd * 7.0) * 1.3)
		if c.strain < 0:
			c.v = c.v.lerp(wander * 40.0, clampf(h * 0.8, 0.0, 1.0))
			if c.div < 0.0:
				if c.infected <= 0.0:
					c.split_t -= h
				if c.split_t <= 0.0 and merged_now < mass:
					c.div = 0.0
					c.div_dir = Vector2.from_angle(rng.randf() * TAU)
			else:
				c.div += h / DIVIDE_TIME
				if c.div >= 1.0:
					_divide(c)
					merged_now += 1
		else:
			match c.move:
				"dart":
					c.dash_t -= h
					if c.dash_t <= 0.0:
						c.v = Vector2.from_angle(rng.randf() * TAU) * c.speed * 2.4
						c.dash_t = rng.randf_range(1.0, 2.0)
					else:
						c.v *= exp(-1.6 * h)
				"blink":
					c.v = c.v.lerp(wander * c.speed, clampf(h * 0.9, 0.0, 1.0))
					c.blink_t -= h
					if c.blink_t <= 0.0:
						_pop(c.p, c.col, 6, 0.4)
						c.p = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, ARENA * 0.8)
						c.fade = 0.3
						c.blink_t = rng.randf_range(2.8, 4.2)
				_:
					c.v = c.v.lerp(wander * c.speed, clampf(h * 0.9, 0.0, 1.0))
					if c.move == "swarm" and centres.has(c.strain):
						var acc: Array = centres[c.strain]
						var ctr: Vector2 = acc[0] / float(acc[1])
						c.v += (ctr - c.p).limit_length(1.0) * 90.0 * h
		c.p += (c.v + _flow(c.p)) * h
		var lim := ARENA - c.r
		if c.p.length() > lim:
			var nrm := c.p.normalized()
			c.p = nrm * lim
			if c.v.dot(nrm) > 0.0:
				c.v -= nrm * c.v.dot(nrm) * 2.0
	# soft separation so cells jostle instead of overlapping
	var n := cells.size()
	for i in n:
		var a := cells[i]
		if a.dead or a.fusing:
			continue
		for j in range(i + 1, n):
			var b := cells[j]
			if b.dead or b.fusing:
				continue
			var d := b.p - a.p
			var need := a.r + b.r
			var l := d.length()
			if l < need and l > 0.01:
				var push := d / l * (need - l) * 0.5
				a.p -= push
				b.p += push
	cells.assign(cells.filter(func(c: Cell) -> bool: return not c.dead))


func _divide(c: Cell) -> void:
	var off := c.div_dir * c.r * 0.6
	var twin := _new_merged(c.p + off, c.col, c.col2)
	twin.v = c.div_dir * 60.0
	twin.fade = 1.0
	c.p -= off
	c.v = -c.div_dir * 60.0
	c.div = -1.0
	c.split_t = _split_time()
	_pop(twin.p, c.col.lerp(c.col2, 0.5), 5, 0.35)
	_sfx("lab_divide", -8.0)


func _tick_fusions(h: float) -> void:
	for f in fusions:
		f.t += h
		var mid := (f.a.p + f.b.p) * 0.5
		f.a.p = f.a.p.lerp(mid, clampf(h * 9.0, 0.0, 1.0))
		f.b.p = f.b.p.lerp(mid, clampf(h * 9.0, 0.0, 1.0))
		if f.t >= FUSE_TIME:
			f.a.dead = true
			f.b.dead = true
			var m := _new_merged(mid, f.a.col, f.b.col)
			m.fade = 0.4
			merges += 1
			_pop(mid, Color("ffe9a8"), 10, 0.6)
			_text(mid + Vector2(0, -40), "Fused!", Color("ffe9a8"))
			_sfx("lab_fuse", -4.0)
	fusions.assign(fusions.filter(func(f: Fusion) -> bool: return f.t < FUSE_TIME))
	cells.assign(cells.filter(func(c: Cell) -> bool: return not c.dead))


func _tick_phages(h: float) -> void:
	var targets: Array[Cell] = []
	for c in cells:
		if c.strain < 0 and not c.dead:
			targets.append(c)
	var born: Array[Phage] = []
	for ph in phages:
		ph.fade = minf(1.0, ph.fade + h * 1.5)
		if ph.host:
			if ph.host.dead:
				ph.host = null
				continue
			ph.p = ph.host.p + Vector2.from_angle(ph.angle) * (ph.host.r + PHAGE_R * 0.6)
			ph.host.infected += h
			if ph.host.infected >= INFECT_TIME:
				var host := ph.host
				host.dead = true
				_pop(host.p, Color("5a1030"), 12, 0.7)
				_text(host.p + Vector2(0, -36), "Lost a cell", Color("ff6b8a"))
				_sfx("lab_infect", -5.0)
				ph.host = null
				ph.v = Vector2.from_angle(rng.randf() * TAU) * 60.0
				if phages.size() + born.size() < PHAGE_MAX:
					var kid := Phage.new()
					kid.p = host.p
					kid.v = -ph.v
					kid.fade = 1.0
					born.append(kid)
			continue
		var best: Cell = null
		var bd := INF
		for c in targets:
			var d := c.p.distance_squared_to(ph.p)
			if d < bd:
				bd = d
				best = c
		if best:
			ph.v = ph.v.lerp((best.p - ph.p).normalized() * PHAGE_SPEED, clampf(h * 2.0, 0.0, 1.0))
			if sqrt(bd) < best.r + PHAGE_R * 0.6:
				ph.host = best
				ph.angle = (ph.p - best.p).angle()
		else:
			ph.v = ph.v.lerp(Vector2.from_angle(_t * 0.7 + ph.angle) * 40.0, clampf(h, 0.0, 1.0))
		ph.p += (ph.v + _flow(ph.p) * 0.6) * h
		if ph.p.length() > ARENA - PHAGE_R:
			ph.p = ph.p.normalized() * (ARENA - PHAGE_R)
	phages.append_array(born)
	cells.assign(cells.filter(func(c: Cell) -> bool: return not c.dead))
	phages.assign(phages.filter(func(p: Phage) -> bool: return not p.dead))


func _tick_spawns(h: float) -> void:
	# the broth keeps feeding fresh cells in from the rim
	var base := 0
	for c in cells:
		if c.strain >= 0 and not c.fusing:
			base += 1
	if base < BASE_CELLS:
		_respawn_t -= h
		if _respawn_t <= 0.0:
			_respawn_t = 2.5
			_spawn_cell(_fewest_strain(), Vector2.from_angle(rng.randf() * TAU) * ARENA * 0.82)
	# phages come once there is something to eat
	var m := merged_count()
	if m > 0 and phages.size() < PHAGE_MAX:
		_phage_t -= h
		if _phage_t <= 0.0:
			_phage_t = maxf(1.8, 6.0 - m * 0.15) * rng.randf_range(0.8, 1.2)
			var ph := Phage.new()
			ph.p = Vector2.from_angle(rng.randf() * TAU) * (ARENA - 20.0)
			ph.angle = rng.randf() * TAU
			phages.append(ph)
			_sfx("lab_phage", -12.0)
	# ambient soup bubbles
	_bubble_t -= h
	if _bubble_t <= 0.0:
		_bubble_t = rng.randf_range(0.2, 0.6)
		var b := _fx(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, ARENA * 0.9), Vector2.ZERO, rng.randf_range(4.0, 11.0), Color(1.0, 0.95, 0.8, 0.5), rng.randf_range(0.8, 1.6))
		b.ring = true


func _tick_fx(h: float) -> void:
	for f in fx:
		f.t += h
		f.p += f.v * h
		f.v *= exp(-2.5 * h)
	fx.assign(fx.filter(func(f: Fx) -> bool: return f.t < f.life))
	for b in beams:
		b[2] = float(b[2]) + h
	beams.assign(beams.filter(func(b: Array) -> bool: return float(b[2]) < 0.14))


## Division slows as the dish fills up, so growth is logistic, not runaway.
func _split_time() -> float:
	return rng.randf_range(SPLIT_MIN, SPLIT_MAX) * (1.0 + 1.2 * float(merged_count()) / mass)


func merged_count() -> int:
	var n := 0
	for c in cells:
		if c.strain < 0 and not c.dead:
			n += 1
	return n


func _fewest_strain() -> int:
	var counts: Array[int] = []
	counts.resize(strains.size())
	counts.fill(0)
	for c in cells:
		if c.strain >= 0:
			counts[c.strain] += 1
	var best := 0
	for i in counts.size():
		if counts[i] < counts[best]:
			best = i
	return best


func _spawn_cell(si: int, p: Vector2) -> Cell:
	var st: Dictionary = Db.lab_strain(strains[si])
	var c := Cell.new()
	c.strain = si
	c.p = p
	c.move = String(st.move)
	c.speed = float(st.speed)
	c.r = float(st.r)
	c.col = Db.item_color(strains[si])
	c.hp = 2 if c.move == "armor" else 1
	c.sd = rng.randf() * 10.0
	c.dash_t = rng.randf_range(0.2, 1.5)
	c.blink_t = rng.randf_range(2.0, 4.0)
	c.v = Vector2.from_angle(rng.randf() * TAU) * c.speed * 0.5
	cells.append(c)
	return c


func _new_merged(p: Vector2, a: Color, b: Color) -> Cell:
	var c := Cell.new()
	c.strain = -1
	c.p = p
	c.r = MERGED_R
	c.col = a
	c.col2 = b
	c.move = "merged"
	c.sd = rng.randf() * 10.0
	c.split_t = _split_time()
	cells.append(c)
	return c


# --------------------------------------------------------------------------
# the ray
# --------------------------------------------------------------------------

## Distance along a ray to a circle, or -1 if it misses.
static func _ray_circle(from: Vector2, dir: Vector2, centre: Vector2, rad: float) -> float:
	var w := centre - from
	var tp := w.dot(dir)
	if tp < -rad:
		return -1.0
	var d2 := w.length_squared() - tp * tp
	if d2 > rad * rad:
		return -1.0
	return maxf(0.0, tp - sqrt(rad * rad - d2))


func fire(dir: Vector2) -> void:
	if phase != "play" or _cd > 0.0 or dir == Vector2.ZERO:
		return
	_cd = RAY_CD
	dir = dir.normalized()
	var from := probe_p + dir * 16.0
	var best := RAY_RANGE
	var hit_c: Cell = null
	var hit_p: Phage = null
	for ph in phages:
		var d := _ray_circle(from, dir, ph.p, PHAGE_R + 8.0)
		if d >= 0.0 and d < best:
			best = d
			hit_p = ph
	for c in cells:
		# the ray passes through your merged cells; it only grabs loose strains
		if c.dead or c.fusing or c.strain < 0 or c.fade < 0.5:
			continue
		var d := _ray_circle(from, dir, c.p, c.r + 6.0)
		if d >= 0.0 and d < best:
			best = d
			hit_c = c
			hit_p = null
	var end := from + dir * best
	beams.append([from, end, 0.0])
	_sfx("lab_zap", -12.0)
	if hit_p:
		hit_p.dead = true
		if hit_p.host:
			hit_p.host.infected = 0.0
		phages_zapped += 1
		_pop(hit_p.p, Color("ff3d6e"), 9, 0.45)
		_sfx("lab_pop", -6.0)
		phages.assign(phages.filter(func(p: Phage) -> bool: return not p.dead))
		return
	if hit_c == null:
		return
	if hit_c.hp > 1:
		hit_c.hp -= 1
		_pop(end, Color(1, 1, 1), 5, 0.3)
		_text(hit_c.p + Vector2(0, -34), "Shell cracked", Color(0.9, 0.95, 1.0))
		_sfx("lab_armor", -8.0)
		return
	if tag == null or tag == hit_c:
		_tag(hit_c)
	elif tag.strain == hit_c.strain:
		_text(hit_c.p + Vector2(0, -34), "Same strain", Color("ffb86b"))
		_tag(hit_c)
	else:
		var f := Fusion.new()
		f.a = tag
		f.b = hit_c
		tag.fusing = true
		hit_c.fusing = true
		fusions.append(f)
		tag = null
		_sfx("lab_tag", -6.0, 0.3)


func _tag(c: Cell) -> void:
	tag = c
	tag_t = TAG_TIME
	_sfx("lab_tag", -8.0)


func _end(g: int) -> void:
	if phase != "play":
		return
	phase = "result"
	grade = g
	tag = null
	_in_fire = false
	result = Game.lab_finish(recipe_id, g)
	if g >= 0:
		for c in cells:
			if c.strain < 0:
				_pop(c.p, Color("ffd23f"), 6, 0.9)
		_sfx("lab_success", -3.0)
	else:
		_sfx("lab_fail", -3.0)


## Autoplay for tests and screenshot tours: clear phages first, otherwise
## tag the nearest loose cell and then the nearest cell of another strain.
func _bot() -> void:
	var tgt := Vector2.INF
	var bd := INF
	for ph in phages:
		var d := ph.p.distance_to(probe_p)
		if d < bd:
			bd = d
			tgt = ph.p
	if tgt == Vector2.INF:
		for c in cells:
			if c.strain < 0 or c.fusing or c.dead or c.fade < 0.6:
				continue
			if tag and (c == tag or c.strain == tag.strain):
				continue
			var d := c.p.distance_to(probe_p)
			if d < bd:
				bd = d
				tgt = c.p
	_in_fire = false
	_in_move = Vector2.ZERO
	if tgt == Vector2.INF:
		return
	var to := tgt - probe_p
	aim = to.normalized().rotated(rng.randf_range(-bot_error, bot_error))
	if bd > RAY_RANGE * 0.55:
		_in_move = aim
	elif bd < 110.0:
		_in_move = -aim * 0.5
	_in_fire = bd < RAY_RANGE * 0.9 and _bot_cd <= 0.0
	if _in_fire and _cd <= 0.0:
		_bot_cd = bot_rate


# --------------------------------------------------------------------------
# effects
# --------------------------------------------------------------------------

func _fx(p: Vector2, v: Vector2, r: float, col: Color, life: float) -> Fx:
	var f := Fx.new()
	f.p = p
	f.v = v
	f.r = r
	f.col = col
	f.life = life
	fx.append(f)
	return f


func _pop(p: Vector2, col: Color, n: int, life: float) -> void:
	for i in n:
		_fx(p, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 160.0), rng.randf_range(2.0, 5.0), col, life * rng.randf_range(0.7, 1.2))
	var ring := _fx(p, Vector2.ZERO, 10.0, Color(col, 0.7), life)
	ring.ring = true


func _text(p: Vector2, text: String, col: Color) -> void:
	var f := _fx(p, Vector2(0, -30), 0.0, col, 1.4)
	f.text = text


func _sfx(sname: String, db: float, pitch := 0.08) -> void:
	# the Homespace mutes SFX, so the lab speaks on the UI bus
	if not manual:
		Sound.play(sname, db, pitch, "UI", 0.04)


# --------------------------------------------------------------------------
# drawing
# --------------------------------------------------------------------------

func _draw_view() -> void:
	for f in fx:
		if f.ring and f.text == "" and f.life > 0.75:
			_draw_fx(f)
	for c in cells:
		if c.strain < 0:
			_draw_cell(c)
	for c in cells:
		if c.strain >= 0:
			_draw_cell(c)
	if tag and not tag.dead:
		_draw_tag()
	for ph in phages:
		_draw_phage(ph)
	for f in fusions:
		var mid := _S((f.a.p + f.b.p) * 0.5)
		_view.draw_circle(mid, (20.0 + 30.0 * f.t / FUSE_TIME) * _s, Color(1.0, 0.95, 0.7, 0.25 * (1.0 - f.t / FUSE_TIME)))
	_draw_probe()
	for b in beams:
		_draw_beam(b[0], b[1], float(b[2]))
	for f in fx:
		if not (f.ring and f.text == "" and f.life > 0.75):
			_draw_fx(f)
	_draw_hud()


func _membrane(ctr: Vector2, rr: float, seed_: float, wob: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * k / 28.0
		var w := 1.0 + wob * (sin(a * 3.0 + _t * 2.0 + seed_) * 0.6 + sin(a * 5.0 - _t * 3.1 + seed_ * 2.0) * 0.4)
		pts.append(ctr + Vector2.from_angle(a) * rr * w)
	return pts


func _draw_blob(ctr: Vector2, rr: float, col: Color, col2: Color, alpha: float, seed_: float, merged: bool, infected: float) -> void:
	var body := col.lerp(col2, 0.5) if merged else col
	body = body.lerp(Color("3a0a22"), clampf(infected / INFECT_TIME, 0.0, 1.0) * 0.7)
	var pts := _membrane(ctr, rr, seed_, 0.07 if merged else 0.09)
	if merged:
		var halo := 0.5 + 0.5 * sin(_t * 3.0 + seed_)
		_view.draw_circle(ctr, rr * 1.35, Color(1.0, 0.85, 0.3, (0.08 + 0.06 * halo) * alpha))
	_view.draw_colored_polygon(pts, Color(body, 0.45 * alpha))
	var inner := _membrane(ctr + Vector2(-rr * 0.1, -rr * 0.12), rr * 0.7, seed_ + 1.0, 0.05)
	_view.draw_colored_polygon(inner, Color(body.lightened(0.3), 0.22 * alpha))
	pts.append(pts[0])
	# a dark outer membrane so cells read against the broth, then the bright one
	_view.draw_polyline(pts, Color(body.darkened(0.7), 0.7 * alpha), 5.0, true)
	_view.draw_polyline(pts, Color(body.lightened(0.45), 0.95 * alpha), 2.5, true)
	if merged:
		# merged cells wear a gold ring: they're what you're growing
		var gold := Color(1.0, 0.85, 0.3, (0.55 + 0.25 * sin(_t * 3.0 + seed_)) * alpha)
		_view.draw_arc(ctr, rr * 1.18, 0, TAU, 32, gold, 2.0, true)
	# nuclei and a few organelles
	var na := seed_ * 2.3 + _t * 0.3
	if merged:
		_view.draw_circle(ctr + Vector2.from_angle(na) * rr * 0.32, rr * 0.24, Color(col.darkened(0.35), 0.9 * alpha))
		_view.draw_circle(ctr - Vector2.from_angle(na) * rr * 0.32, rr * 0.24, Color(col2.darkened(0.35), 0.9 * alpha))
		_view.draw_circle(ctr + Vector2.from_angle(na) * rr * 0.36, rr * 0.08, Color(col.lightened(0.5), alpha))
		_view.draw_circle(ctr - Vector2.from_angle(na) * rr * 0.28, rr * 0.08, Color(col2.lightened(0.5), alpha))
	else:
		var nc := ctr + Vector2.from_angle(na) * rr * 0.18
		_view.draw_circle(nc, rr * 0.3, Color(col.darkened(0.4), 0.85 * alpha))
		_view.draw_circle(nc + Vector2(-rr * 0.06, -rr * 0.06), rr * 0.1, Color(col.lightened(0.4), 0.9 * alpha))
	for k in 3:
		var op := ctr + Vector2.from_angle(seed_ * 5.0 + k * 2.1 + _t * 0.5) * rr * 0.55
		_view.draw_circle(op, rr * 0.07, Color(body.lightened(0.6), 0.7 * alpha))
	# a specular glint
	_view.draw_circle(ctr + Vector2(-rr * 0.42, -rr * 0.42), rr * 0.12, Color(1, 1, 1, 0.35 * alpha))


func _draw_cell(c: Cell) -> void:
	var sp := _S(c.p)
	var rr := c.r * _s * (0.5 + 0.5 * c.fade)
	var alpha := c.fade
	if c.move == "blink" and c.blink_t < 0.6:
		alpha *= 0.55 + 0.45 * sin(_t * 40.0)
	if c.strain < 0:
		if c.div >= 0.0:
			var off := c.div_dir * rr * 0.62 * c.div
			var sr := rr * (1.0 - 0.18 * c.div)
			_draw_blob(sp - off, sr, c.col, c.col2, alpha, c.sd, true, c.infected)
			_draw_blob(sp + off, sr, c.col, c.col2, alpha, c.sd + 3.0, true, c.infected)
		else:
			_draw_blob(sp, rr, c.col, c.col2, alpha, c.sd, true, c.infected)
		return
	# flagellum trails behind darting cells
	if c.move == "dart" and c.v.length() > 10.0:
		var back := -c.v.normalized()
		var side := Vector2(-back.y, back.x)
		var line := PackedVector2Array()
		for k in 9:
			var u := float(k) / 8.0
			line.append(sp + back * rr * (1.0 + u * 1.4) + side * sin(u * 9.0 - _t * 18.0) * rr * 0.25 * u)
		_view.draw_polyline(line, Color(c.col.lightened(0.3), 0.7 * alpha), 2.0, true)
	if c.move == "swarm":
		for k in 6:
			var a := TAU * k / 6.0 + _t
			_view.draw_line(sp + Vector2.from_angle(a) * rr, sp + Vector2.from_angle(a) * rr * 1.35, Color(c.col, 0.6 * alpha), 1.5)
	_draw_blob(sp, rr, c.col, c.col, alpha, c.sd, false, 0.0)
	if c.move == "armor":
		var hexp := PackedVector2Array()
		for k in 7:
			hexp.append(sp + Vector2.from_angle(TAU * k / 6.0 + c.sd) * rr * 1.12)
		if c.hp > 1:
			_view.draw_polyline(hexp, Color(1, 1, 1, 0.75 * alpha), 3.5, true)
		else:
			for k in 6:
				if k % 2 == 0:
					_view.draw_line(hexp[k], hexp[k + 1], Color(1, 1, 1, 0.45 * alpha), 2.0)
	if c.move == "blink":
		for k in 8:
			var a := TAU * k / 8.0 - _t * 1.5
			_view.draw_arc(sp, rr * 1.25, a, a + 0.35, 4, Color(c.col.lightened(0.5), 0.6 * alpha), 2.0)


func _draw_tag() -> void:
	var sp := _S(tag.p)
	var rr := tag.r * _s + 9.0
	for k in 6:
		var a := TAU * k / 6.0 + _t * 3.0
		_view.draw_arc(sp, rr, a, a + 0.6, 6, Color(1, 1, 1, 0.9), 2.5)
	_view.draw_arc(sp, rr + 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(tag_t / TAG_TIME, 0.0, 1.0), 32, Color(_glow, 0.8), 3.0)
	# a faint tether back to the probe
	var a0 := _S(probe_p)
	var line := PackedVector2Array()
	var d := sp - a0
	var side := Vector2(-d.y, d.x).normalized()
	for k in 17:
		var u := float(k) / 16.0
		line.append(a0.lerp(sp, u) + side * sin(u * 12.0 - _t * 10.0) * 4.0)
	_view.draw_polyline(line, Color(_glow, 0.25), 1.5, true)


func _draw_phage(ph: Phage) -> void:
	var sp := _S(ph.p)
	var s := _s * 1.6 * (0.5 + 0.5 * ph.fade)
	var down := Vector2.DOWN
	if ph.host:
		down = (ph.host.p - ph.p).normalized()
	elif ph.v.length() > 1.0:
		down = ph.v.normalized()
	var side := Vector2(-down.y, down.x)
	var col := Color("ff3d6e")
	_view.draw_circle(sp, 20.0 * s, Color(col, 0.12))
	var head := sp - down * 6.0 * s
	var hexp := PackedVector2Array()
	for k in 6:
		hexp.append(head + Vector2.from_angle(TAU * k / 6.0 + down.angle()) * 10.0 * s)
	_view.draw_colored_polygon(hexp, Color("5a1030"))
	hexp.append(hexp[0])
	_view.draw_polyline(hexp, col, 2.0, true)
	var tail := sp + down * 10.0 * s
	_view.draw_line(head + down * 8.0 * s, tail, col.lightened(0.2), 3.0 * s + 1.0)
	var kick := sin(_t * 12.0 + ph.angle) * 0.3
	for sgn: float in [-1.0, 1.0]:
		var knee := tail + (side * sgn * 7.0 + down * 2.0) * s
		_view.draw_line(tail, knee, col, 1.5)
		_view.draw_line(knee, knee + (side * sgn * (3.0 + kick * 4.0) + down * 7.0) * s, col, 1.5)
	if ph.host:
		_view.draw_circle(tail, 3.0, Color(1, 0.3, 0.5, 0.5 + 0.5 * sin(_t * 10.0)))


func _draw_probe() -> void:
	var sp := _S(probe_p)
	var s := _s * 1.4
	# aim guide: a dotted line out to the ray's reach
	if phase == "play":
		var k := 0.0
		while k < RAY_RANGE:
			_view.draw_circle(_S(probe_p + aim * (26.0 + k)), 1.6, Color(_glow, 0.28 * (1.0 - k / RAY_RANGE)))
			k += 22.0
	_view.draw_circle(sp, 24.0 * s, Color(_glow, 0.12))
	_view.draw_circle(sp, 14.0 * s, Color("1b2230"))
	_view.draw_arc(sp, 14.0 * s, 0, TAU, 24, _glow, 2.5, true)
	var tip := sp + aim * 24.0 * s
	var side := Vector2(-aim.y, aim.x)
	_view.draw_colored_polygon(PackedVector2Array([sp + side * 6.0 * s + aim * 8.0 * s, tip, sp - side * 6.0 * s + aim * 8.0 * s]), _accent)
	_view.draw_circle(sp - aim * 3.0 * s, 4.5 * s, Color(_glow, 0.6 + 0.4 * sin(_t * 6.0)))
	# little cilia-like fins
	for k2 in 3:
		var a := aim.angle() + PI + (k2 - 1) * 0.6
		var base := sp + Vector2.from_angle(a) * 14.0 * s
		_view.draw_line(base, base + Vector2.from_angle(a + sin(_t * 14.0 + k2) * 0.4) * 9.0 * s, Color(_glow, 0.7), 2.0)


func _draw_beam(from: Vector2, to: Vector2, t: float) -> void:
	var a := _S(from)
	var b := _S(to)
	var d := b - a
	var side := Vector2(-d.y, d.x).normalized()
	var line := PackedVector2Array()
	for k in 13:
		var u := float(k) / 12.0
		line.append(a.lerp(b, u) + side * sin(u * 30.0 + t * 90.0) * 5.0 * (1.0 - u * 0.5))
	var fade := 1.0 - t / 0.14
	_view.draw_polyline(line, Color(_glow, 0.25 * fade), 10.0, true)
	_view.draw_polyline(line, Color(_glow.lightened(0.6), fade), 2.5, true)
	_view.draw_circle(b, 8.0 * fade, Color(1, 1, 1, 0.6 * fade))


func _draw_fx(f: Fx) -> void:
	var u := f.t / f.life
	var sp := _S(f.p)
	if f.text != "":
		var font := UiKit.title_font()
		var w := font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16).x
		_view.draw_string_outline(font, sp - Vector2(w * 0.5, 0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.7 * (1.0 - u)))
		_view.draw_string(font, sp - Vector2(w * 0.5, 0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(f.col, 1.0 - u))
	elif f.ring:
		_view.draw_arc(sp, f.r * _s * (1.0 + u * 1.2), 0, TAU, 20, Color(f.col, f.col.a * (1.0 - u)), 1.5, true)
		if f.life > 0.75:
			# a soup bubble: a glint on top, and it pops at the end
			_view.draw_circle(sp + Vector2(-f.r * 0.35, -f.r * 0.35) * _s, f.r * 0.25 * _s, Color(1, 1, 1, 0.35 * (1.0 - u)))
	else:
		_view.draw_circle(sp, f.r * _s * (1.0 - u * 0.6), Color(f.col, f.col.a * (1.0 - u)))


func _bar(pos: Vector2, w: float, frac: float, col: Color) -> void:
	_view.draw_rect(Rect2(pos, Vector2(w, 12)), Color(0, 0, 0, 0.55))
	_view.draw_rect(Rect2(pos, Vector2(w * clampf(frac, 0.0, 1.0), 12)), col)
	_view.draw_rect(Rect2(pos, Vector2(w, 12)), Color(1, 1, 1, 0.3), false, 1.0)


func _str(pos: Vector2, text: String, fsize: int, col: Color, title := false, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := UiKit.title_font() if title else UiKit.body_font()
	_view.draw_string_outline(font, pos, text, align, width, fsize, 4, Color(0, 0, 0, 0.6))
	_view.draw_string(font, pos, text, align, width, fsize, col)


func _draw_hud() -> void:
	var vs := _view.size
	_str(Vector2(40, 58), "MICRO LAB", 30, Color.WHITE, true)
	var out := String(recipe.get("out", ""))
	var makes := "upgrade" if recipe.has("bonus") else Db.item_name(out)
	_str(Vector2(42, 88), "%s  →  %s" % [recipe.get("name", ""), makes], 16, Db.item_color(out))
	# strains
	_str(Vector2(42, 134), "STRAINS", 14, UiKit.MUTED, true)
	for i in strains.size():
		var y := 162.0 + i * 30.0
		var col := Db.item_color(strains[i])
		_view.draw_circle(Vector2(52, y - 5), 8.0, Color(col, 0.6))
		_view.draw_arc(Vector2(52, y - 5), 8.0, 0, TAU, 16, col.lightened(0.4), 1.5, true)
		var mv := String(Db.lab_strain(strains[i]).move)
		_str(Vector2(68, y), "%s  ·  %s" % [Db.item_name(strains[i]), MOVE_WORDS.get(mv, mv)], 15, UiKit.TEXT)
	var ly := 172.0 + strains.size() * 30.0
	_str(Vector2(42, ly), "Zap a cell, then a", 14, UiKit.MUTED)
	_str(Vector2(42, ly + 20), "different strain to fuse.", 14, UiKit.MUTED)
	_str(Vector2(42, ly + 40), "Fused cells divide.", 14, UiKit.MUTED)
	_str(Vector2(42, ly + 60), "Zap red phages on sight.", 14, Color("ff6b8a"))
	# the right panel: critical mass and stability
	var x := vs.x - 350.0
	var m := merged_count()
	_str(Vector2(x, 58), "CRITICAL MASS", 14, Color("ffd23f"), true)
	_bar(Vector2(x, 70), 300.0, float(m) / mass, Color("ffd23f"))
	_str(Vector2(x, 104), "Merged cells  %d / %d" % [m, mass], 16, UiKit.TEXT)
	var frac := stability / time_total
	_str(Vector2(x, 146), "STABILITY", 14, Color("6ee06a"), true)
	var scol := Color("6ee06a") if frac >= PRISTINE_AT else (Color("ffd23f") if frac >= REFINED_AT else Color("ff6b6b"))
	_bar(Vector2(x, 158), 300.0, frac, scol)
	for mark in [[PRISTINE_AT, "P"], [REFINED_AT, "R"]]:
		var mx: float = x + 300.0 * float(mark[0])
		_view.draw_line(Vector2(mx, 154), Vector2(mx, 174), Color(1, 1, 1, 0.7), 2.0)
		_str(Vector2(mx - 4, 190), String(mark[1]), 12, UiKit.MUTED)
	var g := 2 if frac >= PRISTINE_AT else (1 if frac >= REFINED_AT else 0)
	if phase == "play":
		_str(Vector2(x, 214), "On track for: %s" % Db.LAB_GRADES[g], 16, Db.LAB_GRADE_COLORS[g])
		if phages.size() > 0:
			_str(Vector2(x, 240), "Phages in the soup: %d" % phages.size(), 15, Color("ff6b8a"))
	var hint := "WASD steer  ·  Mouse aim  ·  Left click zap  ·  Esc abandon"
	_str(Vector2(0, vs.y - 26), hint, 14, UiKit.MUTED, false, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if _abandon_t > 0.0 and phase == "play":
		_str(Vector2(0, vs.y * 0.5 - 40), "Press Esc again to abandon (half the ingredients come back)", 20, Color("ffb86b"), true, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if phase == "result":
		_draw_result(vs)


func _draw_result(vs: Vector2) -> void:
	var a := clampf(_result_t * 3.0, 0.0, 1.0)
	var box := Rect2(vs * 0.5 - Vector2(300, 130), Vector2(600, 260))
	var edge: Color = Db.LAB_GRADE_COLORS[grade] if grade >= 0 else Color("ff6b6b")
	var sb := UiKit.box(Color(0.03, 0.05, 0.1, 0.92 * a), Color(edge, a), 14, 2, 18)
	_view.draw_style_box(sb, box)
	var cx := box.position.x
	var ok := grade >= 0
	var title := "CRITICAL MASS" if ok else "CULTURE LOST"
	_str(Vector2(cx, box.position.y + 58), title, 34, Color(1, 1, 1, a), true, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	if ok:
		_str(Vector2(cx, box.position.y + 102), Db.LAB_GRADES[grade].to_upper(), 26, Color(Db.LAB_GRADE_COLORS[grade], a), true, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	_str(Vector2(cx + 30, box.position.y + 146), String(result.get("text", "")), 16, Color(UiKit.TEXT, a), false, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 60)
	_str(Vector2(cx, box.position.y + 186), "%d fusions  ·  %d phages zapped  ·  %ds" % [merges, phages_zapped, int(elapsed)], 14, Color(UiKit.MUTED, a), false, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	if _result_t > 0.8:
		_str(Vector2(cx, box.position.y + 234), "[E] or click to continue", 15, Color(Color("9bd1ff"), a), true, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
