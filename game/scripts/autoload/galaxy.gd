extends Node
## Deterministic procedural galaxy. Same seed -> same stars, planets, names.

const GALAXY_SEED := 424242
const STAR_COUNT := 48
const BASE_WARP_RANGE := 20.0

const STAR_CLASSES := [
	{"cls": "O", "color": Color("9bb0ff"), "weight": 1},
	{"cls": "B", "color": Color("aabfff"), "weight": 2},
	{"cls": "A", "color": Color("d5e0ff"), "weight": 3},
	{"cls": "F", "color": Color("fff4ea"), "weight": 4},
	{"cls": "G", "color": Color("ffe7a8"), "weight": 5},
	{"cls": "K", "color": Color("ffb56b"), "weight": 5},
	{"cls": "M", "color": Color("ff8a5b"), "weight": 4},
]

const SYL_A := ["Ka", "Ve", "Lo", "Zy", "Tor", "Mi", "Qua", "Ae", "Xi", "Ny", "Sol", "Or", "Pe", "Ru", "Ith", "Ba", "Cel", "Dra", "Eo", "Fyn", "Gal", "Hel", "Io", "Ju", "Ly"]
const SYL_B := ["ra", "lon", "th", "vi", "mar", "sis", "tae", "no", "rix", "dun", "pho", "lia", "mon", "xa", "ren", "sol", "tis", "gor", "vel", "que"]
const SYL_C := ["", "", "", " Prime", " IV", "is", "a", "on", " Major", " Minor", "us", "ia"]

var stars: Array = []


func _ready() -> void:
	generate()


func generate() -> void:
	stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = GALAXY_SEED
	var used_names := {}
	var town_names := {}
	for i in STAR_COUNT:
		var pos := Vector3.ZERO
		if i > 0:
			# spiral-ish disc; keep a minimum spacing
			for _attempt in 40:
				var r := sqrt(rng.randf()) * 70.0 + 6.0
				var a := rng.randf() * TAU
				var arm := sin(a * 2.0 + r * 0.08) * 6.0
				pos = Vector3(cos(a) * (r + arm), rng.randf_range(-3, 3), sin(a) * (r + arm))
				var ok := true
				for s in stars:
					if s.pos.distance_to(pos) < 7.5:
						ok = false
						break
				if ok:
					break
		var cls: Dictionary = _pick_weighted(rng, STAR_CLASSES)
		var star := {
			"index": i,
			"name": _unique_name(rng, used_names),
			"pos": pos,
			"cls": cls.cls,
			"color": cls.color,
			"seed": rng.randi(),
			"planets": [],
		}
		var count := rng.randi_range(2, 5)
		var biomes: Array = Db.BIOMES.keys().filter(func(k): return not Db.BIOMES[k].get("legendary", false))
		if i == 0:
			star.name = "Solace"
			star.cls = "G"
			star.color = Color("ffe7a8")
			count = 4
		for p in count:
			var biome: String = biomes[rng.randi() % biomes.size()]
			if i == 0:
				biome = ["verdant", "dune", "frost", "prism"][p]
			var pname := "%s %s" % [star.name, ["I", "II", "III", "IV", "V", "VI"][p]]
			if rng.randf() < 0.45 or i == 0:
				pname = _unique_name(rng, used_names)
			if i == 0 and p == 0:
				pname = "Cradle"
			star.planets.append({
				"index": p,
				"star": i,
				"key": "%d:%d" % [i, p],
				"name": pname,
				"biome": biome,
				"radius": rng.randf_range(150.0, 210.0) if not (i == 0 and p == 0) else 170.0,
				"seed": rng.randi(),
				"orbit": 380.0 + p * 260.0 + rng.randf_range(-40, 40),
				"angle": rng.randf() * TAU,
				"tilt": rng.randf_range(-0.25, 0.25),
				"rings": rng.randf() < 0.3,
			})
		star["belt"] = _make_belt(star)
		star["station"] = _make_station(star)
		for pl in star.planets:
			pl["_star_dist"] = pos.length()
			pl["town"] = _make_town(i, pl, town_names)
		stars.append(star)
	_add_extras()


## Everything added after launch uses its own seeded streams so the original
## stars, planets and names never shift.
func _add_extras() -> void:
	# the three farthest stars hold the legendary edge worlds
	var order: Array = range(1, stars.size())
	order.sort_custom(func(a, b): return stars[a].pos.length() > stars[b].pos.length())
	var legends := ["forge", "abyss", "tempest"]
	var legend_names := ["Anvil", "Thalassa", "Maelstrom"]
	for li in 3:
		var st: Dictionary = stars[order[li]]
		st["legendary"] = legends[li]
		st.planets.append({"index": st.planets.size(), "star": st.index, "key": "%d:%d" % [st.index, st.planets.size()],
			"name": legend_names[li], "biome": legends[li], "radius": 200.0, "seed": hash("legend:%d" % st.index),
			"orbit": 380.0 + st.planets.size() * 260.0, "angle": 1.3, "tilt": 0.1, "rings": li == 1, "town": {}, "legendary": true})
	for st in stars:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("extras:%d" % st.index)
		var home: bool = st.index == 0
		# moons around some worlds
		var parents: Array = st.planets.duplicate()
		for p in parents:
			if p.get("legendary", false):
				continue
			if (home and p.index == 0) or (not home and rng.randf() < 0.3):
				var mi: int = st.planets.size()
				st.planets.append({"index": mi, "star": st.index, "key": "%d:%d" % [st.index, mi],
					"name": _moon_name(p.name), "biome": ["frost", "dune", "ember", "prism"][rng.randi() % 4],
					"radius": rng.randf_range(80.0, 100.0), "seed": rng.randi(), "orbit": 0.0, "angle": rng.randf() * TAU,
					"tilt": 0.0, "rings": false, "town": {}, "moon_of": p.index, "moon_dist": rng.randf_range(95.0, 120.0)})
		# a gas giant in about half the systems (always at home)
		if home or rng.randf() < 0.5:
			var outer := 0.0
			for p in st.planets:
				outer = maxf(outer, float(p.orbit))
			st["giant"] = {"orbit": outer + 320.0, "angle": rng.randf() * TAU, "radius": rng.randf_range(55.0, 80.0),
				"hue": rng.randf(), "rings": rng.randf() < 0.5, "name": "%s Giant" % st.name}
		# derelicts to board
		var derelicts := []
		for k in (1 if home else rng.randi_range(1, 2)):
			derelicts.append({"orbit": rng.randf_range(350.0, 900.0), "angle": rng.randf() * TAU, "height": rng.randf_range(-40, 60)})
		st["derelicts"] = derelicts
		# the system's relay beacon
		st["relay"] = {"orbit": rng.randf_range(620.0, 780.0), "angle": rng.randf() * TAU}


## A short proper name for a moon, derived from its parent's name so it
## doesn't consume the generator's random stream.
func _moon_name(parent: String) -> String:
	var h := absi(hash(parent + ":moon"))
	var a := ["Ka", "Vel", "Ori", "Tas", "Ny", "Sel", "Mira", "Ost", "Lu", "Pha", "Ise", "Dre"]
	var b := ["ra", "wen", "th", "nis", "del", "mo", "ssa", "ly", "rek", "ne", "via", "ku"]
	return (a[h % a.size()] as String) + (b[(h / 13) % b.size()] as String)


## Where a planet (or moon) is at time t, in system space coordinates.
func orbit_pos(p: Dictionary, t: float) -> Vector3:
	if p.has("moon_of"):
		var parent: Dictionary = stars[p.star].planets[p.moon_of]
		var c := orbit_pos(parent, t)
		var a: float = p.angle + t * 0.02
		return c + Vector3(cos(a), 0.15, sin(a)) * float(p.moon_dist)
	var orbit: float = p.orbit
	var w := 0.0025 * pow(400.0 / maxf(orbit, 100.0), 1.5)
	var a2: float = p.angle + t * w
	return Vector3(cos(a2) * orbit, sin(p.angle * 3.0) * 30.0, sin(a2) * orbit)


func is_moon(p: Dictionary) -> bool:
	return p.has("moon_of")


func star(i: int) -> Dictionary:
	return stars[clampi(i, 0, stars.size() - 1)]


func planet(star_i: int, planet_i: int) -> Dictionary:
	var s := star(star_i)
	return s.planets[clampi(planet_i, 0, s.planets.size() - 1)]


func distance(a: int, b: int) -> float:
	return star(a).pos.distance_to(star(b).pos)


func _pick_weighted(rng: RandomNumberGenerator, arr: Array) -> Dictionary:
	var total := 0
	for e in arr:
		total += e.weight
	var roll := rng.randi() % total
	for e in arr:
		roll -= e.weight
		if roll < 0:
			return e
	return arr[0]


func _unique_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for _i in 30:
		var n: String = SYL_A[rng.randi() % SYL_A.size()] + SYL_B[rng.randi() % SYL_B.size()] + SYL_C[rng.randi() % SYL_C.size()]
		if not used.has(n):
			used[n] = true
			return n
	return "Unnamed-%d" % rng.randi_range(100, 999)


## Species name for fauna/flora on a planet, deterministic per (planet seed, kind).
func species_name(planet_seed: int, kind: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [planet_seed, kind])
	var pre := ["Glim", "Puff", "Zor", "Mop", "Quill", "Snub", "Bram", "Wob", "Flin", "Tuv", "Rho", "Pim"]
	var suf := ["ling", "bat", "orb", "hopper", "wort", "cap", "shade", "grub", "snout", "tail", "bloom", "fern"]
	return pre[rng.randi() % pre.size()] + suf[rng.randi() % suf.size()]


## Trade hub for a planet, or {} if it has none. Deterministic.
func _make_town(star_i: int, pl: Dictionary, used: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("town:%s" % pl.key)
	var home: bool = star_i == 0 and pl.index == 0
	if not home and rng.randf() > 0.4:
		return {}
	var name := "The Cradle"
	if not home:
		for _i in 20:
			name = Db.TOWN_PRE[rng.randi() % Db.TOWN_PRE.size()] + Db.TOWN_SUF[rng.randi() % Db.TOWN_SUF.size()]
			if not used.has(name):
				break
		used[name] = true
	var dist: float = pl.get("_star_dist", 0.0)
	# trainers teach higher ranks the farther you get from home
	var max_tier := 1
	if dist > 18.0 or (star_i == 0 and pl.index > 0):
		max_tier = 2
	var tradeable := ["ferrite", "cobalt", "lumen", "voidshard", "biofiber", "sporegel", "plasma", "scrap", "alloy", "circuit", "polymer"]
	var town := {
		"name": name,
		"specialty": tradeable[rng.randi() % tradeable.size()],
		"max_tier": max_tier,
		"seed": rng.randi(),
	}
	# Artisan trainers are rare and live at the edge of the galaxy
	if dist > 42.0 and rng.randf() < 0.4:
		town.max_tier = 3
	return town


## Asteroid belt for a star: ring between two planet orbits. Uses its own RNG
## so adding belts never changes the rest of the galaxy.
func _make_belt(star: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("belt:%d" % star.index)
	var orbits: Array = []
	for p in star.planets:
		orbits.append(p.orbit)
	orbits.sort()
	var k := mini(1, orbits.size() - 1)
	var inner: float = orbits[k - 1] if k > 0 else 260.0
	var outer: float = orbits[k] if orbits.size() > k else inner + 300.0
	if star.index == 0:
		inner = orbits[0]
		outer = orbits[1]
	var mix: Dictionary = Db.BELT_MIX.get(star.cls, Db.BELT_MIX.G).duplicate()
	if star.index == 0:
		mix = {"rocky": 50, "metallic": 25, "icy": 22, "crystal": 3, "void": 0}
	return {
		"radius": (inner + outer) * 0.5,
		"width": clampf((outer - inner) * 0.35, 60.0, 140.0),
		"count": rng.randi_range(110, 160),
		"mix": mix,
		"comet": star.index == 0 or rng.randf() < 0.45,
		"seed": rng.randi(),
		"tilt": rng.randf_range(-0.08, 0.08),
	}


## Orbital trade station: sits near the first world, with its own demand.
func _make_station(star: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("station:%d" % star.index)
	var goods := ["ferrite", "cobalt", "lumen", "voidshard", "biofiber", "sporegel", "plasma", "nickel", "cryo_ice", "stardust", "scrap", "alloy", "circuit", "polymer"]
	var picks := []
	while picks.size() < 4:
		var g: String = goods[rng.randi() % goods.size()]
		if not picks.has(g):
			picks.append(g)
	var suffix: String = Db.STATION_SUFFIX[rng.randi() % Db.STATION_SUFFIX.size()]
	return {
		"name": "%s %s" % [star.name, suffix],
		"demand": [picks[0], picks[1]],
		"surplus": [picks[2], picks[3]],
		"seed": rng.randi(),
	}
