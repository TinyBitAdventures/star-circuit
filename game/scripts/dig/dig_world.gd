extends Node2D
## The Deep: a side-on slice of a planet's crust. Dig tunnels with the
## drill pod, collect ore, dodge gas and lava, and find sealed chambers.

const W := 44
const H := 150
const CS := 32
const CHUNK := 16
const SURFACE := 4 # rows of open sky above the crust

enum { AIR, DIRT, STONE, DEEP, CRYSTAL, MAGMA, BEDROCK, HARD, VOIDROCK, GAS, LAVA, RUNE }
const ORE0 := 32

const LAYERS := [
	{"name": "Topsoil", "top": SURFACE, "cell": DIRT, "hard": 0.22},
	{"name": "Bedrock Shelf", "top": 30, "cell": STONE, "hard": 0.42},
	{"name": "Deep Stone", "top": 62, "cell": DEEP, "hard": 0.65},
	{"name": "Crystal Veins", "top": 96, "cell": CRYSTAL, "hard": 0.9},
	{"name": "Magma Belt", "top": 126, "cell": MAGMA, "hard": 1.15},
]

## ore cell = ORE0 + index. layer range is inclusive.
const ORES := [
	{"item": "ferrite", "layers": [0, 1], "qty": [1, 3], "chance": 0.05, "req": 1},
	{"item": "nickel", "layers": [1, 2], "qty": [1, 3], "chance": 0.035, "req": 1},
	{"item": "cobalt", "layers": [1, 2], "qty": [1, 2], "chance": 0.03, "req": 15},
	{"item": "lumen", "layers": [2, 3], "qty": [1, 2], "chance": 0.03, "req": 30},
	{"item": "stardust", "layers": [2, 4], "qty": [1, 1], "chance": 0.012, "req": 20},
	{"item": "voidshard", "layers": [3, 4], "qty": [1, 2], "chance": 0.02, "req": 55},
	{"item": "exotic", "layers": [4, 4], "qty": [1, 1], "chance": 0.006, "req": 40},
	{"item": "fossil", "layers": [1, 3], "qty": [1, 1], "chance": 0.0035, "req": 1},
	{"item": "biofiber", "layers": [0, 0], "qty": [1, 2], "chance": 0.03, "req": 1},
]

const THEMES := {
	"fungal": {"name": "Fungal Grotto", "color": Color("7ef0d8")},
	"fossil": {"name": "Fossil Bed", "color": Color("e8dcc4")},
	"crystal": {"name": "Crystal Cavern", "color": Color("c9a6ff")},
	"vault": {"name": "Ancient Vault", "color": Color("ffd98a")},
}

var cells := PackedByteArray()
var dug := PackedByteArray() # 1 = dug by the player
var seen := PackedByteArray() # 1 = charted on the minimap
var chambers: Array = [] # {id, rect: Rect2i, theme, centre: Vector2}
var palette: Array = []
var biome := "verdant"
var cave_key := ""
var hud: CanvasLayer
var pod: DigPod
var _chunks := {} # Vector2i -> [solid Node2D, glow Node2D]
var _gas_clouds: Array = [] # {pos, t}
var _run_items := {} # items collected this dive
var _dug_since_save := 0
var _depth_label: Label
var _layer_label: Label
var _dark: CanvasModulate
var _rift_nodes := {}
var _t := 0.0


func _ready() -> void:
	var c: Dictionary = Game.cave
	if c.is_empty():
		# launched directly (dev): fake a cave on the home world
		c = {"key": "0:0:dev", "seed": 1234, "biome": "verdant", "dir": [0, 1, 0], "star": 0, "planet": 0, "pod": []}
		Game.cave = c
	cave_key = c.key
	biome = c.biome
	_make_palette()
	_generate(int(c.seed))
	_load_dug()
	_build_backdrop()
	for cy in ceili(float(H) / CHUNK):
		for cx in ceili(float(W) / CHUNK):
			_make_chunk(Vector2i(cx, cy))
	_build_chamber_fx()
	_build_lava()
	_dark = CanvasModulate.new()
	add_child(_dark)

	pod = DigPod.new()
	pod.world = self
	add_child(pod)
	var saved: Array = c.get("pod", [])
	if saved.size() == 2:
		pod.position = Vector2(saved[0], saved[1])
	else:
		pod.position = cell_centre(Vector2i(W / 2, SURFACE - 1))

	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "dig"
	add_child(hud)
	_build_depth_meter()
	_build_minimap()
	UiKit.add_vignette(self, 0.5)
	Game.player_died.connect(_on_died)
	Sound.stop_all_loops()
	Sound.play_music("underground", 2.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(self):
			Game.tip("first_dig", "Drill by pushing into rock: %s/%s to bore sideways, %s to dig down, %s to thrust up. Glowing pockets are Discovery Chambers. Avoid the magma, and watch your energy for the climb home." % [Game.key("move_left"), Game.key("move_right"), Game.key("move_back"), Game.key("move_forward")])
	)
	if saved.is_empty():
		hud.show_location_banner("The Deep", "A: left  D: right  S: dig down  W: thrust  ·  push into rock to drill")


# --------------------------------------------------------------------------
# generation
# --------------------------------------------------------------------------

func _make_palette() -> void:
	var b: Dictionary = Db.BIOMES[biome]
	var tint: Color = b.colors.mid
	palette = [
		(b.colors.high as Color).darkened(0.25).lerp(Color("7a5a3c"), 0.45),
		(b.colors.rock as Color).lerp(Color("5a5560"), 0.5),
		Color("3d4452").lerp(tint, 0.12),
		Color("3a2f55").lerp(tint, 0.15),
		Color("4a2222"),
	]


func layer_of(y: int) -> int:
	var li := 0
	for i in LAYERS.size():
		if y >= LAYERS[i].top:
			li = i
	return li


func idx(x: int, y: int) -> int:
	return y * W + x


func get_cell(x: int, y: int) -> int:
	if x < 0 or x >= W or y < 0 or y >= H:
		return BEDROCK
	return cells[idx(x, y)]


func is_solid(x: int, y: int) -> bool:
	var c := get_cell(x, y)
	return c != AIR and c != GAS


func _generate(seed_: int) -> void:
	cells.resize(W * H)
	dug.resize(W * H)
	dug.fill(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var cav := FastNoiseLite.new()
	cav.seed = seed_
	cav.frequency = 0.07
	cav.fractal_octaves = 3
	var worm := FastNoiseLite.new()
	worm.seed = seed_ + 9
	worm.frequency = 0.035
	for y in H:
		var li := layer_of(y)
		for x in W:
			var c: int = LAYERS[li].cell
			if y < SURFACE:
				c = AIR
			elif x == 0 or x == W - 1 or y == H - 1:
				c = BEDROCK
			else:
				var n := cav.get_noise_2d(x, y * 1.4)
				var wv := absf(worm.get_noise_2d(x * 1.3, y))
				if y > SURFACE + 8 and (n > 0.38 or wv < 0.035):
					c = AIR # natural caverns + winding worm tunnels
				elif li >= 2 and rng.randf() < 0.03 + li * 0.01:
					c = HARD if li < 4 else VOIDROCK
				elif li >= 1 and rng.randf() < 0.006:
					c = GAS
				elif (li == 4 or (biome == "ember" and li >= 2)) and rng.randf() < 0.02:
					c = LAVA
				else:
					for oi in ORES.size():
						var o: Dictionary = ORES[oi]
						if li >= o.layers[0] and li <= o.layers[1] and rng.randf() < o.chance:
							if o.item == "biofiber" and not biome in ["verdant", "bloom"]:
								continue
							c = ORE0 + oi
							break
			cells[idx(x, y)] = c
	# grow hazards into small blobs
	for y in range(SURFACE, H - 1):
		for x in range(1, W - 1):
			var c := cells[idx(x, y)]
			if (c == LAVA or c == GAS) and rng.randf() < 0.6:
				var nx := clampi(x + rng.randi_range(-1, 1), 1, W - 2)
				var ny := clampi(y + rng.randi_range(0, 1), SURFACE + 1, H - 2)
				cells[idx(nx, ny)] = c
	# keep the lift shaft area solid ground to land on
	for x in range(W / 2 - 2, W / 2 + 3):
		cells[idx(x, SURFACE)] = DIRT
	# sealed chambers
	chambers.clear()
	var bands := [[34, 56, "fungal"], [66, 92, "fossil"], [100, 122, "crystal"], [128, 144, "vault"]]
	if biome == "prism":
		bands[0][2] = "crystal"
	var id := 0
	for band in bands:
		for k in (2 if band[2] != "vault" else 1):
			var cw := 9
			var ch := 6
			var cx := rng.randi_range(2, W - cw - 2)
			var cy := rng.randi_range(band[0], band[1] - ch)
			var r := Rect2i(cx, cy, cw, ch)
			for yy in range(r.position.y - 1, r.end.y + 1):
				for xx in range(r.position.x - 1, r.end.x + 1):
					var border := xx == r.position.x - 1 or xx == r.end.x or yy == r.position.y - 1 or yy == r.end.y
					cells[idx(xx, yy)] = RUNE if border else AIR
			chambers.append({"id": id, "rect": r, "theme": band[2], "centre": Vector2((cx + cw * 0.5) * CS, (cy + ch - 1) * CS)})
			id += 1


func _load_dug() -> void:
	var st := Game.dig_state(cave_key)
	seen.resize(W * H)
	var sraw := Marshalls.base64_to_raw(st.get("seen", "")) if st.get("seen", "") != "" else PackedByteArray()
	for i in mini(sraw.size() * 8, W * H):
		if sraw[i >> 3] & (1 << (i & 7)):
			seen[i] = 1
	if st.dug != "":
		var raw := Marshalls.base64_to_raw(st.dug)
		for i in mini(raw.size() * 8, W * H):
			if raw[i >> 3] & (1 << (i & 7)):
				dug[i] = 1
				cells[i] = AIR


func save_dug() -> void:
	var raw := PackedByteArray()
	raw.resize((W * H + 7) / 8)
	for i in W * H:
		if dug[i]:
			raw[i >> 3] |= (1 << (i & 7))
	Game.dig_state(cave_key).dug = Marshalls.raw_to_base64(raw)
	var sraw := PackedByteArray()
	sraw.resize((W * H + 7) / 8)
	for i in W * H:
		if seen[i]:
			sraw[i >> 3] |= (1 << (i & 7))
	Game.dig_state(cave_key)["seen"] = Marshalls.raw_to_base64(sraw)


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

func cell_centre(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CS, (c.y + 0.5) * CS)


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CS), floori(p.y / CS))


func _build_backdrop() -> void:
	var bg := Node2D.new()
	bg.z_index = -10
	add_child(bg)
	bg.draw.connect(func():
		# sky
		var sky: Color = (Db.BIOMES[biome].atmo as Color)
		bg.draw_rect(Rect2(-CS * 10, -CS * 30, CS * (W + 20), CS * (30 + SURFACE)), sky.darkened(0.2))
		# tunnel walls: a darker version of each layer
		for i in LAYERS.size():
			var top: int = LAYERS[i].top
			var bottom: int = LAYERS[i + 1].top if i + 1 < LAYERS.size() else H
			var col: Color = palette[i]
			bg.draw_rect(Rect2(0, top * CS, W * CS, (bottom - top) * CS), col.darkened(0.72))
		# faint strata lines
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for k in 220:
			var y := rng.randf_range(SURFACE, H) * CS
			var x := rng.randf_range(0, W) * CS
			bg.draw_line(Vector2(x, y), Vector2(x + rng.randf_range(40, 180), y + rng.randf_range(-6, 6)), Color(1, 1, 1, 0.04), 2.0)
	)
	bg.queue_redraw()


func _make_chunk(c: Vector2i) -> void:
	var solid := Node2D.new()
	add_child(solid)
	var glow := Node2D.new()
	glow.z_index = 2
	var gm := CanvasItemMaterial.new()
	gm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = gm
	add_child(glow)
	solid.draw.connect(func(): _draw_chunk(solid, c, false))
	glow.draw.connect(func(): _draw_chunk(glow, c, true))
	_chunks[c] = [solid, glow]
	solid.queue_redraw()
	glow.queue_redraw()


func redraw_cell(p: Vector2i) -> void:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var q := Vector2i((p.x + dx) / CHUNK, (p.y + dy) / CHUNK)
			if _chunks.has(q):
				_chunks[q][0].queue_redraw()
				_chunks[q][1].queue_redraw()


func _hash(x: int, y: int) -> float:
	return float(hash(Vector2i(x, y)) % 1000) / 1000.0


func _draw_chunk(n: Node2D, c: Vector2i, glow: bool) -> void:
	for y in range(c.y * CHUNK, mini(H, (c.y + 1) * CHUNK)):
		for x in range(c.x * CHUNK, mini(W, (c.x + 1) * CHUNK)):
			var t := cells[idx(x, y)]
			if t == AIR:
				continue
			var r := Rect2(x * CS, y * CS, CS, CS)
			var h := _hash(x, y)
			var li := layer_of(y)
			if not glow:
				var base: Color = palette[li]
				match t:
					HARD:
						base = base.darkened(0.45)
					VOIDROCK:
						base = Color("1a1420")
					BEDROCK:
						base = Color("121015")
					RUNE:
						base = Color("2c2a38")
					LAVA:
						base = Color("5a1a0a")
					GAS:
						base = palette[li].darkened(0.6)
				n.draw_rect(r, base.lightened(h * 0.08).darkened((1.0 - h) * 0.06))
				# bevelled edges against open space
				if not is_solid(x, y - 1):
					n.draw_rect(Rect2(r.position, Vector2(CS, 4)), base.lightened(0.28))
				if not is_solid(x, y + 1):
					n.draw_rect(Rect2(r.position + Vector2(0, CS - 4), Vector2(CS, 4)), base.darkened(0.45))
				if not is_solid(x - 1, y):
					n.draw_rect(Rect2(r.position, Vector2(3, CS)), base.lightened(0.12))
				if not is_solid(x + 1, y):
					n.draw_rect(Rect2(r.position + Vector2(CS - 3, 0), Vector2(3, CS)), base.darkened(0.3))
				if t == HARD or t == VOIDROCK:
					n.draw_line(r.position + Vector2(6, 8), r.position + Vector2(CS - 8, CS - 6), base.lightened(0.18), 2.0)
				elif h > 0.7:
					n.draw_circle(r.position + Vector2(8 + h * 14, 10 + (1.0 - h) * 12), 2.5, base.darkened(0.3))
			else:
				if t >= ORE0:
					var col := Db.item_color(ORES[t - ORE0].item)
					for k in 3:
						var p := r.position + Vector2(6 + fmod(h * 97.0 * (k + 1), 20.0), 6 + fmod(h * 53.0 * (k + 2), 20.0))
						var s := 3.0 + fmod(h * 13.0 * (k + 1), 3.0)
						n.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)
				elif t == GAS:
					n.draw_circle(r.get_center() + Vector2(h * 8 - 4, 0), 5.0, Color(0.6, 1.0, 0.4, 0.55))
					n.draw_circle(r.get_center() + Vector2(4, h * 8 - 4), 3.0, Color(0.6, 1.0, 0.4, 0.45))
				elif t == RUNE:
					var rc: Color = THEMES[_chamber_theme_near(x, y)].color
					n.draw_line(r.position + Vector2(8, CS * 0.5), r.position + Vector2(CS - 8, CS * 0.5), Color(rc, 0.7), 2.0)
					n.draw_circle(r.get_center(), 2.0, rc)


func _chamber_theme_near(x: int, y: int) -> String:
	for ch in chambers:
		if ch.rect.grow(1).has_point(Vector2i(x, y)):
			return ch.theme
	return "vault"


func _build_chamber_fx() -> void:
	for ch in chambers:
		var r: Rect2i = ch.rect
		var col: Color = THEMES[ch.theme].color
		var fx := Node2D.new()
		fx.z_index = -5
		var gm := CanvasItemMaterial.new()
		gm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		fx.material = gm
		add_child(fx)
		fx.draw.connect(func():
			var rr := Rect2(r.position * CS, r.size * CS)
			fx.draw_rect(rr, Color(col, 0.10))
			var visited: bool = Game.dig_state(cave_key).chambers.has(ch.id)
			var c: Vector2 = ch.centre + Vector2(0, -CS * 0.9)
			var a := 0.35 if visited else 1.0
			fx.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -34), c + Vector2(16, 0), c + Vector2(0, 26), c + Vector2(-16, 0)]), Color(col, a))
			fx.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -22), c + Vector2(8, 0), c + Vector2(0, 14), c + Vector2(-8, 0)]), Color(1, 1, 1, 0.8 * a))
		)
		var light := PointLight2D.new()
		light.texture = _light_tex()
		light.texture_scale = 3.2
		light.color = col
		light.energy = 0.9
		light.position = ch.centre + Vector2(0, -CS)
		add_child(light)
		_rift_nodes[ch.id] = [fx, light]


var _ltex: GradientTexture2D
func _light_tex() -> GradientTexture2D:
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


# --------------------------------------------------------------------------
# digging
# --------------------------------------------------------------------------

func hardness(c: int, y: int) -> float:
	match c:
		BEDROCK, LAVA:
			return -1.0
		HARD:
			return 1.3
		VOIDROCK:
			return 1.8
		RUNE:
			return 1.4
		GAS:
			return 0.1
	if c >= ORE0:
		return LAYERS[layer_of(y)].hard * 1.25
	return LAYERS[layer_of(y)].hard


## Can the pod cut this cell? Returns "" or a reason.
func dig_block_reason(p: Vector2i) -> String:
	var c := get_cell(p.x, p.y)
	if c == BEDROCK:
		return "Bedrock. Nothing cuts that."
	if c == LAVA:
		return "Molten rock. Your drill would melt."
	var sk := Game.skill_level("mining")
	if c == HARD and sk < 30:
		return "Hardened rock needs Mining 30."
	if c == VOIDROCK and sk < 55:
		return "Void rock needs Mining 55."
	if c >= ORE0 and sk < int(ORES[c - ORE0].req):
		return "%s vein needs Mining %d." % [Db.item_name(ORES[c - ORE0].item), ORES[c - ORE0].req]
	return ""


func dig_out(p: Vector2i) -> void:
	var c := get_cell(p.x, p.y)
	cells[idx(p.x, p.y)] = AIR
	dug[idx(p.x, p.y)] = 1
	_mm_dirty = true
	redraw_cell(p)
	var pos := cell_centre(p)
	_debris(pos, palette[layer_of(p.y)])
	Game.drain_energy(0.35)
	Game.record_dig(1)
	if c >= ORE0:
		var o: Dictionary = ORES[c - ORE0]
		var q := randi_range(o.qty[0], o.qty[1])
		if o.item == "fossil":
			Game.collect_relic("fossil")
			hud.big("FOSSIL FOUND", "Something old, pressed into the stone", Color("e8dcc4"))
		else:
			var got := Game.add_item(o.item, q)
			_run_items[o.item] = int(_run_items.get(o.item, 0)) + got
		Game.gain_skill_xp("mining", 8.0 + layer_of(p.y) * 6.0)
		Sound.play("rock_break", -6.0, 0.1)
	elif c == GAS:
		_gas_clouds.append({"pos": pos, "t": 5.0})
		Game.notify.emit("Gas pocket! Get clear.", Color("9be86a"))
		Sound.play("shield_hit", -2.0, 0.2)
	_dug_since_save += 1
	if _dug_since_save >= 25:
		_dug_since_save = 0
		save_dug()


func _debris(pos: Vector2, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 12
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = col.lightened(0.2)
	p.position = pos
	p.emitting = true
	add_child(p)
	p.finished.connect(p.queue_free)


# --------------------------------------------------------------------------
# frame
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var depth := int(maxf(0.0, pod.position.y / CS - SURFACE) * 2.0)
	var li := layer_of(int(pod.position.y / CS))
	_depth_label.text = "%d m" % depth
	_layer_label.text = LAYERS[li].name if pod.position.y / CS >= SURFACE else "Surface"
	# darker the deeper you go; the headlamp matters more
	var dk := clampf((pod.position.y / CS - SURFACE) / 40.0, 0.0, 1.0)
	_dark.color = Color(1, 1, 1).lerp(Color(0.07, 0.07, 0.1), dk)
	# gas clouds
	for g in _gas_clouds.duplicate():
		g.t -= delta
		if g.t <= 0.0:
			_gas_clouds.erase(g)
		elif pod.position.distance_to(g.pos) < 70.0 and not pod.dead:
			Game.take_damage(12.0 * delta)
	queue_redraw()
	_chart(delta)
	# prompts
	var txt := ""
	if pod.position.y / CS < SURFACE + 0.5:
		txt = "[E] Ride the lift back to the surface"
		if Input.is_action_just_pressed("interact") and not Game.ui_open:
			_exit_to_surface()
	var ch := chamber_at(pod.position)
	if not ch.is_empty():
		var visited: bool = Game.dig_state(cave_key).chambers.has(ch.id)
		txt = "[E] Enter the %s%s" % [THEMES[ch.theme].name, "  (explored)" if visited else ""]
		if Input.is_action_just_pressed("interact") and not Game.ui_open:
			save_dug()
			Game.enter_chamber(ch, pod.position)
	if txt == "" and not pod.dig_msg.is_empty():
		txt = pod.dig_msg
	hud.set_prompt(txt, Color("ffd98a") if pod.dig_msg.is_empty() or txt != pod.dig_msg else Color("ff9f43"), pod.dig_progress)
	if Input.is_action_just_pressed("takeoff") and not Game.ui_open:
		_emergency_recall()


func _draw() -> void:
	for g in _gas_clouds:
		var a: float = clampf(g.t / 5.0, 0.0, 1.0)
		draw_circle(g.pos, 70.0 * (1.2 - a * 0.4), Color(0.5, 0.95, 0.35, 0.22 * a))


func chamber_at(p: Vector2) -> Dictionary:
	for ch in chambers:
		var r: Rect2i = ch.rect
		if Rect2(r.position * CS, r.size * CS).has_point(p) and p.distance_to(ch.centre) < CS * 3.0:
			return ch
	return {}


func _exit_to_surface() -> void:
	save_dug()
	Game.cave["pod"] = []
	Sound.play("takeoff", -8.0, 0.0)
	Game.leave_cave()


func _emergency_recall() -> void:
	if pod.position.y / CS < SURFACE + 1:
		return
	if Game.spend_energy(30.0):
		Game.notify.emit("Emergency lift: 30 energy", Color("ffd98a"))
	else:
		var lost := _lose_run_items(0.4)
		Game.notify.emit("Emergency lift without power: %d units of ore left behind" % lost, Color("ff6b6b"))
	pod.position = cell_centre(Vector2i(W / 2, SURFACE - 1))
	pod.velocity = Vector2.ZERO
	save_dug()


func _lose_run_items(frac: float) -> int:
	var lost := 0
	for it in _run_items.keys():
		var q := int(floor(int(_run_items[it]) * frac))
		q = mini(q, Game.count(it))
		if q > 0:
			Game.remove_item(it, q)
			lost += q
			_run_items[it] = int(_run_items[it]) - q
	return lost


func _on_died() -> void:
	if pod.dead:
		return
	pod.dead = true
	var lost := _lose_run_items(0.5)
	hud.show_death()
	Sound.play("death", -2.0, 0.0)
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	pod.position = cell_centre(Vector2i(W / 2, SURFACE - 1))
	pod.velocity = Vector2.ZERO
	pod.dead = false
	Game.hull = Game.max_hull() * 0.6
	Game.energy = maxf(Game.energy, Game.max_energy() * 0.4)
	Game.hull_changed.emit()
	Game.energy_changed.emit(Game.energy, Game.max_energy())
	hud.hide_death()
	Game.big_notify.emit("REBOOTED", "Hauled back up the shaft%s" % ("  ·  %d units of ore lost" % lost if lost > 0 else ""), Color("6ee06a"))


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
	_depth_label = UiKit.label("0 m", 30, Color("ffd98a"), true)
	v.add_child(_depth_label)
	_layer_label = UiKit.label("", 14, UiKit.ACCENT)
	v.add_child(_layer_label)
	v.add_child(UiKit.label("T  emergency lift", 12, UiKit.MUTED))



# --------------------------------------------------------------------------
# lava: one animated layer, a few lights and rising embers
# --------------------------------------------------------------------------

func _build_lava() -> void:
	var lava_cells: Array[Vector2i] = []
	for y in H:
		for x in W:
			if cells[idx(x, y)] == LAVA:
				lava_cells.append(Vector2i(x, y))
	if lava_cells.is_empty():
		return
	var layer := Node2D.new()
	layer.z_index = 1
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lava2d.gdshader")
	layer.material = mat
	add_child(layer)
	layer.draw.connect(func():
		for c in lava_cells:
			layer.draw_rect(Rect2(c.x * CS, c.y * CS, CS, CS), Color.WHITE)
	)
	layer.queue_redraw()
	# lights: a sparse sample so big pools don't cost a light per cell
	var lit := 0
	for c in lava_cells:
		if (c.x + c.y * 3) % 4 != 0 or lit >= 48:
			continue
		lit += 1
		var l := PointLight2D.new()
		l.texture = _light_tex()
		l.texture_scale = 2.4
		l.color = Color(1.0, 0.45, 0.12)
		l.energy = 0.75
		l.position = cell_centre(c)
		add_child(l)
		_lava_lights.append(l)
	# embers from lava with open space above
	var pts := PackedVector2Array()
	for c in lava_cells:
		if not is_solid(c.x, c.y - 1):
			pts.append(Vector2((c.x + 0.5) * CS, c.y * CS))
	if pts.is_empty():
		return
	var e := CPUParticles2D.new()
	e.amount = mini(12 + pts.size() * 3, 140)
	e.lifetime = 1.8
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	e.emission_points = pts
	e.direction = Vector2(0, -1)
	e.spread = 25.0
	e.initial_velocity_min = 25.0
	e.initial_velocity_max = 70.0
	e.gravity = Vector2(0, -12)
	e.scale_amount_min = 1.5
	e.scale_amount_max = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	g.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	e.color_ramp = g
	var em := CanvasItemMaterial.new()
	em.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	em.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	e.material = em
	e.z_index = 3
	add_child(e)


var _lava_lights: Array[PointLight2D] = []


# --------------------------------------------------------------------------
# minimap: everything the pod's lamp has touched
# --------------------------------------------------------------------------

const MM_SCALE := 3
const MM_SIGHT := 4
var _mm_img: Image
var _mm_tex: ImageTexture
var _mm_rect: TextureRect
var _mm_marker: Control
var _mm_view: Control
var _mm_t := 0.0
var _mm_dirty := true


func _build_minimap() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pc.position = Vector2(20, 236)
	pc.theme = UiKit.theme()
	pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.03, 0.04, 0.06, 0.85), UiKit.LINE, 8, 1, 6))
	layer.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(UiKit.label("SURVEY", 11, UiKit.MUTED, true))
	# a window onto the full map that follows the pod
	_mm_view = Control.new()
	_mm_view.custom_minimum_size = Vector2(W * MM_SCALE, 260)
	_mm_view.clip_contents = true
	v.add_child(_mm_view)
	_mm_img = Image.create(W, H, false, Image.FORMAT_RGBA8)
	_mm_tex = ImageTexture.create_from_image(_mm_img)
	_mm_rect = TextureRect.new()
	_mm_rect.texture = _mm_tex
	_mm_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mm_rect.size = Vector2(W, H) * MM_SCALE
	_mm_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_mm_view.add_child(_mm_rect)
	_mm_marker = Control.new()
	_mm_marker.draw.connect(func():
		var a := 0.6 + 0.4 * sin(_t * 6.0)
		_mm_marker.draw_circle(Vector2.ZERO, 3.5, Color(1, 1, 1, a))
	)
	_mm_view.add_child(_mm_marker)


func _chart(delta: float) -> void:
	_mm_t -= delta
	if _mm_t <= 0.0:
		_mm_t = 0.2
		var c := cell_at(pod.position)
		for dy in range(-MM_SIGHT, MM_SIGHT + 1):
			for dx in range(-MM_SIGHT, MM_SIGHT + 1):
				var x := c.x + dx
				var y := c.y + dy
				if x < 0 or y < 0 or x >= W or y >= H or dx * dx + dy * dy > MM_SIGHT * MM_SIGHT:
					continue
				if not seen[idx(x, y)]:
					seen[idx(x, y)] = 1
					_mm_dirty = true
		if _mm_dirty:
			_mm_dirty = false
			_paint_minimap()
	if _mm_rect == null:
		return
	# keep the pod centred vertically in the window
	var pp := pod.position / CS * MM_SCALE
	var vh := _mm_view.size.y
	var oy := clampf(pp.y - vh * 0.5, 0.0, maxf(0.0, H * MM_SCALE - vh))
	_mm_rect.position = Vector2(0, -oy)
	_mm_marker.position = Vector2(pp.x, pp.y - oy)
	_mm_marker.queue_redraw()


func _paint_minimap() -> void:
	for y in H:
		for x in W:
			var i := idx(x, y)
			var t := cells[i]
			var col := Color(0.02, 0.02, 0.03, 1.0)
			if y < SURFACE:
				col = Color(0.35, 0.5, 0.65, 0.5)
			elif seen[i]:
				if t == AIR:
					col = Color(0.85, 0.78, 0.6, 0.85) if dug[i] else Color(0.45, 0.5, 0.58, 0.7)
				elif t == LAVA:
					col = Color(1.0, 0.4, 0.1)
				elif t == GAS:
					col = Color(0.5, 0.9, 0.35)
				elif t >= ORE0:
					col = Db.item_color(ORES[t - ORE0].item)
				elif t == RUNE:
					col = THEMES[_chamber_theme_near(x, y)].color
				else:
					col = (palette[layer_of(y)] as Color).darkened(0.35)
			_mm_img.set_pixel(x, y, col)
	for ch in chambers:
		var cc: Vector2i = cell_at(ch.centre)
		if seen[idx(cc.x, cc.y)]:
			_mm_img.set_pixel(cc.x, cc.y, Color.WHITE)
	_mm_tex.update(_mm_img)
