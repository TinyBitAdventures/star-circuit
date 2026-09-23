extends Node3D
## A sealed chamber deep in a planet: a small walkable 3D room themed by
## depth (fungal / fossil / crystal / vault), with cave species to scan,
## rare nodes, relics and an exit rift back to the dig.

const ROOM_R := 15.0
const THEME_LOOK := {
	"fungal": {"rock": Color("3a2f3d"), "seam": Color("7ef0d8"), "light": Color("7ef0d8"), "fog": Color("0e2a26"), "nodes": {"glowcap": 5, "spore": 2, "fiber": 1}, "props": "res://assets/models/flora_mushroom.glb", "prop_scale": 0.45},
	"fossil": {"rock": Color("5a4a3c"), "seam": Color("ffcf8a"), "light": Color("ffc98a"), "fog": Color("2a1c10"), "nodes": {"ferrite": 2, "cobalt": 2}, "props": "res://assets/models/prop_boulder.glb", "prop_scale": 0.7},
	"crystal": {"rock": Color("2c2447"), "seam": Color("c9a6ff"), "light": Color("b98cff"), "fog": Color("150e2a"), "nodes": {"lumen": 4, "cobalt": 1}, "props": "res://assets/models/res_crystal.glb", "prop_scale": 1.1},
	"derelict": {"rock": Color("4a4f5a"), "seam": Color("ff9f43"), "light": Color("ffb870"), "fog": Color("141210"), "nodes": {"salvage": 5, "energy": 1}, "props": "res://assets/models/prop_terminal.glb", "prop_scale": 1.0},
	"vault": {"rock": Color("2a2a33"), "seam": Color("ffd98a"), "light": Color("ffd98a"), "fog": Color("1a1408"), "nodes": {"lumen": 1, "void": 2}, "props": "res://assets/models/poi_ruin.glb", "prop_scale": 0.3},
}

var chamber: Dictionary
var theme := "fungal"
var look: Dictionary
var hud: CanvasLayer
var player: CharacterBody3D
var flora_tint := Color.WHITE
var critters: Array = []
var _interactables: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var key := ""


func _ready() -> void:
	chamber = Game.cave.get("chamber", {"id": 0, "theme": "crystal"})
	theme = chamber.theme
	look = THEME_LOOK[theme]
	key = "%s:ch%d" % [Game.cave.get("key", "dev"), int(chamber.id)]
	_rng.seed = hash(key)
	flora_tint = look.light
	_build_env()
	_build_room()
	_build_contents()
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "grotto"
	add_child(hud)
	player = preload("res://scripts/grotto/grotto_player.gd").new()
	player.world = self
	add_child(player)
	# arrive beside the rift on the west wall, looking into the room
	player.global_position = Vector3(-(ROOM_R - 7.0), 1.0, 0.0)
	player.cam_yaw = -PI * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if theme == "derelict":
		key = Game.cave.key
		hud.show_location_banner("Derelict", "Hull breached long ago. The air is gone; the cargo isn't." if not Game.boarded.has(key) else "Already picked over")
		Sound.play_music("space", 1.5)
		return
	var first: bool = not Game.dig_state(Game.cave.get("key", "dev")).chambers.has(int(chamber.id))
	Game.record_chamber(Game.cave.get("key", "dev"), int(chamber.id), theme)
	var tname: String = {"fungal": "Fungal Grotto", "fossil": "Fossil Bed", "crystal": "Crystal Cavern", "vault": "Ancient Vault"}[theme]
	hud.show_location_banner(tname, "Sealed since before the Quiet" if first else "You've been here before")
	Sound.play_music("underground", 1.5)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = (look.fog as Color).darkened(0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = (look.light as Color).lerp(Color(0.5, 0.5, 0.6), 0.5)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = look.fog
	env.fog_density = 0.018
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	UiKit.polish_environment(env)
	env.volumetric_fog_enabled = Sound.gfx_quality >= 2
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = look.fog
	we.environment = env
	add_child(we)
	UiKit.add_vignette(self, 0.45)


func _rock_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/cave_rock.gdshader")
	m.set_shader_parameter("rock_color", look.rock)
	m.set_shader_parameter("seam_color", look.seam)
	return m


func _build_room() -> void:
	var rock := _rock_mat()
	# floor
	var floor_mi := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = ROOM_R + 2.0
	fm.bottom_radius = ROOM_R + 2.0
	fm.height = 1.0
	fm.radial_segments = 48
	floor_mi.mesh = fm
	floor_mi.material_override = rock
	floor_mi.position.y = -0.5
	add_child(floor_mi)
	# dome (seen from inside)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = ROOM_R + 1.5
	dm.height = (ROOM_R + 1.5) * 2.0
	dm.radial_segments = 48
	dm.rings = 24
	dome.mesh = dm
	dome.scale = Vector3(1.0, 0.55, 1.0)
	dome.material_override = rock
	add_child(dome)
	var body := StaticBody3D.new()
	add_child(body)
	var fcs := CollisionShape3D.new()
	var fshape := CylinderShape3D.new()
	fshape.radius = ROOM_R + 2.0
	fshape.height = 1.0
	fcs.shape = fshape
	fcs.position.y = -0.5
	body.add_child(fcs)
	# wall ring colliders
	for i in 28:
		var a := i * TAU / 28.0
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(4.0, 12.0, 1.0)
		cs.shape = bx
		cs.position = Vector3(cos(a), 0, sin(a)) * (ROOM_R - 0.5) + Vector3(0, 5, 0)
		cs.rotation.y = -a + PI * 0.5
		body.add_child(cs)
	# rubble around the edge + stalactites/stalagmites
	var rubble := []
	for i in 40:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(ROOM_R - 3.0, ROOM_R + 0.5)
		var s := _rng.randf_range(0.5, 1.5)
		rubble.append(Transform3D(Basis.from_euler(Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())).scaled(Vector3.ONE * s), Vector3(cos(a) * r, 0.1, sin(a) * r)))
	ModelUtil.multimesh(self, "res://assets/models/prop_boulder.glb", rubble)
	for i in 26:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, ROOM_R - 1.0)
		var ceil_y := 0.55 * sqrt(maxf(0.0, pow(ROOM_R + 1.5, 2) - r * r))
		var len := _rng.randf_range(1.2, 3.5)
		var st := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = _rng.randf_range(0.25, 0.6)
		cm.bottom_radius = 0.02
		cm.height = len
		cm.radial_segments = 7
		st.mesh = cm
		st.material_override = rock
		st.position = Vector3(cos(a) * r, ceil_y - len * 0.45, sin(a) * r)
		add_child(st)
		if i % 3 == 0 and r > 5.0:
			var sg := MeshInstance3D.new()
			var cm2 := CylinderMesh.new()
			cm2.top_radius = 0.02
			cm2.bottom_radius = cm.top_radius * 1.2
			cm2.height = len * 0.7
			cm2.radial_segments = 7
			sg.mesh = cm2
			sg.material_override = rock
			sg.position = Vector3(cos(a) * r, len * 0.35, sin(a) * r)
			add_child(sg)
	# lights
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		var l := OmniLight3D.new()
		l.light_color = look.light
		l.light_energy = 1.6
		l.omni_range = 11.0
		l.shadow_enabled = i == 0 and Sound.gfx_quality >= 1
		l.position = Vector3(cos(a) * 7.0, 3.5, sin(a) * 7.0)
		add_child(l)


func _build_contents() -> void:
	# theme props (decor)
	var props := []
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(ROOM_R - 6.0, ROOM_R - 2.5)
		props.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * float(look.prop_scale) * _rng.randf_range(0.7, 1.3)), Vector3(cos(a) * r, 0, sin(a) * r)))
	ModelUtil.multimesh(self, look.props, props, "Foliage", flora_tint, true, 0.02 if theme == "fungal" else 0.0)
	# harvestable nodes (never respawn in a sealed room: keyed per chamber)
	var nid := 0
	for type in look.nodes:
		for i in int(look.nodes[type]):
			nid += 1
			var id := 30000 + int(chamber.id) * 50 + nid
			if Game.is_harvested(key, id):
				continue
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(4.0, ROOM_R - 4.0)
			var n := ResourceNode.new()
			add_child(n)
			n.setup(type, id, self)
			n.position = Vector3(cos(a) * r, 0, sin(a) * r)
			n.rotation.y = _rng.randf() * TAU
			_interactables.append(n)
	# relic pedestal / fossil slab
	if theme == "derelict":
		key = Game.cave.key
	if theme in ["vault", "fossil", "derelict"]:
		var ped := RelicPedestal.new()
		add_child(ped)
		ped.setup(self, {"vault": "ancient_relic", "fossil": "fossil", "derelict": "resonance_crystal"}[theme], key)
		ped.position = Vector3(0, 0, -4.0)
		_interactables.append(ped)
	# cave species
	var sp_count := 3 if not theme in ["vault", "derelict"] else (1 if theme == "vault" else 0)
	for v in 2:
		var col: Color = (look.light as Color).lerp(Color.from_hsv(_rng.randf(), 0.6, 1.0), 0.35)
		for i in sp_count:
			var c := GrottoCritter.new()
			add_child(c)
			c.setup(self, col, "%s:cave:%d" % [key, v], Galaxy.species_name(hash(key), "cave%d" % v), _rng.randf_range(0.5, 0.8))
			c.position = Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
			critters.append(c)
	# exit rift
	var ex := ExitRift.new()
	add_child(ex)
	ex.setup(self, look.light)
	ex.position = Vector3(-(ROOM_R - 3.0), 0, 5.5)
	ex.rotation.y = PI * 0.5
	_interactables.append(ex)


func nearest_interactable(pos: Vector3, max_dist: float) -> Node:
	var best: Node = null
	var best_d := max_dist
	for n in _interactables:
		if not is_instance_valid(n):
			continue
		var d := n.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func on_harvested(n: ResourceNode) -> void:
	Game.mark_harvested(key, n.node_id)
	_interactables.erase(n)


func scan(pos: Vector3, radius: float) -> void:
	CombatFx.shockwave(self, pos, Vector3.UP, radius * 0.5, Color(0.3, 0.9, 1.0))
	var found := 0
	for c in critters:
		if c.global_position.distance_to(pos) < radius:
			if Game.record_scan(c.species_key, c.species_name + " (cave fauna)"):
				found += 1
	for n in _interactables:
		if n is ResourceNode and is_instance_valid(n):
			n.reveal(20.0)
	if found == 0:
		Game.notify.emit("Scan: nothing new here", Color("5ff7ff"))
