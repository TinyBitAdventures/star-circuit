extends CharacterBody3D
## Third-person robot controller that walks around a spherical planet.

const GRAVITY := 22.0
const JUMP := 9.5
const BASE_SPEED := 7.0
const SPRINT_MULT := 1.9
const JET_ACCEL := 36.0
const JET_DRAIN := 13.0
const INTERACT_RANGE := 4.2
const SCAN_COST := 5.0
const DIVE_DEPTH := 6.0

var world: Node3D
var center := Vector3.ZERO
var heading := Vector3.FORWARD
var ref_fwd := Vector3.FORWARD
var cam_yaw := 0.0
var cam_pitch := -0.3
var visual: RobotVisual
var harvest_fx: HarvestFx
var cam_rig: Node3D
var spring: SpringArm3D
var camera: Camera3D

var target: Node = null
var harvest_progress := 0.0
var scan_cooldown := 0.0
var launching := false
var launch_time := 0.0
var air_time := 0.0
var in_liquid := false
var swim_depth := 0.0 # metres below the sea surface (robot)
var _uw_layer: CanvasLayer
var _uw_rect: ColorRect
var _uw_mat: ShaderMaterial
var _uw := 0.0 # 0..1 how submerged the camera is
var _bubbles: CPUParticles3D
var _was_in_liquid := false
var _uw_amb := false
var _lava_warned := false

# combat
const FIRE_RATE := 0.26
const FIRE_COST := 1.0
const AIM_RANGE := 90.0
var dead := false
var fire_cd := 0.0
var ability_cd := 0.0
var aim_enemy: Enemy = null
var _dash_time := 0.0
var _knock := Vector3.ZERO
var _fire_pose := 0.0
var _warn_cd := 0.0
var _was_on_floor := true
var _loop_harvest := ""
var _low_energy_warned := false
var _dust: CPUParticles3D
var shake := CamShake.new()
var status := Status.new() # burn, chill/freeze, shock from enemy attacks
var _beam_on := 0.0 # Cryo beam hum: seconds left before it stops
var _dropping := false
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.6
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.9
	shape.shape = cap
	shape.position = Vector3(0, 0.95, 0)
	add_child(shape)

	visual = RobotVisual.new()
	add_child(visual)
	harvest_fx = HarvestFx.new()
	add_child(harvest_fx)
	visual.setup(Game.robot_id)
	visual.apply_look.call_deferred(Game.appearance)
	Game.appearance_changed.connect(func(): visual.apply_look(Game.appearance))
	visual.step.connect(func(): Sound.play("step_%d" % randi_range(1, 3), -14.0, 0.12, "SFX", 0.1))

	cam_rig = Node3D.new()
	cam_rig.top_level = true
	add_child(cam_rig)
	spring = SpringArm3D.new()
	spring.spring_length = 7.0
	spring.margin = 0.3
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	spring.shape = sphere
	spring.add_excluded_object(get_rid())
	cam_rig.add_child(spring)
	camera = Camera3D.new()
	camera.fov = Sound.fov
	camera.far = 4000.0
	camera.near = 0.1
	spring.add_child(camera)
	camera.make_current()
	spring.position = Vector3(0.85, 0, 0) # over-the-shoulder so the crosshair is clear
	_dust = CPUParticles3D.new()
	_dust.amount = 40
	_dust.lifetime = 0.7
	_dust.local_coords = false
	_dust.emitting = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 0.4
	_dust.direction = Vector3(0, 1, 1)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 3.0
	_dust.gravity = Vector3.ZERO
	_dust.damping_min = 2.0
	_dust.damping_max = 3.0
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.4
	var dq := QuadMesh.new()
	dq.size = Vector2(0.6, 0.6)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = ModelUtil.soft_dot()
	dq.material = dm
	_dust.mesh = dq
	var dg := Gradient.new()
	dg.set_color(0, Color(0.9, 0.85, 0.75, 0.5))
	dg.set_color(1, Color(0.9, 0.85, 0.75, 0.0))
	_dust.color_ramp = dg
	_dust.position = Vector3(0, 0.2, 0.3)
	add_child(_dust)
	Game.player_died.connect(_on_died)
	Game.player_damaged.connect(func(a): shake.add(clampf(a / 40.0, 0.12, 0.5)))


func place_at(dir: Vector3, gen: PlanetGen) -> void:
	var up := _clear_spot(dir.normalized(), gen)
	global_position = gen.surface_point(up) + up * 1.5
	ref_fwd = PlanetGen.align_basis(up).z * -1.0
	heading = ref_fwd
	velocity = Vector3.ZERO
	_update_basis(up)
	_update_camera(up, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if Game.get("ui_open"):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring.spring_length = clampf(spring.spring_length - 0.6, 3.0, 16.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring.spring_length = clampf(spring.spring_length + 0.6, 3.0, 16.0)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var md := Sound.look_delta(event.relative)
		cam_yaw -= md.x * 0.0035
		cam_pitch = clampf(cam_pitch - md.y * 0.003, -1.25, 0.6)


func _physics_process(delta: float) -> void:
	var up := (global_position - center).normalized()
	if dead:
		_update_camera(up, delta)
		return
	ref_fwd = (ref_fwd - up * ref_fwd.dot(up))
	if ref_fwd.length() < 0.01:
		ref_fwd = PlanetGen.align_basis(up).z * -1.0
	ref_fwd = ref_fwd.normalized()
	var cam_fwd := ref_fwd.rotated(up, cam_yaw)
	var cam_right := cam_fwd.cross(up).normalized()

	var ui_block: bool = Game.get("ui_open")
	var burn := status.tick(delta)
	if burn > 0.0:
		world.damage_player(burn, null)
		if dead:
			return
	var input := Vector2.ZERO
	if not ui_block and not launching and not status.frozen():
		input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var wish := (cam_fwd * input.y + cam_right * input.x)
	if wish.length() > 1.0:
		wish = wish.normalized()

	var dist := global_position.distance_to(center)
	var liquid_r: float = world.gen.sea_radius() if world.gen.has_liquid() else 0.0
	in_liquid = dist < liquid_r - 0.4
	var is_lava: bool = world.biome.get("lava", false)

	var speed := BASE_SPEED * Game.stat("speed") * maxf(status.speed_mult(), 0.35)
	var sprinting := Input.is_action_pressed("sprint") and not ui_block and input.length() > 0.1
	if sprinting:
		speed *= SPRINT_MULT
	if in_liquid and not is_lava:
		speed *= 0.6

	var vv := velocity.dot(up)
	var hv := velocity - up * vv
	var accel := 10.0 if is_on_floor() else 3.5
	hv = hv.lerp(wish * speed, clampf(accel * delta, 0.0, 1.0))

	var jetting := false
	if launching:
		launch_time += delta
		vv = lerpf(maxf(vv, 0.0), 60.0, delta * 1.5)
		jetting = true
		# lift-off ignores collisions so nothing can pin the robot down
		global_position += up * vv * delta
		velocity = up * vv
		_update_basis(up)
		_update_camera(up, delta)
		visual.jetting = true
		visual.boost = true
		if launch_time > 1.6:
			_finish_launch(up)
		return
	elif in_liquid and not is_lava:
		if _dropping:
			_touchdown(up)
		# near-neutral buoyancy: drift down slowly, Space swims up, Ctrl dives
		vv = lerpf(vv, -1.2, delta * 2.0)
		if Input.is_action_pressed("jump") and not ui_block:
			vv = lerpf(vv, 6.5, delta * 4.0)
		if Input.is_action_pressed("descend") and not ui_block:
			vv = lerpf(vv, -7.0, delta * 4.0)
	elif _dropping:
		# retro-thrusters cap the descent; flames all the way down
		vv = maxf(vv - GRAVITY * delta, -15.0)
		jetting = true
		if is_on_floor() and air_time > 0.3:
			_touchdown(up)
		air_time += delta
	else:
		vv -= GRAVITY * delta
		if is_on_floor():
			air_time = 0.0
			if Input.is_action_just_pressed("jump") and not ui_block:
				vv = JUMP
				Sound.play("jump", -10.0)
		else:
			air_time += delta
			if Input.is_action_pressed("jump") and not ui_block and air_time > 0.18 and Game.energy > 0.5:
				var jet_eff := Game.stat("jet") * (1.4 if Game.has_upgrade("jet_booster") else 1.0)
				vv += JET_ACCEL * jet_eff * delta
				vv = minf(vv, 9.0 * jet_eff)
				Game.drain_energy(JET_DRAIN / jet_eff * (0.6 if Game.has_upgrade("jet_booster") else 1.0) * delta)
				jetting = true
			if Input.is_action_pressed("descend") and not ui_block:
				vv -= GRAVITY * delta

	if _dash_time > 0.0:
		_dash_time -= delta
		hv = heading * 42.0
		if _dash_time <= 0.0:
			Game.invulnerable = false
	if _knock.length() > 0.2:
		hv += _knock - up * _knock.dot(up)
		vv = maxf(vv, _knock.dot(up))
		_knock = _knock.lerp(Vector3.ZERO, clampf(delta * 5.0, 0.0, 1.0))
	velocity = hv + up * vv
	up_direction = up
	move_and_slide()
	_unstick(up, wish, delta)
	if is_on_floor() and not _was_on_floor and air_time > 0.35:
		Sound.play("land", -6.0 - (0.0 if air_time > 1.0 else 6.0))
	_was_on_floor = is_on_floor()
	if jetting and not launching:
		Sound.loop_start("jet", "jet_loop", -8.0)
	elif not launching:
		Sound.loop_stop("jet", 0.25)

	# face aim while shooting, otherwise movement direction
	if _fire_pose > 0.0:
		heading = heading.slerp(cam_fwd, clampf(20.0 * delta, 0.0, 1.0))
	elif wish.length() > 0.1:
		heading = heading.slerp(wish.normalized(), clampf(12.0 * delta, 0.0, 1.0))
	elif target and harvest_progress > 0.0:
		var to: Vector3 = (target.global_position - global_position)
		to = (to - up * to.dot(up))
		if to.length() > 0.1:
			heading = heading.slerp(to.normalized(), clampf(8.0 * delta, 0.0, 1.0))
	heading = (heading - up * heading.dot(up)).normalized()
	if not heading.is_finite() or heading.length() < 0.5:
		heading = cam_fwd
	_update_basis(up)
	_update_camera(up, delta)
	world.hud.set_compass(global_position, up, cam_fwd, world.compass_markers())

	visual.move_amount = lerpf(visual.move_amount, clampf(hv.length() / (BASE_SPEED * 1.2), 0.0, 1.0), 0.2)
	var running_now := sprinting and is_on_floor() and hv.length() > BASE_SPEED * 1.2
	visual.sprinting = running_now
	_dust.emitting = running_now and not in_liquid
	camera.fov = lerpf(camera.fov, Sound.fov + (10.0 if running_now else 0.0), clampf(delta * 5.0, 0.0, 1.0))
	visual.airborne = not is_on_floor()
	visual.jetting = jetting
	visual.boost = launching

	_update_energy(delta, up, is_lava)
	_update_water(delta, up, is_lava, liquid_r, dist)
	_update_interaction(delta, ui_block)
	scan_cooldown = maxf(0.0, scan_cooldown - delta)

	if not ui_block and not launching:
		if Input.is_action_just_pressed("scan"):
			_scan()
		if Input.is_action_just_pressed("use_cell"):
			Game.use_energy_cell()
		if Input.is_action_just_pressed("takeoff"):
			if Game.in_combat():
				Game.notify.emit("Can't break orbit while in combat!", Color("ff6b6b"))
			else:
				_start_launch()
		if Input.is_action_just_pressed("repair"):
			Game.use_repair_kit()
		if Input.is_action_just_pressed("weapon_cycle"):
			Game.cycle_weapon()
		if Input.is_action_just_pressed("ability"):
			_use_ability(up)
	_update_combat(delta, up, ui_block)

	# safety: fell through the world
	if dist < world.gen.radius * 0.8:
		place_at(up, world.gen)


func _update_combat(delta: float, up: Vector3, ui_block: bool) -> void:
	fire_cd = maxf(0.0, fire_cd - delta)
	# the Cryo hum stops a moment after you let go
	if _beam_on > 0.0:
		_beam_on -= delta
		if _beam_on <= 0.0:
			Sound.loop_stop("weapon", 0.15)
			_beam_acc.clear()
	ability_cd = maxf(0.0, ability_cd - delta)
	_warn_cd = maxf(0.0, _warn_cd - delta)
	_fire_pose = maxf(0.0, _fire_pose - delta)
	visual.aiming = _fire_pose > 0.0
	# out-of-combat repair and shield recharge
	if not Game.in_combat():
		Game.repair(5.0 * delta)
		Game.recharge_shield(12.0 * delta)
	elif Time.get_ticks_msec() / 1000.0 - Game.last_hit_time > 3.0:
		Game.recharge_shield(6.0 * delta)
	# what's under the crosshair
	var hit := _aim_ray()
	aim_enemy = hit.get("collider") as Enemy
	world.hud.set_target(aim_enemy if aim_enemy else _recent_target())
	world.hud.set_crosshair_hot(aim_enemy != null)
	world.hud.set_ability_cooldown(ability_cd, Game.robot().ability.cd)
	if ui_block or launching or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if status.frozen():
		return
	if Input.is_action_pressed("fire") and fire_cd <= 0.0:
		var wd := Game.weapon_def()
		if Game.energy < FIRE_COST * float(wd.cost):
			if _warn_cd <= 0.0:
				_warn_cd = 2.0
				Game.notify.emit("Blaster offline: out of energy (R for a cell)", Color("ff6b6b"))
			return
		Game.drain_energy(FIRE_COST * float(wd.cost))
		fire_cd = FIRE_RATE * float(wd.rate)
		_weapon_sound(wd)
		_fire_pose = 0.6
		_shoot(up)


var _last_target: Enemy = null
func _recent_target() -> Enemy:
	if is_instance_valid(_last_target) and _last_target.is_alive() and _last_target.state == "chase":
		return _last_target
	return null


func _aim_ray() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * AIM_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		r = {"position": to}
	return r


func _shoot(up: Vector3) -> void:
	var wd := Game.weapon_def()
	var muzzle := global_position + up * 1.3 + global_basis.x * 0.55 - global_basis.z * 0.5
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var mode: String = wd.get("mode", "hitscan")
	var kind: String = wd.get("kind", "kinetic")
	var tier := Game.weapon_tier_mult(Game.weapon)
	if mode == "lobbed":
		# Cinder: a grenade on an arc, aimed a little above the crosshair
		var vel := fwd * 26.0 + up * 5.0
		PlayerGrenade.launch(world, muzzle, vel, Game.weapon_damage() * float(wd.dmg) * tier, 3.5, 3.0)
		return
	var reach: float = AIM_RANGE * float(wd.range)
	var col: Color = Game.robot().color.lightened(0.3)
	if Game.appearance.has("glow"):
		col = Color(Game.appearance.glow)
	for i in int(wd.pellets):
		var dir := fwd
		if float(wd.spread) > 0.0:
			dir = (fwd + camera.global_basis.x * randf_range(-1, 1) * float(wd.spread) + camera.global_basis.y * randf_range(-1, 1) * float(wd.spread)).normalized()
		var exclude: Array[RID] = [get_rid()]
		var end := from + dir * reach
		# rail slugs punch through up to four targets
		for pierce in (4 if wd.pierce else 1):
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1 | 4, exclude)
			var r := get_world_3d().direct_space_state.intersect_ray(q)
			if r.is_empty():
				break
			end = r.position
			var e := r.get("collider") as Enemy
			if e == null:
				break
			if e.is_alive():
				var crit := mode != "beam" and randf() < 0.12
				var dmg := Game.weapon_damage() * float(wd.dmg) * tier * randf_range(0.9, 1.1) * (1.8 if crit else 1.0)
				if mode != "beam":
					Sound.play_3d("crit" if crit else "hit", r.position, -4.0 if crit else -8.0)
				# rail slugs pierce shields; everything else can be blocked from the front
				e.take_hit(dmg, crit, kind, global_position)
				_last_target = e
				if mode == "chain":
					_chain_from(e, dmg)
				elif mode == "beam" and e.is_alive():
					_beam_chill(e)
			exclude.append(e.get_rid())
		if wd.pierce:
			CombatFx.tracer(world, muzzle, end, col * 1.6)
			CombatFx.spark(world, end, col, 1.2)
		elif mode == "chain":
			CombatFx.arc_bolt(world, muzzle, end, Color(0.75, 0.7, 1.0) * 2.2)
		elif mode == "beam":
			CombatFx.tracer(world, muzzle, end, Color(0.55, 0.9, 1.0) * 2.0)
		else:
			world.tracer(muzzle, end, col)


const CHAIN_RANGE := 8.0
const CHAIN_JUMPS := 3

## Arc: the bolt leaps from the first target to the nearest others, weaker each jump, shocking each.
func _chain_from(first: Enemy, dmg: float) -> void:
	if first.is_alive():
		first.apply_status("shock", 2.5)
	var hit := [first]
	var at: Vector3 = first.global_position + first.dir * 1.2
	var d := dmg
	for i in CHAIN_JUMPS:
		var best: Enemy = null
		var bd := CHAIN_RANGE
		for e in world.enemies_near(at, CHAIN_RANGE):
			if hit.has(e):
				continue
			var dist: float = e.global_position.distance_to(at)
			if dist < bd:
				bd = dist
				best = e
		if best == null:
			break
		d *= 0.7
		var to: Vector3 = best.global_position + best.dir * 1.2
		CombatFx.arc_bolt(world, at, to, Color(0.75, 0.7, 1.0) * 2.2)
		best.take_hit(d, false, "shock", at)
		if best.is_alive():
			best.apply_status("shock", 2.5)
		hit.append(best)
		at = to


var _beam_acc := {} # enemy -> seconds of beam since its last chill stack

## Cryo: every half second of beam on a target adds a chill stack (the fourth freezes).
func _beam_chill(e: Enemy) -> void:
	var t: float = _beam_acc.get(e, 0.0) + FIRE_RATE * float(Game.weapon_def().rate)
	if t >= 0.5:
		t = 0.0
		e.apply_status("chill", 3.0, 1.0)
	_beam_acc[e] = t


func _weapon_sound(wd: Dictionary) -> void:
	match wd.name:
		"Arc":
			Sound.play("arc_zap", -4.0, 0.1, "SFX", 0.0)
		"Cinder":
			Sound.play("cinder_thump", -3.0, 0.08, "SFX", 0.0)
		"Cryo":
			Sound.loop_start("weapon", "cryo_loop", -10.0)
			_beam_on = 0.2
		"Rail":
			Sound.play("sentinel_shot", -3.0, 0.05, "SFX", 0.0)
		"Scatter":
			Sound.play("blaster", -3.0, 0.2, "SFX", 0.0)
		_:
			Sound.play("blaster", -7.0, 0.1, "SFX", 0.0)


func _use_ability(up: Vector3) -> void:
	var ab: Dictionary = Game.robot().ability
	if ability_cd > 0.0:
		Game.notify.emit("%s recharging (%.0fs)" % [ab.name, ability_cd], Color("9aa0a6"))
		return
	if not Game.spend_energy(ab.cost):
		Game.notify.emit("Not enough energy for %s." % ab.name, Color("ff6b6b"))
		return
	ability_cd = ab.cd
	var dmg := Game.weapon_damage()
	var col: Color = Game.robot().color
	Sound.play({"dash": "dash", "slam": "slam", "turret": "turret_deploy", "nova": "nova"}[ab.id], -2.0, 0.04)
	match ab.id:
		"dash":
			var cam_fwd := ref_fwd.rotated(up, cam_yaw)
			var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
			var dir := (cam_fwd * input.y + cam_fwd.cross(up) * input.x)
			heading = dir.normalized() if dir.length() > 0.1 else cam_fwd
			_dash_time = 0.28
			Game.invulnerable = true
			world.shockwave(global_position, 2.0, col)
		"slam":
			shake.add(0.55)
			world.shockwave(global_position, 7.0, Color(1.0, 0.65, 0.25))
			world.explosion(global_position + up * 0.3, Color(0.8, 0.6, 0.4), 1.0)
			for e in world.enemies_near(global_position, 7.5):
				e.take_hit(dmg * 2.2)
				e.knockback((e.global_position - global_position).normalized() * 18.0)
		"turret":
			var cam_fwd2 := ref_fwd.rotated(up, cam_yaw)
			var spot := (global_position + cam_fwd2 * 2.5).normalized()
			Turret.new().setup(world, spot)
		"nova":
			world.shockwave(global_position, 8.0, Color(1.0, 0.88, 0.4))
			var total := 0.0
			for e in world.enemies_near(global_position, 8.5):
				var d := dmg * 1.6
				total += d
				e.take_hit(d)
			if total > 0.0:
				Game.repair(total * 0.5)
				world.floating_text(global_position + up * 2.6, "+%d" % int(total * 0.5), Color("6ee06a"), true)
	Game.notify.emit(ab.name + "!", col.lightened(0.3))


func knockback(v: Vector3) -> void:
	_knock += v


func _on_died() -> void:
	if dead:
		return
	dead = true
	status.clear()
	Sound.loop_stop("weapon", 0.1)
	Game.invulnerable = false
	Sound.play("death", -2.0, 0.0)
	Sound.loop_stop("jet", 0.1)
	_harvest_sound("")
	visual.visible = false
	world.explosion(global_position + global_basis.y, Game.robot().color, 1.8)
	world.hud.show_death()
	world.reset_aggro()
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	place_at(world.spawn_dir, world.gen)
	Game.hull = Game.max_hull() * 0.6
	Game.shield = Game.max_shield()
	Game.energy = maxf(Game.energy, Game.max_energy() * 0.5)
	Game.hull_changed.emit()
	Game.energy_changed.emit(Game.energy, Game.max_energy())
	visual.visible = true
	dead = false
	world.hud.hide_death()
	Sound.play("respawn", -4.0, 0.0)
	Game.big_notify.emit("REBOOTED", "Systems restored at the landing site", Color("6ee06a"))


func _update_basis(up: Vector3) -> void:
	var back := -heading
	var right := up.cross(back).normalized()
	global_basis = Basis(right, up, back).orthonormalized()


func _update_camera(up: Vector3, delta: float) -> void:
	var cam_fwd := ref_fwd.rotated(up, cam_yaw)
	var back := -cam_fwd
	var right := up.cross(back).normalized()
	var b := Basis(right, up, back).orthonormalized() * Basis(Vector3.RIGHT, cam_pitch)
	cam_rig.global_position = cam_rig.global_position.lerp(global_position + up * 1.8, clampf(delta * 18.0, 0.0, 1.0))
	cam_rig.global_basis = b
	var sh := shake.update(delta)
	camera.h_offset = sh.x
	camera.v_offset = sh.y
	camera.rotation.z = sh.z * 0.08


func _harvest_sound(skill: String) -> void:
	var name: String = {"mining": "drill_loop", "botany": "harvest_loop", "siphoning": "siphon_loop"}.get(skill, "")
	if name == _loop_harvest:
		return
	_loop_harvest = name
	if name == "":
		Sound.loop_stop("harvest", 0.15)
	else:
		Sound.loop_start("harvest", name, -8.0 if skill == "mining" else -4.0)


func _update_energy(delta: float, up: Vector3, is_lava: bool) -> void:
	var frac := Game.energy / Game.max_energy()
	if frac < 0.15 and not _low_energy_warned:
		_low_energy_warned = true
		Sound.play("low_energy", -4.0, 0.0, "UI")
	elif frac > 0.3:
		_low_energy_warned = false
	var day: float = up.dot(world.sun_dir)
	var reactor := 1.5 if Game.has_upgrade("exotic_reactor") else 1.0
	if day > 0.05:
		var regen := 1.4 * Game.stat("regen") * (2.0 if Game.has_upgrade("solar_skin") else 1.0) * reactor
		Game.add_energy(regen * delta)
	elif reactor > 1.0:
		Game.add_energy(0.8 * delta) # the reactor hums along at night
	if is_lava and global_position.distance_to(center) < world.gen.sea_radius() + 0.6 and not Game.has_upgrade("lava_plating"):
		Game.drain_energy(14.0 * delta)
		if not _lava_warned:
			_lava_warned = true
			Game.notify.emit("LAVA! Systems overheating. Get out!", Color("ff5a1f"))
		if Game.energy <= 0.0:
			Game.big_notify.emit("SYSTEMS CRITICAL", "Emergency recall to landing point", Color("ff4d4d"))
			Game.add_energy(Game.max_energy() * 0.4)
			place_at(world.spawn_dir, world.gen)
	else:
		_lava_warned = false


func _update_interaction(delta: float, ui_block: bool) -> void:
	var t: Node = world.nearest_interactable(global_position, INTERACT_RANGE)
	if t != target:
		target = t
		harvest_progress = 0.0
		_harvest_sound("")
	var hud = world.hud
	# deep enough in an ocean: the Deep Sea opens up below
	if target == null and not ui_block and not launching and in_liquid and swim_depth >= DIVE_DEPTH and not world.biome.get("lava", false):
		visual.working = false
		harvest_fx.update(false, "", Vector3.ZERO, Vector3.ZERO, 0.0, Color.WHITE, delta)
		hud.set_prompt("[E] Dive into the Deep Sea  (%d m down)" % int(swim_depth), Color("7fd8ff"), 0.0)
		if Input.is_action_just_pressed("interact"):
			hud.set_prompt("", Color.WHITE, 0.0)
			Game.enter_sea(global_position.normalized(), world.planet)
		return
	if target == null or ui_block or launching:
		visual.working = false
		harvest_fx.update(false, "", Vector3.ZERO, Vector3.ZERO, 0.0, Color.WHITE, delta)
		_harvest_sound("")
		hud.set_prompt("", Color.WHITE, 0.0)
		return
	var info: Dictionary = target.interact_info()
	if info.get("instant", false):
		hud.set_prompt(info.text, info.color, 0.0)
		if Input.is_action_just_pressed("interact"):
			target.interact(self)
		visual.working = false
		harvest_fx.update(false, "", Vector3.ZERO, Vector3.ZERO, 0.0, Color.WHITE, delta)
		return
	if Input.is_action_pressed("interact") and info.get("ok", true):
		harvest_progress += delta * Game.harvest_speed(info.skill) / info.time
		visual.working = true
		visual.work_skill = info.skill
		visual.work_progress = harvest_progress
		_harvest_sound(info.skill)
		var aim: Vector3 = target.work_point() if target.has_method("work_point") else target.global_position
		var col: Color = Db.item_color(target.def.item) if "def" in target and target.def.has("item") else Color.WHITE
		harvest_fx.update(true, info.skill, visual.hand_position(), aim, harvest_progress, col, delta)
		if target.has_method("work"):
			target.work(harvest_progress, info.skill, delta)
		if info.skill == "mining":
			shake.add(delta * 0.35)
		if harvest_progress >= 1.0:
			harvest_progress = 0.0
			HarvestFx.burst(world, aim, col, info.skill, self)
			if info.skill == "mining":
				shake.add(0.25)
			target.interact(self)
			target = null
			_harvest_sound("")
	else:
		if Input.is_action_just_pressed("interact") and not info.get("ok", true):
			Game.notify.emit(info.get("why", "Can't do that yet."), Color("ff6b6b"))
		harvest_progress = maxf(0.0, harvest_progress - delta * 2.0)
		visual.working = false
		harvest_fx.update(false, "", Vector3.ZERO, Vector3.ZERO, 0.0, Color.WHITE, delta)
		if target.has_method("work"):
			target.work(0.0, "", delta)
		_harvest_sound("")
	hud.set_prompt(info.text, info.color, harvest_progress)


func _scan() -> void:
	if scan_cooldown > 0.0:
		return
	if not Game.spend_energy(SCAN_COST):
		Game.notify.emit("Not enough energy to scan.", Color("ff6b6b"))
		return
	scan_cooldown = 2.5
	Sound.play("scan", -4.0, 0.0)
	var radius := 70.0 * Game.stat("scan") * (2.0 if Game.has_upgrade("scanner_mk2") else 1.0)
	world.scan(global_position, radius)


func _start_launch() -> void:
	shake.add(0.35)
	Sound.loop_stop("jet", 0.1)
	_harvest_sound("")
	Sound.play("takeoff", -2.0, 0.0)
	launching = true
	launch_time = 0.0
	Game.big_notify.emit("BREAKING ORBIT", "Leaving %s" % world.planet.name, Color("5ff7ff"))


func _finish_launch(up: Vector3) -> void:
	set_physics_process(false)
	Game.land_dir = up
	Game.record_orbit()
	Game.go_to_space()



## Nudge a spawn point until the capsule isn't inside a tree, rock or building.
func _clear_spot(up: Vector3, gen: PlanetGen) -> Vector3:
	if not is_inside_tree() or world == null or world.terrain_body == null:
		return up
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.7
	cap.height = 2.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = [get_rid(), world.terrain_body.get_rid()]
	var d := up
	for i in 16:
		var p := gen.surface_point(d) + d * 1.6
		q.transform = Transform3D(PlanetGen.align_basis(d), p)
		if space.intersect_shape(q, 1).is_empty():
			return d
		var b := PlanetGen.align_basis(up, i * 2.4)
		d = (up + b.x * (2.5 + i * 0.8) / gen.radius).normalized()
	return up



## Arriving from orbit: start high above the landing site and descend.
func start_drop() -> void:
	var up := global_position.normalized()
	global_position += up * 42.0
	velocity = -up * 15.0
	_dropping = true
	air_time = 0.0
	spring.spring_length = 15.0
	cam_pitch = -0.55
	Sound.play("atmo_entry", -6.0, 0.0)


func _touchdown(up: Vector3) -> void:
	_dropping = false
	shake.add(0.45)
	Sound.play("land", 0.0, 0.05)
	CombatFx.shockwave(world, global_position, up, 5.0, Color(0.85, 0.78, 0.65))
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.amount = 40
	dust.lifetime = 1.4
	dust.explosiveness = 0.9
	dust.local_coords = false
	dust.direction = up
	dust.spread = 80.0
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 6.0
	dust.gravity = -up * 2.0
	dust.damping_min = 2.0
	dust.damping_max = 4.0
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 3.5
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = ModelUtil.soft_dot()
	q.material = m
	dust.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.8, 0.7, 0.6))
	g.set_color(1, Color(0.85, 0.8, 0.7, 0.0))
	dust.color_ramp = g
	world.add_child(dust)
	dust.global_position = global_position
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
	var t := create_tween()
	t.tween_property(spring, "spring_length", 7.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "cam_pitch", -0.3, 1.6)



## Safety nets against getting wedged: never below the ground, and if the
## player pushes for a while without moving, pop them up and free.
func _unstick(up: Vector3, wish: Vector3, delta: float) -> void:
	var gen: PlanetGen = world.gen
	var ground := gen.surface_radius(up)
	var r := global_position.length()
	if r < ground - 0.25:
		global_position = up * (ground + 0.4)
		velocity = Vector3.ZERO
	if wish.length() > 0.5 and not _dropping:
		if global_position.distance_to(_last_pos) < 0.02:
			_stuck_t += delta
			if _stuck_t > 1.8:
				_stuck_t = 0.0
				var free_dir := _clear_spot(up, gen)
				global_position = gen.surface_point(free_dir) + free_dir * 1.2
				velocity = Vector3.ZERO
		else:
			_stuck_t = 0.0
	else:
		_stuck_t = 0.0
	_last_pos = global_position



# --------------------------------------------------------------------------
# water: swimming, the underwater look, bubbles, muffled sound
# --------------------------------------------------------------------------

func _update_water(delta: float, up: Vector3, is_lava: bool, liquid_r: float, dist: float) -> void:
	if liquid_r <= 0.0 or is_lava:
		return
	swim_depth = maxf(0.0, liquid_r - dist - 0.9)
	var swimming := in_liquid and not is_on_floor()
	visual.swimming = in_liquid
	if in_liquid != _was_in_liquid:
		_was_in_liquid = in_liquid
		if absf(velocity.dot(up)) > 2.0:
			Sound.play("splash", -6.0, 0.1)
	if _bubbles == null:
		_bubbles = CPUParticles3D.new()
		_bubbles.amount = 16
		_bubbles.lifetime = 2.0
		_bubbles.local_coords = false
		_bubbles.emitting = false
		_bubbles.spread = 25.0
		_bubbles.initial_velocity_min = 0.6
		_bubbles.initial_velocity_max = 1.4
		_bubbles.scale_amount_min = 0.6
		_bubbles.scale_amount_max = 1.4
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		sm.radial_segments = 6
		sm.rings = 3
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = Color(0.85, 0.97, 1.0, 0.6)
		sm.material = bm
		_bubbles.mesh = sm
		add_child(_bubbles)
		_bubbles.position = Vector3(0, 1.7, 0)
	_bubbles.emitting = in_liquid
	_bubbles.direction = Vector3.UP
	_bubbles.gravity = up * 1.5
	# the camera decides the look: half in, half out of the water
	var cam_depth := liquid_r - camera.global_position.distance_to(center)
	var want := clampf(cam_depth * 2.0 + 0.5, 0.0, 1.0)
	_uw = move_toward(_uw, want, delta * 4.0)
	if _uw > 0.0 and _uw_layer == null:
		_uw_layer = CanvasLayer.new()
		_uw_layer.layer = 1
		add_child(_uw_layer)
		_uw_rect = ColorRect.new()
		_uw_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_uw_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_uw_mat = ShaderMaterial.new()
		_uw_mat.shader = preload("res://shaders/underwater.gdshader")
		_uw_rect.material = _uw_mat
		_uw_layer.add_child(_uw_rect)
	if _uw_layer:
		_uw_layer.visible = _uw > 0.01
		var wc: Color = world.biome.water
		_uw_mat.set_shader_parameter("water", Color(wc.r, wc.g, wc.b))
		_uw_mat.set_shader_parameter("depth", maxf(cam_depth, 0.0))
		_uw_mat.set_shader_parameter("strength", _uw)
	world.underwater = _uw
	world.underwater_depth = maxf(cam_depth, 0.0)
	Sound.set_underwater(_uw > 0.5)
	# the hush of the sea once the camera is under
	if _uw > 0.5 and not _uw_amb:
		_uw_amb = true
		Sound.loop_start("uw_amb", "ocean_loop", -10.0, "Ambience", 0.6)
		world.refresh_music(2.0)
	elif _uw < 0.3 and _uw_amb:
		_uw_amb = false
		Sound.loop_stop("uw_amb", 0.6)
		world.refresh_music(2.5)
	if swimming and swim_depth > 2.0:
		Game.tip("first_swim", "You're swimming. Hold %s to rise and %s to dive. Keep going down and you can drop into the Deep Sea to explore, mine and scan what lives there." % [Game.key("jump"), Game.key("descend")])


func _exit_tree() -> void:
	Sound.set_underwater(false)
