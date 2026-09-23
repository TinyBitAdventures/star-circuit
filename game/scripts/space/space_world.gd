extends Node3D
## A star system in flight mode: the star, orbiting planets (same generator as
## the surface, at orbital scale), the flying robot and the HUD.

const SPACE_SCALE := 0.12
const PLANET_RES := 36

var star: Dictionary
var hud: CanvasLayer
var player: Node3D
var planets: Array = [] # [{data, node, radius}]
var env: Environment
var asteroids: Array[Asteroid] = []
var space_enemies: Array[SpaceEnemy] = []
var danger := 1
var station: OrbitalStation
var _ambush_t := 0.0
var _combat_t := 0.0
var belt: AsteroidBelt


func _ready() -> void:
	star = Galaxy.star(Game.star_index)
	_build_environment()
	_build_star()
	for p in star.planets:
		_build_planet(p)
	belt = AsteroidBelt.new()
	add_child(belt)
	belt.build(self, star.belt)
	danger = Game.space_level(Game.star_index)
	# trade station parked on the first world's orbit, a little ahead of it
	var p0: Dictionary = star.planets[0]
	var sa: float = p0.angle + 0.22
	station = OrbitalStation.new()
	add_child(station)
	station.build(self, star.station, Vector3(cos(sa) * p0.orbit, 25.0, sin(sa) * p0.orbit))
	_spawn_patrols()
	_ambush_t = randf_range(100.0, 200.0)

	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "space"
	add_child(hud)

	player = preload("res://scripts/space/space_player.gd").new()
	player.world = self
	add_child(player)
	_place_player()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sound.loop_stop("ambience", 1.5)
	Sound.loop_stop("harvest", 0.1)
	Sound.loop_stop("jet", 0.1)
	Sound.play_music("space")
	Sound.loop_start("engine", "thruster_loop", -14.0)
	hud.show_location_banner(star.name, "Class %s star  ·  %d worlds" % [star.cls, star.planets.size()])


func _place_player() -> void:
	if Game.arrived_by_warp or Game.land_dir == Vector3.ZERO:
		# fresh warp arrival: drop in near the first world, looking at it
		Game.arrived_by_warp = false
		var pl: Dictionary = planets[0]
		var p: Vector3 = pl.node.global_position
		var pos: Vector3 = p + (p.normalized() + Vector3(0, 0.25, 0)).normalized() * pl.radius * 5.0
		player.global_position = pos
		player.look_at(p, Vector3.UP)
	else:
		# coming up from a planet: appear above the take-off point
		var pl: Dictionary = planets[clampi(Game.planet_index, 0, planets.size() - 1)]
		var dir: Vector3 = (pl.node.global_basis * Game.land_dir).normalized()
		var pos: Vector3 = pl.node.global_position + dir * pl.radius * 2.6
		player.global_position = pos
		player.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	player.snap_camera()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/space_sky.gdshader")
	sky_mat.set_shader_parameter("seed", float(star.seed % 1000))
	sky_mat.set_shader_parameter("nebula_a", Color.from_hsv(fposmod(float(star.seed % 360) / 360.0, 1.0), 0.6, 0.55))
	sky_mat.set_shader_parameter("nebula_b", Color.from_hsv(fposmod(float(star.seed % 360) / 360.0 + 0.4, 1.0), 0.7, 0.5))
	sky_mat.set_shader_parameter("nebula_strength", 0.8)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0
	UiKit.polish_environment(env, false)
	we.environment = env
	add_child(we)
	UiKit.add_vignette(self, 0.4)


func _build_star() -> void:
	var col: Color = star.color
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 70.0
	sm.height = 140.0
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/star.gdshader")
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("intensity", 5.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var corona := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 120.0
	cm.height = 240.0
	corona.mesh = cm
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://shaders/atmo_rim.gdshader")
	cmat.set_shader_parameter("color", col)
	cmat.set_shader_parameter("power", 1.6)
	cmat.set_shader_parameter("strength", 2.5)
	corona.material_override = cmat
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(corona)
	var light := OmniLight3D.new()
	light.light_color = col.lerp(Color.WHITE, 0.5)
	light.omni_range = 6000.0
	light.omni_attenuation = 0.0
	light.light_energy = 1.6
	add_child(light)


func _build_planet(p: Dictionary) -> void:
	var gen := PlanetGen.new(p)
	var root := Node3D.new()
	add_child(root)
	var a: float = p.angle
	var orbit: float = p.orbit
	root.position = Vector3(cos(a) * orbit, sin(a * 3.0) * 30.0, sin(a) * orbit)
	var r: float = p.radius * SPACE_SCALE
	var mi := MeshInstance3D.new()
	mi.mesh = gen.build_mesh(PLANET_RES, SPACE_SCALE)
	mi.material_override = gen.terrain_material(SPACE_SCALE)
	root.add_child(mi)
	var biome: Dictionary = Db.BIOMES[p.biome]
	if gen.has_liquid():
		var w := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = gen.sea_radius() * SPACE_SCALE
		sm.height = sm.radius * 2.0
		w.mesh = sm
		var wm := StandardMaterial3D.new()
		var wc: Color = biome.water
		wm.albedo_color = Color(wc.r, wc.g, wc.b, 1.0)
		wm.roughness = 0.15
		wm.metallic_specular = 0.8
		if biome.get("lava", false):
			wm.emission_enabled = true
			wm.emission = Color(wc.r, wc.g, wc.b)
			wm.emission_energy_multiplier = 2.0
		w.material_override = wm
		root.add_child(w)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = r * 1.14
	am.height = am.radius * 2.0
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://shaders/atmo_rim.gdshader")
	amat.set_shader_parameter("color", biome.atmo)
	atmo.material_override = amat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(atmo)
	var clouds := gen.cloud_shell(gen.radius * SPACE_SCALE * 1.06, 48)
	(clouds.material_override as ShaderMaterial).set_shader_parameter("sun_dir", (-root.position).normalized())
	root.add_child(clouds)
	if p.rings:
		root.add_child(_make_rings(r, biome.colors.beach))
	root.rotation = Vector3(p.tilt, 0, p.tilt * 0.5)

	var label := Label3D.new()
	label.text = "%s\n%s" % [p.name, biome.name]
	if not p.town.is_empty():
		label.text += "\n⌂ %s" % p.town.name
	label.font = UiKit.body_font()
	label.font_size = 26
	label.outline_size = 8
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 1, 0.85)
	label.position = Vector3(0, r * 1.5, 0)
	root.add_child(label)
	planets.append({"data": p, "node": root, "radius": r, "label": label, "gen": gen})


func _make_rings(r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 5.0, r * 5.0)
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec3 col : source_color;
float h(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	vec2 c = UV - 0.5;
	float d = length(c) * 2.0;
	float band = smoothstep(0.5, 0.52, d) * (1.0 - smoothstep(0.96, 1.0, d));
	float lane = floor(d * 60.0);
	float stripes = 0.35 + 0.65 * h(lane);
	// dithered coverage: opaque pass, but gaps between the ringlets
	float keep = band * step(0.3, h(lane + 7.0));
	if (keep < 0.5) discard;
	ALBEDO = col * (0.55 + 0.45 * stripes);
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", col)
	mi.material_override = m
	return mi


func nearest_planet(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for p in planets:
		var d: float = pos.distance_to(p.node.global_position) - p.radius
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		return {}
	return {"planet": best, "dist": best_d}


## Land straight on a planet's trade hub pad.
func land_at_town(p: Dictionary) -> void:
	var td: Vector3 = p.gen.town_dir()
	Game.land_dir = td
	Game.space_return_pos = p.node.global_position + p.node.global_basis * td * p.radius * 2.6
	Sound.play("atmo_entry", -2.0, 0.0)
	Sound.loop_stop("engine", 1.0)
	Game.big_notify.emit("DOCKING", "%s  ·  %s" % [p.data.town.name, p.data.name], Color("ffd98a"))
	Game.go_to_planet(Game.star_index, p.data.index)


func land(p: Dictionary, from_pos: Vector3) -> void:
	var dir: Vector3 = (from_pos - p.node.global_position).normalized()
	# undo the planet's display tilt so the landing point matches the surface
	dir = p.node.global_basis.inverse() * dir
	Game.land_dir = dir.normalized()
	Game.space_return_pos = from_pos
	Sound.play("atmo_entry", -2.0, 0.0)
	Sound.loop_stop("engine", 1.0)
	Game.big_notify.emit("ENTERING ATMOSPHERE", p.data.name, Db.BIOMES[p.data.biome].atmo)
	Game.go_to_planet(Game.star_index, p.data.index)



# --------------------------------------------------------------------------
# space mining
# --------------------------------------------------------------------------

func spawn_asteroid(t: String, size: float, pos: Vector3, gen: int) -> Asteroid:
	var a := Asteroid.new()
	add_child(a)
	a.setup(self, t, size, pos, gen)
	asteroids.append(a)
	return a


func on_asteroid_broken(a: Asteroid) -> void:
	asteroids.erase(a)


func spawn_shards(pos: Vector3, item: String, qty: int, size: float) -> void:
	# split the yield over a few shards so the break feels generous
	var pieces := clampi(qty, 1, 4)
	var left := qty
	for i in pieces:
		var q := left / (pieces - i)
		left -= q
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		OreShard.new().setup(self, item, q, pos + dir * size * 0.5, dir * randf_range(4.0, 9.0))


func scan_space(pos: Vector3, radius: float) -> void:
	var near := []
	for a in asteroids:
		if is_instance_valid(a) and a.global_position.distance_to(pos) < radius:
			near.append(a)
	near.sort_custom(func(x, y): return x.global_position.distance_to(pos) < y.global_position.distance_to(pos))
	var n := near.size()
	for i in mini(18, n):
		near[i].reveal(25.0)
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
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.3)
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos
	var t := create_tween().set_parallel()
	t.tween_property(mi, "scale", Vector3.ONE * radius, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(mat, "albedo_color:a", 0.0, 1.4)
	t.chain().tween_callback(mi.queue_free)
	Game.notify.emit("Scan: %d asteroids in range" % n if n > 0 else "Scan: no asteroids nearby. The belt glows on your radar.", Color("5ff7ff"))



# --------------------------------------------------------------------------
# space combat
# --------------------------------------------------------------------------

func _spawn_patrols() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(star.seed) + 404
	var home := Game.star_index == 0
	var groups := 1 if home else rng.randi_range(2, 3)
	var br: float = star.belt.radius
	for g in groups:
		var a := rng.randf() * TAU
		var centre := Vector3(cos(a) * br, rng.randf_range(-20, 20), sin(a) * br)
		if centre.distance_to(station.global_position) < 380.0:
			centre = Vector3(cos(a + PI) * br, centre.y, sin(a + PI) * br)
		var wing: Array = ["raider", "raider"] if home else [["raider", "raider", "swarmer", "swarmer"], ["gunship", "raider", "raider"], ["swarmer", "swarmer", "swarmer", "raider"]][rng.randi() % 3]
		for i in wing.size():
			_spawn_pirate(wing[i], danger + rng.randi_range(0, 1), centre + Vector3(rng.randf_range(-30, 30), rng.randf_range(-10, 10), rng.randf_range(-30, 30)), centre)
	# flagships guard systems far from home
	if Galaxy.distance(0, Game.star_index) > 30.0 and rng.randf() < 0.6:
		var a2 := rng.randf() * TAU
		var fc := Vector3(cos(a2) * br * 1.3, 40.0, sin(a2) * br * 1.3)
		_spawn_pirate("marauder", danger + 2, fc, fc)
		for i in 3:
			_spawn_pirate("raider", danger, fc + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40)), fc)


func _spawn_pirate(t: String, lvl: int, pos: Vector3, home_pos: Vector3) -> SpaceEnemy:
	var e := SpaceEnemy.new()
	add_child(e)
	e.setup(self, t, lvl, pos, home_pos)
	space_enemies.append(e)
	return e


func on_space_enemy_killed(e: SpaceEnemy) -> void:
	space_enemies.erase(e)


func spawn_space_bolt(from: Vector3, dir: Vector3, speed: float, dmg: float, color: Color, missile: bool, size := 0.45, target: SpaceEnemy = null) -> void:
	var b := SpaceBolt.new()
	b.setup(self, from, dir, speed, dmg, color, missile, size)
	b.homing = target


func damage_player(amount: float, _source: Node) -> void:
	if player == null or player.dead or Game.invulnerable:
		return
	Sound.play("shield_hit" if Game.shield > 0.0 else "player_hurt", -5.0, 0.08, "SFX", 0.08)
	CombatFx.floating_text(self, player.global_position + Vector3.UP * 3.0, Vector3.UP, "-%d" % int(amount), Color("ff5d5d"))
	Game.take_damage(amount)


func reset_aggro() -> void:
	for e in space_enemies:
		if e.is_alive() and e.state == "attack":
			e.state = "return"


## Pirates warp in behind you now and then, more often far from home.
func _ambush() -> void:
	if player == null or player.dead:
		return
	var home := Game.star_index == 0
	if home and Game.quest_index < _quest_index("pirates"):
		return # keep the home system calm until the story introduces pirates
	var back: Vector3 = player.global_basis.z
	var centre: Vector3 = player.global_position + back * 320.0 + Vector3(0, randf_range(-40, 40), 0)
	var wave: Array = ["raider", "swarmer", "swarmer"] if home else [["raider", "raider", "swarmer", "swarmer"], ["gunship", "raider", "raider"], ["raider", "raider", "raider"]][randi() % 3]
	for t in wave:
		var e := _spawn_pirate(t, danger, centre + Vector3(randf_range(-25, 25), randf_range(-15, 15), randf_range(-25, 25)), centre)
		e.aggro()
	Game.big_notify.emit("PIRATE AMBUSH", "%d contacts dropping out of warp behind you" % wave.size(), Color("ff4d4d"))
	Sound.play("klaxon", -2.0, 0.0, "UI")


func _quest_index(id: String) -> int:
	for i in Db.QUESTS.size():
		if Db.QUESTS[i].id == id:
			return i
	return 999


func _physics_process(delta: float) -> void:
	_ambush_t -= delta
	if _ambush_t <= 0.0:
		_ambush_t = randf_range(150.0, 260.0) if Game.star_index == 0 else randf_range(90.0, 180.0)
		_ambush()
	_combat_t -= delta
	if _combat_t <= 0.0:
		_combat_t = 0.5
		for e in space_enemies:
			if e.is_alive() and e.state == "attack":
				Sound.set_combat(true)
				break


## On-screen and off-screen threat markers for the HUD.
func threat_markers(cam: Camera3D) -> Array:
	var out := []
	var vp := cam.get_viewport().get_visible_rect().size
	for e in space_enemies:
		if not e.is_alive():
			continue
		var d := cam.global_position.distance_to(e.global_position)
		if d > 900.0 or (e.state != "attack" and d > 450.0):
			continue
		var behind := cam.is_position_behind(e.global_position)
		var sp := cam.unproject_position(e.global_position)
		var on := not behind and Rect2(Vector2.ZERO, vp).has_point(sp)
		if behind:
			sp = vp - sp # mirror so the arrow points the right way
		out.append({"pos": sp, "on": on, "elite": e.elite, "attacking": e.state == "attack", "dist": d})
	return out
