class_name GroundCover
extends Node3D
## Dense grass/flowers/crystals around the player. Instances are placed on a
## worker thread and swapped in when ready; the patch follows the player.

const RADIUS := 42.0
const MOVE_REBUILD := 11.0

## per biome: blade colours, density (0..1), sprig type for the second layer
const LOOK := {
	"verdant": {"base": Color("2f6e22"), "tip": Color("a6e060"), "density": 1.0, "height": 0.75, "sprig": "flower", "sprig_density": 0.06},
	"bloom": {"base": Color("5a2a5e"), "tip": Color("ff9bd6"), "density": 0.8, "height": 0.6, "sprig": "mushroom", "sprig_density": 0.08, "emissive": 0.25},
	"prism": {"base": Color("3a2a6b"), "tip": Color("c9a6ff"), "density": 0.35, "height": 0.5, "sprig": "crystal", "sprig_density": 0.12, "emissive": 0.4},
	"frost": {"base": Color("8fb3d1"), "tip": Color("f2f8ff"), "density": 0.35, "height": 0.45, "sprig": "", "sprig_density": 0.0},
	"dune": {"base": Color("8c6a3c"), "tip": Color("e8cf94"), "density": 0.18, "height": 0.55, "sprig": "", "sprig_density": 0.0},
	"ember": {"base": Color("2a1d1d"), "tip": Color("ff6a2a"), "density": 0.0, "height": 0.3, "sprig": "", "sprig_density": 0.0},
}

var world: Node3D
var look: Dictionary
var max_instances := 8000
var _grass: MultiMeshInstance3D
var _sprigs: MultiMeshInstance3D
var _centre := Vector3.ZERO
var _busy := false
var _gen := 0
var _task := -1


func setup(w: Node3D, biome: String, quality: int) -> void:
	world = w
	look = LOOK.get(biome, LOOK.verdant)
	max_instances = [0, 4500, 9000][clampi(quality, 0, 2)]
	if max_instances == 0 or float(look.density) <= 0.0:
		set_process(false)
		return
	var tint: Color = w.flora_tint
	var base: Color = (look.base as Color).lerp(tint.darkened(0.45), 0.35)
	var tip: Color = (look.tip as Color).lerp(tint.lightened(0.2), 0.3)
	_grass = _make_mmi(_tuft_mesh(float(look.height)), base, tip, float(look.get("emissive", 0.0)))
	if look.sprig != "":
		var sprig_col: Color = {"flower": Color("ffd23f"), "mushroom": Color("7ee8fa"), "crystal": Color("d9b8ff")}[look.sprig]
		_sprigs = _make_mmi(_sprig_mesh(look.sprig), sprig_col.darkened(0.3), sprig_col, 0.8 if look.sprig != "flower" else 0.1)


func _make_mmi(mesh: Mesh, base: Color, tip: Color, emissive: float) -> MultiMeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("tip_color", tip)
	mat.set_shader_parameter("emissive", emissive)
	mat.set_shader_parameter("fade_near", RADIUS * 0.7)
	mat.set_shader_parameter("fade_far", RADIUS * 0.98)
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = RADIUS
	add_child(mmi)
	return mmi


## A tuft of 5 tapered blades, normals pointing up so they shade like the ground.
func _tuft_mesh(height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b in 5:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.18)
		var side := Vector3(-sin(a + 1.2), 0, cos(a + 1.2)) * 0.05
		var hgt := height * rng.randf_range(0.6, 1.2)
		var lean := Vector3(cos(a), 0, sin(a)) * hgt * rng.randf_range(0.1, 0.35)
		for v in [[off - side, 0.0], [off + side, 0.0], [off + lean + Vector3(0, hgt, 0), 1.0]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5, v[1]))
			st.add_vertex(v[0])
	return st.commit()


func _sprig_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"flower":
			# stem + a little star of petals
			for v in [[Vector3(-0.02, 0, 0), 0.0], [Vector3(0.02, 0, 0), 0.0], [Vector3(0, 0.45, 0), 0.6]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.5, v[1]))
				st.add_vertex(v[0])
			for i in 5:
				var a := i * TAU / 5.0
				var c := Vector3(0, 0.45, 0)
				var p1 := c + Vector3(cos(a - 0.35), 0.02, sin(a - 0.35)) * 0.14
				var p2 := c + Vector3(cos(a + 0.35), 0.02, sin(a + 0.35)) * 0.14
				for v in [c, p1, p2]:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(0.5, 1.0))
					st.add_vertex(v)
		"mushroom":
			for v in [[Vector3(-0.03, 0, 0), 0.0], [Vector3(0.03, 0, 0), 0.0], [Vector3(0, 0.3, 0), 0.5]]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.5, v[1]))
				st.add_vertex(v[0])
			for i in 8:
				var a := i * TAU / 8.0
				var b := (i + 1) * TAU / 8.0
				for v in [Vector3(0, 0.36, 0), Vector3(cos(a) * 0.15, 0.28, sin(a) * 0.15), Vector3(cos(b) * 0.15, 0.28, sin(b) * 0.15)]:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(0.5, 1.0))
					st.add_vertex(v)
		_:
			# crystal: a thin hexagonal spike
			for i in 6:
				var a := i * TAU / 6.0
				var b := (i + 1) * TAU / 6.0
				for v in [[Vector3(cos(a) * 0.06, 0, sin(a) * 0.06), 0.0], [Vector3(cos(b) * 0.06, 0, sin(b) * 0.06), 0.0], [Vector3(0.03, 0.55, 0.01), 1.0]]:
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(0.5, v[1]))
					st.add_vertex(v[0])
	return st.commit()


func _process(_delta: float) -> void:
	var player: Node3D = world.player
	if player == null or _busy:
		return
	var pos := player.global_position
	if _centre != Vector3.ZERO and pos.distance_to(_centre) < MOVE_REBUILD:
		return
	_centre = pos
	_busy = true
	_gen += 1
	var job_gen := _gen
	var dir := pos.normalized()
	var town_c: Vector3 = world.town.centre if world.town else Vector3.ZERO
	var gen: PlanetGen = world.gen
	var params := {"n": int(max_instances * float(look.density)), "sprig_n": int(max_instances * float(look.sprig_density))}
	_task = WorkerThreadPool.add_task(func(): _build(job_gen, dir, town_c, gen, params))


func _exit_tree() -> void:
	# never leave a worker running against a planet that's being torn down
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Runs on a worker thread: touches only its arguments (the generator is
## reference-counted and never mutated after creation).
func _build(job_gen: int, dir: Vector3, town_c: Vector3, gen: PlanetGen, params: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(dir * 4000.0))
	var b := PlanetGen.align_basis(dir)
	var grass := []
	var sprigs := []
	var n: int = params.n
	var sprig_n: int = params.sprig_n
	var sea := gen.sea + 0.003 if gen.has_liquid() else -1.0
	for i in n + sprig_n:
		var rr := RADIUS * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var d := (dir + (b.x * cos(a) + b.z * sin(a)) * rr / gen.radius).normalized()
		var hgt := gen.height(d)
		if hgt < sea:
			continue
		var d2 := (d + b.x * 0.4 / gen.radius).normalized()
		if absf(gen.height(d2) - hgt) * gen.radius / 0.4 > 0.55:
			continue # too steep
		var p := d * gen.radius * (1.0 + hgt) - d * 0.04
		if town_c != Vector3.ZERO and p.distance_to(town_c) < 17.0:
			continue
		var edge := 1.0 - smoothstep(RADIUS * 0.75, RADIUS, rr)
		var s := rng.randf_range(0.7, 1.3) * (0.35 + 0.65 * edge)
		var xf := Transform3D(PlanetGen.align_basis(d, rng.randf() * TAU).scaled(Vector3.ONE * s), p)
		if i < n:
			grass.append(xf)
		else:
			sprigs.append(xf)
	_apply.call_deferred(job_gen, grass, sprigs)


func _apply(job_gen: int, grass: Array, sprigs: Array) -> void:
	_busy = false
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if job_gen != _gen or not is_inside_tree():
		return
	_fill(_grass, grass)
	if _sprigs:
		_fill(_sprigs, sprigs)


func _fill(mmi: MultiMeshInstance3D, xforms: Array) -> void:
	var mm := mmi.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
