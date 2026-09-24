class_name SpaceEnemy
extends StaticBody3D
## A pirate craft. Patrols near its spawn, aggroes on the player, then flies
## according to its style: fighter (strafing runs), brawler (stand-off
## volleys), kamikaze (ram and detonate) or flagship (circle + shielded).

const LAYER := 16
const LEASH := 1200.0
const BOLT_SPEED := 190.0

var world: Node3D
var type := ""
var def: Dictionary
var level := 1
var elite := false
var max_hp := 1.0
var hp := 1.0
var max_shield := 0.0
var shield := 0.0
var state := "patrol" # patrol | attack | return | dead
var home := Vector3.ZERO
var velocity := Vector3.ZERO

var _model: Node3D
var _bar: MeshInstance3D
var _sbar: MeshInstance3D
var _name: Label3D
var _patrol_target := Vector3.ZERO
var _cd := 0.0
var _burst := 0
var _evade_t := 0.0
var _evade_dir := Vector3.ZERO
var _last_hit := -100.0
var _flash := 0.0
var _orbit_sign := 1.0
var gate: Array = [] # while any of these live, this ship can't be hurt


func setup(w: Node3D, t: String, lvl: int, pos: Vector3, home_pos: Vector3) -> void:
	world = w
	type = t
	def = Db.SPACE_ENEMIES[t]
	level = lvl
	elite = def.get("elite", false)
	max_hp = def.hp[0] + def.hp[1] * lvl
	hp = max_hp
	max_shield = def.shield[0] + def.shield[1] * lvl
	shield = max_shield
	home = home_pos
	collision_layer = LAYER
	collision_mask = 0
	_model = ModelUtil.instance(def.model)
	add_child(_model)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = def.size * 1.1
	cs.shape = sp
	add_child(cs)
	_bar = _make_bar(Color("e0453a"), def.size * 1.6 + 2.0)
	if max_shield > 0.0:
		_sbar = _make_bar(Color("5ab8ff"), def.size * 1.6 + 2.5)
	_name = Label3D.new()
	_name.text = "%s  %d%s" % [def.name, level, "  Elite" if elite else ""]
	_name.font = UiKit.body_font()
	_name.font_size = 24
	_name.outline_size = 8
	_name.fixed_size = true
	_name.pixel_size = 0.0011
	_name.no_depth_test = true
	_name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name.modulate = CombatFx.hdr(Color("ffd23f") if elite else Db.con_color(level, Game.level), 1.6)
	_name.position.y = def.size * 1.6 + 4.0
	add_child(_name)
	position = pos
	_orbit_sign = 1.0 if randf() < 0.5 else -1.0
	_pick_patrol()
	_update_bars()


func _make_bar(col: Color, y: float) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(def.size * 1.2 + 1.5, 0.25 + def.size * 0.03)
	b.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/billboard_bar.gdshader")
	b.material_override = m
	b.position.y = y
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	b.set_instance_shader_parameter("bar_color", col)
	return b


func _update_bars() -> void:
	_bar.set_instance_shader_parameter("fill", hp / max_hp)
	if _sbar:
		_sbar.set_instance_shader_parameter("fill", shield / max_shield if max_shield > 0.0 else 0.0)


func is_alive() -> bool:
	return state != "dead"


func _pick_patrol() -> void:
	_patrol_target = home + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * randf_range(30.0, 140.0)


func _physics_process(delta: float) -> void:
	if state == "dead":
		return
	var player: Node3D = world.player
	var alive_player: bool = player != null and not player.dead
	var ppos: Vector3 = player.global_position if player else Vector3.ZERO
	var dist := global_position.distance_to(ppos) if alive_player else INF
	_cd = maxf(0.0, _cd - delta)
	var desired := -global_basis.z
	var speed: float = def.speed
	var now := Time.get_ticks_msec() / 1000.0

	match state:
		"patrol":
			speed *= 0.45
			if global_position.distance_to(_patrol_target) < 15.0:
				_pick_patrol()
			desired = (_patrol_target - global_position).normalized()
			if def.style == "turret":
				speed = 0.0
			if alive_player and dist < (float(def.range) + 80.0 if def.style == "turret" else (420.0 if elite else 320.0)) and not (world.station and ppos.distance_to(world.station.global_position) < OrbitalStation.SAFE_RADIUS):
				aggro()
		"return":
			desired = (home - global_position).normalized()
			speed *= 1.3
			hp = minf(max_hp, hp + max_hp * delta * 0.3)
			shield = max_shield
			_update_bars()
			if global_position.distance_to(home) < 60.0:
				state = "patrol"
		"attack":
			if not alive_player or global_position.distance_to(home) > LEASH:
				state = "return"
				return
			if def.style != "turret" and world.station and global_position.distance_to(world.station.global_position) < OrbitalStation.SAFE_RADIUS:
				state = "return" # the station's guns scare them off
				return
			var lead: Vector3 = ppos + player.velocity * clampf(dist / BOLT_SPEED, 0.0, 2.0)
			match def.style:
				"fighter":
					if _evade_t > 0.0:
						_evade_t -= delta
						desired = _evade_dir
						speed *= 1.25
					elif dist < 45.0:
						_evade_t = randf_range(1.2, 2.0)
						_evade_dir = ((global_position - ppos).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8).normalized()
					else:
						desired = (lead - global_position).normalized()
				"brawler":
					var want := 130.0
					var to := ppos - global_position
					desired = to.normalized()
					speed *= clampf((dist - want) / 60.0, -0.6, 1.0)
				"kamikaze":
					desired = (lead - global_position).normalized()
					speed *= 1.1
					if dist < def.size + 4.0:
						world.damage_player(_damage(), self)
						_die(false)
						return
				"turret":
					desired = (ppos - global_position).normalized()
					speed = 0.0
				"flagship":
					var to2 := ppos - global_position
					var tangent := to2.cross(Vector3.UP).normalized() * _orbit_sign
					desired = (to2.normalized() * clampf((dist - 190.0) / 80.0, -1.0, 1.0) + tangent).normalized()
					if now - _last_hit > 5.0 and shield < max_shield:
						shield = minf(max_shield, shield + max_shield * 0.2 * delta)
						_update_bars()
			# weapons
			if def.burst > 0 and dist < def.range and _cd <= 0.0:
				var aim := (lead - global_position).normalized()
				var facing := -global_basis.z
				var arc := 0.5 if def.style == "flagship" or def.style == "brawler" else 0.2
				# brawlers and flagships carry turrets: they fire from any heading
				if aim.dot(facing) > cos(arc) or def.style in ["brawler", "flagship", "turret"]:
					_fire(aim)
	# steering
	if desired.length() > 0.01:
		var fwd := -global_basis.z
		var new_fwd := _turn_toward(fwd, desired.normalized(), float(def.turn) * delta)
		if new_fwd.is_finite() and new_fwd.length() > 0.5:
			var up := Vector3.UP if absf(new_fwd.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
			# bank into turns
			var bank := fwd.cross(new_fwd).dot(up) * 30.0
			global_basis = Basis.looking_at(new_fwd, up).rotated(new_fwd, clampf(bank, -0.8, 0.8))
	velocity = velocity.lerp(-global_basis.z * speed, clampf(delta * 2.0, 0.0, 1.0))
	global_position += velocity * delta
	# don't fly through the star
	if global_position.length() < 160.0:
		global_position = global_position.normalized() * 160.0
	if _flash > 0.0:
		_flash -= delta
		_model.scale = Vector3.ONE * (1.0 + _flash * 0.5)
	var show: bool = alive_player and (state == "attack" or dist < 450.0)
	_bar.visible = show
	_name.visible = show
	if _sbar:
		_sbar.visible = show and shield > 0.0


## Rotate `fwd` toward `want` by at most `max_angle` radians. Unlike slerp this
## still works when the two point in opposite directions.
func _turn_toward(fwd: Vector3, want: Vector3, max_angle: float) -> Vector3:
	var ang := fwd.angle_to(want)
	if ang < 0.0001:
		return want
	var axis := fwd.cross(want)
	if axis.length() < 0.001:
		axis = global_basis.y
	return fwd.rotated(axis.normalized(), minf(ang, max_angle)).normalized()


func _damage() -> float:
	var d: float = def.dmg[0] + def.dmg[1] * level
	return d * clampf(1.0 + (level - Game.level) * 0.08, 0.5, 2.0)


func _fire(aim: Vector3) -> void:
	if _burst <= 0:
		_burst = def.burst
	_burst -= 1
	_cd = def.cd if _burst > 0 else def.rest * randf_range(0.8, 1.2)
	var spread := 0.025 if def.style != "flagship" else 0.06
	var dir := (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var side: Vector3 = global_basis.x * def.size * 0.6 * (1.0 if _burst % 2 == 0 else -1.0)
	var muzzle: Vector3 = global_position - global_basis.z * def.size + side
	world.spawn_space_bolt(muzzle, dir, BOLT_SPEED * (0.75 if def.style == "brawler" else 1.0), _damage(), def.bolt, false, 0.9 if def.style == "brawler" else 0.45)
	Sound.play_3d("turret_shot" if def.style != "brawler" else "sentinel_shot", muzzle, -6.0, 0.15, 40.0)


func aggro() -> void:
	if state == "dead" or state == "attack":
		return
	state = "attack"
	# the whole wing joins in
	for e in world.space_enemies:
		if e != self and e.is_alive() and e.state == "patrol" and e.global_position.distance_to(global_position) < 200.0:
			e.aggro()


## Returns true if destroyed.
func take_hit(amount: float, crit := false) -> bool:
	if state == "dead":
		return false
	for g in gate:
		if is_instance_valid(g) and g.is_alive():
			CombatFx.floating_text(world, global_position + Vector3.UP * (def.size + 2.0), Vector3.UP, "SHIELDED", Color("ff5d9a"))
			if state != "attack":
				aggro()
			return false
	_last_hit = Time.get_ticks_msec() / 1000.0
	_flash = 0.12
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hp -= amount - absorbed
	CombatFx.floating_text(world, global_position + Vector3.UP * (def.size + 2.0), Vector3.UP, ("%d!" if crit else "%d") % int(amount), Color("5ab8ff") if absorbed > 0.0 else (Color("ffe066") if crit else Color.WHITE), crit)
	if state != "attack":
		aggro()
	_update_bars()
	if hp <= 0.0:
		_die(true)
		return true
	return false


func _die(reward: bool) -> void:
	state = "dead"
	collision_layer = 0
	_bar.visible = false
	_name.visible = false
	if _sbar:
		_sbar.visible = false
	CombatFx.explosion(world, global_position, Color(1.0, 0.5, 0.2), clampf(def.size * 0.6, 1.2, 5.0))
	Sound.play_3d("enemy_die", global_position, 2.0 if elite else 0.0, 0.1, 60.0)
	if reward:
		var loot: Dictionary = Game.record_space_kill(type, level, elite)
		for item in loot:
			world.spawn_shards(global_position, item, loot[item], def.size)
		if world.has_method("share_space_kill"):
			world.share_space_kill(self)
	world.on_space_enemy_killed(self)
	if type == "heart" and reward:
		world.on_heart_destroyed()
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
