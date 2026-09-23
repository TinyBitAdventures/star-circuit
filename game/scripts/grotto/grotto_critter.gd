class_name GrottoCritter
extends Node3D
## Glowing cave fauna that pads around the chamber floor.

var world: Node3D
var species_key := ""
var species_name := ""
var _heading := Vector3.FORWARD
var _speed := 1.4
var _t := 0.0
var _model: Node3D


func setup(w: Node3D, col: Color, key: String, sname: String, size: float) -> void:
	world = w
	species_key = key
	species_name = sname
	_model = ModelUtil.instance("res://assets/models/fauna_critter.glb")
	add_child(_model)
	ModelUtil.tint(_model, "Foliage", col)
	ModelUtil.add_rim(_model, 0.8, 0.9)
	scale = Vector3.ONE * size
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = 3.0
	l.light_energy = 1.2
	l.position.y = 1.0
	add_child(l)
	_heading = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	var p: Node3D = world.player
	if p and global_position.distance_to(p.global_position) < 4.0:
		var away := global_position - p.global_position
		away.y = 0.0
		_heading = _heading.slerp(away.normalized(), clampf(delta * 4.0, 0.0, 1.0))
	else:
		_heading = _heading.rotated(Vector3.UP, sin(_t * 0.7) * delta)
	var nxt := global_position + _heading * _speed * delta
	nxt.y = 0.0
	if Vector2(nxt.x, nxt.z).length() > world.ROOM_R - 4.0:
		_heading = -Vector3(nxt.x, 0, nxt.z).normalized()
	else:
		global_position = nxt
	_model.position.y = absf(sin(_t * 6.0)) * 0.3
	look_at(global_position + _heading, Vector3.UP)
