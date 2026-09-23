class_name PlanetGen
extends RefCounted
## Procedural spherical planet. Height is a pure function of direction, so the
## walkable surface, the orbital model seen from space and the object scatter
## all agree for a given seed.

var data: Dictionary
var biome: Dictionary
var radius: float
var sea: float # normalised height of sea level (or -1 for none)
var amp: float
var ridge_amp: float
var _noise := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _patch := FastNoiseLite.new()
var craters: Array = [] # [dir, cos_outer, radius_rad, depth]


func _init(planet: Dictionary) -> void:
	data = planet
	biome = Db.BIOMES[planet.biome]
	radius = planet.radius
	sea = biome.sea
	amp = biome.amp
	ridge_amp = biome.ridge
	var s: int = planet.seed
	_noise.seed = s
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.1
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_ridge.seed = s + 1
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.frequency = 1.8
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 3
	_detail.seed = s + 2
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 9.0
	_patch.seed = s + 3
	_patch.frequency = 3.0
	_make_craters(s)


const CRATER_COUNT := {"dune": 9, "ember": 7, "frost": 6, "prism": 4, "verdant": 3, "bloom": 2}


func _make_craters(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s + 17
	for i in CRATER_COUNT.get(data.biome, 3):
		var z := rng.randf_range(-1.0, 1.0)
		var a := rng.randf() * TAU
		var r := sqrt(1.0 - z * z)
		var d := Vector3(r * cos(a), z, r * sin(a))
		# keep the home outpost area crater-free
		if data.key == "0:0" and d.dot(Vector3(0, 0.25, 1).normalized()) > 0.85:
			continue
		var rad := rng.randf_range(0.05, 0.13)
		craters.append([d, cos(rad * 1.5), rad, rng.randf_range(0.012, 0.026)])


## Bowl with a raised rim. Returns the height offset contributed by craters.
func _crater_height(dir: Vector3) -> float:
	var h := 0.0
	for c in craters:
		var dd: float = dir.dot(c[0])
		if dd < c[1]:
			continue
		var x: float = acos(clampf(dd, -1.0, 1.0)) / c[2]
		if x < 1.0:
			h -= c[3] * (1.0 - x * x)
		h += c[3] * 0.45 * exp(-pow((x - 1.0) / 0.22, 2.0))
	return h


## Normalised height offset for a unit direction (surface = radius * (1 + h)).
func height(dir: Vector3) -> float:
	var n := _noise.get_noise_3dv(dir)
	var h := n * amp
	var r := _ridge.get_noise_3dv(dir) # -1..1 ridged
	var mountain_mask := smoothstep(0.05, 0.4, n)
	h += maxf(0.0, r) * ridge_amp * mountain_mask
	h += _detail.get_noise_3dv(dir) * amp * 0.08
	if not craters.is_empty():
		h += _crater_height(dir)
	# flatten ocean floors a bit, create beaches
	if sea > -0.5 and h < sea:
		h = sea + (h - sea) * 0.6
	return h


func surface_radius(dir: Vector3) -> float:
	return radius * (1.0 + height(dir))


func surface_point(dir: Vector3) -> Vector3:
	return dir * surface_radius(dir)


func sea_radius() -> float:
	return radius * (1.0 + sea) if sea > -0.5 else 0.0


func has_liquid() -> bool:
	return sea > -0.5


## Finite-difference surface normal (seamless across cube faces).
func normal_at(dir: Vector3, eps := 0.004) -> Vector3:
	var t1 := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var t2 := dir.cross(t1).normalized()
	var p0 := surface_point(dir)
	var p1 := surface_point((dir + t1 * eps).normalized())
	var p2 := surface_point((dir + t2 * eps).normalized())
	var n := (p1 - p0).cross(p2 - p0).normalized()
	if n.dot(dir) < 0.0:
		n = -n
	return n


func color_at(dir: Vector3, h: float, slope: float) -> Color:
	var c: Dictionary = biome.colors
	var col: Color
	var s := sea if sea > -0.5 else -0.02
	if h < s - 0.004:
		col = c.deep
	elif h < s + 0.004:
		col = c.beach
	else:
		var t := clampf((h - s) / (amp * 1.6 + ridge_amp), 0.0, 1.0)
		if t < 0.35:
			col = c.low.lerp(c.mid, t / 0.35)
		elif t < 0.7:
			col = c.mid.lerp(c.high, (t - 0.35) / 0.35)
		else:
			col = c.high.lerp(c.peak, clampf((t - 0.7) / 0.2, 0.0, 1.0))
	# steep slopes show rock
	col = col.lerp(c.rock, smoothstep(0.12, 0.35, slope))
	# polar caps (ice, or pale ash on volcanic worlds, bleached sand on deserts)
	var lat := absf(dir.y) + _patch.get_noise_3dv(dir * 2.0) * 0.08
	if h > s - 0.004:
		var cap: Color = {"ember": Color("6b6466"), "dune": Color("f3e3c3")}.get(data.biome, Color("f2f7ff"))
		col = col.lerp(cap, smoothstep(0.8, 0.88, lat) * 0.9)
	# soft Spore-like colour patches
	var p := _patch.get_noise_3dv(dir)
	col = col.lightened(maxf(0.0, p) * 0.12).darkened(maxf(0.0, -p) * 0.1)
	return col


## Cube-sphere mesh. `res` = quads per cube-face edge. `scale` shrinks the
## result (used for the orbital model in space).
func build_mesh(res: int, scale := 1.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var faces := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for f in faces:
		var axis_a := Vector3(f.y, f.z, f.x)
		var axis_b: Vector3 = f.cross(axis_a)
		var base := verts.size()
		for y in res + 1:
			for x in res + 1:
				var px := float(x) / res * 2.0 - 1.0
				var py := float(y) / res * 2.0 - 1.0
				var cube: Vector3 = f + axis_a * px + axis_b * py
				var dir := _cube_to_sphere(cube)
				var h := height(dir)
				var p := dir * radius * (1.0 + h)
				var n := normal_at(dir)
				var slope := 1.0 - n.dot(dir)
				verts.append(p * scale)
				normals.append(n)
				colors.append(color_at(dir, h, slope))
		for y in res:
			for x in res:
				var i := base + y * (res + 1) + x
				indices.append_array([i, i + res + 1, i + 1, i + 1, i + res + 1, i + res + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _cube_to_sphere(p: Vector3) -> Vector3:
	# equal-area-ish mapping, smoother than plain normalize
	var x2 := p.x * p.x
	var y2 := p.y * p.y
	var z2 := p.z * p.z
	return Vector3(
		p.x * sqrt(1.0 - y2 / 2.0 - z2 / 2.0 + y2 * z2 / 3.0),
		p.y * sqrt(1.0 - z2 / 2.0 - x2 / 2.0 + z2 * x2 / 3.0),
		p.z * sqrt(1.0 - x2 / 2.0 - y2 / 2.0 + x2 * y2 / 3.0)
	).normalized()


func terrain_material() -> Material:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	return m


## Orthonormal basis whose Y axis is `up`, rotated `yaw` radians around it.
static func align_basis(up: Vector3, yaw := 0.0) -> Basis:
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var z := ref.cross(up).normalized()
	var x := up.cross(z).normalized()
	var b := Basis(x, up, z)
	if yaw != 0.0:
		b = Basis(up, yaw) * b
	return b.orthonormalized()



## Nearest flat, dry spot to `start` (deterministic).
func find_land(start: Vector3) -> Vector3:
	var d := start.normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.seed) + 5
	var s := sea if has_liquid() else -1.0
	for i in 400:
		var h := height(d)
		var slope := 1.0 - normal_at(d).dot(d)
		if h > s + 0.008 and slope < 0.1:
			return d
		var jitter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * (0.02 + i * 0.004)
		d = (start.normalized() + jitter).normalized()
	return start.normalized()


const HOME_DIR := Vector3(0.0, 0.25, 1.0)


## Where this planet's trade hub sits (ZERO if it has none).
func town_dir() -> Vector3:
	var town: Dictionary = data.get("town", {})
	if town.is_empty():
		return Vector3.ZERO
	if data.key == "0:0":
		return find_land(HOME_DIR)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(town.seed) + 3
	var z := rng.randf_range(-0.7, 0.7)
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return find_land(Vector3(r * cos(a), z, r * sin(a)))
