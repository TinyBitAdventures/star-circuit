class_name SkyStrike
extends Node3D
## A lightning strike called down on a spot: a ring warns, then a bolt from the
## sky hits everything inside it and shocks the player.

var world: Node3D
var damage := 10.0
var radius := 2.4
var _delay := 1.1
var _dir := Vector3.UP
var _pos := Vector3.ZERO
var _ring: MeshInstance3D


static func call_down(w: Node3D, dir: Vector3, dmg: float, r: float, delay: float) -> SkyStrike:
	var s := SkyStrike.new()
	s.world = w
	s.damage = dmg
	s.radius = r
	s._delay = delay
	s._dir = dir.normalized()
	s._pos = w.gen.surface_point(s._dir)
	w.add_child(s)
	s.global_position = s._pos
	s._ring = CombatFx.ground_ring(w, s._pos, s._dir, r, Color(0.7, 0.6, 1.0, 0.35), delay)
	return s


func _physics_process(delta: float) -> void:
	_delay -= delta
	if _delay > 0.0:
		return
	if is_instance_valid(_ring):
		_ring.queue_free()
	_bolt()
	var p: Node3D = world.player
	if p and not p.dead and p.global_position.distance_to(_pos) < radius + 0.3:
		world.damage_player(damage, null, "shock", 3.0)
	world.shockwave(_pos, radius, Color(0.75, 0.65, 1.0))
	Sound.play_3d("thunder", _pos, 0.0, 0.1, 30.0)
	world.shake_near(_pos, 0.5)
	set_physics_process(false)
	get_tree().create_timer(0.25).timeout.connect(queue_free)


func _bolt() -> void:
	# a jagged column of short bright segments from 40 m up to the ground
	var top := _pos + _dir * 40.0
	var b := PlanetGen.align_basis(_dir)
	var prev := top
	for i in range(1, 9):
		var k := float(i) / 8.0
		var next := top.lerp(_pos, k)
		if i < 8:
			next += (b.x * randf_range(-1, 1) + b.z * randf_range(-1, 1)) * 1.2
		CombatFx.tracer(world, prev, next, Color(0.8, 0.75, 1.0) * 2.5)
		prev = next
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 0.75, 1.0)
	light.omni_range = 18.0
	light.light_energy = 6.0
	world.add_child(light)
	light.global_position = _pos + _dir * 3.0
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.3)
	get_tree().create_timer(0.35).timeout.connect(light.queue_free)


func _exit_tree() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
