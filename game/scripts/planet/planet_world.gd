extends Node3D
## Builds and runs a single planet: terrain, sky, water, flora, resources,
## fauna, the home outpost, the player and the HUD.

const TERRAIN_RES := 112
const DAY_LENGTH := 720.0 # seconds per full day
const HOME_DIR := Vector3(0.0, 0.25, 1.0)

var planet: Dictionary
var biome: Dictionary
var gen: PlanetGen
var player: CharacterBody3D
var hud: CanvasLayer
var sun: DirectionalLight3D
var sun_dir := Vector3.UP
var env: Environment
var underwater := 0.0 # 0..1, set by the player when the camera is below the sea
var underwater_depth := 0.0
var _uw_fog := false
var _post: CanvasLayer
var _post_mat: ShaderMaterial

## Per-world look for the atmosphere pass: heat haze, sun-shaft strength,
## colour grade, and whether cold nights frost the lens.
const POST := {
	"dune": {"shimmer": 1.0, "rays": 0.35, "grade": Color(1.06, 1.0, 0.9), "grade_amt": 0.5},
	"ember": {"shimmer": 1.3, "rays": 0.3, "grade": Color(1.1, 0.95, 0.85), "grade_amt": 0.4, "hot_night": true},
	"forge": {"shimmer": 1.1, "rays": 0.3, "grade": Color(1.08, 0.96, 0.88), "grade_amt": 0.4, "hot_night": true},
	"frost": {"shimmer": 0.0, "rays": 0.4, "grade": Color(0.92, 0.98, 1.08), "grade_amt": 0.5, "frost": true},
	"verdant": {"shimmer": 0.0, "rays": 0.55, "grade": Color(1.02, 1.03, 0.97), "grade_amt": 0.3},
	"bloom": {"shimmer": 0.15, "rays": 0.6, "grade": Color(1.05, 0.95, 1.08), "grade_amt": 0.5},
	"prism": {"shimmer": 0.2, "rays": 0.5, "grade": Color(1.02, 0.96, 1.1), "grade_amt": 0.4},
	"abyss": {"shimmer": 0.0, "rays": 0.5, "grade": Color(0.92, 1.0, 1.08), "grade_amt": 0.4},
	"tempest": {"shimmer": 0.0, "rays": 0.25, "grade": Color(0.9, 0.95, 1.05), "grade_amt": 0.5},
}
var spawn_dir := Vector3.UP
var flora_tint := Color.WHITE
var is_home := false
var danger_level := 1
var enemies: Array[Enemy] = []
var town: Town
var town_dir := Vector3.ZERO
var _in_town := false
var pois: Array[Poi] = []
var weather: Weather
var outpost_pos := Vector3.ZERO
var _sky_pivot: Node3D
var sky_bodies: Array[Node3D] = []
var ring_node: MeshInstance3D
var _sky_offset := 0.0
var _cloud_mat: ShaderMaterial
var ground_cover: GroundCover

var _nodes: Array[ResourceNode] = []
var _interactables: Array[Node3D] = []
var _critters: Array[Critter] = []
var _flora_points := {} # type -> PackedVector3Array
var _atmo_mat: ShaderMaterial
var terrain_body: StaticBody3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	planet = Galaxy.planet(Game.star_index, Game.planet_index)
	biome = Db.BIOMES[planet.biome]
	is_home = Game.star_index == 0 and Game.planet_index == 0
	gen = PlanetGen.new(planet)
	_rng.seed = planet.seed

	var hue_shift := _rng.randf_range(-0.07, 0.07)
	var base_col: Color = biome.colors.low
	flora_tint = Color.from_hsv(fposmod(base_col.h + hue_shift + 0.02, 1.0), clampf(base_col.s + 0.1, 0.0, 1.0), clampf(base_col.v + 0.12, 0.0, 1.0))

	_build_environment()
	_build_terrain()
	_build_liquid()
	_build_atmosphere()
	var clouds := gen.cloud_shell(gen.radius * 1.3)
	add_child(clouds)
	_cloud_mat = clouds.material_override

	spawn_dir = _find_land(Game.land_dir if Game.land_dir != Vector3.ZERO else HOME_DIR)
	if is_home and (Game.visited_planets.is_empty() or Game.land_dir.distance_to(HOME_DIR.normalized()) < 0.02):
		spawn_dir = _find_land(HOME_DIR)
	var outpost_dir := _find_land(HOME_DIR) if is_home else Vector3.ZERO
	town_dir = gen.town_dir()

	_scatter_flora(outpost_dir)
	_spawn_nodes(outpost_dir)
	_spawn_critters()
	if is_home:
		_build_outpost(outpost_dir)
	if town_dir != Vector3.ZERO:
		town = Town.new()
		add_child(town)
		town.build(self, planet.town, town_dir, is_home)
	danger_level = Game.planet_level(Game.star_index, Game.planet_index)
	_spawn_enemies(outpost_dir)
	_spawn_pois(outpost_dir)
	_build_floating_islands()
	_build_sky_bodies()
	if is_home:
		outpost_pos = gen.surface_point(outpost_dir)

	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "planet"
	add_child(hud)

	player = preload("res://scripts/player/planet_player.gd").new()
	player.world = self
	add_child(player)
	player.place_at(spawn_dir, gen)
	if is_home and Game.visited_planets.is_empty():
		# face the Archivist on first boot
		player.ref_fwd = (_surface_basis(outpost_dir, 0.0) * Vector3(0, 0, -1))

	ground_cover = GroundCover.new()
	add_child(ground_cover)
	ground_cover.setup(self, planet.biome, Sound.gfx_quality)
	UiKit.add_vignette(self)
	weather = Weather.new()
	add_child(weather)
	weather.setup(self, planet.biome, planet.seed)
	Sound.play_music(Sound.music_for_biome(planet.biome))
	Sound.loop_start("ambience", "wind_loop", {"dune": -6.0, "frost": -5.0, "ember": -10.0}.get(planet.biome, -12.0), "Ambience", 2.0)
	if Game.arriving_from_space:
		Game.arriving_from_space = false
		player.start_drop()
	Game.record_landing(planet.key)
	hud.refresh_survey(survey_status())
	Game.land_dir = spawn_dir
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_art_style.call_deferred()
	get_tree().node_added.connect(_on_node_added)
	Sound.art_style_changed.connect(_apply_art_style)
	var vents := pois.filter(func(p): return p.type == "volcano").size()
	hud.show_location_banner(planet.name, "%s world  ·  %s system  ·  Danger level %d%s" % [biome.name, Galaxy.star(Game.star_index).name, danger_level, ("  ·  %d Volcanic Vents" % vents) if vents > 0 else ""])
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(self):
			get_tree().create_timer(40.0).timeout.connect(func():
				if is_instance_valid(self):
					Game.tip("homespace", "You have a home, wherever you are. Press %s to step into your Homespace: a Vault for what your hold can't carry, and an Inbox for letters and trader orders." % Game.key("home"))
			)
			Game.tip("first_landing", "Walk with WASD, sprint with %s, jump with %s (hold it mid-air for the jetpack). Press %s to gather glowing resources and %s to scan creatures and plants." % [Game.key("sprint"), Game.key("jump"), Game.key("interact"), Game.key("scan")])
	)


var _combat_check := 0.0


func _process(delta: float) -> void:
	_combat_check -= delta
	if _combat_check <= 0.0:
		_combat_check = 0.5
		if player:
			_update_town(player.global_position)
		for e in enemies:
			if e.is_alive() and e.state == "chase":
				Sound.set_combat(true)
				break
	var a := Game.play_time * TAU / DAY_LENGTH + PI * 0.5
	sun_dir = Vector3(cos(a) * 0.93, 0.28, sin(a) * 0.93).normalized()
	sun.global_basis = Basis.looking_at(-sun_dir, Vector3.UP if absf(sun_dir.y) < 0.95 else Vector3.RIGHT)
	_atmo_mat.set_shader_parameter("sun_dir", sun_dir)
	if _cloud_mat:
		_cloud_mat.set_shader_parameter("sun_dir", sun_dir)
	if _sky_pivot:
		_sky_pivot.rotation.y = -(a - PI * 0.5) + _sky_offset
	if player:
		var up := player.global_position.normalized()
		var day := smoothstep(-0.25, 0.2, up.dot(sun_dir))
		env.fog_light_color = (biome.horizon as Color).darkened(0.2) * day + Color(0.02, 0.03, 0.07) * (1.0 - day)
		env.ambient_light_energy = lerpf(0.25, 0.6, day)
		sun.light_energy = 1.25 * smoothstep(-0.12, 0.12, up.dot(sun_dir))
		_update_post(up, day)
		if underwater > 0.0:
			var wc: Color = biome.water
			var murk := Color(wc.r, wc.g, wc.b).darkened(0.35 + clampf(underwater_depth * 0.03, 0.0, 0.5))
			env.fog_light_color = env.fog_light_color.lerp(murk * (0.4 + 0.6 * day), underwater)
			env.fog_density = lerpf(0.0022, 0.045 + underwater_depth * 0.004, underwater)
			_uw_fog = true
		elif _uw_fog:
			_uw_fog = false
			env.fog_density = 0.0022 # the weather takes it from here
		if day < 0.1 and _combat_check >= 0.49:
			Game.tip("night", "Night falls. Your energy only recharges in sunlight, so go easy on the jetpack until dawn. Energy Cells %s top you up." % Game.key("use_cell"))


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/space_sky.gdshader")
	var star: Dictionary = Galaxy.star(Game.star_index)
	sky_mat.set_shader_parameter("seed", float(star.seed % 1000))
	sky_mat.set_shader_parameter("nebula_a", Color.from_hsv(fposmod(float(star.seed % 360) / 360.0, 1.0), 0.6, 0.5))
	sky_mat.set_shader_parameter("nebula_b", Color.from_hsv(fposmod(float(star.seed % 360) / 360.0 + 0.4, 1.0), 0.7, 0.45))
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = biome.ambient
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = biome.horizon
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	UiKit.polish_environment(env)
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = (star.color as Color).lerp(Color.WHITE, 0.5)
	sun.light_energy = 1.2
	Sound.tune_sun(sun)
	sun.light_angular_distance = 0.6 if Sound.gfx_quality == 2 else 0.0
	add_child(sun)


func _build_terrain() -> void:
	var t0 := Time.get_ticks_msec()
	var mesh := gen.build_mesh(TERRAIN_RES)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = gen.terrain_material()
	if planet.biome == "forge":
		(mi.material_override as ShaderMaterial).set_shader_parameter("grid_glow", 1.0)
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	# collide from both sides: nothing may ever slip underneath the ground
	(tri as ConcavePolygonShape3D).backface_collision = true
	cs.shape = tri
	body.add_child(cs)
	add_child(body)
	terrain_body = body
	print("[planet] terrain built in %d ms" % (Time.get_ticks_msec() - t0))


func _build_liquid() -> void:
	if not gen.has_liquid():
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := gen.sea_radius()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 160
	sm.rings = 80
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("water_color", biome.water)
	mat.render_priority = -100
	if biome.get("lava", false):
		mat.set_shader_parameter("emissive", 2.5)
		mat.set_shader_parameter("wave_speed", 0.15)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_atmosphere() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := gen.radius * 1.9
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	mi.mesh = sm
	_atmo_mat = ShaderMaterial.new()
	_atmo_mat.shader = load("res://shaders/atmosphere.gdshader")
	# draw the sky dome before every other transparent thing (labels, beams,
	# particles), otherwise it paints over them from behind
	_atmo_mat.render_priority = -128
	_atmo_mat.set_shader_parameter("zenith_color", biome.atmo)
	_atmo_mat.set_shader_parameter("horizon_color", biome.horizon)
	_atmo_mat.set_shader_parameter("planet_radius", gen.radius)
	_atmo_mat.set_shader_parameter("atmo_height", gen.radius * 0.8)
	_atmo_mat.set_shader_parameter("sun_color", (Galaxy.star(Game.star_index).color as Color).lerp(Color.WHITE, 0.4))
	mi.material_override = _atmo_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)


func _find_land(start: Vector3) -> Vector3:
	return gen.find_land(start)


func _surface_basis(dir: Vector3, yaw: float) -> Basis:
	return PlanetGen.align_basis(gen.normal_at(dir).lerp(dir, 0.6).normalized(), yaw)


func _random_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


func _is_placeable(dir: Vector3, max_slope: float, away_from: Vector3, clear_radius: float) -> bool:
	if town_dir != Vector3.ZERO and _in_town_zone(dir, 34.0):
		return false
	var h := gen.height(dir)
	if gen.has_liquid() and h < gen.sea + 0.003:
		return false
	if away_from != Vector3.ZERO and gen.surface_point(dir).distance_to(gen.surface_point(away_from)) < clear_radius:
		return false
	return 1.0 - gen.normal_at(dir).dot(dir) < max_slope


func _scatter_flora(outpost_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 11
	var colliders := StaticBody3D.new()
	add_child(colliders)
	for type in biome.flora:
		var count: int = int(biome.flora[type] * 4)
		if count <= 0:
			continue
		var xforms := []
		var pts := PackedVector3Array()
		var is_tree: bool = type != "prop_boulder"
		for i in count:
			var d := _random_dir(rng)
			if not _is_placeable(d, 0.22, outpost_dir, 16.0):
				continue
			var s := rng.randf_range(0.7, 1.5) * (1.0 if is_tree else rng.randf_range(0.6, 1.8))
			var p := gen.surface_point(d) - d * 0.25
			var b := _surface_basis(d, rng.randf() * TAU) if not is_tree else PlanetGen.align_basis(d, rng.randf() * TAU)
			xforms.append(Transform3D(b.scaled(Vector3.ONE * s), p))
			pts.append(p)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = (0.45 if is_tree else 1.0) * s
			cyl.height = 4.0 * s
			cs.shape = cyl
			cs.transform = Transform3D(PlanetGen.align_basis(d), p + d * 2.0 * s)
			colliders.add_child(cs)
		var tint := flora_tint.lerp(Color.from_hsv(rng.randf(), 0.55, 0.9), 0.25)
		var sway: float = {"flora_tree_round": 0.07, "flora_tree_disc": 0.06, "flora_mushroom": 0.035, "flora_cactus": 0.02}.get(type, 0.0)
		ModelUtil.multimesh(self, "res://assets/models/%s.glb" % type, xforms, "Foliage", tint, true, sway)
		_flora_points[type] = pts

	# small non-colliding pebbles for ground detail
	var pebbles := []
	for i in 900:
		var d := _random_dir(rng)
		if not _is_placeable(d, 0.3, Vector3.ZERO, 0.0):
			continue
		var s := rng.randf_range(0.12, 0.35)
		pebbles.append(Transform3D(PlanetGen.align_basis(d, rng.randf() * TAU).scaled(Vector3.ONE * s), gen.surface_point(d) - d * 0.1))
	ModelUtil.multimesh(self, "res://assets/models/prop_boulder.glb", pebbles, "", Color.WHITE, false)


func _spawn_nodes(outpost_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 23
	var id := 0
	for type in biome.nodes:
		var count := int(biome.nodes[type] * 1.8)
		for i in count:
			var d := _random_dir(rng)
			var ok := _is_placeable(d, 0.2, outpost_dir, 10.0)
			id += 1
			if ok:
				_add_node(type, id, d, rng.randf() * TAU)
	# guaranteed starter cluster near the outpost / landing site
	var anchor := outpost_dir if is_home else spawn_dir
	var starter := {"ferrite": 5, "fiber": 3, "energy": 2} if is_home else {}
	if not is_home:
		# a couple of the planet's signature resources close to the landing site
		var keys: Array = biome.nodes.keys()
		starter = {keys[0]: 2, keys[1 % keys.size()]: 2}
	var sid := 10000
	var basis := PlanetGen.align_basis(anchor)
	for type in starter:
		for i in starter[type]:
			sid += 1
			var ang := rng.randf() * TAU
			var near_town := town_dir != Vector3.ZERO and gen.surface_point(anchor).distance_to(gen.surface_point(town_dir)) < 40.0
			var dist := rng.randf_range(36.0, 52.0) if near_town else rng.randf_range(14.0, 30.0)
			var offset := (basis.x * cos(ang) + basis.z * sin(ang)) * dist / gen.radius
			var d := (anchor + offset).normalized()
			if gen.has_liquid() and gen.height(d) < gen.sea + 0.003:
				continue
			_add_node(type, sid, d, ang)


func _add_node(type: String, id: int, d: Vector3, yaw: float) -> void:
	if Game.is_harvested(planet.key, id):
		return
	var n := ResourceNode.new()
	add_child(n)
	n.setup(type, id, self)
	n.global_transform = Transform3D(_surface_basis(d, yaw), gen.surface_point(d) - d * 0.2).scaled_local(n.scale)
	_nodes.append(n)
	_interactables.append(n)


func _spawn_critters() -> void:
	var count: int = biome.critters
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 41
	var colors: Array = biome.fauna_colors
	for i in count:
		# herds near the spawn so there is always something to see
		var d: Vector3
		if i < count / 2:
			var b := PlanetGen.align_basis(spawn_dir)
			var ang := rng.randf() * TAU
			d = (spawn_dir + (b.x * cos(ang) + b.z * sin(ang)) * rng.randf_range(20.0, 70.0) / gen.radius).normalized()
		else:
			d = _random_dir(rng)
		if gen.has_liquid() and gen.height(d) < gen.sea + 0.004:
			continue
		var variant := i % colors.size()
		var c := Critter.new()
		add_child(c)
		var key := "%s:fauna:%d" % [planet.key, variant]
		var sname := Galaxy.species_name(planet.seed, "fauna%d" % variant)
		c.setup(self, d, colors[variant], key, sname, rng.randf_range(0.7, 1.4) * (1.0 + variant * 0.25))
		_critters.append(c)


func _build_outpost(d: Vector3) -> void:
	var b := PlanetGen.align_basis(d)
	var base := gen.surface_point(d) - d * 0.35
	var pad := ModelUtil.instance("res://assets/models/prop_outpost.glb")
	add_child(pad)
	pad.global_transform = Transform3D(b, base)
	var pad_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 7.0
	cyl.height = 6.0
	cs.shape = cyl
	pad_body.add_child(cs)
	add_child(pad_body)
	# tall enough to reach into the ground everywhere under the rim
	pad_body.global_transform = Transform3D(b, base + d * 0.3 - d * 2.7)

	var npc := ArchivistNpc.new()
	add_child(npc)
	npc.setup(self)
	npc.global_transform = Transform3D(b * Basis(Vector3.UP, PI), base + d * 0.6 - b.z * 3.0)
	_interactables.append(npc)

	var fab := Fabricator.new()
	add_child(fab)
	fab.setup(self)
	fab.global_transform = Transform3D(b * Basis(Vector3.UP, -PI * 0.5), base + d * 0.6 + b.x * 4.0)
	_interactables.append(fab)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color("39e5ff")
	lamp.omni_range = 18.0
	lamp.light_energy = 1.4
	add_child(lamp)
	lamp.global_position = base + d * 4.0


# --------------------------------------------------------------------------
# runtime API used by player / hud
# --------------------------------------------------------------------------

func nearest_interactable(pos: Vector3, max_dist: float) -> Node:
	var best: Node = null
	var best_d := max_dist
	for n in _interactables:
		if not is_instance_valid(n):
			continue
		var dd := n.global_position.distance_to(pos)
		if dd < best_d:
			best_d = dd
			best = n
	return best


func on_harvested(n: ResourceNode) -> void:
	Game.mark_harvested(planet.key, n.node_id)
	_interactables.erase(n)
	_nodes.erase(n)


func scan(pos: Vector3, radius: float) -> void:
	_scan_pulse(pos, radius)
	var found := 0
	for n in _nodes:
		if is_instance_valid(n) and n.global_position.distance_to(pos) < radius:
			n.reveal(25.0)
			found += 1
	var new_species := 0
	for c in _critters:
		if c.global_position.distance_to(pos) < radius * 0.6:
			if Game.record_scan(c.species_key, c.species_name + " (fauna)"):
				new_species += 1
	for type in _flora_points:
		if type == "prop_boulder":
			continue
		for p in _flora_points[type]:
			if p.distance_to(pos) < radius * 0.6:
				var key := "%s:flora:%s" % [planet.key, type]
				if Game.record_scan(key, Galaxy.species_name(planet.seed, type) + " (flora)"):
					new_species += 1
				break
	var sites := 0
	for p in pois:
		if not p.revealed and p.global_position.distance_to(pos) < radius * 3.0:
			p.revealed = true
			sites += 1
	Game.notify.emit("Scan: %d resource nodes in range%s" % [found, ("  ·  %d sites marked on compass" % sites) if sites > 0 else ""], Color("5ff7ff"))
	check_survey()


func _scan_pulse(pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var t := create_tween().set_parallel()
	t.tween_property(mi, "scale", Vector3.ONE * radius, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 1.1)
	t.chain().tween_callback(mi.queue_free)


# --------------------------------------------------------------------------
# combat
# --------------------------------------------------------------------------

func _spawn_enemies(outpost_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 61
	var safe := outpost_dir if is_home else spawn_dir
	var camps: int = (7 if is_home else 9 + danger_level / 5)
	var made := 0
	var tries := 0
	while made < camps and tries < 400:
		tries += 1
		var d: Vector3
		if made < 2:
			# a couple of camps within reach of the landing site
			var b := PlanetGen.align_basis(safe)
			var ang := rng.randf() * TAU
			d = (safe + (b.x * cos(ang) + b.z * sin(ang)) * rng.randf_range(100.0, 140.0) / gen.radius).normalized()
		else:
			d = _random_dir(rng)
		if not _is_placeable(d, 0.25, safe, 50.0):
			continue
		if town_dir != Vector3.ZERO and _in_town_zone(d, 95.0):
			continue
		made += 1
		var types := ["scrapper", "scrapper", "sentinel"]
		var n := rng.randi_range(2, 3 if is_home else 4)
		var with_brute := not is_home and rng.randf() < 0.35
		for i in n:
			var t: String = types[rng.randi() % types.size()]
			var lvl := clampi(danger_level + rng.randi_range(0, 1 if is_home else 2), 1, 40)
			_spawn_enemy(t, lvl, _near(d, rng, 7.0), made)
		if with_brute:
			_spawn_enemy("brute", danger_level + 2, d, made)


func _near(d: Vector3, rng: RandomNumberGenerator, dist: float) -> Vector3:
	var b := PlanetGen.align_basis(d)
	var ang := rng.randf() * TAU
	return (d + (b.x * cos(ang) + b.z * sin(ang)) * rng.randf_range(1.0, dist) / gen.radius).normalized()


func _spawn_enemy(t: String, lvl: int, d: Vector3, camp: int) -> Enemy:
	var e := Enemy.new()
	add_child(e)
	e.setup(self, t, lvl, d, camp)
	enemies.append(e)
	return e


func on_enemy_killed(e: Enemy) -> void:
	enemies.erase(e)
	var t := e.type
	var lvl := e.level
	var home := e.home_dir
	var camp := e.camp_id
	# camps repopulate, like WoW spawns
	get_tree().create_timer(120.0).timeout.connect(func():
		if not is_inside_tree():
			return
		if player and player.global_position.distance_to(gen.surface_point(home)) < 35.0:
			get_tree().create_timer(30.0).timeout.connect(func():
				if is_inside_tree():
					_spawn_enemy(t, lvl, home, camp)
			)
		else:
			_spawn_enemy(t, lvl, home, camp)
	)


func damage_player(amount: float, _source: Node) -> void:
	if player == null or player.dead:
		return
	if Game.invulnerable:
		return
	Sound.play("shield_hit" if Game.shield > 0.0 else "player_hurt", -5.0, 0.08, "SFX", 0.08)
	if Game.take_damage(amount):
		pass # player_died signal handles it
	floating_text(player.global_position + player.global_basis.y * 2.4, "-%d" % int(amount), Color("ff5d5d"), false)


func reset_aggro() -> void:
	for e in enemies:
		if e.is_alive() and e.state == "chase":
			e._leash()


func spawn_enemy_bolt(from: Vector3, to: Vector3, dmg: float, color: Color) -> void:
	EnemyBolt.new().setup(self, from, to, dmg, color)


func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	CombatFx.tracer(self, from, to, color)


func explosion(pos: Vector3, color: Color, size: float) -> void:
	CombatFx.explosion(self, pos, color, size)
	shake_near(pos, size * 0.25)


## Shake the camera if something big happens near the player.
func shake_near(pos: Vector3, amount: float) -> void:
	if player:
		var d := pos.distance_to(player.global_position)
		player.shake.add(amount * clampf(1.0 - d / 45.0, 0.0, 1.0))


func shockwave(center: Vector3, radius: float, color: Color) -> void:
	CombatFx.shockwave(self, center, center.normalized(), radius, color)
	shake_near(center, radius * 0.07)


func floating_text(pos: Vector3, text: String, color: Color, big := false) -> void:
	CombatFx.floating_text(self, pos, pos.normalized(), text, color, big)


func enemies_near(pos: Vector3, radius: float) -> Array:
	var out := []
	for e in enemies:
		if e.is_alive() and e.global_position.distance_to(pos) < radius:
			out.append(e)
	return out


# --------------------------------------------------------------------------
# exploration depth: points of interest, surveys, sky, floating islands
# --------------------------------------------------------------------------

func register_interactable(n: Node3D) -> void:
	_interactables.append(n)


func _spawn_pois(outpost_dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 91
	var types := ["monolith", "ruin", "ruin", "crash", "crash", "geode"]
	if not is_home:
		types.append(["ruin", "crash", "geode"][rng.randi() % 3])
	# caves go last so older saves keep their site indices
	types.append("cave")
	if not is_home:
		types.append("cave")
	# volcanoes last of all, so saves from before they existed keep their indices
	# (the first volcano keeps its old slot; two more follow it)
	if biome.get("lava", false):
		types.append_array(["volcano", "volcano", "volcano"])
	var first_cave := true
	var first_volcano := true
	var placed: Array[Vector3] = []
	var safe := outpost_dir if is_home else spawn_dir
	var idx := 0
	for t in types:
		var d := Vector3.ZERO
		for attempt in 200:
			var cand: Vector3
			var near_cave: bool = (t == "cave" and first_cave) or (t == "volcano" and first_volcano)
			if idx == 0 or near_cave:
				# the first site (and first cave) is always within walking distance of the landing
				var b := PlanetGen.align_basis(safe)
				var ang := rng.randf() * TAU
				cand = (safe + (b.x * cos(ang) + b.z * sin(ang)) * (rng.randf_range(45.0, 80.0) if near_cave else rng.randf_range(70.0, 120.0)) / gen.radius).normalized()
			else:
				cand = _random_dir(rng)
			if not _is_placeable(cand, 0.12, safe, 45.0):
				continue
			var ok := true
			for q in placed:
				if gen.surface_point(q).distance_to(gen.surface_point(cand)) < 80.0:
					ok = false
					break
			if ok:
				d = cand
				break
		if d == Vector3.ZERO:
			continue
		placed.append(d)
		if t == "cave":
			first_cave = false
		if t == "volcano":
			first_volcano = false
		var p := Poi.new()
		add_child(p)
		p.setup(self, t, idx, d)
		pois.append(p)
		if t == "ruin" and not p.is_looted():
			var guards := 2 if is_home else 3
			for g in guards:
				_spawn_enemy(["scrapper", "sentinel"][g % 2], danger_level + 1, _near(d, rng, 9.0), 500 + idx)
		if t == "geode":
			_spawn_hotspot(d, idx, rng)
		idx += 1


## Crystal geodes mark a cluster of the planet's rarest resource.
func _spawn_hotspot(d: Vector3, idx: int, rng: RandomNumberGenerator) -> void:
	var rarest := ""
	var best_req := -1
	for n in biome.nodes:
		if Db.NODES[n].req > best_req:
			best_req = Db.NODES[n].req
			rarest = n
	for i in 7:
		var nd := _near(d, rng, 14.0)
		if gen.surface_point(nd).distance_to(gen.surface_point(d)) < 5.0:
			continue
		_add_node(rarest, 20000 + idx * 20 + i, nd, rng.randf() * TAU)


func survey_status() -> Dictionary:
	var species := {}
	for c in _critters:
		species[c.species_key] = true
	for t in _flora_points:
		if t != "prop_boulder" and _flora_points[t].size() > 0:
			species["%s:flora:%s" % [planet.key, t]] = true
	var found_species := 0
	for k in species:
		if Game.scanned.has(k):
			found_species += 1
	var found_sites := 0
	for p in pois:
		if p.is_discovered():
			found_sites += 1
	Game.note_world_species(planet.key, planet.name, planet.biome, species.size())
	return {"species": found_species, "species_total": species.size(), "sites": found_sites, "sites_total": pois.size(),
		"done": Game.surveyed.has(planet.key)}


func check_survey() -> void:
	var st := survey_status()
	hud.refresh_survey(st)
	if not st.done and st.species >= st.species_total and st.sites >= st.sites_total:
		Game.complete_survey(planet.key, planet.name)
		hud.refresh_survey(survey_status())


## Compass markers for the HUD: revealed sites, the outpost, north.
func compass_markers() -> Array:
	var out := []
	for p in pois:
		if p.revealed or p.is_discovered() or p.type == "volcano":
			out.append({"pos": p.global_position, "color": p.def.color, "label": p.def.name, "done": p.is_looted() or p.type == "geode"})
	if town:
		out.append({"pos": town.centre, "color": Color("ffd98a"), "label": planet.town.name, "done": false})
	var q := quest_target()
	if not q.is_empty():
		out.append({"pos": q.pos, "color": Color("ffd23f"), "label": "★ " + q.label, "done": false, "quest": true})
	return out


## Other worlds of this system hang in the sky, and this world's rings arc overhead.
func _build_sky_bodies() -> void:
	_sky_pivot = Node3D.new()
	add_child(_sky_pivot)
	var star: Dictionary = Galaxy.star(Game.star_index)
	var here := _orbit_pos(planet)
	# rotate the sky so the real star direction lines up with the day-cycle sun
	var to_star := (-here).normalized()
	_sky_offset = atan2(to_star.x, to_star.z) - atan2(0.93, 0.0)
	var sky_r := 3200.0
	for o in star.planets:
		if o.index == planet.index:
			continue
		var rel: Vector3 = _orbit_pos(o) - here
		var dist := rel.length()
		var size := clampf(o.radius / dist * sky_r * 5.0, 30.0, 260.0)
		var b: Dictionary = Db.BIOMES[o.biome]
		# the sister world's real terrain, at low resolution
		var og := PlanetGen.new(o)
		var body := MeshInstance3D.new()
		body.mesh = og.build_mesh(14, size / og.radius)
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/sky_body.gdshader")
		body.material_override = m
		if og.has_liquid():
			var sea := MeshInstance3D.new()
			var ss := SphereMesh.new()
			ss.radius = og.sea_radius() * size / og.radius
			ss.height = ss.radius * 2.0
			ss.radial_segments = 32
			ss.rings = 16
			sea.mesh = ss
			var sm2 := ShaderMaterial.new()
			sm2.shader = load("res://shaders/sky_body.gdshader")
			sm2.set_shader_parameter("flat_color", b.water)
			sm2.set_shader_parameter("use_flat", true)
			sea.material_override = sm2
			body.add_child(sea)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sky_pivot.add_child(body)
		body.position = rel.normalized() * sky_r
		sky_bodies.append(body)
		var rim := MeshInstance3D.new()
		var rm := SphereMesh.new()
		rm.radius = size * 1.12
		rm.height = rm.radius * 2.0
		rim.mesh = rm
		var rmat := ShaderMaterial.new()
		rmat.shader = load("res://shaders/atmo_rim.gdshader")
		rmat.set_shader_parameter("color", b.atmo)
		rim.material_override = rmat
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(rim)
	if planet.rings:
		var ring := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(gen.radius * 9.0, gen.radius * 9.0)
		pm.subdivide_width = 0
		ring.mesh = pm
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, fog_disabled;
uniform vec3 col : source_color;
float h(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float band = step(0.5, d) * step(d, 0.98);
	float lane = floor(d * 90.0);
	if (band * step(0.3, h(lane + 7.0)) < 0.5) discard;
	ALBEDO = col * (0.55 + 0.45 * h(lane));
	EMISSION = col * 0.15;
	ROUGHNESS = 0.9;
}
"""
		var rmat2 := ShaderMaterial.new()
		rmat2.shader = sh
		rmat2.set_shader_parameter("col", biome.colors.beach)
		ring.material_override = rmat2
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.extra_cull_margin = 16384.0
		add_child(ring)
		ring.rotation = Vector3(planet.tilt + 0.35, 0, planet.tilt * 0.5)
		ring_node = ring


func _orbit_pos(p: Dictionary) -> Vector3:
	return Galaxy.orbit_pos(p, Game.play_time)


## Spore-style floating rock islands on the stranger worlds, reachable by jetpack.
func _build_floating_islands() -> void:
	if not planet.biome in ["prism", "bloom", "verdant", "abyss"]:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed + 131
	var count: int = {"verdant": 10, "abyss": 40}.get(planet.biome, 22)
	var rocks := []
	var tops := []
	var body := StaticBody3D.new()
	add_child(body)
	for i in count:
		var d := _random_dir(rng)
		var alt := rng.randf_range(16.0, 34.0)
		var ground := gen.surface_radius(d)
		if gen.has_liquid():
			ground = maxf(ground, gen.sea_radius())
		var pos := d * (ground + alt)
		var s := rng.randf_range(1.6, 3.2)
		var b := PlanetGen.align_basis(d, rng.randf() * TAU)
		rocks.append(Transform3D(b.scaled(Vector3(s * 1.4, s * 0.8, s * 1.4)), pos))
		tops.append(Transform3D(b.scaled(Vector3.ONE * s * 0.45), pos + d * s * 0.9))
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = s * 2.2
		cyl.height = s * 1.2
		cs.shape = cyl
		cs.transform = Transform3D(b, pos + d * s * 0.3)
		body.add_child(cs)
	ModelUtil.multimesh(self, "res://assets/models/prop_boulder.glb", rocks)
	var top_model: String = {"prism": "res://assets/models/res_crystal.glb", "bloom": "res://assets/models/flora_mushroom.glb", "verdant": "res://assets/models/flora_tree_round.glb", "abyss": "res://assets/models/flora_tree_disc.glb"}[planet.biome]
	ModelUtil.multimesh(self, top_model, tops, "Foliage", flora_tint)



# --------------------------------------------------------------------------
# towns
# --------------------------------------------------------------------------

func _in_town_zone(d: Vector3, r: float) -> bool:
	return gen.surface_point(d).distance_to(gen.surface_point(town_dir)) < r


func town_planet() -> Dictionary:
	return planet


func _update_town(pos: Vector3) -> void:
	if town == null:
		return
	var d := pos.distance_to(town.centre)
	if not _in_town and d < 38.0:
		_in_town = true
		refresh_music(2.0)
		if not Game.visited_towns.has(planet.key):
			hud.show_location_banner(planet.town.name, "Trade hub  ·  Merchant, Trainer, Bounty Board")
		else:
			Game.notify.emit("Entering %s" % planet.town.name, Color("ffd98a"))
		Game.record_town_visit(planet.key)
	elif _in_town and d > 55.0:
		_in_town = false
		refresh_music(3.0)



# --------------------------------------------------------------------------
# quest guidance
# --------------------------------------------------------------------------

var _qt_cache := {}
var _qt_t := 0.0

## Where the current quest wants you to go on this planet (or {}).
func quest_target() -> Dictionary:
	_qt_t -= get_process_delta_time()
	if _qt_t > 0.0:
		return _qt_cache
	_qt_t = 0.5
	_qt_cache = _compute_quest_target()
	return _qt_cache


func _nearest(nodes: Array, pos: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in nodes:
		if is_instance_valid(n):
			var d: float = n.global_position.distance_to(pos)
			if d < bd:
				bd = d
				best = n
	return best


func _nearest_vent(pos: Vector3) -> Node3D:
	return _nearest(pois.filter(func(p): return p.type == "volcano"), pos)


func _compute_quest_target() -> Dictionary:
	if player == null:
		return {}
	var q := Game.current_quest()
	if q.is_empty():
		return {}
	var pos := player.global_position
	if not Game.quest_accepted:
		if Game.quest_index == 0 and is_home:
			for n in _interactables:
				if n is ArchivistNpc:
					return {"pos": n.global_position, "label": "The Archivist"}
		return {}
	var o: Dictionary = q.obj
	if o.type == "collect" and o.item in ["fire_opal", "obsidian", "core_ember"]:
		var v := _nearest_vent(pos)
		return {"pos": v.global_position, "label": "Volcanic Vent"} if v else {}
	match o.type:
		"collect":
			var hits := _nodes.filter(func(n): return is_instance_valid(n) and n.def.item == o.item)
			var n := _nearest(hits, pos)
			if n:
				return {"pos": n.global_position, "label": n.def.name}
		"scan":
			var c := _nearest(_critters, pos)
			if c:
				return {"pos": c.global_position, "label": "Creatures to scan"}
		"dig", "chamber":
			var caves := pois.filter(func(p): return p.type == "cave")
			var cv := _nearest(caves, pos)
			if cv:
				return {"pos": cv.global_position, "label": "Cave Mouth"}
		"kill", "kill_elite":
			var foes := enemies.filter(func(e): return e.is_alive() and (e.elite or o.type == "kill"))
			var e := _nearest(foes, pos)
			if e:
				return {"pos": e.global_position, "label": "Rogue drones"}
		"sell", "train":
			if town:
				for n in town.npcs:
					if n.role == ("merchant" if o.type == "sell" else "trainer"):
						return {"pos": n.global_position, "label": n.npc_name}
	return {}



# --------------------------------------------------------------------------
# atmosphere post-process
# --------------------------------------------------------------------------

func _update_post(up: Vector3, day: float) -> void:
	if player == null or player.camera == null:
		return
	var cfg: Dictionary = POST.get(planet.biome, POST.verdant)
	if _post == null:
		_post = CanvasLayer.new()
		_post.layer = 1
		add_child(_post)
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_post_mat = ShaderMaterial.new()
		_post_mat.shader = preload("res://shaders/atmo_post.gdshader")
		r.material = _post_mat
		_post.add_child(r)
	# the underwater pass takes over below the surface
	_post.visible = underwater < 0.5
	if not _post.visible:
		return
	var cam: Camera3D = player.camera
	var vs := get_viewport().get_visible_rect().size
	_post_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	# where the horizon sits on screen: a point far out along the level view direction
	var fwd := -cam.global_basis.z
	var flat := (fwd - up * fwd.dot(up)).normalized()
	var hp := cam.global_position + flat * 400.0 - up * 12.0
	var hy := 0.5
	if not cam.is_position_behind(hp):
		hy = clampf(cam.unproject_position(hp).y / vs.y, -0.2, 1.2)
	_post_mat.set_shader_parameter("horizon_y", hy)
	var storm := weather.storm if weather else 0.0
	# heat haze comes with the daytime heat (volcanic worlds stay hot all night)
	var heat: float = cfg.shimmer * (1.0 if cfg.get("hot_night", false) else smoothstep(0.1, 0.6, day))
	_post_mat.set_shader_parameter("shimmer", heat)
	# sun shafts: medium+ quality, strongest when the sun is low or the air is thick
	var sun_p := cam.global_position + sun_dir * 2000.0
	var vis := 0.0
	var suv := Vector2(0.5, 0.2)
	if Sound.gfx_quality >= 1 and not cam.is_position_behind(sun_p):
		suv = cam.unproject_position(sun_p) / vs
		var elev := up.dot(sun_dir)
		vis = smoothstep(-0.08, 0.05, elev) * (1.0 - smoothstep(-0.5, 1.2, absf(suv.x - 0.5) + absf(suv.y - 0.5) - 0.5))
	var low_sun := 1.0 - smoothstep(0.15, 0.6, up.dot(sun_dir))
	_post_mat.set_shader_parameter("sun_uv", suv)
	_post_mat.set_shader_parameter("sun_vis", vis)
	_post_mat.set_shader_parameter("rays", float(cfg.rays) * (0.5 + 0.5 * low_sun + 0.3 * storm))
	_post_mat.set_shader_parameter("ray_color", (sun.light_color as Color).lerp(biome.horizon, 0.4))
	# frost on glacial worlds at night and in blizzards
	var fr := 0.0
	if cfg.get("frost", false):
		fr = maxf(1.0 - day, storm) * 0.8
	_post_mat.set_shader_parameter("frost", fr)
	_post_mat.set_shader_parameter("grade", cfg.grade)
	_post_mat.set_shader_parameter("grade_amt", cfg.grade_amt)



## One place decides the planet's music: the sea when the camera is under,
## the town theme inside a trade hub, otherwise the world's own theme.
func refresh_music(fade := 2.5) -> void:
	if underwater > 0.5 and not biome.get("lava", false):
		Sound.play_music("ocean", fade)
	elif _in_town:
		Sound.play_music("town", fade)
	else:
		Sound.play_music(Sound.music_for_biome(planet.biome), fade)



# --------------------------------------------------------------------------
# art style (Classic / Illustrative / Storybook)
# --------------------------------------------------------------------------

func _apply_art_style() -> void:
	if not is_inside_tree():
		return
	ArtStyle.apply(self)
	ArtStyle.apply_env(env, player.camera if player else null)


func _on_node_added(n: Node) -> void:
	# things spawned later (drops, effects, enemies) pick up the current style
	if Sound.art_style > 0 and (n is GeometryInstance3D) and is_ancestor_of(n):
		ArtStyle.apply_node.call_deferred(n)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
