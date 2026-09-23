extends Node3D
## Free-flight robot controller for star systems.

const THRUST := 55.0
const MAX_SPEED := 70.0
const BOOST_MULT := 2.6
const BOOST_DRAIN := 4.0
const LAND_RANGE := 2.2 # multiples of planet radius from the surface

var world: Node3D
var velocity := Vector3.ZERO
var visual: RobotVisual
var camera: Camera3D
var _mouse := Vector2.ZERO
var _landing := false
var _land_target := {}
const LASER_RANGE := 110.0
const LASER_DPS := 22.0
const CANNON_RANGE := 420.0
const CANNON_RATE := 0.14
const CANNON_COST := 0.6
const MISSILE_CD := 4.0
const MISSILE_COST := 6.0
var dead := false
var _fire_cd := 0.0
var _missile_cd := 0.0
var _gun_side := 1.0
var _dust: CPUParticles3D
var _streaks: CPUParticles3D
var shake := CamShake.new()
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _lasering := false
var _scan_cd := 0.0
var _bump_cd := 0.0


func _ready() -> void:
	visual = RobotVisual.new()
	add_child(visual)
	visual.setup(Game.robot_id)
	visual.apply_look.call_deferred(Game.appearance)
	Game.appearance_changed.connect(func(): visual.apply_look(Game.appearance))
	visual.flying = true
	visual.rotation = Vector3(-PI * 0.45, 0, 0)
	visual.position = Vector3(0, -0.8, 0)
	camera = Camera3D.new()
	camera.top_level = true
	camera.fov = Sound.fov + 2.0
	camera.far = 20000.0
	camera.near = 0.5
	add_child(camera)
	camera.make_current()
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.22
	cyl.height = 1.0
	cyl.radial_segments = 8
	_beam.mesh = cyl
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Game.robot().color.lightened(0.3) * Color(3, 3, 3, 0.85)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)
	Game.player_died.connect(_on_died)
	Game.player_damaged.connect(func(a): shake.add(clampf(a / 40.0, 0.12, 0.5)))
	_build_space_fx()


func snap_camera() -> void:
	camera.global_transform = _camera_target()


func _camera_target() -> Transform3D:
	var pos := global_transform * Vector3(0, 2.2, 8.5)
	var t := Transform3D(Basis(), pos)
	return t.looking_at(global_transform * Vector3(0, 0.6, -12), global_basis.y)


func _unhandled_input(event: InputEvent) -> void:
	if Game.ui_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += Sound.look_delta(event.relative)


func _physics_process(delta: float) -> void:
	var ui := Game.ui_open
	if dead:
		_follow_camera(delta)
		return
	if _landing:
		var p: Dictionary = _land_target
		var c: Vector3 = p.node.global_position
		var target: Vector3 = c + (global_position - c).normalized() * p.radius * 1.3
		global_position = global_position.lerp(target, delta * 2.0)
		visual.boost = true
		_follow_camera(delta)
		return
	# steering
	if not ui:
		rotate_object_local(Vector3.UP, -_mouse.x * 0.0025)
		rotate_object_local(Vector3.RIGHT, -_mouse.y * 0.0025)
	_mouse = Vector2.ZERO
	var roll := 0.0
	var fwd := -global_basis.z
	var right := global_basis.x
	var up := global_basis.y
	var boost := Input.is_action_pressed("sprint") and not ui and Game.energy > 0.5
	var speed_mult := Game.stat("space_speed") * (1.6 if Game.has_upgrade("thrusters_mk2") else 1.0)
	var max_speed := MAX_SPEED * speed_mult * (BOOST_MULT if boost else 1.0)
	var acc := Vector3.ZERO
	if not ui:
		acc += fwd * Input.get_axis("move_back", "move_forward")
		acc += right * Input.get_axis("move_left", "move_right") * 0.6
		if Input.is_action_pressed("jump"):
			acc += up * 0.6
		if Input.is_action_pressed("descend"):
			acc -= up * 0.6
		roll = Input.get_axis("move_right", "move_left")
	velocity += acc * THRUST * speed_mult * (BOOST_MULT if boost else 1.0) * delta
	if acc.length() < 0.1:
		velocity = velocity.lerp(Vector3.ZERO, delta * 0.8)
	if velocity.length() > max_speed:
		velocity = velocity.lerp(velocity.normalized() * max_speed, delta * 3.0)
	global_position += velocity * delta
	if boost and acc.length() > 0.1:
		Game.drain_energy(BOOST_DRAIN * delta)

	_update_mining(delta, ui)
	_bump_cd = maxf(0.0, _bump_cd - delta)
	for a in world.asteroids:
		if not is_instance_valid(a):
			continue
		var ca: Vector3 = a.global_position
		var md: float = a.size * 1.1 + 1.2
		var dd := global_position.distance_to(ca)
		if dd < md:
			var n2 := (global_position - ca).normalized()
			global_position = ca + n2 * md
			var impact := -velocity.dot(n2)
			if impact > 0.0:
				velocity += n2 * impact * 1.4
				if impact > 25.0 and _bump_cd <= 0.0:
					_bump_cd = 1.0
					Game.take_damage(impact * 0.25)
					Sound.play("player_hurt", -6.0)
					Game.notify.emit("Hull scraped on rock!", Color("ff6b6b"))
	# keep out of planets and the star
	for p in world.planets:
		var c: Vector3 = p.node.global_position
		var min_d: float = p.radius * 1.25
		if global_position.distance_to(c) < min_d:
			var n := (global_position - c).normalized()
			global_position = c + n * min_d
			velocity -= n * minf(0.0, velocity.dot(n))
	if global_position.length() < 150.0:
		global_position = global_position.normalized() * 150.0
		Game.drain_energy(20.0 * delta)
	elif global_position.length() < 900.0:
		Game.add_energy(3.0 * delta * (1.5 if Game.has_upgrade("exotic_reactor") else 1.0)) # solar recharge near the star
	elif Game.has_upgrade("exotic_reactor"):
		Game.add_energy(1.0 * delta)

	if boost and not visual.boost:
		Sound.play("boost", -4.0)
		shake.add(0.2)
	visual.boost = boost
	_streaks.emitting = boost and velocity.length() > MAX_SPEED * 0.8
	var sp := velocity.length() / (MAX_SPEED * speed_mult)
	Sound.loop_set("engine", lerpf(-16.0, -4.0, clampf(sp, 0.0, 1.5) / 1.5), 0.8 + clampf(sp, 0.0, 2.0) * 0.25)
	visual.rotation.z = lerpf(visual.rotation.z, roll * 0.35, delta * 4.0)
	_follow_camera(delta)
	_update_prompt(ui)


func _follow_camera(delta: float) -> void:
	camera.global_transform = camera.global_transform.interpolate_with(_camera_target(), clampf(delta * 7.0, 0.0, 1.0))
	var sh := shake.update(delta, 0.6)
	camera.h_offset = sh.x
	camera.v_offset = sh.y


func _update_prompt(ui: bool) -> void:
	var near: Dictionary = world.nearest_planet(global_position)
	var hud = world.hud
	var it: Dictionary = world.space_interactable(global_position)
	if not it.is_empty():
		hud.set_prompt(it.text, it.color, 0.0)
		if not ui and Input.is_action_just_pressed("interact") and it.action.is_valid():
			it.action.call()
		return
	var st: OrbitalStation = world.station
	if st and global_position.distance_to(st.global_position) < OrbitalStation.DOCK_RANGE:
		hud.set_speed_text("Docking range  ·  %s" % st.data.name)
		if hud.current_panel != "station":
			hud.set_prompt("[E] Dock at %s  (sell cargo, repair, contracts)" % st.data.name, Color("ffd98a"), 0.0)
		if not ui and Input.is_action_just_pressed("interact"):
			velocity = Vector3.ZERO
			hud.set_prompt("", Color.WHITE, 0.0)
			Sound.play("ui_open", -4.0, 0.0, "UI")
			hud.open_station_panel(Game.star_index)
		return
	hud.set_speed_text("Speed %d  ·  %s" % [int(velocity.length()), ("Nearest: %s  %d u" % [near.planet.data.name, int(near.dist)]) if not near.is_empty() else ""])
	# the gas giant can't be landed on, but it can be probed
	if world.giant and global_position.distance_to(world.giant.global_position) < world.giant_r * 1.9:
		var gi := Game.orbit_info("giant", Game.star_index, -1)
		hud.set_prompt("[%s] Hold orbit over %s and probe its core  (%s)" % [Sound.key_name("orbit"), gi.name, _gem_text(gi)], Color("ffd96b"), 0.0)
		if not ui and Input.is_action_just_pressed("orbit"):
			velocity = Vector3.ZERO
			hud.set_prompt("", Color.WHITE, 0.0)
			Game.enter_orbit(gi, global_position)
		return
	if near.is_empty():
		hud.set_prompt("", Color.WHITE, 0.0)
		return
	var p: Dictionary = near.planet
	if near.dist < p.radius * LAND_RANGE:
		var b: Dictionary = Db.BIOMES[p.data.biome]
		var visited := Game.visited_planets.has(p.data.key)
		var txt := "[E] Land on %s  (%s%s)" % [p.data.name, b.name, ", visited" if visited else ", uncharted"]
		if not p.data.town.is_empty():
			txt += "\n[F] Dock at %s" % p.data.town.name
		var oi := Game.orbit_info("planet", Game.star_index, p.data.index)
		txt += "\n[%s] Hold orbit and probe for gems  (%s)" % [Sound.key_name("orbit"), _gem_text(oi)]
		if not ui and Input.is_action_just_pressed("orbit"):
			_landing = true
			velocity = Vector3.ZERO
			hud.set_prompt("", Color.WHITE, 0.0)
			Game.enter_orbit(oi, global_position)
			return
		hud.set_prompt(txt, b.atmo.lightened(0.3), 0.0)
		if not ui and not p.data.town.is_empty() and Input.is_action_just_pressed("ability"):
			_landing = true
			_land_target = p
			hud.set_prompt("", Color.WHITE, 0.0)
			world.land_at_town(p)
			return
		if not ui and Input.is_action_just_pressed("interact"):
			_landing = true
			_land_target = p
			hud.set_prompt("", Color.WHITE, 0.0)
			world.land(p, global_position)
	else:
		hud.set_prompt("", Color.WHITE, 0.0)



func _aim_ray() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * CANNON_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, Asteroid.LAYER | SpaceEnemy.LAYER)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _update_mining(delta: float, ui: bool) -> void:
	_scan_cd = maxf(0.0, _scan_cd - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_missile_cd = maxf(0.0, _missile_cd - delta)
	if not ui and Input.is_action_just_pressed("weapon_cycle"):
		Game.cycle_weapon()
	if not ui and Input.is_action_just_pressed("scan") and _scan_cd <= 0.0:
		if Game.spend_energy(5.0):
			_scan_cd = 3.0
			Sound.play("scan", -4.0, 0.0)
			world.scan_space(global_position, 520.0)
	var hit := _aim_ray()
	var rock := hit.get("collider") as Asteroid
	var foe := hit.get("collider") as SpaceEnemy
	if rock and global_position.distance_to(hit.position) > LASER_RANGE:
		rock = null
	# target frame
	if foe:
		var sub := "Shield %d  ·  Hull %d" % [int(foe.shield), int(foe.hp)] if foe.max_shield > 0.0 else "Hull %d / %d" % [int(foe.hp), int(foe.max_hp)]
		world.hud.set_target_info("%s  %d%s" % [foe.def.name, foe.level, "  ELITE" if foe.elite else ""], Color("ffd23f") if foe.elite else Db.con_color(foe.level, Game.level), foe.hp, foe.max_hp, sub)
	elif rock:
		var i := rock.info()
		world.hud.set_target_info("%s%s" % [i.name, "" if i.ok else "  -  needs Mining %d" % i.req], i.color, rock.hp, rock.max_hp, i.items)
	else:
		world.hud.set_target_info("", Color.WHITE, 0, 1, "")
	world.hud.set_crosshair_hot(rock != null or foe != null)
	world.hud.set_threats(world.threat_markers(camera))
	var captured := not ui and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# right mouse: homing missiles
	if captured and Input.is_action_just_pressed("fire2"):
		_launch_missiles(foe)
	var firing := captured and Input.is_action_pressed("fire") and Game.energy > 0.5
	if not firing or rock == null:
		_stop_laser()
	if not firing:
		return
	# left mouse is contextual: laser on rock, cannons on everything else
	if rock:
		_mine(rock, hit, delta)
	elif _fire_cd <= 0.0 and Game.energy >= CANNON_COST * float(Game.weapon_def().cost):
		_fire_cannons(hit, foe)


func _mine(rock: Asteroid, hit: Dictionary, delta: float) -> void:
	var muzzle := global_transform * Vector3(0.6, -0.4, -1.6)
	_show_beam(muzzle, hit.position)
	if not _lasering:
		_lasering = true
		Sound.loop_start("laser", "laser_loop", -6.0)
	Game.drain_energy(2.0 * delta)
	var i2 := rock.info()
	if not i2.ok:
		if _scan_cd <= 0.0:
			_scan_cd = 2.0
			Game.notify.emit("Laser can't cut this. Requires Mining %d." % i2.req, Color("ff6b6b"))
		return
	var dps := LASER_DPS * Game.harvest_speed("mining") * (1.8 if Game.has_upgrade("space_laser_mk2") else 1.0) * (1.0 + Game.skill_level("mining") * 0.01)
	rock.mine(dps * delta)
	if randf() < delta * 12.0:
		CombatFx.spark(world, hit.position, rock.def.vein, 0.6)


func _fire_cannons(_hit: Dictionary, _foe: SpaceEnemy) -> void:
	var wd := Game.weapon_def()
	_fire_cd = CANNON_RATE * float(wd.rate) * (0.7 if wd.name == "Scatter" else 1.0)
	Game.drain_energy(CANNON_COST * float(wd.cost))
	_gun_side = -_gun_side
	var muzzle := global_transform * Vector3(0.9 * _gun_side, -0.5, -1.4)
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var reach: float = CANNON_RANGE * float(wd.range)
	var col: Color = Game.robot().color.lightened(0.4)
	if Game.appearance.has("glow"):
		col = Color(Game.appearance.glow)
	match wd.name:
		"Rail":
			Sound.play("sentinel_shot", -4.0, 0.05, "SFX", 0.0)
		"Scatter":
			Sound.play("blaster", -5.0, 0.2, "SFX", 0.0)
		_:
			Sound.play("blaster", -9.0, 0.12, "SFX", 0.0)
	for i in int(wd.pellets):
		var dir := fwd
		if float(wd.spread) > 0.0:
			dir = (fwd + camera.global_basis.x * randf_range(-1, 1) * float(wd.spread) * 0.6 + camera.global_basis.y * randf_range(-1, 1) * float(wd.spread) * 0.6).normalized()
		var exclude: Array[RID] = []
		var end := from + dir * reach
		for pierce in (5 if wd.pierce else 1):
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Asteroid.LAYER | SpaceEnemy.LAYER, exclude)
			var r := get_world_3d().direct_space_state.intersect_ray(q)
			if r.is_empty():
				break
			end = r.position
			var e := r.get("collider") as SpaceEnemy
			if e == null:
				break
			if e.is_alive():
				var crit := randf() < 0.1
				e.take_hit(Game.space_weapon_damage() * float(wd.dmg) * randf_range(0.9, 1.1) * (1.8 if crit else 1.0), crit)
				Sound.play_3d("crit" if crit else "hit", r.position, -6.0, 0.1, 40.0)
			exclude.append(e.get_rid())
		CombatFx.tracer(world, muzzle, end, col * (1.6 if wd.pierce else 1.0))


func _launch_missiles(aimed: SpaceEnemy) -> void:
	if _missile_cd > 0.0:
		Game.notify.emit("Missiles reloading (%.1fs)" % _missile_cd, Color("9aa0a6"))
		return
	var target := aimed if aimed else _missile_target()
	if target == null:
		Game.notify.emit("No missile lock. Point at a pirate.", Color("9aa0a6"))
		return
	if not Game.spend_energy(MISSILE_COST):
		Game.notify.emit("Not enough energy for missiles.", Color("ff6b6b"))
		return
	var rack := Game.has_upgrade("missile_rack")
	_missile_cd = MISSILE_CD * (0.6 if rack else 1.0)
	for i in (2 if rack else 1):
		var side := 1.0 if i == 0 else -1.0
		var from := global_transform * Vector3(1.2 * side, 0.4, -1.0)
		var dir := (-global_basis.z + global_basis.x * side * 0.4 + global_basis.y * 0.2).normalized()
		world.spawn_space_bolt(from, dir, 90.0, Game.space_weapon_damage() * 3.2, Color("ffb86b"), true, 0.5, target)
	Sound.play("boost", -4.0, 0.1)


## The pirate closest to the crosshair, within a 30 degree cone.
func _missile_target() -> SpaceEnemy:
	var best: SpaceEnemy = null
	var best_dot := cos(deg_to_rad(30.0))
	var fwd := -camera.global_basis.z
	for e in world.space_enemies:
		if not e.is_alive():
			continue
		var to: Vector3 = e.global_position - camera.global_position
		if to.length() > 800.0:
			continue
		var d := to.normalized().dot(fwd)
		if d > best_dot:
			best_dot = d
			best = e
	return best


func _on_died() -> void:
	if dead:
		return
	dead = true
	_stop_laser()
	visual.visible = false
	velocity = Vector3.ZERO
	CombatFx.explosion(world, global_position, Game.robot().color, 3.0)
	Sound.play("death", -2.0, 0.0)
	# a fifth of the raw cargo spills into space: fly back for it if you dare
	var lost := Game.spill_cargo(0.2)
	var units := 0
	for it in lost:
		units += lost[it]
		world.spawn_shards(global_position, it, lost[it], 3.0)
	if units > 0:
		Game.notify.emit("%d units of cargo spilled where your ship went down" % units, Color("ffb86b"))
	world.hud.show_death()
	world.reset_aggro()
	await get_tree().create_timer(4.0).timeout
	if not is_inside_tree():
		return
	var pl: Dictionary = world.planets[0]
	global_position = pl.node.global_position + Vector3(0.3, 0.3, 1.0).normalized() * pl.radius * 4.0
	look_at(pl.node.global_position, Vector3.UP)
	snap_camera()
	Game.hull = Game.max_hull() * 0.6
	Game.shield = Game.max_shield()
	Game.energy = maxf(Game.energy, Game.max_energy() * 0.5)
	Game.hull_changed.emit()
	Game.energy_changed.emit(Game.energy, Game.max_energy())
	visual.visible = true
	dead = false
	world.hud.hide_death()
	Game.big_notify.emit("REBOOTED", "Emergency beacon recovered you near %s" % pl.data.name, Color("6ee06a"))


func _show_beam(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	_beam.visible = true
	var y := (to - from).normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	_beam.global_transform = Transform3D(Basis(x, y * len, z), (from + to) * 0.5)
	_beam_mat.albedo_color.a = 0.6 + randf() * 0.35


func _stop_laser() -> void:
	_beam.visible = false
	if _lasering:
		_lasering = false
		Sound.loop_stop("laser", 0.12)



## Parallax dust that hangs still in space (so you feel your speed), plus
## streaks that rush past while boosting.
func _build_space_fx() -> void:
	var dq := QuadMesh.new()
	dq.size = Vector2(0.18, 0.18)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_texture = ModelUtil.soft_dot()
	dm.albedo_color = Color(0.75, 0.85, 1.0, 0.55)
	dq.material = dm
	_dust = CPUParticles3D.new()
	_dust.mesh = dq
	_dust.amount = [120, 260, 420][Sound.gfx_quality]
	_dust.lifetime = 9.0
	_dust.preprocess = 9.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(70, 45, 70)
	_dust.gravity = Vector3.ZERO
	_dust.initial_velocity_min = 0.0
	_dust.initial_velocity_max = 0.4
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.6
	add_child(_dust)
	var sm := CylinderMesh.new()
	sm.top_radius = 0.025
	sm.bottom_radius = 0.025
	sm.height = 6.0
	sm.radial_segments = 4
	sm.rings = 1
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.albedo_color = Color(0.7, 0.9, 1.0, 0.5)
	sm.material = smat
	_streaks = CPUParticles3D.new()
	_streaks.mesh = sm
	_streaks.amount = 90
	_streaks.lifetime = 0.45
	_streaks.local_coords = true
	_streaks.emitting = false
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(22, 14, 4)
	_streaks.position = Vector3(0, 0, -40)
	_streaks.direction = Vector3(0, 0, 1)
	_streaks.spread = 2.0
	_streaks.initial_velocity_min = 160.0
	_streaks.initial_velocity_max = 220.0
	_streaks.gravity = Vector3.ZERO
	_streaks.particle_flag_align_y = true
	add_child(_streaks)



func _gem_text(info: Dictionary) -> String:
	var total: int = Game.world_gems(info).size()
	var left := Game.gems_left(info)
	if not Game.gems_taken.has(info.key):
		return "uncharted core"
	return "%d / %d gems left" % [left, total] if left > 0 else "core picked clean"
