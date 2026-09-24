class_name VolcanoRunner
extends Node2D
## The robot inside a volcano: runs, jumps, and fires short jetpack bursts
## (fuel refills on solid ground). No drilling here: the rock is too hot
## and hard, so you find your way through the tubes.

const HALF := Vector2(10, 14)
const SPEED := 200.0
const GRAVITY := 950.0
const JUMP := 430.0
const JET := 1500.0
const MAX_UP := 300.0
const MAX_FALL := 700.0

var world: Node2D
var velocity := Vector2.ZERO
var on_ground := false
var dead := false
var fuel := 1.0
var launched := 0.0 # geyser lift in progress
var _facing := 1.0
var _t := 0.0
var _jetting := false
var _cam: Camera2D
var _lamp: PointLight2D
var _flame: CPUParticles2D
var _shell := Color.WHITE
var _accent := Color.WHITE
var _glow := Color.WHITE
var shake := 0.0


func _ready() -> void:
	_shell = Color(Game.appearance.shell) if Game.appearance.has("shell") else Color("e6e8ec")
	_accent = Color(Game.appearance.accent) if Game.appearance.has("accent") else Game.robot().color
	_glow = Color(Game.appearance.glow) if Game.appearance.has("glow") else Color("5ff7ff")
	_cam = Camera2D.new()
	_cam.zoom = Vector2(1.15, 1.15)
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 6.0
	_cam.limit_left = -world.CS * 6
	_cam.limit_right = world.W * world.CS + world.CS * 6
	_cam.limit_top = -world.CS * 6
	_cam.limit_bottom = world.H * world.CS + world.CS * 2
	add_child(_cam)
	_cam.make_current()
	_lamp = PointLight2D.new()
	_lamp.texture = world.light_tex()
	_lamp.texture_scale = 3.6
	_lamp.energy = 1.0
	_lamp.color = Color(1.0, 0.95, 0.85)
	add_child(_lamp)
	_flame = CPUParticles2D.new()
	_flame.amount = 36
	_flame.lifetime = 0.3
	_flame.emitting = false
	_flame.direction = Vector2(0, 1)
	_flame.spread = 20.0
	_flame.initial_velocity_min = 150.0
	_flame.initial_velocity_max = 230.0
	_flame.gravity = Vector2.ZERO
	_flame.scale_amount_min = 3.0
	_flame.scale_amount_max = 5.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.set_color(1, Color(_glow.r, _glow.g, _glow.b, 0))
	_flame.color_ramp = g
	_flame.position = Vector2(-4, HALF.y - 2)
	var fm := CanvasItemMaterial.new()
	fm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	fm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flame.material = fm
	add_child(_flame)
	z_index = 6


func _physics_process(delta: float) -> void:
	_t += delta
	if dead:
		visible = false
		return
	visible = true
	var ui := Game.ui_open
	var ix := 0.0 if ui else Input.get_axis("move_left", "move_right")
	var jump_held := not ui and (Input.is_action_pressed("jump") or Input.is_action_pressed("move_forward"))
	var jump_pressed := not ui and (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_forward"))
	if ix != 0.0:
		_facing = signf(ix)
	var target := ix * SPEED
	velocity.x = move_toward(velocity.x, target, (1600.0 if on_ground else 900.0) * delta)
	velocity.y += GRAVITY * delta
	_jetting = false
	launched = maxf(0.0, launched - delta)
	if on_ground:
		fuel = minf(1.0, fuel + delta * 1.2)
		if jump_pressed:
			velocity.y = -JUMP
			on_ground = false
			Sound.play("jump", -10.0, 0.1)
	elif jump_held and fuel > 0.0 and velocity.y > -MAX_UP:
		velocity.y = maxf(velocity.y - JET * delta, -MAX_UP)
		fuel = maxf(0.0, fuel - delta * 0.55)
		Game.drain_energy(2.0 * delta)
		_jetting = true
	velocity.y = minf(velocity.y, MAX_FALL)
	_flame.emitting = _jetting
	if _jetting:
		Sound.loop_start("jet", "jet_loop", -12.0)
	else:
		Sound.loop_stop("jet", 0.2)
	var drilling := false
	position.x += velocity.x * delta
	if _collides():
		position.x -= velocity.x * delta
		velocity.x = 0.0
		# pushing into rock drills it: the tile level with the body, else the one at the feet
		if ix != 0.0 and not world._briefing:
			var mid: Vector2i = world.cell_at(position + Vector2(_facing * (HALF.x + 4.0), 0.0))
			var feet: Vector2i = world.cell_at(position + Vector2(_facing * (HALF.x + 4.0), HALF.y - 4.0))
			var tgt := mid if world.is_solid(mid.x, mid.y) else feet
			drilling = world.drill(tgt, delta) >= 0.0
	var vy := velocity.y
	position.y += vy * delta
	var was_ground := on_ground
	on_ground = false
	if _collides():
		position.y -= vy * delta
		if vy > 0.0:
			on_ground = true
			if vy > 620.0 and launched <= 0.0 and not world.ended:
				Game.take_damage((vy - 620.0) * 0.06)
				shake = 0.4
			if not was_ground and vy > 250.0:
				Sound.play("land", -12.0, 0.1)
		velocity.y = 0.0
	if not on_ground:
		position.y += 1.0
		on_ground = _collides()
		position.y -= 1.0
	# drill down (S) standing on rock, or up by jetting into a ceiling
	var down := not ui and Input.is_action_pressed("move_back")
	if not drilling and not world._briefing:
		if down and on_ground:
			drilling = world.drill(world.cell_at(position + Vector2(0.0, HALF.y + 4.0)), delta) >= 0.0
		elif _jetting and vy < 0.0 and velocity.y == 0.0:
			drilling = world.drill(world.cell_at(position - Vector2(0.0, HALF.y + 4.0)), delta) >= 0.0
	if not drilling:
		world.stop_drill()
	shake = maxf(0.0, shake - delta * 1.5)
	_cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (shake * shake * 16.0 + world.rumble * 3.0)
	_lamp.position = Vector2(_facing * 10.0, -4.0)
	if not ui:
		if Input.is_action_just_pressed("use_cell"):
			Game.use_energy_cell()
		if Input.is_action_just_pressed("repair"):
			Game.use_repair_kit()
	queue_redraw()


func launch(power: float) -> void:
	velocity.y = -power
	launched = 1.2
	on_ground = false
	fuel = 1.0


func _collides() -> bool:
	var a: Vector2i = world.cell_at(position - HALF)
	var b: Vector2i = world.cell_at(position + HALF - Vector2(0.01, 0.01))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if world.is_solid(x, y):
				return true
	return false


func _draw() -> void:
	var run := on_ground and absf(velocity.x) > 20.0
	var step := sin(_t * 14.0) if run else 0.0
	var f := _facing
	var o := Vector2(0, -abs(step) * 1.5)
	# legs
	draw_line(o + Vector2(-4, 6), o + Vector2(-4 + step * 5.0, 14), Color("2a2f3a"), 4.0)
	draw_line(o + Vector2(4, 6), o + Vector2(4 - step * 5.0, 14), Color("2a2f3a"), 4.0)
	# jetpack
	draw_rect(Rect2(o + Vector2(-f * 12.0 - 4.0, -8), Vector2(8, 13)), Color("3a3f4a"))
	# body
	draw_rect(Rect2(o + Vector2(-9, -8), Vector2(18, 15)), _shell)
	draw_rect(Rect2(o + Vector2(-9, 1), Vector2(18, 3)), _accent)
	# head + visor
	draw_circle(o + Vector2(f * 2.0, -14), 8.0, _shell)
	draw_rect(Rect2(o + Vector2(f * 5.0 - 5.0, -17), Vector2(10, 5)), Color("1b1f29"))
	draw_rect(Rect2(o + Vector2(f * 5.0 - 3.5, -16), Vector2(7, 3)), _glow)
	# arm swinging
	draw_line(o + Vector2(0, -3), o + Vector2(f * (6.0 + step * 4.0), 6), _accent.darkened(0.2), 3.0)
	# antenna
	draw_line(o + Vector2(-f * 3.0, -21), o + Vector2(-f * 5.0, -27), Color("2a2f3a"), 2.0)
	draw_circle(o + Vector2(-f * 5.0, -28), 2.0, _glow)
