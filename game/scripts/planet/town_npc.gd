class_name TownNpc
extends Node3D
## Town inhabitants. Merchants and trainers stand at their stalls; the bounty
## board is a prop; townsfolk wander the plaza and chat when you pass by.

var world: Node3D
var role := "folk" # merchant | trainer | board | folk
var npc_name := ""
var title := ""
var home := Vector3.ZERO # town centre (world space)
var up := Vector3.UP

var _visual: RobotVisual
var _bubble: Label3D
var _plate: Label3D
var _bubble_t := 0.0
var _target := Vector3.ZERO
var _wait := 0.0
var _t := 0.0
var _heading := Vector3.FORWARD


func setup(w: Node3D, r: String, n: String, t: String, tint: Color, centre: Vector3) -> void:
	world = w
	role = r
	npc_name = n
	title = t
	home = centre
	up = centre.normalized()
	if role == "board":
		add_child(ModelUtil.instance("res://assets/models/town_board.glb"))
	else:
		_visual = RobotVisual.new()
		add_child(_visual)
		_visual.setup_model("res://assets/models/npc_townsfolk.glb", tint)
	var plate := Label3D.new()
	plate.text = n if t == "" else "%s\n<%s>" % [n, t]
	plate.font = UiKit.body_font()
	plate.font_size = 40
	plate.outline_size = 10
	plate.pixel_size = 0.006
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.modulate = CombatFx.hdr(Color("ffd23f") if role in ["merchant", "trainer", "board"] else Color("b8e3ff"))
	plate.position.y = 3.9 if role == "board" else 2.5
	add_child(plate)
	_plate = plate
	if role in ["merchant", "trainer", "board"]:
		var mark := Label3D.new()
		mark.text = {"merchant": "$", "trainer": "✦", "board": "!"}[role]
		mark.font = UiKit.body_font()
		mark.font_size = 90
		mark.outline_size = 16
		mark.pixel_size = 0.008
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.modulate = CombatFx.hdr(Color("ffd23f"))
		mark.position.y = (4.8 if role == "board" else 3.4)
		add_child(mark)
	if role == "folk":
		_bubble = Label3D.new()
		_bubble.font = UiKit.body_font()
		_bubble.font_size = 32
		_bubble.outline_size = 10
		_bubble.pixel_size = 0.006
		_bubble.width = 420
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.modulate = CombatFx.hdr(Color.WHITE, 1.4)
		_bubble.position.y = 3.2
		_bubble.visible = false
		add_child(_bubble)
		_t = randf() * 10.0
		_bubble_t = randf_range(2.0, 8.0)
		_pick_target()


func _pick_target() -> void:
	var b := PlanetGen.align_basis(up, randf() * TAU)
	var d: Vector3 = (up + b.z * randf_range(4.0, 16.0) / world.gen.radius).normalized()
	_target = world.gen.surface_point(d)
	_wait = randf_range(1.0, 4.0)


func _process(delta: float) -> void:
	_t += delta
	if role != "folk":
		return
	var player: Node3D = world.player
	var pos := global_position
	var pdist: float = pos.distance_to(player.global_position) if player != null else INF
	var near_player: bool = pdist < 7.0
	_plate.visible = pdist < 20.0
	if pdist > 12.0 and _bubble.visible:
		_bubble.visible = false
	var dir := pos.normalized()
	if near_player:
		# stop and face the player
		var to: Vector3 = player.global_position - pos
		to -= dir * to.dot(dir)
		if to.length() > 0.1:
			_heading = _heading.slerp(to.normalized(), clampf(delta * 5.0, 0.0, 1.0))
		_visual.move_amount = lerpf(_visual.move_amount, 0.0, 0.2)
	elif _wait > 0.0:
		_wait -= delta
		_visual.move_amount = lerpf(_visual.move_amount, 0.0, 0.2)
	else:
		var to2 := _target - pos
		to2 -= dir * to2.dot(dir)
		if to2.length() < 0.8:
			_pick_target()
		else:
			_heading = _heading.slerp(to2.normalized(), clampf(delta * 4.0, 0.0, 1.0))
			var next: Vector3 = (dir + _heading.normalized() * 2.2 * delta / world.gen.radius).normalized()
			dir = next
			_visual.move_amount = lerpf(_visual.move_amount, 0.6, 0.2)
	_heading = (_heading - dir * _heading.dot(dir)).normalized()
	if not _heading.is_finite() or _heading.length() < 0.5:
		_heading = PlanetGen.align_basis(dir).z
	global_position = world.gen.surface_point(dir)
	global_basis = Basis(dir.cross(_heading).normalized() * -1.0, dir, -_heading).orthonormalized()
	# chatter
	_bubble_t -= delta
	if _bubble_t <= 0.0:
		if _bubble.visible:
			_bubble.visible = false
			_bubble_t = randf_range(5.0, 12.0)
		elif pdist < 11.0:
			_bubble.text = Db.CHATTER[randi() % Db.CHATTER.size()]
			_bubble.visible = true
			_bubble_t = 5.0
		else:
			_bubble_t = 2.0


func interact_info() -> Dictionary:
	match role:
		"merchant":
			return {"text": "[E] Trade with %s" % npc_name, "color": Color("ffd23f"), "instant": true}
		"trainer":
			return {"text": "[E] Train with %s" % npc_name, "color": Color("ffd23f"), "instant": true}
		"board":
			var ready := 0
			for b in Game.bounties:
				if Game.bounty_ready(b):
					ready += 1
			return {"text": "[E] Bounty Board" + ("  -  %d ready to turn in" % ready if ready > 0 else ""), "color": Color("ffd23f"), "instant": true}
	return {"text": "%s: \"%s\"" % [npc_name, Db.CHATTER[hash(npc_name) % Db.CHATTER.size()]], "color": Color("b8e3ff"), "instant": true}


func interact(_player: Node) -> void:
	match role:
		"merchant":
			world.hud.open_town_panel("trade", world.town_planet())
		"trainer":
			world.hud.open_town_panel("trainer", world.town_planet())
		"board":
			world.hud.open_town_panel("board", world.town_planet())
		_:
			_bubble.text = Db.CHATTER[randi() % Db.CHATTER.size()]
			_bubble.visible = true
			_bubble_t = 5.0
			Sound.play_3d("chirp_%d" % (1 + randi() % 3), global_position, -10.0, 0.3, 6.0)
