extends Node3D
## Hyperspace: the trip between stars. You fly down a tunnel of light; on a
## calm jump it's a short, pretty ride (Space to skip). If pirates interdict,
## they drop into the tunnel ahead in waves. Steer with WASD to dodge their
## fire, aim with the mouse, shoot with the left button, and fire homing
## missiles with the right. Survive to the far end and you burst out at the
## destination. Get knocked out and you still arrive, but battered and
## lighter by some cargo.

const R := 15.0 # how far from the tube's axis you can fly
const SHOT_SPEED := 340.0
const ENEMY_BOLT_SPEED := 85.0

var hud: CanvasLayer
var player: Node3D # the robot, flying
var visual: RobotVisual
var camera: Camera3D
var env: Environment
var tunnel_mat: ShaderMaterial
var info := {}
var enemies: Array = [] # {node, type, def, hp, max_hp, pos, vel, station, t, cd, burst, state, dive}
var shots: Array = [] # {node, pos, vel, life, dmg, hostile, homing}
var mines: Array = [] # {node, pos, vel, hp}
var waves: Array = [] # [time, type, count]
var duration := 8.0
var elapsed := 0.0
var interdicted := false
var kills := 0
var ended := false
var knocked := false
var _vel := Vector2.ZERO
var _fire_cd := 0.0
var _missile_cd := 0.0
var _side := 1.0
var _aim := Vector3(0, 0, -100)
var _aim_enemy := -1
var _crosshair: Control
var _bar: ProgressBar
var _status: Label
var _shake := 0.0
var _alarm := 0.0
var _streaks: CPUParticles3D
var _core: MeshInstance3D
var _bolt_mesh: CapsuleMesh
var _t := 0.0


func _ready() -> void:
	info = Game.warp
	if info.is_empty():
		# launched directly (dev): an interdicted jump from home
		info = {"from": 0, "to": 3, "relay": false, "interdict": true, "dist": 20.0, "level": 3}
		Game.warp = info
	interdicted = info.interdict
	var dist: float = info.dist
	duration = clampf(38.0 + dist * 0.5, 40.0, 70.0) if interdicted else 7.0
	_build_env()
	_build_tunnel()
	_build_player()
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.mode = "warp"
	add_child(hud)
	_build_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if interdicted else Input.MOUSE_MODE_CAPTURED
	Sound.stop_all_loops()
	Sound.loop_start("hyper", "hyper_loop", -8.0, "Ambience")
	var dest: String = Galaxy.star(int(info.to)).name
	if interdicted:
		Sound.play_music("hyperspace", 1.0)
		_plan_waves()
		hud.show_location_banner("Hyperspace", "Bound for %s" % dest)
		get_tree().create_timer(2.5).timeout.connect(func():
			if is_instance_valid(self):
				_alarm = 1.0
				Sound.play("klaxon", -6.0, 0.0)
				hud.big("INTERDICTION", "Pirates are dropping into the tunnel!", Color("ff4d4d"))
				Game.tip("hyperspace", "Pirates in hyperspace! Steer with WASD to dodge, aim with the mouse, hold Left Mouse to fire and Right Mouse for homing missiles. Reach the far end to escape.")
		)
	else:
		Sound.play_music("space", 2.0)
		hud.show_location_banner("Hyperspace", ("Riding the Circuit to %s" if info.relay else "Bound for %s") % dest)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("020208")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 1.0)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 20, 0)
	key.light_energy = 0.9
	key.light_color = Color(0.8, 0.85, 1.0)
	add_child(key)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.position = Vector3(0, 3.2, 11.0)
	add_child(camera)
	camera.make_current()


func _build_tunnel() -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 34.0
	cyl.bottom_radius = 34.0
	cyl.height = 900.0
	cyl.radial_segments = 64
	cyl.rings = 8
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	mi.rotation.x = -PI * 0.5 # the tube's top (UV.y = 0) points down -Z, away from us
	mi.position = Vector3(0, 0, -400.0)
	tunnel_mat = ShaderMaterial.new()
	tunnel_mat.shader = preload("res://shaders/hyperspace_tunnel.gdshader")
	if info.relay:
		tunnel_mat.set_shader_parameter("col_a", Color(0.2, 0.8, 1.0))
		tunnel_mat.set_shader_parameter("col_b", Color(0.8, 1.0, 1.0))
	mi.material_override = tunnel_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# the light at the end of the tunnel
	_core = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 40.0
	sp.height = 80.0
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.4, 1.5, 1.8)
	sp.material = cm
	_core.mesh = sp
	_core.position = Vector3(0, 0, -840)
	add_child(_core)
	# speed lines rushing past
	_streaks = CPUParticles3D.new()
	_streaks.amount = 220
	_streaks.lifetime = 1.2
	_streaks.preprocess = 1.2
	_streaks.local_coords = false
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(26, 26, 10)
	_streaks.position = Vector3(0, 0, -260)
	_streaks.direction = Vector3(0, 0, 1)
	_streaks.spread = 0.0
	_streaks.initial_velocity_min = 240.0
	_streaks.initial_velocity_max = 320.0
	_streaks.gravity = Vector3.ZERO
	# thin rods already pointing down the tube (Z), so they streak past lengthwise
	var q := BoxMesh.new()
	q.size = Vector3(0.05, 0.05, 7.0)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.albedo_color = Color(0.8, 0.9, 1.0, 0.55)
	q.material = qm
	_streaks.mesh = q
	add_child(_streaks)
	_bolt_mesh = CapsuleMesh.new()
	_bolt_mesh.radius = 0.25
	_bolt_mesh.height = 2.6


func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	visual = RobotVisual.new()
	player.add_child(visual)
	visual.setup(Game.robot_id)
	visual.apply_look.call_deferred(Game.appearance)
	visual.flying = true
	visual.boost = true
	visual.rotation = Vector3(-PI * 0.45, 0, 0)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pc.position = Vector2(-320, 84)
	pc.custom_minimum_size = Vector2(640, 0)
	pc.theme = UiKit.theme()
	pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.02, 0.02, 0.08, 0.75), Color(0.6, 0.5, 1.0, 0.5), 8, 1, 8))
	layer.add_child(pc)
	var top := VBoxContainer.new()
	pc.add_child(top)
	_status = UiKit.label("", 16, Color("c9b8ff"), true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_status)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(600, 8)
	top.add_child(_bar)
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(func():
		var locked := _aim_enemy >= 0
		var col := Color("ff5d5d") if locked else Color(0.7, 0.95, 1.0, 0.9)
		var r := 14.0 if locked else 11.0
		_crosshair.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 2.0)
		for k in 4:
			var d := Vector2.from_angle(k * PI * 0.5 + PI * 0.25)
			_crosshair.draw_line(d * (r + 3.0), d * (r + 9.0), col, 2.0)
		_crosshair.draw_circle(Vector2.ZERO, 2.0, col)
	)
	layer.add_child(_crosshair)
	_crosshair.visible = interdicted


# --------------------------------------------------------------------------
# waves
# --------------------------------------------------------------------------

func _plan_waves() -> void:
	var lvl: int = info.level
	var first := Game.visited_stars.size() <= 2 and Game.interdictions == 0
	waves = [[4.0, "swarmer", 3 if first else 4]]
	if first:
		waves.append([16.0, "raider", 1])
		waves.append([26.0, "swarmer", 3])
		return
	waves.append([14.0, "raider", 2 + (1 if lvl >= 6 else 0)])
	waves.append([22.0, "mines", 5])
	waves.append([28.0, "swarmer", 5])
	if duration > 45.0 or lvl >= 8:
		waves.append([36.0, "gunship", 1])
		waves.append([40.0, "raider", 2])
	if lvl >= 12:
		waves.append([48.0, "swarmer", 6])


func _spawn(type: String, n: int) -> void:
	if type == "mines":
		for i in n:
			_spawn_mine(i)
		return
	var def: Dictionary = Db.SPACE_ENEMIES[type]
	var lvl: int = info.level
	for i in n:
		var node := Node3D.new()
		var m := ModelUtil.instance(def.model)
		m.rotation.y = PI # pirates face back toward you
		node.add_child(m)
		ModelUtil.add_rim(m, 0.5, 0.8)
		add_child(node)
		var ang := randf() * TAU
		var station := Vector3(cos(ang) * randf_range(4.0, 10.0), sin(ang) * randf_range(3.0, 8.0), randf_range(-70.0, -34.0))
		if type == "gunship":
			station = Vector3(randf_range(-4, 4), randf_range(-1, 4), -80.0)
		var hp: float = (def.hp[0] + def.hp[1] * lvl) * (0.55 if type != "gunship" else 0.5)
		var first_cd := randf_range(2.5, 5.0) if type == "swarmer" else randf_range(1.0, 2.5)
		var e := {"node": node, "type": type, "def": def, "hp": hp, "max_hp": hp, "pos": Vector3(station.x * 3.0, station.y * 3.0, -520.0 - i * 40.0),
			"station": station, "t": randf() * 10.0, "cd": first_cd, "burst": 0, "state": "arrive", "flash": 0.0,
			"dmg": (def.dmg[0] + def.dmg[1] * lvl) * (0.35 if type == "swarmer" else 0.45)}
		node.position = e.pos
		enemies.append(e)
	Sound.play("atmo_entry", -10.0, 0.1)


func _spawn_mine(i: int) -> void:
	var node := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.4
	sp.height = 2.8
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color("2a2530")
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.25, 0.2)
	mm.emission_energy_multiplier = 0.6
	sp.material = mm
	node.mesh = sp
	for k in 6:
		var spike := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.35
		c.height = 1.4
		c.material = mm
		spike.mesh = c
		var d: Vector3 = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK][k]
		spike.position = d * 1.7
		spike.look_at_from_position(d * 1.7, d * 3.0, Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT)
		spike.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		node.add_child(spike)
	add_child(node)
	var p := Vector3(randf_range(-R, R) * 0.8, randf_range(-R, R) * 0.6, -300.0 - i * 45.0)
	node.position = p
	mines.append({"node": node, "pos": p, "vel": Vector3(0, 0, 48.0), "hp": 20.0 + info.level * 4.0})


# --------------------------------------------------------------------------
# frame
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ended:
		return
	_t += delta
	elapsed += delta
	_alarm = move_toward(_alarm, 1.0 if (interdicted and not enemies.is_empty()) else 0.0, delta * 0.8)
	tunnel_mat.set_shader_parameter("alarm", _alarm)
	tunnel_mat.set_shader_parameter("speed", 3.0 + minf(elapsed, 3.0) * 0.5)
	# the light at the end swells as you arrive
	var f := clampf(elapsed / duration, 0.0, 1.0)
	_core.position.z = lerpf(-840.0, -300.0, f * f)
	_bar.value = f
	var dest: String = Galaxy.star(int(info.to)).name
	if interdicted:
		_status.text = "HYPERSPACE  →  %s    ·    %ds    ·    pirates down: %d" % [dest, int(ceil(duration - elapsed)), kills]
	else:
		_status.text = "HYPERSPACE  →  %s    ·    [Space] skip" % dest
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact"):
			elapsed = duration
	# waves
	for w in waves.duplicate():
		if elapsed >= float(w[0]):
			waves.erase(w)
			_spawn(w[1], int(w[2]))
	_fly(delta)
	_aim_update()
	_fire(delta)
	_update_enemies(delta)
	_update_shots(delta)
	_update_mines(delta)
	_shake = maxf(0.0, _shake - delta * 1.8)
	camera.h_offset = randf_range(-1, 1) * _shake * _shake * 0.8
	camera.v_offset = randf_range(-1, 1) * _shake * _shake * 0.8
	if elapsed >= duration:
		_finish()


func _fly(delta: float) -> void:
	var ui := Game.ui_open
	var input := Vector2.ZERO if ui else Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	_vel = _vel.lerp(input * 22.0, clampf(delta * 5.0, 0.0, 1.0))
	var p := Vector2(player.position.x, player.position.y) + _vel * delta
	if p.length() > R:
		p = p.normalized() * R
	player.position = Vector3(p.x, p.y, 0.0)
	# bank into turns
	visual.rotation = Vector3(-PI * 0.45 - _vel.y * 0.01, 0.0, -_vel.x * 0.025)
	# the camera trails behind, following most of the way
	camera.position = camera.position.lerp(Vector3(p.x * 0.7, p.y * 0.7 + 3.2, 11.0), clampf(delta * 4.0, 0.0, 1.0))
	camera.look_at(Vector3(p.x * 0.5, p.y * 0.5 + 0.5, -40.0), Vector3.UP)


func _aim_update() -> void:
	var mp := get_viewport().get_mouse_position()
	if not interdicted:
		return
	_crosshair.position = mp
	_crosshair.queue_redraw()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	_aim_enemy = -1
	var best := INF
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var to: Vector3 = (e.pos as Vector3) - from
		var along := to.dot(dir)
		if along <= 0.0:
			continue
		var miss := (to - dir * along).length()
		var rad: float = float(e.def.size) * 1.4 + 1.5
		if miss < rad and along < best:
			best = along
			_aim_enemy = i
	if _aim_enemy >= 0:
		_aim = enemies[_aim_enemy].pos
	else:
		# aim at a point far down the tunnel along the ray
		_aim = from + dir * 140.0


func _fire(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_missile_cd = maxf(0.0, _missile_cd - delta)
	if not interdicted or Game.ui_open:
		return
	if Input.is_action_pressed("fire") and _fire_cd <= 0.0 and Game.energy > 0.6:
		_fire_cd = 0.12
		_side = -_side
		Game.drain_energy(0.5)
		var from := player.position + Vector3(_side * 0.9, 0.6, -1.2)
		var dir := (_aim - from).normalized()
		_add_shot(from, dir * SHOT_SPEED, Game.space_weapon_damage() * 0.9, false, Color(0.5, 0.95, 1.0))
		Sound.play("blaster", -12.0, 0.08, "SFX", 0.05)
	if Input.is_action_just_pressed("fire2") and _missile_cd <= 0.0:
		var target := _aim_enemy
		if target < 0:
			# nearest pirate to the crosshair
			var bd := INF
			for i in enemies.size():
				var d := (enemies[i].pos as Vector3).distance_to(_aim)
				if d < bd:
					bd = d
					target = i
		if target >= 0:
			_missile_cd = 1.6 if Game.has_upgrade("missile_rack") else 2.6
			for k in (2 if Game.has_upgrade("missile_rack") else 1):
				var from2 := player.position + Vector3((k * 2 - 1) * 1.2, 1.0, 0)
				_add_shot(from2, Vector3(0, 2, -60), Game.space_weapon_damage() * 5.0, false, Color(1.0, 0.7, 0.3), enemies[target].node)
			Sound.play("boost", -8.0, 0.1)


func _add_shot(from: Vector3, vel: Vector3, dmg: float, hostile: bool, col: Color, homing: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col * (3.0 if not hostile else 2.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = from
	if hostile:
		mi.scale = Vector3(1.6, 1.6, 1.6)
	shots.append({"node": mi, "pos": from, "vel": vel, "life": 3.0, "dmg": dmg, "hostile": hostile, "homing": homing})


func _update_shots(delta: float) -> void:
	for s in shots.duplicate():
		if s.homing != null:
			if is_instance_valid(s.homing):
				var want: Vector3 = ((s.homing as Node3D).position - (s.pos as Vector3)).normalized() * 160.0
				s.vel = (s.vel as Vector3).lerp(want, clampf(delta * 4.0, 0.0, 1.0))
			else:
				s.homing = null
		s.pos += s.vel * delta
		s.life -= delta
		var node: MeshInstance3D = s.node
		node.position = s.pos
		if (s.vel as Vector3).length() > 0.1:
			var v: Vector3 = s.vel
			node.look_at(node.position + v, Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.RIGHT)
			node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		var gone: bool = s.life <= 0.0
		if s.hostile:
			if (s.pos as Vector3).distance_to(player.position + Vector3(0, 0.6, 0)) < 1.8:
				_hurt(s.dmg)
				gone = true
			elif (s.pos as Vector3).z > 20.0:
				gone = true
		else:
			for e in enemies:
				if (s.pos as Vector3).distance_to(e.pos) < float(e.def.size) * 1.8 + 0.8:
					_hit_enemy(e, s.dmg)
					gone = true
					break
			if not gone:
				for mn in mines:
					if (s.pos as Vector3).distance_to(mn.pos) < 2.6:
						mn.hp -= s.dmg
						_burst(mn.pos, Color(1.0, 0.5, 0.3), 4)
						gone = true
						break
		if gone:
			node.queue_free()
			shots.erase(s)


func _update_enemies(delta: float) -> void:
	var pp := player.position
	for e in enemies.duplicate():
		e.t += delta
		e.flash = maxf(0.0, float(e.flash) - delta * 4.0)
		var st: Vector3 = e.station
		match e.state:
			"arrive":
				e.pos = (e.pos as Vector3).lerp(st, clampf(delta * 1.6, 0.0, 1.0))
				if (e.pos as Vector3).distance_to(st) < 3.0:
					e.state = "fight"
			"fight":
				# weave around the station
				var wob := Vector3(sin(e.t * 1.3) * 5.0, cos(e.t * 1.7) * 3.5, sin(e.t * 0.6) * 10.0)
				var target := st + wob
				if e.type == "swarmer":
					# swarmers line up and dive straight at you
					e.cd -= delta
					if e.cd <= 0.0 and not e.has("warn"):
						# a telegraph first: it flares and beeps, then commits to the dive
						e["warn"] = 0.8
						Sound.play("telegraph", -14.0, 0.1, "SFX", 0.2)
					if e.has("warn"):
						e.warn = float(e.warn) - delta
						e.flash = 1.0
						if float(e.warn) <= 0.0:
							e.erase("warn")
							e.state = "dive"
							e.dive = pp + Vector3(0, 0.6, 0)
				e.pos = (e.pos as Vector3).lerp(target, clampf(delta * 2.0, 0.0, 1.0))
				if e.type != "swarmer":
					e.cd -= delta
					if e.cd <= 0.0:
						if int(e.burst) < int(e.def.burst):
							e.burst = int(e.burst) + 1
							e.cd = float(e.def.cd) + 0.1
							var aim: Vector3 = pp + Vector3(_vel.x, _vel.y, 0) * 0.5 + Vector3(0, 0.6, 0)
							var dir: Vector3 = (aim - (e.pos as Vector3)).normalized()
							var n := 3 if e.type == "gunship" else 1
							for k in n:
								var spread := Vector3((k - (n - 1) * 0.5) * 0.06, 0, 0)
								_add_shot(e.pos, (dir + spread).normalized() * ENEMY_BOLT_SPEED, e.dmg, true, e.def.bolt)
							Sound.play("sentinel_shot", -16.0, 0.1, "SFX", 0.05)
						else:
							e.burst = 0
							e.cd = float(e.def.rest) + randf_range(0.2, 1.0)
			"dive":
				var d: Vector3 = (e.dive as Vector3) - (e.pos as Vector3)
				e.pos = (e.pos as Vector3) + d.normalized() * 55.0 * delta + Vector3(0, 0, 14.0 * delta)
				if (e.pos as Vector3).distance_to(pp + Vector3(0, 0.6, 0)) < 2.4:
					_hurt(e.dmg)
					_kill(e, false)
					continue
				if (e.pos as Vector3).z > (e.dive as Vector3).z - 1.0:
					# missed: loop round and come again from ahead
					e.pos = Vector3(e.pos.x, e.pos.y, -200.0)
					e.state = "arrive"
					e.cd = randf_range(3.5, 6.0)
		var node: Node3D = e.node
		node.position = e.pos
		node.rotation = Vector3(sin(e.t * 1.3) * 0.2, 0, cos(e.t * 1.1) * 0.35)
		if e.state == "dive":
			node.look_at(pp, Vector3.UP)
			node.rotate_y(PI)
		var s := 1.0 + float(e.flash) * 0.15
		node.scale = Vector3.ONE * s * (1.8 if e.type == "swarmer" else 1.5)


func _update_mines(delta: float) -> void:
	for mn in mines.duplicate():
		mn.pos += mn.vel * delta
		(mn.node as Node3D).position = mn.pos
		(mn.node as Node3D).rotate_y(delta * 1.5)
		if float(mn.hp) <= 0.0:
			CombatFx.explosion(self, mn.pos, Color(1.0, 0.5, 0.2), 2.5)
			Sound.play("enemy_die", -10.0, 0.1)
			mn.node.queue_free()
			mines.erase(mn)
			continue
		if (mn.pos as Vector3).distance_to(player.position + Vector3(0, 0.6, 0)) < 3.0:
			_hurt(18.0 + info.level * 2.0)
			CombatFx.explosion(self, mn.pos, Color(1.0, 0.4, 0.2), 4.0)
			Sound.play("slam", -6.0, 0.1)
			mn.node.queue_free()
			mines.erase(mn)
		elif (mn.pos as Vector3).z > 15.0:
			mn.node.queue_free()
			mines.erase(mn)


func _hit_enemy(e: Dictionary, dmg: float) -> void:
	e.hp -= dmg
	e.flash = 1.0
	_burst(e.pos, Color(1.0, 0.8, 0.4), 5)
	Sound.play("hit", -14.0, 0.1, "SFX", 0.04)
	if float(e.hp) <= 0.0:
		_kill(e, true)


func _kill(e: Dictionary, by_player: bool) -> void:
	# a crash right in your face stays small so it doesn't blind you
	var near := (e.pos as Vector3).z > -8.0
	CombatFx.explosion(self, e.pos, e.def.bolt, 0.8 if near else float(e.def.size) * 1.2)
	Sound.play("enemy_die", -6.0, 0.1)
	_shake = maxf(_shake, 0.35)
	if by_player:
		kills += 1
		var loot := Game.record_space_kill(e.type, int(info.level), false)
		for it in loot:
			Game.add_item(it, int(loot[it]), true, true)
	e.node.queue_free()
	enemies.erase(e)


func _burst(p: Vector3, col: Color, n: int) -> void:
	CombatFx.spark(self, p, col, 0.6 + n * 0.1)


func _hurt(amount: float) -> void:
	if knocked:
		return
	_shake = maxf(_shake, 0.55)
	Sound.play("player_hurt", -6.0, 0.1)
	if Game.take_damage(amount):
		_knocked_out()


func _knocked_out() -> void:
	# the ship is too damaged to hold the tunnel: you tumble out at the far end
	knocked = true
	Game.hull = Game.max_hull() * 0.25
	Game.hull_changed.emit()
	var lost := 0
	for it in Game.inventory.keys():
		if Db.ITEMS.get(it, {}).get("kind", "") == "resource":
			var q := int(floor(Game.count(it) * 0.25))
			if q > 0:
				Game.remove_item(it, q)
				lost += q
	hud.big("KNOCKED OUT OF HYPERSPACE", ("Pirates plundered %d units of cargo" % lost) if lost > 0 else "Your hull held together, barely", Color("ff6b6b"))
	elapsed = duration - 1.5


func _finish() -> void:
	if ended:
		return
	ended = true
	var repelled := interdicted and not knocked and waves.is_empty() and enemies.is_empty()
	if interdicted and not knocked:
		var bonus := 60 + int(info.level) * 15 + kills * 10
		if repelled:
			Game.add_credits(bonus)
			hud.big("INTERDICTION REPELLED", "%d pirates down  ·  +⌬ %d salvage bounty" % [kills, bonus], Color("6ee06a"))
		else:
			hud.big("OUTRAN THEM", "%d pirates down" % kills, Color("ffd23f"))
	Sound.play("warp", -4.0, 0.0)
	Sound.loop_stop("hyper", 0.8)
	var t := create_tween()
	t.tween_method(func(v: float): tunnel_mat.set_shader_parameter("intensity", v), 1.0, 4.0, 0.6)
	await t.finished
	Game.finish_warp({"repelled": repelled, "kills": kills})
