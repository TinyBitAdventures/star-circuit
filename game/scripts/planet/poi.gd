class_name Poi
extends Node3D
## A point of interest: monolith, ruins, crash site or crystal geode.
## Walk close to discover it; open its cache / read its glyphs for loot + lore.

const DISCOVER_RANGE := 16.0
# the volcano cone: rim at local y 8.5, base sunk well below ground so hills never show a gap
const CONE_TOP := 3.5
const CONE_BOTTOM := 15.0
const CONE_H := 15.0
const CONE_Y := 1.0

var world: Node3D
var type := ""
var def: Dictionary
var key := ""
var dir := Vector3.UP
var revealed := false
var _beam: MeshInstance3D
var _light: OmniLight3D
var _cache: Node3D
var _t := 0.0


func setup(w: Node3D, t: String, idx: int, d: Vector3) -> void:
	world = w
	type = t
	def = Db.POIS[t]
	dir = d.normalized()
	key = "%s:%d" % [w.planet.key, idx]
	var m: Node3D = ModelUtil.instance(def.model) if def.model != "" else _volcano_model()
	add_child(m)
	if t == "monolith":
		m.scale = Vector3(1.7, 1.5, 1.7)
	if t == "ruin":
		ModelUtil.tint(m, "Foliage", w.flora_tint)
	global_transform = Transform3D(PlanetGen.align_basis(dir, float(idx) * 1.7), w.gen.surface_point(dir) - dir * 0.4)
	revealed = is_discovered()
	_add_collision()
	_add_beacon()
	if def.loot.size() > 0 or def.lore or t == "cave" or t == "volcano":
		_add_cache()


## Where to send the player: the doorway for a volcano, the site itself otherwise.
func entrance() -> Vector3:
	return _cache.global_position if type == "volcano" and _cache else global_position


func is_discovered() -> bool:
	return Game.discovered_pois.has(key)


func is_looted() -> bool:
	return Game.looted_pois.has(key)


func _add_collision() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	match type:
		"monolith":
			var c := CylinderShape3D.new()
			c.radius = 1.2
			c.height = 10.0
			cs.shape = c
			cs.position.y = 5.0
		"crash":
			var sp := SphereShape3D.new()
			sp.radius = 2.2
			cs.shape = sp
			cs.position.y = 1.0
		"cave":
			return # walk right onto the shaft
		"volcano":
			# a solid cone: you walk around it (or jetpack up it), never through it
			var cone := CylinderMesh.new()
			cone.top_radius = CONE_TOP
			cone.bottom_radius = CONE_BOTTOM
			cone.height = CONE_H
			cs.shape = cone.create_convex_shape()
			cs.position.y = CONE_Y
		"geode":
			var sp2 := SphereShape3D.new()
			sp2.radius = 3.0
			cs.shape = sp2
			cs.position.y = 0.8
		_:
			var c2 := CylinderShape3D.new()
			c2.radius = 0.6
			c2.height = 5.2
			cs.shape = c2
			cs.position = Vector3(2.6, 2.6, 0)
			var cs2 := CollisionShape3D.new()
			cs2.shape = c2
			cs2.position = Vector3(-2.6, 2.6, 0)
			body.add_child(cs2)
	body.add_child(cs)


func _add_beacon() -> void:
	# a tall faint light column so undiscovered sites catch the eye from afar
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 1.2
	cyl.height = 90.0
	cyl.radial_segments = 8
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(def.color.r, def.color.g, def.color.b, 0.18)
	mat.disable_fog = true
	cyl.material = mat
	_beam.mesh = cyl
	_beam.position.y = 45.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_beam.visible = not is_discovered()
	_light = OmniLight3D.new()
	_light.light_color = def.color
	_light.omni_range = 14.0
	_light.light_energy = 1.2
	_light.position.y = 3.0
	add_child(_light)


func _add_cache() -> void:
	var c := PoiCache.new()
	c.poi = self
	add_child(c)
	var offset := Vector3.ZERO
	match type:
		"ruin":
			offset = Vector3(0, 0.5, 2.2)
		"crash":
			offset = Vector3(3.6, 0.0, 0.8)
		"monolith":
			offset = Vector3(0, 0.9, 2.3)
		"cave":
			offset = Vector3(0, 0.3, 0)
		"volcano":
			_add_volcano_entrances(c)
			_cache = c
			return
	c.position = offset
	if type != "monolith" and type != "cave" and type != "volcano":
		c.add_child(ModelUtil.instance("res://assets/models/poi_cache.glb"))
	_cache = c
	world.register_interactable(c)


func _process(delta: float) -> void:
	_t += delta
	var player: Node3D = world.player
	if player == null:
		return
	if not is_discovered() and player.global_position.distance_to(global_position) < DISCOVER_RANGE:
		if Game.discover_poi(key, def.name):
			Sound.play("quest_accept", -4.0, 0.0, "UI")
			revealed = true
			var t := create_tween()
			t.tween_property(_beam, "scale", Vector3(0.01, 1, 0.01), 1.0)
			t.tween_callback(func(): _beam.visible = false)
			world.check_survey()
	_light.light_energy = 1.0 + sin(_t * 2.0) * 0.3


func cache_info() -> Dictionary:
	if type == "volcano":
		var runs := int(Game.volcanoes.get(key, {}).get("escapes", 0))
		return {"text": "[E] Climb down into the volcano%s" % ("  ·  escaped %d time%s" % [runs, "" if runs == 1 else "s"] if runs > 0 else ""), "color": def.color, "instant": true}
	if type == "cave":
		var st: Dictionary = Game.digs.get(key, {})
		var n: int = st.get("chambers", []).size()
		return {"text": "[E] Descend into the cave%s" % ("  ·  %d chamber%s found" % [n, "s" if n != 1 else ""] if n > 0 else ""), "color": def.color, "instant": true}
	if type == "monolith":
		if is_looted():
			return {"text": "Circuit Monolith  -  glyphs recorded", "color": UiKit.MUTED, "instant": true}
		return {"text": "[E] Hold to %s" % def.verb, "color": def.color, "time": def.time, "skill": "exploration", "ok": true}
	if is_looted():
		return {"text": "%s  -  already salvaged" % def.name, "color": UiKit.MUTED, "instant": true}
	return {"text": "[E] Hold to %s" % def.verb, "color": def.color, "time": def.time, "skill": "exploration", "ok": true}


func open_cache() -> void:
	if type == "volcano":
		if not is_discovered():
			Game.discover_poi(key, def.name)
		Game.enter_volcano(key, dir, int(world.planet.seed), world.planet.biome)
		return
	if type == "cave":
		if not is_discovered():
			Game.discover_poi(key, def.name)
		Game.enter_cave(key, dir, int(world.planet.seed), world.planet.biome)
		return
	if is_looted():
		return
	if not is_discovered():
		Game.discover_poi(key, def.name)
	Game.loot_poi(key, type)
	Sound.play("craft", -3.0, 0.0, "UI")
	if def.lore:
		var li := Game.learn_lore(hash(key))
		if li >= 0:
			world.hud.show_lore(li)
	world.check_survey()



## Cone radius at a local height (the cone narrows from its sunk base to the rim).
static func cone_radius(h: float) -> float:
	var t := clampf((CONE_Y + CONE_H * 0.5 - h) / CONE_H, 0.0, 1.0)
	return lerpf(CONE_TOP, CONE_BOTTOM, t)


## Two ways in: a lava-tube doorway at the foot of the cone, snapped to the
## real ground there, and the crater rim for anyone who jetpacks up.
func _add_volcano_entrances(door: PoiCache) -> void:
	var up := dir
	var side := global_basis.z.normalized()
	# walk the doorway out until it sits just outside the cone at ground level
	var gen: PlanetGen = world.gen
	var r := 11.0
	var ground := Vector3.ZERO
	for i in 3:
		var d := (up + side * r / gen.radius).normalized()
		ground = gen.surface_point(d)
		r = cone_radius((ground - global_position).dot(up)) + 1.2
	var gup := ground.normalized()
	var outward := (side - gup * side.dot(gup)).normalized()
	door.global_position = ground + gup * 1.0 + outward * 0.8
	var arch := _lava_door()
	door.add_child(arch)
	arch.global_transform = Transform3D(Basis(gup.cross(outward).normalized(), gup, outward), ground + gup * 1.4 - outward * 0.6)
	world.register_interactable(door)
	var rim := PoiCache.new()
	rim.poi = self
	add_child(rim)
	rim.position = Vector3(0, CONE_Y + CONE_H * 0.5 + 0.6, 0)
	world.register_interactable(rim)


## A dark arch in the cone's flank with lava glowing inside (faces local +Z).
func _lava_door() -> Node3D:
	var root := Node3D.new()
	root.top_level = true
	var arch := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 3.4, 1.2)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("1a1210")
	dark.roughness = 1.0
	bm.material = dark
	arch.mesh = bm
	root.add_child(arch)
	var glow := MeshInstance3D.new()
	var gm := QuadMesh.new()
	gm.size = Vector2(2.2, 2.6)
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1.0, 0.45, 0.12)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.4, 0.1)
	gmat.emission_energy_multiplier = 3.0
	gm.material = gmat
	glow.mesh = gm
	glow.position = Vector3(0, -0.2, 0.61)
	root.add_child(glow)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.2)
	l.light_energy = 2.0
	l.omni_range = 7.0
	l.position = Vector3(0, 0, 1.6)
	root.add_child(l)
	return root


## A smoking cone with a glowing crater (built here rather than in Blender).
func _volcano_model() -> Node3D:
	var root := Node3D.new()
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = CONE_TOP
	cm.bottom_radius = CONE_BOTTOM
	cm.height = CONE_H
	cm.radial_segments = 14
	cm.rings = 4
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color("3a2a26")
	rock.roughness = 1.0
	cm.material = rock
	cone.mesh = cm
	cone.position.y = CONE_Y
	root.add_child(cone)
	var lava := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 3.0
	lm.bottom_radius = 3.0
	lm.height = 0.3
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("ff5a1a")
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.45, 0.1)
	lmat.emission_energy_multiplier = 4.0
	lm.material = lmat
	lava.mesh = lm
	lava.position.y = 8.45
	root.add_child(lava)
	var smoke := CPUParticles3D.new()
	smoke.amount = 30
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0
	smoke.position.y = 9.0
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 4.0
	smoke.gravity = Vector3.ZERO
	smoke.scale_amount_min = 3.0
	smoke.scale_amount_max = 6.0
	var q := QuadMesh.new()
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.albedo_texture = ModelUtil.soft_dot()
	qm.vertex_color_use_as_albedo = true
	q.material = qm
	smoke.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.3, 0.3, 0.5))
	g.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	smoke.color_ramp = g
	root.add_child(smoke)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 3.0
	glow.omni_range = 18.0
	glow.position.y = 10.0
	root.add_child(glow)
	return root
