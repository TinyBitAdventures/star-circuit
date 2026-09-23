class_name SeaDiver
extends Node2D
## The robot swimming in the Deep Sea: free 8-way movement with drag and a
## little negative buoyancy, a boost, and a cutter that drills rock it's
## pushing into. Drawn procedurally in the robot's paint colours.

const HALF := Vector2(11, 11)
const ACCEL := 520.0
const MAX_SPEED := 150.0
const BOOST_SPEED := 270.0
const DRAG := 2.2
const SINK := 14.0

var world: Node2D
var velocity := Vector2.ZERO
var dead := false
var dig_progress := 0.0
var dig_msg := ""
var boosting := false
var _dig_target := Vector2i(-99, -99)
var _dig_dir := Vector2i(1, 0)
var _drilling := false
var _facing := 1.0
var _t := 0.0
var _lamp: PointLight2D
var _aura: PointLight2D
var _cam: Camera2D
var _bubbles: CPUParticles2D
var _shell := Color.WHITE
var _accent := Color.WHITE
var _glow := Color.WHITE
var _shake := 0.0
var knock := Vector2.ZERO


func _ready() -> void:
	_shell = Color(Game.appearance.shell) if Game.appearance.has("shell") else Color("e6e8ec")
	_accent = Color(Game.appearance.accent) if Game.appearance.has("accent") else Game.robot().color
	_glow = Color(Game.appearance.glow) if Game.appearance.has("glow") else Color("5ff7ff")
	_cam = Camera2D.new()
	_cam.zoom = Vector2(1.25, 1.25)
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 6.0
	_cam.limit_left = -160
	_cam.limit_right = world.W * world.CS + 160
	_cam.limit_top = -world.CS * 8
	_cam.limit_bottom = world.H * world.CS + 60
	add_child(_cam)
	_cam.make_current()
	_lamp = PointLight2D.new()
	_lamp.texture = world.light_tex()
	_lamp.texture_scale = 4.0
	_lamp.energy = 1.2
	_lamp.color = Color(0.85, 0.97, 1.0)
	add_child(_lamp)
	_aura = PointLight2D.new()
	var aura := _aura
	aura.texture = world.light_tex()
	aura.texture_scale = 8.0
	aura.energy = 0.3
	aura.color = _glow.lerp(Color.WHITE, 0.5)
	add_child(aura)
	_bubbles = CPUParticles2D.new()
	_bubbles.amount = 18
	_bubbles.lifetime = 1.6
	_bubbles.direction = Vector2(0, -1)
	_bubbles.spread = 30.0
	_bubbles.initial_velocity_min = 20.0
	_bubbles.initial_velocity_max = 50.0
	_bubbles.gravity = Vector2(0, -40)
	_bubbles.scale_amount_min = 1.5
	_bubbles.scale_amount_max = 3.5
	_bubbles.color = Color(0.85, 0.97, 1.0, 0.55)
	_bubbles.local_coords = false
	var bm := CanvasItemMaterial.new()
	bm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_bubbles.material = bm
	add_child(_bubbles)
	z_index = 5


func _physics_process(delta: float) -> void:
	_t += delta
	if dead:
		visible = false
		return
	visible = true
	var ui := Game.ui_open
	var input := Vector2.ZERO
	if not ui:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_pressed("jump"):
			input.y = -1.0
		if Input.is_action_pressed("descend"):
			input.y = 1.0
	if input.x != 0.0:
		_facing = signf(input.x)
	boosting = not ui and Input.is_action_pressed("sprint") and input.length() > 0.1 and Game.energy > 1.0
	if boosting:
		Game.drain_energy(6.0 * delta)
	var top := BOOST_SPEED if boosting else MAX_SPEED
	velocity += input.normalized() * ACCEL * (1.5 if boosting else 1.0) * delta
	velocity.y += SINK * delta
	velocity -= velocity * DRAG * delta
	if velocity.length() > top:
		velocity = velocity.normalized() * top
	velocity += knock
	knock = knock.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	# the surface is a ceiling
	var push := Vector2i.ZERO
	position.x += velocity.x * delta
	if _collides():
		position.x -= velocity.x * delta
		if input.x != 0.0:
			push.x = int(signf(input.x))
		velocity.x = 0.0
	position.y += velocity.y * delta
	if _collides():
		position.y -= velocity.y * delta
		if input.y != 0.0:
			push.y = int(signf(input.y))
		velocity.y = 0.0
	var surf_y: float = world.SURF * world.CS + HALF.y
	if position.y < surf_y:
		position.y = surf_y
		velocity.y = maxf(velocity.y, 0.0)
	var want := Vector2i.ZERO
	if push.x != 0:
		want = Vector2i(push.x, 0)
	elif push.y != 0:
		want = Vector2i(0, push.y)
	_update_drill(want, delta)
	_bubbles.emitting = true
	_bubbles.amount = 18
	_bubbles.position = Vector2(-_facing * 12.0, 2)
	_shake = maxf(0.0, _shake - delta * 1.5)
	_cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * _shake * 12.0
	_lamp.position = Vector2(_facing * 14.0, 0)
	queue_redraw()


func _collides() -> bool:
	var a: Vector2i = world.cell_at(position - HALF)
	var b: Vector2i = world.cell_at(position + HALF - Vector2(0.01, 0.01))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if world.is_solid(x, y):
				return true
	return false


func _update_drill(want: Vector2i, delta: float) -> void:
	dig_msg = ""
	if want == Vector2i.ZERO:
		_stop_drill()
		return
	_dig_dir = want
	var target: Vector2i = world.cell_at(position) + want
	if not world.is_solid(target.x, target.y):
		_stop_drill()
		return
	var why: String = world.dig_block_reason(target)
	if why != "":
		dig_msg = why
		_stop_drill()
		return
	if target != _dig_target:
		_dig_target = target
		dig_progress = 0.0
	var h: float = world.hardness(target)
	var speed := Game.harvest_speed("mining") * (1.0 + Game.skill_level("mining") * 0.008)
	if Game.energy < 1.0:
		speed *= 0.3
		dig_msg = "Running on reserves: cutter at 30%."
	dig_progress += delta * speed / maxf(h, 0.05)
	_shake = maxf(_shake, 0.1)
	if not _drilling:
		_drilling = true
		Sound.loop_start("dig", "drill_loop", -10.0)
	if dig_progress >= 1.0:
		dig_progress = 0.0
		_dig_target = Vector2i(-99, -99)
		world.dig_out(target)


func _stop_drill() -> void:
	dig_progress = 0.0
	_dig_target = Vector2i(-99, -99)
	if _drilling:
		_drilling = false
		Sound.loop_stop("dig", 0.1)


## Lamps matter in the dark and would only wash out the bright shallows.
func set_light(dark: float) -> void:
	_lamp.energy = lerpf(0.15, 1.2, dark)
	_aura.energy = lerpf(0.05, 0.3, dark)


func hurt(amount: float, from: Vector2) -> void:
	if dead:
		return
	Game.take_damage(amount)
	knock = (position - from).normalized() * 220.0
	_shake = 0.5


func _draw() -> void:
	var o := Vector2(0, sin(_t * 3.0) * 1.5)
	var f := _facing
	# body tilts into the swim
	var tilt := clampf(velocity.x / BOOST_SPEED, -1.0, 1.0) * 0.25 + clampf(velocity.y / BOOST_SPEED, -1.0, 1.0) * 0.2 * f
	draw_set_transform(o, tilt, Vector2.ONE)
	# propeller at the back
	var pp := Vector2(-f * 15.0, 2)
	var spin := sin(_t * (40.0 if velocity.length() > 20.0 else 8.0))
	draw_line(pp + Vector2(0, -7 * spin), pp + Vector2(0, 7 * spin), Color("9aa3b0"), 3.0)
	draw_circle(pp, 2.5, Color("2a2f3a"))
	# torso
	draw_rect(Rect2(Vector2(-12, -8), Vector2(24, 16)), _shell)
	draw_circle(Vector2(f * 6.0, -9), 9.0, _shell)
	draw_rect(Rect2(Vector2(-12, 1), Vector2(24, 4)), _accent)
	# visor
	draw_rect(Rect2(Vector2(f * 6.0 - 6.0, -13), Vector2(12, 6)), Color("1b1f29"))
	draw_rect(Rect2(Vector2(f * 6.0 - 4.0, -12), Vector2(8, 4)), _glow)
	# arms stroking / cutter arm when drilling
	if _drilling:
		var d := Vector2(_dig_dir)
		var tip := d * 24.0
		draw_line(Vector2.ZERO, tip, Color("c9ced6"), 4.0)
		draw_circle(tip, 4.0 + sin(_t * 50.0), Color(1.0, 0.7, 0.3))
	else:
		var st := sin(_t * 6.0)
		draw_line(Vector2(0, 2), Vector2(f * (10.0 + st * 4.0), 10.0 + st * 3.0), _accent.darkened(0.2), 4.0)
		draw_line(Vector2(0, 2), Vector2(-f * (4.0 - st * 4.0), 12.0 - st * 3.0), _accent.darkened(0.35), 4.0)
	# legs kick behind
	var k := sin(_t * 8.0) * 4.0
	draw_line(Vector2(-f * 6.0, 7), Vector2(-f * 16.0, 10 + k), Color("2a2f3a"), 4.0)
	draw_line(Vector2(-f * 2.0, 7), Vector2(-f * 14.0, 13 - k), Color("2a2f3a"), 4.0)
	# antenna light
	draw_line(Vector2(f * 8.0, -17), Vector2(f * 11.0, -24), Color("2a2f3a"), 2.0)
	draw_circle(Vector2(f * 11.0, -25), 2.5, _glow)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# drill crack on the target cell
	if dig_progress > 0.0 and _dig_target != Vector2i(-99, -99):
		var cc: Vector2 = world.cell_centre(_dig_target) - position
		var s: float = world.CS * 0.5 * dig_progress
		draw_line(cc - Vector2(s, s * 0.4), cc + Vector2(s, s * 0.4), Color(0, 0, 0, 0.6), 2.0)
		draw_line(cc - Vector2(s * 0.3, s), cc + Vector2(s * 0.5, s), Color(0, 0, 0, 0.6), 2.0)
