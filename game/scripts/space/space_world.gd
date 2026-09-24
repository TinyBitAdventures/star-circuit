extends Node3D
## A star system in flight mode: the star, orbiting planets (same generator as
## the surface, at orbital scale), the flying robot and the HUD.

const SPACE_SCALE := 0.12
const PLANET_RES := 36

var star: Dictionary
var hud: CanvasLayer
var player: Node3D
var net_view: NetView # other players flying in this system
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
	station.build(self, star.station, _station_pos())
	_build_extras()
	_spawn_patrols()
	_ambush_t = randf_range(100.0, 200.0)

	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "space"
	add_child(hud)

	player = preload("res://scripts/space/space_player.gd").new()
	player.world = self
	add_child(player)
	net_view = NetView.new()
	add_child(net_view)
	net_view.setup(self, "space")
	_place_player()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sound.loop_stop("ambience", 1.5)
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(self):
			Game.tip("first_space", "Steer with the mouse, thrust with %s and boost with %s. Fly close to a planet and press %s to land. %s opens the system map; warp to other stars from the galaxy map." % [Game.key("move_forward"), Game.key("sprint"), Game.key("interact"), Game.key("map")])
	)
	Sound.loop_stop("harvest", 0.1)
	Sound.loop_stop("jet", 0.1)
	Sound.play_music("space")
	Sound.loop_start("engine", "thruster_loop", -14.0)
	hud.show_location_banner(star.name, "Class %s star  ·  %d worlds" % [star.cls, star.planets.size()])


func _place_player() -> void:
	if Game.space_spawn != Vector3.ZERO:
		# back from boarding a derelict
		player.global_position = Game.space_spawn
		Game.space_spawn = Vector3.ZERO
		player.look_at(Vector3.ZERO, Vector3.UP)
		player.snap_camera()
		return
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
	root.position = Galaxy.orbit_pos(p, Game.play_time)
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
	Game.arriving_from_space = true
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
	Game.arriving_from_space = true
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
	if Game.relay_lit(Game.star_index) and not home:
		groups = 1 # a lit relay keeps most pirates away
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
	if Game.relay_lit(Game.star_index) and randf() < 0.75:
		return # lit systems see far fewer raids
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
	var wp := waypoint_pos()
	if wp != Vector3.INF:
		var behind2 := cam.is_position_behind(wp)
		var sp2 := cam.unproject_position(wp)
		var on2 := not behind2 and Rect2(Vector2.ZERO, vp).has_point(sp2)
		if behind2:
			sp2 = vp - sp2
		var wname: String = Game.waypoint.get("name", "Waypoint") if not Game.waypoint.is_empty() and int(Game.waypoint.get("star", -1)) == Game.star_index else quest_space_target().get("name", "Quest")
		out.append({"pos": sp2, "on": on2, "waypoint": true, "dist": cam.global_position.distance_to(wp), "name": wname, "elite": false, "attacking": false})
	return out


# --------------------------------------------------------------------------
# system extras: gas giant, derelicts, relay, the Heart, flares, orbits
# --------------------------------------------------------------------------

var giant: Node3D
var giant_r := 0.0
var derelicts: Array = [] # {node, idx}
var relay: Node3D
var relay_guards: Array[SpaceEnemy] = []
var heart: SpaceEnemy
var pylons: Array[SpaceEnemy] = []
var _relay_core: Node3D
var _skim_t := 0.0
var _flare_t := 0.0
var _flare_state := ""
var _flare_left := 0.0
var _heart_wave := 0.0


func _station_pos() -> Vector3:
	var p0: Dictionary = star.planets[0]
	var pp := Galaxy.orbit_pos(p0, Game.play_time)
	var off := pp.normalized().cross(Vector3.UP).normalized() * 95.0
	return pp + off + Vector3(0, 25, 0)


func _build_extras() -> void:
	_flare_t = randf_range(150.0, 260.0)
	if star.has("giant"):
		_build_giant(star.giant)
	for i in star.derelicts.size():
		_build_derelict(star.derelicts[i], i)
	_build_relay(star.relay)
	if star.get("legendary", "") == "forge" and not Game.heart_defeated:
		_build_heart()


func _build_giant(g: Dictionary) -> void:
	giant = Node3D.new()
	add_child(giant)
	var a: float = g.angle
	giant.position = Vector3(cos(a) * g.orbit, 40.0, sin(a) * g.orbit)
	giant_r = g.radius
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = giant_r
	sm.height = giant_r * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/gas_giant.gdshader")
	var h: float = g.hue
	m.set_shader_parameter("band_a", Color.from_hsv(h, 0.35, 0.95))
	m.set_shader_parameter("band_b", Color.from_hsv(fposmod(h + 0.05, 1.0), 0.55, 0.6))
	m.set_shader_parameter("storm", Color.from_hsv(fposmod(h - 0.05, 1.0), 0.7, 0.9))
	m.set_shader_parameter("seed", h * 10.0)
	mi.material_override = m
	giant.add_child(mi)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = giant_r * 1.08
	am.height = am.radius * 2.0
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://shaders/atmo_rim.gdshader")
	amat.set_shader_parameter("color", Color.from_hsv(h, 0.4, 1.0))
	atmo.material_override = amat
	giant.add_child(atmo)
	if g.rings:
		var ring := _make_rings(giant_r, Color.from_hsv(h, 0.25, 0.85))
		ring.scale = Vector3.ONE * 1.1
		giant.add_child(ring)
	giant.rotation = Vector3(0.3, 0, 0.15)
	_label(giant, "%s\nGas giant  ·  skim the upper atmosphere for fuel" % g.name, giant_r * 1.3, Color("ffd9a8"))


func _build_derelict(d: Dictionary, i: int) -> void:
	var n := Node3D.new()
	add_child(n)
	var a: float = d.angle
	n.position = Vector3(cos(a) * d.orbit, d.height, sin(a) * d.orbit)
	var m := ModelUtil.instance("res://assets/models/derelict_ship.glb")
	n.add_child(m)
	n.rotation = Vector3(0.4, a, 0.9)
	var looted: bool = Game.boarded.has("derelict:%d:%d" % [Game.star_index, i])
	_label(n, "Derelict%s" % ("  (salvaged)" if looted else "\nPress E to board"), 30.0, Color("ff9f43"))
	var l := OmniLight3D.new()
	l.light_color = Color("ff9f43")
	l.omni_range = 60.0
	l.light_energy = 0.8
	n.add_child(l)
	derelicts.append({"node": n, "idx": i})


func _build_relay(r: Dictionary) -> void:
	relay = Node3D.new()
	add_child(relay)
	var a: float = r.angle
	relay.position = Vector3(cos(a) * r.orbit, 60.0, sin(a) * r.orbit)
	var m := ModelUtil.instance("res://assets/models/relay_beacon.glb")
	relay.add_child(m)
	_relay_core = m.find_child("Core", true, false)
	_label(relay, "", 34.0, Color("5ff7ff"))
	var lit := Game.relay_lit(Game.star_index)
	_set_relay_look(lit)
	if not lit:
		for k in 3 + (1 if danger > 6 else 0):
			var e := _spawn_pirate(["raider", "raider", "gunship", "raider"][k], danger + 1, relay.position + Vector3(randf_range(-60, 60), randf_range(-20, 20), randf_range(-60, 60)), relay.position)
			relay_guards.append(e)


func _set_relay_look(lit: bool) -> void:
	var lbl: Label3D = relay.get_meta("label")
	lbl.text = "Circuit Relay  ·  %s" % ("ONLINE" if lit else "DARK\nNeeds a Resonance Crystal + Relay Coupler")
	lbl.modulate = CombatFx.hdr(Color("5ff7ff") if lit else Color("8a8f99"), 1.5)
	for mi in ModelUtil._mesh_instances(relay):
		var mesh: Mesh = mi.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.emission_enabled:
				var d: StandardMaterial3D = mat.duplicate()
				d.emission_energy_multiplier = 6.0 if lit else 0.15
				d.albedo_color = Color("5ff7ff") if lit else Color("3a3f48")
				mi.set_surface_override_material(i, d)
	if lit and not relay.has_meta("light"):
		var l := OmniLight3D.new()
		l.light_color = Color("5ff7ff")
		l.omni_range = 160.0
		l.light_energy = 2.0
		l.position = Vector3(0, 19, 0)
		relay.add_child(l)
		relay.set_meta("light", l)


func _label(n: Node3D, text: String, y: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UiKit.body_font()
	l.font_size = 26
	l.outline_size = 8
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = CombatFx.hdr(col, 1.5)
	l.top_level = true
	n.add_child(l)
	l.global_position = n.global_position + Vector3.UP * y
	n.set_meta("label", l)
	n.set_meta("label_h", y)


func _build_heart() -> void:
	var c := Vector3(0, 80, -1100)
	heart = _spawn_pirate("heart", danger + 4, c, c)
	for k in 4:
		var a := k * TAU / 4.0
		var p := _spawn_pirate("pylon", danger + 3, c + Vector3(cos(a) * 85.0, sin(a * 2.0) * 20.0, sin(a) * 85.0), c)
		pylons.append(p)
	heart.gate = pylons


func relay_guards_alive() -> int:
	var n := 0
	for e in relay_guards:
		if is_instance_valid(e) and e.is_alive():
			n += 1
	return n


## What the player can press E on right now (derelicts, relay).
func space_interactable(pos: Vector3) -> Dictionary:
	for d in derelicts:
		var n: Node3D = d.node
		if pos.distance_to(n.global_position) < 55.0:
			var key := "derelict:%d:%d" % [Game.star_index, d.idx]
			var idx: int = d.idx
			return {"text": "[E] Board the derelict%s" % ("  (already salvaged)" if Game.boarded.has(key) else ""), "color": Color("ff9f43"),
				"action": func(): Game.enter_derelict(Game.star_index, idx, pos + (pos - n.global_position).normalized() * 20.0)}
	if relay and pos.distance_to(relay.global_position) < 70.0:
		if Game.relay_lit(Game.star_index):
			return {"text": "Circuit Relay online  ·  %d relays lit  ·  fast travel via the galaxy map" % Game.lit_relays.size(), "color": Color("5ff7ff"), "action": Callable()}
		if relay_guards_alive() > 0:
			return {"text": "Relay guard still active (%d)  ·  clear them first" % relay_guards_alive(), "color": Color("ff6b6b"), "action": Callable()}
		var ok := Game.count("resonance_crystal") > 0 and Game.count("relay_coupler") > 0
		return {"text": "[E] Relight the relay  (Resonance Crystal %d/1 · Relay Coupler %d/1)" % [Game.count("resonance_crystal"), Game.count("relay_coupler")],
			"color": Color("5ff7ff") if ok else Color("ffb86b"), "action": _try_light_relay}
	return {}


func _try_light_relay() -> void:
	if Game.light_relay(Game.star_index):
		_set_relay_look(true)
		CombatFx.shockwave(self, relay.global_position, Vector3.UP, 90.0, Color("5ff7ff"))
		CombatFx.explosion(self, relay.global_position + Vector3.UP * 19.0, Color("5ff7ff"), 6.0)
		Sound.play("quest_complete", 0.0, 0.0, "UI")
		Sound.play("warp", -8.0, 0.0)
		if player:
			player.shake.add(0.5)


func _process(delta: float) -> void:
	# planets and moons follow their orbits
	for p in planets:
		p.node.position = Galaxy.orbit_pos(p.data, Game.play_time)
	if station:
		station.position = _station_pos()
	for d in derelicts:
		d.node.rotate_object_local(Vector3(0.3, 1, 0.2).normalized(), delta * 0.02)
	# only nearby points of interest keep their labels up
	if player:
		for n in [relay, giant] + derelicts.map(func(x): return x.node):
			if n and n.has_meta("label"):
				var lb: Label3D = n.get_meta("label")
				lb.global_position = n.global_position + Vector3.UP * _label_h(n)
				lb.visible = player.global_position.distance_to(n.global_position) < (1600.0 if n == giant else 700.0)
	if giant:
		giant.rotate_y(delta * 0.01)
		_skim(delta)
	_flares(delta)
	if heart and is_instance_valid(heart) and heart.is_alive() and heart.state == "attack":
		_heart_wave -= delta
		if _heart_wave <= 0.0:
			_heart_wave = 18.0
			for k in 3:
				var e := _spawn_pirate("swarmer", danger + 2, heart.global_position + Vector3(randf_range(-40, 40), randf_range(-40, 40), randf_range(-40, 40)), heart.global_position)
				e.aggro()


func _skim(delta: float) -> void:
	if player == null or player.dead:
		return
	var d := player.global_position.distance_to(giant.global_position)
	if d < giant_r * 1.02:
		player.global_position = giant.global_position + (player.global_position - giant.global_position).normalized() * giant_r * 1.02
	if d < giant_r * 1.25:
		player.shake.add(delta * 0.6)
		_skim_t -= delta
		if _skim_t <= 0.0:
			_skim_t = 0.7
			Game.add_item("plasma" if randf() < 0.7 else "cryo_ice", 1)
			Game.gain_skill_xp("siphoning", 4.0)
		if d < giant_r * 1.1:
			Game.take_damage(4.0 * delta)
			hud.set_speed_text("Skimming  ·  TOO DEEP: hull heating")
		else:
			hud.set_speed_text("Skimming the upper atmosphere  ·  collecting fuel")


func _flares(delta: float) -> void:
	if player == null:
		return
	_flare_t -= delta
	if _flare_state == "" and _flare_t <= 0.0:
		_flare_state = "warn"
		_flare_left = 8.0
		Game.big_notify.emit("SOLAR FLARE INCOMING", "Shelter behind a planet or near the station  ·  flares also recharge energy", Color("ffb347"))
		Sound.play("klaxon", -6.0, 0.0, "UI")
	elif _flare_state != "":
		_flare_left -= delta
		if _flare_state == "warn" and _flare_left <= 0.0:
			_flare_state = "burn"
			_flare_left = 10.0
		elif _flare_state == "burn":
			hud.damage_flash.color = Color(1.0, 0.6, 0.2, 0.18 + randf() * 0.05)
			Game.add_energy(8.0 * delta)
			if not _sheltered(player.global_position):
				Game.take_damage(3.0 * delta)
			if _flare_left <= 0.0:
				_flare_state = ""
				_flare_t = randf_range(240.0, 380.0)
				hud.damage_flash.color = Color(1, 0.05, 0.05, 0.0)
				Game.notify.emit("The flare passes.", Color("ffd98a"))


## In a planet's shadow (relative to the star) or near the station.
func _sheltered(pos: Vector3) -> bool:
	if station and pos.distance_to(station.global_position) < 250.0:
		return true
	var to_star := -pos.normalized()
	var bodies: Array = []
	for p in planets:
		bodies.append([p.node.global_position, float(p.radius) * 1.3])
	if giant:
		bodies.append([giant.global_position, giant_r * 1.1])
	for b in bodies:
		var c: Vector3 = b[0]
		var oc := c - pos
		var t := oc.dot(to_star)
		if t > 0.0 and (pos + to_star * t).distance_to(c) < float(b[1]):
			return true
	return false


func flare_active() -> bool:
	return _flare_state == "burn"


## Everything worth drawing on the system map / targeting as a waypoint.
func system_objects() -> Array:
	var out := []
	for p in planets:
		var d: Dictionary = p.data
		out.append({"kind": "planet", "id": d.index, "name": d.name + (" (moon)" if Galaxy.is_moon(d) else ""), "pos": p.node.global_position,
			"color": Db.BIOMES[d.biome].colors.low, "r": float(p.radius), "sub": Db.BIOMES[d.biome].name + (("  ·  ⌂ " + d.town.name) if not d.town.is_empty() else "")})
	if station:
		out.append({"kind": "station", "id": 0, "name": star.station.name, "pos": station.global_position, "color": Color("ffd98a"), "r": 8.0, "sub": "Trade · repair · contracts"})
	if giant:
		out.append({"kind": "giant", "id": 0, "name": star.giant.name, "pos": giant.global_position, "color": Color("ffd9a8"), "r": giant_r, "sub": "Skim for plasma"})
	for d in derelicts:
		out.append({"kind": "derelict", "id": d.idx, "name": "Derelict", "pos": d.node.global_position, "color": Color("ff9f43"), "r": 6.0,
			"sub": "Salvaged" if Game.boarded.has("derelict:%d:%d" % [Game.star_index, d.idx]) else "Unexplored"})
	if relay:
		var lit := Game.relay_lit(Game.star_index)
		out.append({"kind": "relay", "id": 0, "name": "Circuit Relay", "pos": relay.global_position, "color": Color("5ff7ff") if lit else Color("8a8f99"), "r": 7.0, "sub": "Online" if lit else "Dark"})
	if heart and is_instance_valid(heart) and heart.is_alive():
		out.append({"kind": "heart", "id": 0, "name": "Corruption Heart", "pos": heart.global_position, "color": Color("ff2a55"), "r": 30.0, "sub": "The source of the Quiet"})
	return out


func quest_space_target() -> Dictionary:
	var q := Game.current_quest()
	if q.is_empty() or not Game.quest_accepted:
		return {}
	match q.obj.type:
		"relay":
			if relay and not Game.relay_lit(Game.star_index):
				if Game.count("resonance_crystal") < 1 and not derelicts.is_empty():
					for d in derelicts:
						if not Game.boarded.has("derelict:%d:%d" % [Game.star_index, d.idx]):
							return {"kind": "derelict", "id": d.idx, "name": "★ Derelict (Resonance Crystal)"}
				return {"kind": "relay", "id": 0, "name": "★ Circuit Relay"}
		"station_sell":
			return {"kind": "station", "id": 0, "name": "★ " + star.station.name}
		"heart":
			if heart and is_instance_valid(heart):
				return {"kind": "heart", "id": 0, "name": "★ Corruption Heart"}
		"collect":
			if q.obj.item in ["fire_opal", "obsidian", "core_ember"]:
				for p in planets:
					if Db.BIOMES[p.data.biome].get("lava", false):
						return {"kind": "planet", "id": p.data.index, "name": "★ %s (volcanic)" % p.data.name}
			if q.obj.item in ["nickel", "cryo_ice", "stardust"]:
				return {"kind": "belt", "id": 0, "name": "★ Asteroid belt"}
	return {}


func waypoint_pos() -> Vector3:
	var w: Dictionary = Game.waypoint
	if w.is_empty() or int(w.get("star", -1)) != Game.star_index:
		var qt := quest_space_target()
		if qt.is_empty():
			return Vector3.INF
		if qt.kind == "belt":
			var best := Vector3.INF
			for a in asteroids:
				if is_instance_valid(a) and (best == Vector3.INF or a.global_position.distance_to(player.global_position) < best.distance_to(player.global_position)):
					best = a.global_position
			return best
		w = qt
	for o in system_objects():
		if o.kind == w.kind and int(o.id) == int(w.id):
			return o.pos
	return Vector3.INF



func on_heart_destroyed() -> void:
	Game.defeat_heart()
	CombatFx.explosion(self, heart.global_position, Color(1.0, 0.3, 0.4), 14.0)
	if player:
		player.shake.add(1.0)
	for e in space_enemies.duplicate():
		if is_instance_valid(e) and e.is_alive() and e.type == "swarmer":
			e.take_hit(99999.0)
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_inside_tree():
			hud.show_victory()
	)



func _label_h(n: Node3D) -> float:
	return float(n.get_meta("label_h", 20.0))


## What other players see of us: position relative to the nearest planet,
## because orbits run on each player's own clock.
func net_state() -> Dictionary:
	if player == null:
		return {"scene": "away", "label": "Warping in"}
	var pos: Vector3 = player.global_position
	var anchor := -1
	var base := Vector3.ZERO
	var bd := INF
	for p in planets:
		var op: Vector3 = Galaxy.orbit_pos(p.data, Game.play_time)
		var d := op.distance_to(pos)
		if d < bd:
			bd = d
			anchor = int(p.data.index)
			base = op
	var fwd: Vector3 = -player.global_basis.z
	return {"scene": "space", "planet": anchor, "pos": pos - base, "fwd": fwd, "anim": "boost" if player.visual.boost else "fly"}
