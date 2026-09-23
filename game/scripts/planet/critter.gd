class_name Critter
extends Node3D
## Wandering alien fauna. Hops around the planet surface and shies away from
## the player.

var world: Node3D
var dir := Vector3.UP # position on the sphere (unit)
var heading := Vector3.FORWARD
var species_key := ""
var species_name := ""
var _speed := 2.0
var _turn := 0.0
var _t := 0.0
var _model: Node3D
var _size := 1.0
var _chirp_t := 0.0
var _voice := 1
var _fleeing := false


func setup(w: Node3D, start_dir: Vector3, color: Color, key: String, sname: String, size: float) -> void:
	world = w
	dir = start_dir.normalized()
	species_key = key
	species_name = sname
	_size = size
	_model = ModelUtil.instance("res://assets/models/fauna_critter.glb")
	add_child(_model)
	ModelUtil.tint(_model, "Foliage", color)
	ModelUtil.add_rim(_model, 0.45, 0.6)
	scale = Vector3.ONE * size
	heading = PlanetGen.align_basis(dir, randf() * TAU).z
	_t = randf() * 10.0
	_speed = randf_range(1.5, 3.0)
	_chirp_t = randf_range(3.0, 12.0)
	_voice = 1 + (hash(key) % 3 + 3) % 3


func _process(delta: float) -> void:
	_t += delta
	var gen: PlanetGen = world.gen
	var pos := global_position
	var player: Node3D = world.player
	var flee := false
	if player and pos.distance_to(player.global_position) < 7.0:
		if not _fleeing:
			_fleeing = true
			Sound.play_3d("chirp_%d" % _voice, pos, -4.0, 0.2, 8.0)
		var away := (pos - player.global_position)
		away = (away - dir * away.dot(dir)).normalized()
		heading = heading.slerp(away, clampf(delta * 4.0, 0.0, 1.0))
		flee = true
	else:
		_fleeing = false
		_turn += randf_range(-1.0, 1.0) * delta * 2.0
		_turn = clampf(_turn, -0.8, 0.8)
		heading = heading.rotated(dir, _turn * delta)
	_chirp_t -= delta
	if _chirp_t <= 0.0:
		_chirp_t = randf_range(6.0, 16.0)
		if player and pos.distance_to(player.global_position) < 35.0:
			Sound.play_3d("chirp_%d" % _voice, pos, -8.0, 0.15, 8.0)
	var spd := _speed * (2.4 if flee else 1.0)
	var arc := spd * delta / gen.radius
	var next := (dir + heading * arc).normalized()
	if gen.has_liquid() and gen.height(next) < gen.sea + 0.002:
		heading = -heading
	else:
		dir = next
	heading = (heading - dir * heading.dot(dir)).normalized()
	var hop := absf(sin(_t * (9.0 if flee else 6.0))) * 0.5 * _size
	global_position = gen.surface_point(dir) + dir * hop
	var back := -heading
	global_basis = Basis(dir.cross(back).normalized(), dir, back).orthonormalized().scaled(Vector3.ONE * _size)
