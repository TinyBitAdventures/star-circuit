extends CharacterBody3D
## Flat-ground third-person robot for the underground chambers.

const GRAVITY := 22.0
const SPEED := 6.0
const INTERACT_RANGE := 3.4

var world: Node3D
var visual: RobotVisual
var cam_rig: Node3D
var spring: SpringArm3D
var camera: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.25
var target: Node = null
var harvest_progress := 0.0
var shake := CamShake.new()
var dead := false
var _scan_cd := 0.0
var _harvesting := false


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.9
	shape.shape = cap
	shape.position.y = 0.95
	add_child(shape)
	visual = RobotVisual.new()
	add_child(visual)
	visual.setup(Game.robot_id)
	visual.apply_look.call_deferred(Game.appearance)
	visual.step.connect(func(): Sound.play("step_%d" % randi_range(1, 3), -14.0, 0.12, "SFX", 0.1))
	cam_rig = Node3D.new()
	cam_rig.top_level = true
	add_child(cam_rig)
	spring = SpringArm3D.new()
	spring.spring_length = 5.5
	spring.margin = 0.3
	var sp := SphereShape3D.new()
	sp.radius = 0.3
	spring.shape = sp
	spring.add_excluded_object(get_rid())
	spring.position = Vector3(0.7, 0, 0)
	cam_rig.add_child(spring)
	camera = Camera3D.new()
	camera.fov = Sound.fov
	spring.add_child(camera)
	camera.make_current()
	var lamp := SpotLight3D.new()
	lamp.spot_range = 14.0
	lamp.spot_angle = 35.0
	lamp.light_energy = 2.0
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.position = Vector3(0, 1.6, -0.3)
	add_child(lamp)


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var md := Sound.look_delta(event.relative)
		cam_yaw -= md.x * 0.0035
		cam_pitch = clampf(cam_pitch - md.y * 0.003, -1.1, 0.5)


func _physics_process(delta: float) -> void:
	var ui := Game.ui_open
	var input := Vector2.ZERO if ui else Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * -1.0
	var right := fwd.cross(Vector3.UP)
	var wish := fwd * input.y + right * input.x
	var sprint := Input.is_action_pressed("sprint") and not ui
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(wish * SPEED * (1.7 if sprint else 1.0), clampf(10.0 * delta, 0.0, 1.0))
	var vy := velocity.y - GRAVITY * delta
	if is_on_floor() and Input.is_action_just_pressed("jump") and not ui:
		vy = 8.5
	velocity = Vector3(hv.x, vy, hv.z)
	move_and_slide()
	if wish.length() > 0.1:
		var face := wish.normalized()
		var cur := -global_basis.z
		global_basis = Basis.looking_at(cur.slerp(face, clampf(12.0 * delta, 0.0, 1.0)).normalized(), Vector3.UP)
	visual.move_amount = lerpf(visual.move_amount, clampf(hv.length() / 7.0, 0.0, 1.0), 0.2)
	visual.sprinting = sprint and hv.length() > 7.0
	visual.airborne = not is_on_floor()
	# camera
	cam_rig.global_position = cam_rig.global_position.lerp(global_position + Vector3.UP * 1.7, clampf(delta * 18.0, 0.0, 1.0))
	cam_rig.global_basis = Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch)
	var sh := shake.update(delta)
	camera.h_offset = sh.x
	camera.v_offset = sh.y
	_interact(delta, ui)
	_scan_cd = maxf(0.0, _scan_cd - delta)
	if not ui:
		if Input.is_action_just_pressed("scan") and _scan_cd <= 0.0 and Game.spend_energy(5.0):
			_scan_cd = 2.5
			Sound.play("scan", -4.0, 0.0)
			world.scan(global_position, 30.0)
		if Input.is_action_just_pressed("use_cell"):
			Game.use_energy_cell()


func _interact(delta: float, ui: bool) -> void:
	var t: Node = world.nearest_interactable(global_position, INTERACT_RANGE)
	if t != target:
		target = t
		harvest_progress = 0.0
	if target == null or ui:
		visual.working = false
		world.hud.set_prompt("", Color.WHITE, 0.0)
		_loop(false)
		return
	var info: Dictionary = target.interact_info()
	if info.get("instant", false):
		world.hud.set_prompt(info.text, info.color, 0.0)
		if Input.is_action_just_pressed("interact"):
			target.interact(self)
		return
	if Input.is_action_pressed("interact") and info.get("ok", true):
		harvest_progress += delta * Game.harvest_speed(info.skill) / info.time
		visual.working = true
		_loop(true)
		if harvest_progress >= 1.0:
			harvest_progress = 0.0
			target.interact(self)
			target = null
			shake.add(0.15)
	else:
		if Input.is_action_just_pressed("interact") and not info.get("ok", true):
			Game.notify.emit(info.get("why", "Can't do that yet."), Color("ff6b6b"))
		harvest_progress = maxf(0.0, harvest_progress - delta * 2.0)
		visual.working = false
		_loop(false)
	world.hud.set_prompt(info.text, info.color, harvest_progress)


func _loop(on: bool) -> void:
	if on == _harvesting:
		return
	_harvesting = on
	if on:
		Sound.loop_start("harvest", "drill_loop", -8.0)
	else:
		Sound.loop_stop("harvest", 0.15)
