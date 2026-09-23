class_name Poi
extends Node3D
## A point of interest: monolith, ruins, crash site or crystal geode.
## Walk close to discover it; open its cache / read its glyphs for loot + lore.

const DISCOVER_RANGE := 16.0

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
	var m := ModelUtil.instance(def.model)
	add_child(m)
	if t == "monolith":
		m.scale = Vector3(1.7, 1.5, 1.7)
	if t == "ruin":
		ModelUtil.tint(m, "Foliage", w.flora_tint)
	global_transform = Transform3D(PlanetGen.align_basis(dir, float(idx) * 1.7), w.gen.surface_point(dir) - dir * 0.4)
	revealed = is_discovered()
	_add_collision()
	_add_beacon()
	if def.loot.size() > 0 or def.lore or t == "cave":
		_add_cache()


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
	c.position = offset
	if type != "monolith" and type != "cave":
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
