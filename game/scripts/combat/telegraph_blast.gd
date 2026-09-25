class_name TelegraphBlast
extends Node3D
## A warned area attack: a ring (or a lane) glows on the ground, then goes off,
## hurting and knocking back the player if they're still inside it.

var world: Node3D
var damage := 10.0
var effect := ""
var knock := 7.0
var color := Color(1, 0.3, 0.1)
var _delay := 1.0
var _shape := "ring"
var _dir := Vector3.UP # ring centre / lane start (unit)
var _heading := Vector3.ZERO
var _radius := 4.0 # ring radius / lane half-width
var _length := 0.0
var _mark: MeshInstance3D


static func ring(w: Node3D, center_dir: Vector3, r: float, delay: float, dmg: float, col := Color(1.0, 0.3, 0.1), fx := "") -> TelegraphBlast:
	var b := TelegraphBlast.new()
	b.world = w
	b._dir = center_dir.normalized()
	b._radius = r
	b._delay = delay
	b.damage = dmg
	b.color = col
	b.effect = fx
	w.add_child(b)
	b._mark = CombatFx.ground_ring(w, w.gen.surface_point(b._dir), b._dir, r, Color(col.r, col.g, col.b, 0.35), delay)
	return b


static func lane(w: Node3D, start_dir: Vector3, heading: Vector3, length: float, width: float, delay: float, dmg: float, col := Color(1.0, 0.75, 0.1)) -> TelegraphBlast:
	var b := TelegraphBlast.new()
	b.world = w
	b._shape = "lane"
	b._dir = start_dir.normalized()
	b._heading = heading
	b._length = length
	b._radius = width * 0.5
	b._delay = delay
	b.damage = dmg
	b.color = col
	w.add_child(b)
	b._mark = CombatFx.ground_lane(w, b._dir, heading, length, width, Color(col.r, col.g, col.b, 0.35), delay)
	return b


func _physics_process(delta: float) -> void:
	_delay -= delta
	if _delay > 0.0:
		return
	set_physics_process(false)
	if is_instance_valid(_mark):
		_mark.queue_free()
	var p: Node3D = world.player
	var inside := false
	if p and not p.dead:
		inside = _contains(p.global_position.normalized())
	if _shape == "ring":
		var c: Vector3 = world.gen.surface_point(_dir)
		world.shockwave(c, _radius, color)
		Sound.play_3d("slam", c, -2.0, 0.08, 30.0)
	else:
		_lane_fx()
	if inside:
		world.damage_player(damage, null, effect, 3.0, 2.0 if effect == "chill" else damage * 0.2)
		var away: Vector3 = (p.global_position - world.gen.surface_point(_dir)).normalized() if _shape == "ring" else _side_of(p.global_position)
		p.knockback(away * knock + p.global_basis.y * knock * 0.6)
	queue_free()


## Is a point (unit direction) inside the ring or lane?
func _contains(d: Vector3) -> bool:
	var r: float = world.gen.radius
	if _shape == "ring":
		return _dir.angle_to(d) * r < _radius + 0.4
	var fwd := (_heading - _dir * _heading.dot(_dir)).normalized()
	var axis := _dir.cross(fwd).normalized()
	# distance across the lane = angle to the lane's great circle; along = angle from the start
	var across := absf(asin(clampf(d.dot(axis), -1.0, 1.0))) * r
	var flat := (d - axis * d.dot(axis)).normalized()
	var along := _dir.signed_angle_to(flat, axis) * r
	return across < _radius + 0.4 and along > -1.0 and along < _length + 1.0


func _side_of(pos: Vector3) -> Vector3:
	var fwd := (_heading - _dir * _heading.dot(_dir)).normalized()
	var axis := _dir.cross(fwd).normalized()
	return axis if pos.normalized().dot(axis) > 0.0 else -axis


func _lane_fx() -> void:
	var fwd := (_heading - _dir * _heading.dot(_dir)).normalized()
	var axis := _dir.cross(fwd).normalized()
	for i in 6:
		var d := _dir.rotated(axis, (_length * (i + 0.5) / 6.0) / world.gen.radius)
		world.explosion(world.gen.surface_point(d) + d * 0.5, color, 1.0)
	Sound.play_3d("slam", world.gen.surface_point(_dir.rotated(axis, _length * 0.5 / world.gen.radius)), -2.0, 0.08, 30.0)


func _exit_tree() -> void:
	if is_instance_valid(_mark):
		_mark.queue_free()
