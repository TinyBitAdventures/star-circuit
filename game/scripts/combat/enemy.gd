class_name Enemy
extends CharacterBody3D
## A rogue drone. Wanders near its camp, aggroes on the player, chases,
## attacks (melee / ranged bolt / telegraphed slam), leashes home and heals.

const LEASH := 70.0
const SOCIAL_RADIUS := 12.0

var world: Node3D
var type := ""
var def: Dictionary
var level := 1
var elite := false
var max_hp := 1.0
var hp := 1.0
var state := "idle" # idle | chase | return | dead
var dir := Vector3.UP # unit position on the sphere
var home_dir := Vector3.UP
var heading := Vector3.FORWARD
var camp_id := 0

var _model: Node3D
var _parts := {}
var _rest := {}
var _bar: MeshInstance3D
var _name: Label3D
var _atk_cd := 0.0
var _t := 0.0
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _slam_timer := -1.0
var _telegraph: MeshInstance3D
var _knock := Vector3.ZERO
var _flash := 0.0
var _swing := 0.0


func setup(w: Node3D, t: String, lvl: int, start_dir: Vector3, camp: int) -> void:
	world = w
	type = t
	def = Db.ENEMIES[t]
	level = lvl
	elite = def.get("elite", false)
	camp_id = camp
	max_hp = def.hp[0] + def.hp[1] * level
	hp = max_hp
	dir = start_dir.normalized()
	home_dir = dir
	heading = PlanetGen.align_basis(dir, randf() * TAU).z
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 0

	_model = ModelUtil.instance(def.model)
	add_child(_model)
	var s: float = def.scale
	_model.scale = Vector3.ONE * s
	ModelUtil.add_rim(_model, 0.4, 0.2)
	for n in ["Torso", "ArmL", "ArmR", "LegL", "LegR", "Head", "Ring", "Cannon", "SawL", "SawR"]:
		var node := _model.find_child(n, true, false) as Node3D
		if node:
			_parts[n] = node
			_rest[n] = node.transform

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9 * s * (1.4 if elite else 1.0)
	cap.height = 2.4 * s * (1.5 if elite else 1.0)
	cs.shape = cap
	cs.position.y = cap.height * 0.5 + 0.2
	add_child(cs)

	var top := (4.2 if elite else 2.9) * s
	_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.8 if elite else 1.3, 0.16)
	_bar.mesh = q
	var bm := ShaderMaterial.new()
	bm.shader = load("res://shaders/billboard_bar.gdshader")
	_bar.material_override = bm
	_bar.position.y = top
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)
	_name = Label3D.new()
	_name.text = ("%s  %d%s" % [def.name, level, "  Elite" if elite else ""])
	_name.font = UiKit.body_font()
	_name.font_size = 44
	_name.outline_size = 12
	_name.pixel_size = 0.006
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.no_depth_test = true
	_name.fixed_size = false
	_name.position.y = top + 0.35
	add_child(_name)
	_update_plate()
	_place()


func _update_plate() -> void:
	var c := Db.con_color(level, Game.level)
	_name.modulate = CombatFx.hdr(Color("ffd23f") if elite else c)
	_bar.set_instance_shader_parameter("fill", hp / max_hp)
	_bar.set_instance_shader_parameter("bar_color", Color("e0453a") if state != "return" else Color("8a8a8a"))


func is_alive() -> bool:
	return state != "dead"


func _physics_process(delta: float) -> void:
	if state == "dead":
		return
	_t += delta
	_atk_cd = maxf(0.0, _atk_cd - delta)
	var player: Node3D = world.player
	var player_ok: bool = player != null and not player.dead
	var ppos: Vector3 = player.global_position if player else Vector3.ZERO
	var dist := global_position.distance_to(ppos) if player_ok else INF
	var home_pos: Vector3 = world.gen.surface_point(home_dir)

	# slam telegraph resolves regardless of state
	if _slam_timer >= 0.0:
		_slam_timer -= delta
		if _slam_timer < 0.0:
			_resolve_slam()
		_animate(delta, false)
		_update_plate_visibility(dist)
		return

	match state:
		"idle":
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_wander_timer = randf_range(3.0, 7.0)
				var b := PlanetGen.align_basis(home_dir, randf() * TAU)
				_wander_target = world.gen.surface_point((home_dir + b.z * randf_range(0.0, 14.0) / world.gen.radius).normalized())
			if global_position.distance_to(_wander_target) > 1.5:
				_move_toward(_wander_target, def.speed * 0.35, delta)
			if player_ok and dist < def.aggro:
				aggro()
		"chase":
			if not player_ok or global_position.distance_to(home_pos) > LEASH:
				_leash()
			else:
				var want: float = def.range * 0.85
				if def.style == "ranged":
					if dist > want:
						_move_toward(ppos, def.speed, delta)
					elif dist < 9.0:
						_move_toward(global_position + (global_position - ppos), def.speed * 0.8, delta)
					_face(ppos, delta)
				else:
					if dist > want:
						_move_toward(ppos, def.speed * (1.25 if dist > 15.0 else 1.0), delta)
					else:
						_face(ppos, delta)
				if dist <= def.range and _atk_cd <= 0.0:
					_attack(player, dist)
		"return":
			_move_toward(home_pos, def.speed * 1.6, delta)
			hp = minf(max_hp, hp + max_hp * delta * 0.5)
			_bar.set_instance_shader_parameter("fill", hp / max_hp)
			if global_position.distance_to(home_pos) < 3.0:
				state = "idle"
				hp = max_hp
				_update_plate()

	# knockback
	if _knock.length() > 0.1:
		var t := _knock * delta
		dir = (dir + (t - dir * t.dot(dir)) / world.gen.radius).normalized()
		_knock = _knock.lerp(Vector3.ZERO, delta * 6.0)
	_place()
	_animate(delta, state == "chase")
	_update_plate_visibility(dist)


func _update_plate_visibility(dist: float) -> void:
	var show := state == "chase" or dist < 40.0
	_bar.visible = show
	_name.visible = show


func _move_toward(target: Vector3, speed: float, delta: float) -> void:
	var to := target - global_position
	to -= dir * to.dot(dir)
	if to.length() < 0.05:
		return
	var want := to.normalized()
	heading = heading.slerp(want, clampf(delta * 6.0, 0.0, 1.0))
	heading = (heading - dir * heading.dot(dir)).normalized()
	var next: Vector3 = (dir + heading * speed * delta / world.gen.radius).normalized()
	var gen: PlanetGen = world.gen
	if gen.has_liquid() and gen.height(next) < gen.sea - 0.004 and def.hover <= 0.0 and type != "sentinel":
		return # won't wade into deep liquid
	dir = next


func _face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	to -= dir * to.dot(dir)
	if to.length() > 0.05:
		heading = heading.slerp(to.normalized(), clampf(delta * 8.0, 0.0, 1.0))
		heading = (heading - dir * heading.dot(dir)).normalized()


func _place() -> void:
	var hover := 0.0
	if type == "sentinel":
		hover = 1.2 + sin(_t * 2.0) * 0.3
	elif type == "scrapper":
		hover = 0.3 + sin(_t * 4.0) * 0.15
	var gen: PlanetGen = world.gen
	var base_r := gen.surface_radius(dir)
	if type == "sentinel" and gen.has_liquid():
		base_r = maxf(base_r, gen.sea_radius())
	global_position = dir * (base_r + hover)
	var back := -heading
	global_basis = Basis(dir.cross(back).normalized(), dir, back).orthonormalized()


func _animate(delta: float, engaged: bool) -> void:
	_swing = maxf(0.0, _swing - delta * 3.0)
	var sw := sin(_swing * PI)
	if _parts.has("Torso"):
		var tilt := 0.18 if engaged and type == "scrapper" else 0.0
		_pose("Torso", Vector3.ZERO, Vector3(tilt - sw * 0.2, 0, 0))
	if _parts.has("SawL"):
		_parts.SawL.rotation.x = _t * 25.0
		_parts.SawR.rotation.x = -_t * 25.0
	if _parts.has("Ring"):
		_parts.Ring.rotation.z = _t * (3.0 if engaged else 1.0)
	var walk := sin(_t * 7.0) * (0.5 if type == "brute" and state != "idle" else 0.2)
	if type == "brute":
		var raise := 1.0 if _slam_timer >= 0.0 else 0.0
		_pose("ArmL", Vector3.ZERO, Vector3(-walk * 0.5 - raise * 2.4 + sw * 1.5, 0, 0))
		_pose("ArmR", Vector3.ZERO, Vector3(walk * 0.5 - raise * 2.4 + sw * 1.5, 0, 0))
		_pose("LegL", Vector3.ZERO, Vector3(walk, 0, 0))
		_pose("LegR", Vector3.ZERO, Vector3(-walk, 0, 0))
	elif _parts.has("ArmL"):
		_pose("ArmL", Vector3.ZERO, Vector3(-sw * 1.6, 0, 0))
		_pose("ArmR", Vector3.ZERO, Vector3(-sw * 1.6, 0, 0))
	if _flash > 0.0:
		_flash -= delta
		_model.scale = Vector3.ONE * def.scale * (1.0 + _flash * 0.6)


func _pose(part: String, offset: Vector3, rot: Vector3) -> void:
	var n: Node3D = _parts.get(part)
	if n == null:
		return
	var rest: Transform3D = _rest[part]
	n.transform = n.transform.interpolate_with(Transform3D(rest.basis * Basis.from_euler(rot), rest.origin + offset), 0.3)


func damage_output() -> float:
	var d: float = def.dmg[0] + def.dmg[1] * level
	return d * clampf(1.0 + (level - Game.level) * 0.08, 0.5, 2.0)


func _attack(player: Node3D, _dist: float) -> void:
	_atk_cd = def.cd * randf_range(0.9, 1.15)
	match def.style:
		"melee":
			_swing = 1.0
			Sound.play_3d("saw_swipe", global_position, -6.0)
			world.damage_player(damage_output(), self)
		"ranged":
			var muzzle: Vector3 = global_position + dir * 1.8 + heading * 0.8
			Sound.play_3d("sentinel_shot", muzzle, -6.0)
			world.spawn_enemy_bolt(muzzle, player.global_position + player.global_basis.y * 1.0, damage_output(), Color("ff3d9a"))
		"slam":
			_start_slam()


func _start_slam() -> void:
	_slam_timer = 0.95
	Sound.play_3d("telegraph", global_position, -4.0, 0.0, 20.0)
	_telegraph = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.6
	cyl.bottom_radius = 4.6
	cyl.height = 0.08
	cyl.radial_segments = 40
	_telegraph.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 0.1, 0.05, 0.35)
	m.no_depth_test = false
	_telegraph.material_override = m
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_telegraph)
	_telegraph.global_transform = Transform3D(PlanetGen.align_basis(dir), world.gen.surface_point(dir) + dir * 0.15)
	_telegraph.scale = Vector3(0.2, 1, 0.2)
	var tw := _telegraph.create_tween()
	tw.tween_property(_telegraph, "scale", Vector3.ONE, 0.9)


func _resolve_slam() -> void:
	_swing = 1.0
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	var center: Vector3 = world.gen.surface_point(dir)
	world.shockwave(center, 4.6, Color(1.0, 0.4, 0.2))
	Sound.play_3d("slam", center, 0.0, 0.05, 24.0)
	var player: Node3D = world.player
	if player and not player.dead and player.global_position.distance_to(center) < 4.8:
		world.damage_player(damage_output(), self)
		player.knockback((player.global_position - center).normalized() * 7.0 + player.global_basis.y * 5.0)


func aggro() -> void:
	if state == "dead" or state == "chase":
		return
	state = "chase"
	_update_plate()
	# WoW-style social aggro: the rest of the camp joins in
	for e in world.enemies:
		if e != self and e.is_alive() and e.state == "idle" and e.global_position.distance_to(global_position) < SOCIAL_RADIUS:
			e.aggro()


func _leash() -> void:
	state = "return"
	_slam_timer = -1.0
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_update_plate()


func knockback(v: Vector3) -> void:
	_knock += v


## Returns true if this hit killed it.
func take_hit(amount: float, crit := false) -> bool:
	if state == "dead" or state == "return":
		return false
	hp -= amount
	_flash = 0.15
	world.floating_text(global_position + dir * (3.2 if elite else 2.4), ("%d!" if crit else "%d") % int(amount), Color("ffe066") if crit else Color.WHITE, crit)
	if state == "idle":
		aggro()
	_update_plate()
	if hp <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	state = "dead"
	collision_layer = 0
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_bar.visible = false
	_name.visible = false
	Sound.play_3d("enemy_die", global_position, 0.0 if elite else -3.0, 0.1, 22.0)
	Game.record_kill(type, level, elite)
	world.on_enemy_killed(self)
	world.explosion(global_position + dir * 1.2, Color(1.0, 0.45, 0.2), 2.2 if elite else 1.3)
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
