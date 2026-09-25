class_name RemotePlayer
extends Node3D
## Another player's robot, driven by their position updates (about 10 a
## second) and smoothed in between. On planets it walks; in space it flies.

var id := 0
var mode := "planet"
var visual: RobotVisual
var label: Label3D
var anim := ""
var dead := false # enemies may chase a friend's robot; it never takes damage here
var _target := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _has := false
var _speed := 0.0
var _aim_t := 0.0
const SHOT_SOUNDS := {"Arc": "arc_zap", "Cinder": "cinder_thump", "Rail": "sentinel_shot", "Scatter": "blaster", "Cryo": "blaster"}


func setup(pid: int, info: Dictionary, m: String) -> void:
	id = pid
	mode = m
	visual = RobotVisual.new()
	add_child(visual)
	var rid: String = info.robot if Db.ROBOTS.has(info.robot) else String(Db.ROBOTS.keys()[0])
	visual.setup(rid)
	var look: Dictionary = info.get("look", {}) if info.get("look") is Dictionary else {}
	visual.apply_look.call_deferred(look)
	if mode == "space":
		visual.flying = true
		visual.rotation = Vector3(-PI * 0.45, 0, 0)
	label = Label3D.new()
	label.text = String(info.name)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 30
	label.outline_size = 8
	label.modulate = Color("9bd1ff")
	label.no_depth_test = true
	label.font = UiKit.title_font()
	label.position = Vector3(0, 2.6 if mode == "planet" else 3.2, 0)
	add_child(label)


func apply_look(look: Dictionary) -> void:
	visual.apply_look(look)


func push(pos: Vector3, fwd: Vector3, a: String) -> void:
	if not _has or pos.distance_to(_target) > 60.0:
		global_position = pos # first sighting or a teleport: don't glide across the map
		_has = true
	_target = pos
	if fwd.length() > 0.1:
		_fwd = fwd.normalized()
	anim = a


func _process(delta: float) -> void:
	var prev := global_position
	global_position = global_position.lerp(_target, 1.0 - exp(-delta * 10.0))
	_speed = lerpf(_speed, (global_position - prev).length() / maxf(delta, 0.001), clampf(delta * 8.0, 0.0, 1.0))
	var up := global_position.normalized() if mode == "planet" else Vector3.UP
	var f := _fwd - up * _fwd.dot(up) if mode == "planet" else _fwd
	if f.length() > 0.05 and absf(f.normalized().dot(up)) < 0.98:
		global_basis = global_basis.slerp(Basis.looking_at(f.normalized(), up), clampf(delta * 10.0, 0.0, 1.0)).orthonormalized()
	if mode == "planet":
		visual.move_amount = clampf(_speed / 6.0, 0.0, 1.0) if anim in ["walk", "run", "idle"] else 0.0
		visual.sprinting = anim == "run"
		visual.airborne = anim in ["air", "jet"]
		visual.jetting = anim == "jet"
		visual.working = anim == "work"
		visual.swimming = anim == "swim"
	else:
		visual.boost = anim == "boost"
	_aim_t = maxf(0.0, _aim_t - delta)
	visual.aiming = _aim_t > 0.0 and mode == "planet"


func shot_color() -> Color:
	var look: Dictionary = Net.players[id].look if Net.players.has(id) else {}
	if look.has("glow") and Color.html_is_valid(String(look.glow)):
		return Color(String(look.glow))
	return Db.ROBOTS[visual.robot_id].color.lightened(0.3) if Db.ROBOTS.has(visual.robot_id) else Color("9bd1ff")


## Draw a friend's shots from where their robot stands on our screen.
## world: the planet or space scene (space ends arrive relative to a planet).
func show_shots(weapon: String, shots: Array, world: Node3D) -> void:
	var up := global_position.normalized() if mode == "planet" else global_basis.y
	var muzzle := global_position + up * 1.3 + global_basis.x * 0.55 - global_basis.z * 0.5 if mode == "planet" \
		else global_transform * Vector3(0.9, -0.5, -1.4)
	var col := shot_color()
	var reach := 400.0 if mode == "planet" else 3000.0
	var drew := false
	for s in shots.slice(0, Net.MAX_SHOTS):
		if not s is Dictionary:
			continue
		var k := String(s.get("k", "hit"))
		if k == "lob":
			if mode != "planet":
				continue
			var v := Net._vec(s.get("v"))
			var g := PlayerGrenade.launch(world, muzzle, v.limit_length(40.0), 0.0, 3.5, 0.0)
			g.cosmetic = true
			drew = true
			continue
		var end := Net._vec(s.get("b"))
		if mode == "space":
			end = world._abs(int(s.get("a", -1)), end)
		if end.distance_to(muzzle) > reach:
			continue
		drew = true
		match k:
			"rail":
				CombatFx.tracer(world, muzzle, end, col * 1.6)
				CombatFx.spark(world, end, col, 1.2)
			"arc":
				CombatFx.arc_bolt(world, muzzle, end, Color(0.75, 0.7, 1.0) * 2.2)
			"beam":
				CombatFx.tracer(world, muzzle, end, Color(0.55, 0.9, 1.0) * 2.0)
			_:
				CombatFx.tracer(world, muzzle, end, col)
	if drew:
		_aim_t = 0.6
		Sound.play_3d(SHOT_SOUNDS.get(weapon, "blaster"), muzzle, -8.0, 0.12, 20.0 if mode == "planet" else 60.0)
