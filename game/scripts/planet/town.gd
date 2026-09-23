class_name Town
extends Node3D
## Builds a trade hub around a surface point: landing pad, buildings, stalls,
## lamps, merchant, trainer, bounty board and wandering townsfolk.

const FOLK_NAMES := ["Pim", "Rook", "Tesla", "Bolt", "Nib", "Ferra", "Quill", "Dot", "Sprocket", "Ivy", "Coil", "Juno", "Mote", "Hex"]
const MERCHANTS := ["Mar", "Tobb", "Lysa", "Kettle", "Vend-9", "Orla"]
const TRAINERS := ["Tutor Voss", "Master Anvil", "Sage Wren", "Mentor Kade", "Elder Cobb"]

var world: Node3D
var data: Dictionary
var centre := Vector3.ZERO
var dir := Vector3.UP
var npcs: Array[TownNpc] = []


func build(w: Node3D, town: Dictionary, d: Vector3, home: bool) -> void:
	world = w
	data = town
	dir = d.normalized()
	centre = w.gen.surface_point(dir)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(town.seed)
	var b := PlanetGen.align_basis(dir)
	var body := StaticBody3D.new()
	w.add_child(body)

	if not home:
		# every hub gets a pad + fabricator like the Cradle outpost
		var pad := ModelUtil.instance("res://assets/models/prop_outpost.glb")
		w.add_child(pad)
		pad.global_transform = Transform3D(b, centre - dir * 0.35)
		_collider(body, CylinderShape3D.new(), 7.0, 0.6, centre + dir * 0.0)
		var fab := Fabricator.new()
		w.add_child(fab)
		fab.setup(w)
		fab.global_transform = Transform3D(b * Basis(Vector3.UP, -PI * 0.5), centre - dir * 0.2 + b.x * 4.0)
		w.register_interactable(fab)

	# ring of buildings facing the plaza
	var buildings := [["town_hab", 24.0, 8.0], ["town_workshop", 25.0, 6.0], ["town_tower", 27.0, 2.2], ["town_hab", 23.0, 8.0]]
	var angle := rng.randf() * TAU
	for i in buildings.size():
		var bl: Array = buildings[i]
		var a := angle + i * TAU / buildings.size() + rng.randf_range(-0.25, 0.25)
		_place(bl[0], a, bl[1], body, bl[2], rng)

	# stalls with a merchant and a trainer, and the bounty board
	var merchant_name: String = MERCHANTS[rng.randi() % MERCHANTS.size()] if not home else "Mar"
	var trainer_name: String = TRAINERS[rng.randi() % TRAINERS.size()] if not home else "Tutor Voss"
	var a_m := angle + PI * 0.25
	var a_t := angle + PI * 0.75
	var a_b := angle + PI * 1.25
	_place("town_stall", a_m, 11.0, body, 2.0, rng)
	_npc("merchant", merchant_name, "General Goods", Color("ffb347"), a_m, 9.6)
	_place("town_stall", a_t, 11.0, body, 2.0, rng)
	_npc("trainer", trainer_name, "Profession Trainer", Color("8f6cf0"), a_t, 9.6)
	_npc("board", "Bounty Board", "", Color.WHITE, a_b, 10.0)
	_collider_at(body, a_b, 10.0, 1.8)

	for i in 6:
		var la := angle + (i + 0.5) * TAU / 6.0
		var ld := _dir_at(la, 16.0)
		var lamp := ModelUtil.instance("res://assets/models/town_lamp.glb")
		w.add_child(lamp)
		lamp.global_transform = Transform3D(PlanetGen.align_basis(ld, la), w.gen.surface_point(ld) - ld * 0.2)
		var light := OmniLight3D.new()
		light.light_color = Color("ffd98a")
		light.omni_range = 10.0
		light.light_energy = 1.2
		w.add_child(light)
		light.global_position = w.gen.surface_point(ld) + ld * 3.2

	# townsfolk
	var colors := [Color("5a9bd8"), Color("d85a7f"), Color("6ed85a"), Color("d8b45a"), Color("9b5ad8"), Color("5ad8c8")]
	for i in rng.randi_range(4, 7):
		var folk := TownNpc.new()
		w.add_child(folk)
		var fd := _dir_at(rng.randf() * TAU, rng.randf_range(5.0, 15.0))
		folk.global_position = w.gen.surface_point(fd)
		folk.setup(w, "folk", FOLK_NAMES[rng.randi() % FOLK_NAMES.size()], "", colors[i % colors.size()], centre)
		npcs.append(folk)
		w.register_interactable(folk)

	# name sign over the plaza
	var sign := Label3D.new()
	sign.text = town.name
	sign.font = UiKit.title_font()
	sign.font_size = 110
	sign.outline_size = 22
	sign.pixel_size = 0.012
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = CombatFx.hdr(Color("ffd98a"), 1.6)
	w.add_child(sign)
	sign.global_position = centre + dir * 11.0


func _dir_at(a: float, dist: float) -> Vector3:
	var b := PlanetGen.align_basis(dir)
	return (dir + (b.x * cos(a) + b.z * sin(a)) * dist / world.gen.radius).normalized()


func _place(model: String, a: float, dist: float, body: StaticBody3D, col_r: float, rng: RandomNumberGenerator) -> void:
	var d := _dir_at(a, dist)
	var inst := ModelUtil.instance("res://assets/models/%s.glb" % model)
	world.add_child(inst)
	# face the plaza: model front (-Z) points back toward the centre
	var bb := PlanetGen.align_basis(d)
	var to_centre: Vector3 = centre - world.gen.surface_point(d)
	to_centre -= d * to_centre.dot(d)
	var back: Vector3 = -to_centre.normalized()
	var basis := Basis(d.cross(back).normalized(), d, back).orthonormalized()
	if not basis.x.is_finite():
		basis = bb
	inst.global_transform = Transform3D(basis, world.gen.surface_point(d) - d * 0.5)
	if col_r > 0.0:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = col_r
		cyl.height = 8.0
		cs.shape = cyl
		body.add_child(cs)
		cs.global_transform = Transform3D(PlanetGen.align_basis(d), world.gen.surface_point(d) + d * 3.0)


func _collider_at(body: StaticBody3D, a: float, dist: float, r: float) -> void:
	var d := _dir_at(a, dist)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 4.0
	cs.shape = cyl
	body.add_child(cs)
	cs.global_transform = Transform3D(PlanetGen.align_basis(d), world.gen.surface_point(d) + d * 2.0)


func _collider(body: StaticBody3D, shape: CylinderShape3D, r: float, h: float, pos: Vector3) -> void:
	shape.radius = r
	shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	cs.global_transform = Transform3D(PlanetGen.align_basis(dir), pos)


func _npc(role: String, n: String, title: String, tint: Color, a: float, dist: float) -> void:
	var d := _dir_at(a, dist)
	var npc := TownNpc.new()
	world.add_child(npc)
	var to_centre: Vector3 = centre - world.gen.surface_point(d)
	to_centre -= d * to_centre.dot(d)
	var fwd := to_centre.normalized()
	npc.global_transform = Transform3D(Basis(d.cross(-fwd).normalized(), d, -fwd).orthonormalized(), world.gen.surface_point(d))
	npc.setup(world, role, n, title, tint, centre)
	npcs.append(npc)
	world.register_interactable(npc)
