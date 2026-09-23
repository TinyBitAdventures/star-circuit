class_name DigPod
extends Node2D
## The player's drill pod in the Deep: walks, thrusts, and drills in the
## direction it's pushing. Drawn procedurally in the robot's paint colours.

const HALF := Vector2(12, 13)
const SPEED := 170.0
const GRAVITY := 900.0
const THRUST := 1900.0
const MAX_UP := 260.0
const MAX_FALL := 620.0

var world: Node2D
var velocity := Vector2.ZERO
var on_ground := false
var dead := false
var dig_progress := 0.0
var dig_msg := ""
var _dig_target := Vector2i(-99, -99)
var _dig_dir := Vector2i(0, 1)
var _facing := 1.0
var _t := 0.0
var _flame: CPUParticles2D
var _lamp: PointLight2D
var _cam: Camera2D
var _shell := Color.WHITE
var _accent := Color.WHITE
var _glow := Color.WHITE
var _drilling := false
var _lava_warn := 0.0
var _shake := 0.0


func _ready() -> void:
	var r: Dictionary = Game.robot()
	_shell = Color(Game.appearance.shell) if Game.appearance.has("shell") else Color("e6e8ec")
	_accent = Color(Game.appearance.accent) if Game.appearance.has("accent") else r.color
	_glow = Color(Game.appearance.glow) if Game.appearance.has("glow") else Color("5ff7ff")
	_cam = Camera2D.new()
	_cam.zoom = Vector2(1.3, 1.3)
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 7.0
	_cam.limit_left = -200
	_cam.limit_right = world.W * world.CS + 200
	_cam.limit_bottom = world.H * world.CS + 100
	add_child(_cam)
	_cam.make_current()
	_lamp = PointLight2D.new()
	_lamp.texture = world._light_tex()
	_lamp.texture_scale = 3.4
	_lamp.energy = 1.35
	_lamp.color = Color(1.0, 0.95, 0.85)
	add_child(_lamp)
	var aura := PointLight2D.new()
	aura.texture = world._light_tex()
	aura.texture_scale = 9.0
	aura.energy = 0.35
	aura.color = _glow.lerp(Color.WHITE, 0.5)
	add_child(aura)
	_flame = CPUParticles2D.new()
	_flame.amount = 40
	_flame.lifetime = 0.35
	_flame.emitting = false
	_flame.direction = Vector2(0, 1)
	_flame.spread = 18.0
	_flame.initial_velocity_min = 140.0
	_flame.initial_velocity_max = 220.0
	_flame.gravity = Vector2.ZERO
	_flame.scale_amount_min = 3.0
	_flame.scale_amount_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.set_color(1, Color(_glow.r, _glow.g, _glow.b, 0))
	_flame.color_ramp = g
	_flame.position = Vector2(0, HALF.y)
	var fm := CanvasItemMaterial.new()
	fm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	fm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flame.material = fm
	add_child(_flame)
	z_index = 5


func _physics_process(delta: float) -> void:
	_t += delta
	if dead:
		visible = false
		return
	visible = true
	var ui := Game.ui_open
	var ix := 0.0 if ui else Input.get_axis("move_left", "move_right")
	var up_held := not ui and (Input.is_action_pressed("move_forward") or Input.is_action_pressed("jump"))
	var down_held := not ui and Input.is_action_pressed("move_back")
	if ix != 0.0:
		_facing = signf(ix)
	# horizontal
	var target_vx := ix * SPEED * (1.0 if on_ground else 0.8)
	velocity.x = move_toward(velocity.x, target_vx, (1400.0 if on_ground else 700.0) * delta)
	# vertical
	velocity.y += GRAVITY * delta
	var thrusting := up_held and Game.energy > 0.5
	if thrusting:
		velocity.y = maxf(velocity.y - THRUST * delta, -MAX_UP)
		Game.drain_energy(5.0 * delta)
	velocity.y = minf(velocity.y, MAX_FALL)
	_flame.emitting = thrusting
	# move + collide per axis
	var push := Vector2i.ZERO
	position.x += velocity.x * delta
	if _collides():
		position.x -= velocity.x * delta
		if ix != 0.0:
			push.x = int(signf(ix))
		velocity.x = 0.0
	var vy := velocity.y
	position.y += vy * delta
	on_ground = false
	if _collides():
		position.y -= vy * delta
		if vy > 0.0:
			on_ground = true
			if vy > 520.0:
				Game.take_damage((vy - 520.0) * 0.08)
				_shake = 0.4
		velocity.y = 0.0
	# ground check even when resting
	if not on_ground:
		position.y += 1.0
		on_ground = _collides()
		position.y -= 1.0
	# choose what to drill
	var want := Vector2i.ZERO
	if down_held and on_ground:
		want = Vector2i(0, 1)
	elif push.x != 0:
		want = Vector2i(push.x, 0)
	elif up_held and not on_ground and velocity.y == 0.0 and _ceiling():
		want = Vector2i(0, -1)
	_update_drill(want, delta)
	_hazards(delta)
	_shake = maxf(0.0, _shake - delta * 1.5)
	_cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * _shake * 14.0
	_lamp.position = Vector2(_facing * 10.0, 0) + Vector2(_dig_dir) * 10.0
	queue_redraw()


func _collides() -> bool:
	var a: Vector2i = world.cell_at(position - HALF)
	var b: Vector2i = world.cell_at(position + HALF - Vector2(0.01, 0.01))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if world.is_solid(x, y):
				return true
	return false


func _ceiling() -> bool:
	position.y -= 1.0
	var c := _collides()
	position.y += 1.0
	return c


func _update_drill(want: Vector2i, delta: float) -> void:
	dig_msg = ""
	if want == Vector2i.ZERO:
		_stop_drill()
		return
	_dig_dir = want
	var centre: Vector2i = world.cell_at(position)
	var target := centre + want
	# drilling down/up uses the column under the pod's centre; line up with it
	if want.x == 0:
		position.x = move_toward(position.x, (centre.x + 0.5) * world.CS, 90.0 * delta)
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
	var h: float = world.hardness(world.get_cell(target.x, target.y), target.y)
	var speed := Game.harvest_speed("mining") * (1.0 + Game.skill_level("mining") * 0.008)
	if Game.energy < 1.0:
		speed *= 0.3
		dig_msg = "Running on reserves: drill at 30%. Surface or use an Energy Cell (R)."
	if want.y < 0:
		speed *= 0.6
	dig_progress += delta * speed / maxf(h, 0.05)
	_shake = maxf(_shake, 0.12)
	if not _drilling:
		_drilling = true
		Sound.loop_start("dig", "drill_loop", -8.0)
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


func _hazards(delta: float) -> void:
	_lava_warn = maxf(0.0, _lava_warn - delta)
	var c: Vector2i = world.cell_at(position)
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if world.get_cell(c.x + dx, c.y + dy) == world.LAVA:
				var lp: Vector2 = world.cell_centre(Vector2i(c.x + dx, c.y + dy))
				if position.distance_to(lp) < world.CS * 1.05:
					if not Game.has_upgrade("lava_plating"):
						Game.take_damage(20.0 * delta)
					if _lava_warn <= 0.0:
						_lava_warn = 3.0
						Game.notify.emit("Molten rock! Hull overheating." if not Game.has_upgrade("lava_plating") else "Heat Plating holds against the magma.", Color("ff7a3d"))
	if Input.is_action_just_pressed("use_cell") and not Game.ui_open:
		Game.use_energy_cell()
	if Input.is_action_just_pressed("repair") and not Game.ui_open:
		Game.use_repair_kit()


func _draw() -> void:
	var bob := sin(_t * 6.0) * 1.0 if on_ground and absf(velocity.x) > 10.0 else 0.0
	var o := Vector2(0, bob)
	# drill bit, spinning, pointing where we're digging
	var dd := Vector2(_dig_dir)
	if dd == Vector2.ZERO:
		dd = Vector2(0, 1)
	var perp := Vector2(-dd.y, dd.x)
	var tip := o + dd * 24.0
	var base := o + dd * 11.0
	var spin := sin(_t * (40.0 if _drilling else 4.0)) * 3.0
	draw_colored_polygon(PackedVector2Array([base + perp * 8.0, tip + perp * spin * 0.2, base - perp * 8.0]), Color("c9ced6"))
	draw_line(base + perp * spin, tip, Color("7a808a"), 2.0)
	# body
	draw_circle(o + Vector2(0, 2), 13.0, _accent.darkened(0.25))
	draw_rect(Rect2(o + Vector2(-12, -10), Vector2(24, 20)), _shell)
	draw_circle(o + Vector2(0, -10), 12.0, _shell)
	# visor
	draw_rect(Rect2(o + Vector2(-8 + _facing * 2.0, -14), Vector2(16, 6)), Color("1b1f29"))
	draw_rect(Rect2(o + Vector2(-6 + _facing * 3.0, -13), Vector2(12, 4)), _glow)
	# belt + treads
	draw_rect(Rect2(o + Vector2(-13, 2), Vector2(26, 4)), _accent)
	draw_rect(Rect2(o + Vector2(-12, 9), Vector2(24, 5)), Color("2a2f3a"))
	# antenna
	draw_line(o + Vector2(4, -21), o + Vector2(7, -30), Color("2a2f3a"), 2.0)
	draw_circle(o + Vector2(7, -31), 2.5, _glow)
	# drill progress crack on the target cell
	if dig_progress > 0.0 and _dig_target != Vector2i(-99, -99):
		var cc: Vector2 = world.cell_centre(_dig_target) - position
		var s: float = world.CS * 0.5 * dig_progress
		draw_line(cc - Vector2(s, s * 0.4), cc + Vector2(s, s * 0.4), Color(0, 0, 0, 0.6), 2.0)
		draw_line(cc - Vector2(s * 0.3, s), cc + Vector2(s * 0.5, s), Color(0, 0, 0, 0.6), 2.0)
