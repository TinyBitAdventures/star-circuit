class_name Globe
extends RefCounted
## Illustrated planet globes for the views where a whole world is on screen
## (title screen, space, sister worlds in the sky). The planet's real height
## and colours are baked once into a small equirectangular texture; the globe
## shader then draws crisp inked coastlines, shallow-water bands, contour
## lines and cel lighting per pixel, so it stays sharp at any size.
## Settings > Display > Planets switches back to the Classic terrain mesh.

const TEX_W := 320
const TEX_H := 160
const HEIGHT_SCALE := 5.0 # texture alpha = 0.5 + (h - sea) * HEIGHT_SCALE
const CACHE_VERSION := 1

static var _cache := {}


static func enabled() -> bool:
	return Sound.globe_style == 0


## Height + colour texture for a planet, cached in memory and on disk.
static func texture(gen: PlanetGen) -> ImageTexture:
	var key: String = str(gen.data.key)
	if _cache.has(key):
		return _cache[key]
	var path := "user://globes/%s_v%d.png" % [key.replace(":", "_"), CACHE_VERSION]
	var img: Image
	if FileAccess.file_exists(path):
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.get_width() != TEX_W:
		var t0 := Time.get_ticks_msec()
		img = bake(gen)
		if Game.is_dev_run():
			print("[globe] baked %s (%s) in %d ms" % [key, gen.data.biome, Time.get_ticks_msec() - t0])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://globes"))
		img.save_png(path)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func bake(gen: PlanetGen) -> Image:
	var heights := PackedFloat32Array()
	heights.resize(TEX_W * TEX_H)
	var dirs: Array[Vector3] = []
	dirs.resize(TEX_W * TEX_H)
	for y in TEX_H:
		var theta := (y + 0.5) / TEX_H * PI
		for x in TEX_W:
			var phi := ((x + 0.5) / TEX_W - 0.5) * TAU
			var d := Vector3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
			var i := y * TEX_W + x
			dirs[i] = d
			heights[i] = gen.height(d)
	var sea := gen.sea if gen.has_liquid() else -0.02
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	var step_x := TAU / TEX_W
	var step_y := PI / TEX_H
	for y in TEX_H:
		var sin_t := maxf(sin((y + 0.5) / TEX_H * PI), 0.05)
		for x in TEX_W:
			var i := y * TEX_W + x
			var h := heights[i]
			# slope from the height gradient (per radian of surface)
			var hx := heights[y * TEX_W + (x + 1) % TEX_W] - heights[y * TEX_W + (x + TEX_W - 1) % TEX_W]
			var hy := heights[mini(y + 1, TEX_H - 1) * TEX_W + x] - heights[maxi(y - 1, 0) * TEX_W + x]
			var g := Vector2(hx / (2.0 * step_x * sin_t), hy / (2.0 * step_y)).length()
			var slope := 1.0 - 1.0 / sqrt(1.0 + g * g)
			var c := gen.color_at(dirs[i], h, slope)
			c.a = clampf(0.5 + (h - sea) * HEIGHT_SCALE, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return img


## A complete illustrated globe: surface, clouds and halo. `r` is the radius
## in the caller's units; `sun_dir` is the direction light arrives from, in world space.
static func build(gen: PlanetGen, r: float, sun_dir: Vector3, segments := 96, with_clouds := true) -> Node3D:
	var root := Node3D.new()
	var b: Dictionary = gen.biome
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segments
	sm.rings = segments / 2
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/globe.gdshader")
	m.set_shader_parameter("globe_tex", texture(gen))
	m.set_shader_parameter("has_sea", gen.has_liquid())
	m.set_shader_parameter("lava", b.get("lava", false))
	var wc: Color = b.water
	var deep: Color = b.colors.deep
	var water := Color(wc.r, wc.g, wc.b)
	m.set_shader_parameter("deep_color", deep.darkened(0.08))
	m.set_shader_parameter("shallow_color", water.lerp(b.colors.beach, 0.12))
	m.set_shader_parameter("foam_color", water.lightened(0.45))
	m.set_shader_parameter("ink_color", deep.darkened(0.72))
	m.set_shader_parameter("seed", float(int(gen.data.seed) % 97))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if with_clouds:
		var clouds := gen.cloud_shell(r * 1.035, maxi(segments, 48))
		var cm := clouds.material_override as ShaderMaterial
		cm.set_shader_parameter("sun_dir", sun_dir)
		cm.set_shader_parameter("stylized", true)
		root.add_child(clouds)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = r * 1.1
	am.height = am.radius * 2.0
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://shaders/atmo_rim.gdshader")
	amat.set_shader_parameter("color", b.atmo)
	amat.set_shader_parameter("stylized", true)
	atmo.material_override = amat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(atmo)
	return root
