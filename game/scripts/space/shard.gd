class_name OreShard
extends Node3D
## A floating chunk of ore spilled by a broken asteroid. Drifts, spins, and is
## pulled in by the ship's tractor field.

const LIFE := 75.0

var world: Node3D
var item := ""
var qty := 1
var velocity := Vector3.ZERO
var _life := LIFE
var _spin := Vector3.ZERO
var _model: Node3D


func setup(w: Node3D, it: String, q: int, pos: Vector3, vel: Vector3) -> void:
	world = w
	item = it
	qty = q
	velocity = vel
	_model = ModelUtil.instance("res://assets/models/ore_shard.glb")
	add_child(_model)
	var c := Db.item_color(it)
	ModelUtil.tint(_model, "Vein", c)
	_model.scale = Vector3.ONE * (0.9 + 0.25 * q)
	_spin = Vector3(randf(), randf(), randf()).normalized() * randf_range(1.0, 3.0)
	var light := OmniLight3D.new()
	light.light_color = c
	light.omni_range = 5.0
	light.light_energy = 1.4
	add_child(light)
	w.add_child(self)
	global_position = pos


func _process(delta: float) -> void:
	_life -= delta
	_model.rotate(_spin.normalized(), _spin.length() * delta)
	var player: Node3D = world.player
	if player and not player.dead:
		var to: Vector3 = player.global_position - global_position
		var d := to.length()
		var reach: float = 16.0 * (2.5 if Game.has_upgrade("tractor_beam") else 1.0)
		var room: bool = not Game.is_cargo(item) or Game.cargo_free() > 0
		if d < 2.8 and room:
			var got := Game.add_item(item, qty)
			if got > 0:
				Sound.play("pickup", -8.0, 0.1, "SFX", 0.05)
			qty -= got
			if qty <= 0:
				queue_free()
				return
		elif d < 2.8:
			Game._cargo_full_warning()
		if d < reach and room:
			velocity = velocity.lerp(to.normalized() * (30.0 + (reach - d) * 2.0), clampf(delta * 3.0, 0.0, 1.0))
	velocity = velocity.lerp(Vector3.ZERO, delta * 0.3)
	global_position += velocity * delta
	if _life < 5.0:
		_model.scale = Vector3.ONE * maxf(0.05, _life / 5.0)
	if _life <= 0.0:
		queue_free()
