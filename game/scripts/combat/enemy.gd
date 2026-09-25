class_name Enemy
extends CharacterBody3D
## A hostile on a planet. Wanders near its camp, aggroes on the player, chases,
## attacks, leashes home and heals. How it fights lives in a behaviour
## (scripts/combat/behaviors, picked by Db.ENEMIES[type].style); this script
## runs the shared state machine, statuses, damage and death.

const LEASH := 70.0
const SOCIAL_RADIUS := 12.0
const BEHAVIORS := {
	"melee": "res://scripts/combat/behaviors/melee.gd",
	"ranged": "res://scripts/combat/behaviors/ranged.gd",
	"slam": "res://scripts/combat/behaviors/slam.gd",
	"charge": "res://scripts/combat/behaviors/charge.gd",
	"burrow": "res://scripts/combat/behaviors/burrow.gd",
	"shield": "res://scripts/combat/behaviors/shield.gd",
	"swarm": "res://scripts/combat/behaviors/swarm.gd",
	"mortar": "res://scripts/combat/behaviors/mortar.gd",
	"storm": "res://scripts/combat/behaviors/storm.gd",
	"mirror": "res://scripts/combat/behaviors/mirror.gd",
	"stalk": "res://scripts/combat/behaviors/stalk.gd",
	"hive": "res://scripts/combat/behaviors/hive.gd",
	"drift": "res://scripts/combat/behaviors/drift.gd",
	"titan": "res://scripts/combat/behaviors/titan.gd",
}

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
var nid := "" # multiplayer: the same drone on every player's screen shares this id
## Who it's after: our robot, or a friend's robot on this planet (multiplayer).
## Only our own robot takes damage here; a friend's game handles theirs.
var target: Node3D = null
var remote_t := -100.0 # when a friend last hurt it (seconds): it won't heal while contested
var mine_t := -100.0 # when we last hurt it
var behavior: EnemyBehavior
var status := Status.new()
var swing := 0.0 # attack animation, 1 -> 0

var _model: Node3D
var _parts := {}
var _rest := {}
var _bar: MeshInstance3D
var _name: Label3D
var _atk_cd := 0.0
var _t := 0.0
var _wander_target := Vector3.ZERO
var _wander_timer := 0.0
var _knock := Vector3.ZERO
var _flash := 0.0
var _overlay: StandardMaterial3D
var _meshes: Array = []


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
	# every named part can be posed by name (Torso, ArmL, LegFL, Seg0...)
	for node in _model.find_children("*", "Node3D", true, false):
		if not _parts.has(String(node.name)):
			_parts[String(node.name)] = node
			_rest[String(node.name)] = node.transform
	_meshes = _model.find_children("*", "MeshInstance3D", true, false)

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

	var script: GDScript = load(BEHAVIORS.get(def.style, BEHAVIORS.melee))
	behavior = script.new()
	behavior.setup(self)
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
	var burn := status.tick(delta)
	if burn > 0.0:
		take_hit(burn, false, "fire")
		if state == "dead":
			return
	_update_overlay()
	var slow := status.speed_mult()
	_atk_cd = maxf(0.0, _atk_cd - delta * slow)
	var player: Node3D = world.player
	var local_ok: bool = player != null and not player.dead
	var ldist := global_position.distance_to(player.global_position) if local_ok else INF
	target = _pick_target(player if local_ok else null, ldist)
	var player_ok := target != null
	var ppos: Vector3 = target.global_position if player_ok else Vector3.ZERO
	var dist := global_position.distance_to(ppos) if player_ok else INF

	# frozen solid: nothing but the knockback moves it
	if status.frozen():
		if _knock.length() > 0.1:
			_apply_knock(delta)
			_place()
		_update_plate_visibility(ldist)
		return
	if behavior.busy(delta):
		_animate(delta, false)
		_update_plate_visibility(ldist)
		return

	var home_pos: Vector3 = world.gen.surface_point(home_dir)
	match state:
		"idle":
			_wander_timer -= delta
			if _wander_timer <= 0.0:
				_wander_timer = randf_range(3.0, 7.0)
				var b := PlanetGen.align_basis(home_dir, randf() * TAU)
				_wander_target = world.gen.surface_point((home_dir + b.z * randf_range(0.0, 14.0) / world.gen.radius).normalized())
			if global_position.distance_to(_wander_target) > 1.5:
				move_toward_point(_wander_target, def.speed * 0.35, delta)
			if player_ok and dist < def.aggro:
				aggro()
		"chase":
			if not player_ok or global_position.distance_to(home_pos) > LEASH:
				_leash()
			else:
				behavior.chase(delta, ppos, dist)
				if dist <= def.range and _atk_cd <= 0.0:
					_atk_cd = def.cd * randf_range(0.9, 1.15)
					# a swing at a friend's robot can't hurt ours (their game deals it)
					world.damage_mute = self if target != player else null
					behavior.attack(target, dist)
					world.damage_mute = null
		"return":
			move_toward_point(home_pos, def.speed * 1.6, delta)
			var contested := contested()
			if not contested:
				hp = minf(max_hp, hp + max_hp * delta * 0.5)
			_bar.set_instance_shader_parameter("fill", hp / max_hp)
			if global_position.distance_to(home_pos) < 3.0:
				state = "idle"
				if not contested:
					hp = max_hp
				status.clear()
				_update_plate()

	_apply_knock(delta)
	_place()
	_animate(delta, state == "chase")
	_update_plate_visibility(dist)


func _apply_knock(delta: float) -> void:
	if _knock.length() > 0.1:
		var t := _knock * delta
		dir = (dir + (t - dir * t.dot(dir)) / world.gen.radius).normalized()
		_knock = _knock.lerp(Vector3.ZERO, delta * 6.0)


func _update_plate_visibility(dist: float) -> void:
	var show := (state == "chase" or dist < 40.0) and behavior.visible_to_player()
	_bar.visible = show
	_name.visible = show


## Walk along the sphere toward a point (slowed by chill).
func move_toward_point(target: Vector3, speed: float, delta: float) -> void:
	speed *= status.speed_mult()
	var to := target - global_position
	to -= dir * to.dot(dir)
	if to.length() < 0.05 or speed <= 0.0:
		return
	var want := to.normalized()
	heading = heading.slerp(want, clampf(delta * 6.0, 0.0, 1.0))
	heading = (heading - dir * heading.dot(dir)).normalized()
	var next: Vector3 = (dir + heading * speed * delta / world.gen.radius).normalized()
	var gen: PlanetGen = world.gen
	if gen.has_liquid() and gen.height(next) < gen.sea - 0.004 and not def.get("wades", false):
		return # won't wade into deep liquid
	dir = next


func face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	to -= dir * to.dot(dir)
	if to.length() > 0.05:
		heading = heading.slerp(to.normalized(), clampf(delta * 8.0, 0.0, 1.0))
		heading = (heading - dir * heading.dot(dir)).normalized()


func _place() -> void:
	var hover := behavior.hover(_t)
	var gen: PlanetGen = world.gen
	var base_r := gen.surface_radius(dir)
	if def.get("wades", false) and gen.has_liquid():
		base_r = maxf(base_r, gen.sea_radius())
	global_position = dir * (base_r + hover)
	var back := -heading
	global_basis = Basis(dir.cross(back).normalized(), dir, back).orthonormalized()


func _animate(delta: float, engaged: bool) -> void:
	swing = maxf(0.0, swing - delta * 3.0)
	if _flash > 0.0:
		_flash -= delta
		_model.scale = Vector3.ONE * def.scale * (1.0 + _flash * 0.6)
	if behavior.animate(delta, engaged):
		return
	var sw := sin(swing * PI)
	if _parts.has("Torso"):
		var tilt := 0.18 if engaged and type == "scrapper" else 0.0
		pose("Torso", Vector3.ZERO, Vector3(tilt - sw * 0.2, 0, 0))
	if _parts.has("SawL"):
		_parts.SawL.rotation.x = _t * 25.0
		_parts.SawR.rotation.x = -_t * 25.0
	if _parts.has("Ring"):
		_parts.Ring.rotation.z = _t * (3.0 if engaged else 1.0)
	var walk := sin(_t * 7.0) * (0.5 if type == "brute" and state != "idle" else 0.2)
	if type == "brute":
		var raise := 1.0 if behavior.has_method("raised") and behavior.raised() else 0.0
		pose("ArmL", Vector3.ZERO, Vector3(-walk * 0.5 - raise * 2.4 + sw * 1.5, 0, 0))
		pose("ArmR", Vector3.ZERO, Vector3(walk * 0.5 - raise * 2.4 + sw * 1.5, 0, 0))
		pose("LegL", Vector3.ZERO, Vector3(walk, 0, 0))
		pose("LegR", Vector3.ZERO, Vector3(-walk, 0, 0))
	elif _parts.has("ArmL"):
		pose("ArmL", Vector3.ZERO, Vector3(-sw * 1.6, 0, 0))
		pose("ArmR", Vector3.ZERO, Vector3(-sw * 1.6, 0, 0))


func pose(part: String, offset: Vector3, rot: Vector3) -> void:
	var n: Node3D = _parts.get(part)
	if n == null:
		return
	var rest: Transform3D = _rest[part]
	n.transform = n.transform.interpolate_with(Transform3D(rest.basis * Basis.from_euler(rot), rest.origin + offset), 0.3)


## Snap to the ground now (behaviours that move it themselves call this).
func place_now() -> void:
	_place()


## Burrowed or phased out: shots pass through.
func set_hittable(on: bool) -> void:
	collision_layer = 4 if on else 0


func part(part_name: String) -> Node3D:
	return _parts.get(part_name)


## Nearest robot worth chasing: ours, or a friend's on this planet. The current
## target is kept unless another is clearly closer, so it doesn't flicker between two.
func _pick_target(player: Node3D, ldist: float) -> Node3D:
	var best: Node3D = player
	var bd := ldist * (0.75 if player != null and player == target else 1.0)
	var nv = world.get("net_view")
	if nv != null and not nv.avatars.is_empty():
		for id in nv.avatars:
			var a: Node3D = nv.avatars[id]
			var d := global_position.distance_to(a.global_position) * (0.75 if a == target else 1.0)
			if d < bd:
				bd = d
				best = a
	return best


## A friend hurt it in the last few seconds: it doesn't heal or reset.
func contested() -> bool:
	return Time.get_ticks_msec() / 1000.0 - remote_t < 6.0


func model() -> Node3D:
	return _model


func time() -> float:
	return _t


func damage_output() -> float:
	var d: float = def.dmg[0] + def.dmg[1] * level
	return d * clampf(1.0 + (level - Game.level) * 0.08, 0.5, 2.0)


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
	behavior.cleanup()
	status.clear()
	_update_plate()


func knockback(v: Vector3) -> void:
	if def.get("heavy", false):
		v *= 0.3
	_knock += v


## Status effects from weapons and hazards. Returns what took hold ("" if resisted).
func apply_status(kind: String, duration: float, power := 1.0) -> String:
	if state == "dead" or state == "return":
		return ""
	var resist: float = def.get("resist", {}).get(kind, 0.0)
	var got := status.apply(kind, duration, power, resist)
	if got == "freeze":
		world.floating_text(global_position + dir * (3.4 if elite else 2.6), "FROZEN", Color("9be7ff"), true)
		Sound.play_3d("freeze", global_position, -4.0, 0.05)
	if got != "" and state == "idle":
		aggro()
	_update_overlay()
	return got


func _update_overlay() -> void:
	if not status.any():
		if _overlay:
			for mi in _meshes:
				(mi as MeshInstance3D).material_overlay = null
			_overlay = null
		return
	if _overlay == null:
		_overlay = StandardMaterial3D.new()
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for mi in _meshes:
			(mi as MeshInstance3D).material_overlay = _overlay
	var c := status.tint()
	var pulse := 0.28 + 0.1 * sin(_t * 9.0)
	_overlay.albedo_color = Color(c.r, c.g, c.b, pulse if not status.frozen() else 0.55)


## Damage multiplier for a kind of damage (kinetic, fire, frost, shock).
func damage_mod(kind: String) -> float:
	return float(def.get("mods", {}).get(kind, 1.0))


## Returns true if this hit killed it.
## kind: kinetic (default), fire, frost or shock. from: where it came from, for shields.
func take_hit(amount: float, crit := false, kind := "kinetic", from := Vector3.INF) -> bool:
	if state == "dead" or state == "return":
		return false
	amount *= damage_mod(kind) * status.damage_mult()
	amount = behavior.on_hit(amount, kind, from)
	if amount <= 0.0:
		world.floating_text(global_position + dir * (3.2 if elite else 2.4), "BLOCKED", Color("9aa0a6"), false)
		if state == "idle":
			aggro()
		return false
	hp -= amount
	mine_t = Time.get_ticks_msec() / 1000.0
	Net.queue_hit(nid, amount)
	_flash = 0.15
	var col := Color("ffe066") if crit else Color.WHITE
	if kind == "fire":
		col = Color("ff9a4d")
	elif damage_mod(kind) > 1.01:
		col = Color("ffd23f") # a weakness
	world.floating_text(global_position + dir * (3.2 if elite else 2.4), ("%d!" if crit else "%d") % int(amount), col, crit)
	if state == "idle":
		aggro()
	_update_plate()
	if hp <= 0.0:
		_die()
		return true
	return false


## A friend's shots landing on our copy of this drone.
func remote_hit(amount: float) -> void:
	if state == "dead":
		return
	remote_t = Time.get_ticks_msec() / 1000.0
	if state == "idle":
		aggro()
	hp -= amount
	_flash = 0.15
	world.floating_text(global_position + dir * (3.2 if elite else 2.4), "%d" % int(amount), Color("9bd1ff"), false)
	_update_plate()
	if hp <= 0.0:
		_die(true)
		# normally the friend's kill message follows and pays the shared kill;
		# if both of us finished it off with hits, nobody sends one: share it anyway
		var w := world
		var args := [nid, type, level, elite]
		get_tree().create_timer(SHARED_KILL_WAIT).timeout.connect(func(): Enemy._shared_kill_fallback(w, args))


const SHARED_KILL_WAIT := 0.5

## Pays a drone our hits and a friend's killed together, unless a kill message
## for it already paid (the planet's _dead_nids).
static func _shared_kill_fallback(w: Node, args: Array) -> void:
	if not is_instance_valid(w):
		return
	var dead = w.get("_dead_nids")
	var id := String(args[0])
	if not dead is Dictionary or id == "":
		return
	var now := Time.get_ticks_msec()
	if dead.has(id) and now - int(dead[id]) < 15000:
		return
	dead[id] = now
	var t := String(args[1])
	if not Db.ENEMIES.has(t):
		return
	Game.record_kill(t, int(args[2]), bool(args[3]))
	Game.notify.emit("Shared kill: %s (Lv %d)" % [Db.ENEMIES[t].name, int(args[2])], Color("ffb86b"))


## remote: a friend landed the killing blow (their kill message carries the shared reward).
func _die(remote := false) -> void:
	state = "dead"
	collision_layer = 0
	behavior.on_death()
	behavior.cleanup()
	status.clear()
	_update_overlay()
	_bar.visible = false
	_name.visible = false
	Sound.play_3d("enemy_die", global_position, 0.0 if elite else -3.0, 0.1, 22.0)
	if not remote:
		Game.record_kill(type, level, elite)
		world.share_kill(self)
	world.on_enemy_killed(self, remote)
	world.explosion(global_position + dir * 1.2, Color(1.0, 0.45, 0.2), 2.2 if elite else 1.3)
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


## Gone by its own doing (a mite's burst, a withering sporeling): no reward, no loot.
func self_destruct() -> void:
	if state == "dead":
		return
	state = "dead"
	collision_layer = 0
	behavior.cleanup()
	status.clear()
	_update_overlay()
	_bar.visible = false
	_name.visible = false
	world.on_enemy_killed(self)
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.2)
	t.tween_callback(queue_free)


## Near-invisible (a cloaked Stalker): a faint dark shimmer instead of the model.
func set_ghost(on: bool, alpha := 0.08) -> void:
	var ghost: StandardMaterial3D = null
	if on:
		ghost = StandardMaterial3D.new()
		ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.albedo_color = Color(0.45, 0.35, 0.9, alpha)
	for mi in _meshes:
		(mi as MeshInstance3D).material_override = ghost
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _exit_tree() -> void:
	if behavior:
		behavior.cleanup()
