class_name Turret
extends Node3D
## Engineer ability: an auto-turret that shoots the nearest rogue drone.

const RANGE := 24.0
const LIFE := 15.0
const RATE := 0.45

var world: Node3D
var _life := LIFE
var _cd := 0.0
var _head: Node3D
var _up := Vector3.UP


func setup(w: Node3D, dir: Vector3) -> void:
	world = w
	_up = dir.normalized()
	var m := ModelUtil.instance("res://assets/models/prop_turret.glb")
	add_child(m)
	_head = m.find_child("Head", true, false)
	w.add_child(self)
	global_transform = Transform3D(PlanetGen.align_basis(_up), w.gen.surface_point(_up) - _up * 0.1)
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _physics_process(delta: float) -> void:
	_life -= delta
	_cd -= delta
	if _life <= 0.0:
		set_physics_process(false)
		world.explosion(global_position + _up, Color("ff9bf0"), 0.8)
		queue_free()
		return
	if _cd > 0.0:
		return
	var best: Enemy = null
	var best_d := RANGE
	for e in world.enemies:
		if e.is_alive() and e.state != "return":
			var d: float = e.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = e
	if best == null:
		return
	_cd = RATE
	var muzzle := global_position + _up * 1.0
	var target := best.global_position + best.global_basis.y * 1.2
	if _head:
		_head.look_at(target, _up)
	world.tracer(muzzle, target, Color("ff9bf0"))
	Sound.play_3d("turret_shot", muzzle, -10.0)
	best.take_hit(Game.weapon_damage() * 0.45)
