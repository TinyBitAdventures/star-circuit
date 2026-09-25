extends Control
## Top-down map of the current star system. Click anything to set a waypoint.

var hud: CanvasLayer
var world: Node3D
var hovered := {}
var _info: VBoxContainer
var _scale := 0.25


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := UiKit.label("%s SYSTEM" % Galaxy.star(Game.star_index).name.to_upper(), 30, Color.WHITE, true)
	title.position = Vector2(40, 30)
	add_child(title)
	var sub := UiKit.label("Click anything to set a waypoint  ·  M / Esc to close", 15, UiKit.MUTED)
	sub.position = Vector2(42, 74)
	add_child(sub)
	var gb := UiKit.button("Galaxy map  >", func(): hud.toggle_panel("map"))
	gb.position = Vector2(42, 104)
	add_child(gb)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	pc.position = Vector2(-420, -200)
	pc.custom_minimum_size = Vector2(380, 400)
	add_child(pc)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 10)
	pc.add_child(_info)
	_refresh_info({})


func _centre() -> Vector2:
	return size * Vector2(0.38, 0.54)


func _map(p: Vector3) -> Vector2:
	return _centre() + Vector2(p.x, p.z) * _scale


func _process(_d: float) -> void:
	var ext := 400.0
	for o in world.system_objects():
		ext = maxf(ext, Vector2(o.pos.x, o.pos.z).length())
	_scale = minf(size.x * 0.33, size.y * 0.42) / ext
	queue_redraw()


func _draw() -> void:
	var c := _centre()
	var star: Dictionary = Galaxy.star(Game.star_index)
	var font := UiKit.body_font()
	# orbits
	for p in world.planets:
		if not Galaxy.is_moon(p.data):
			var r := Vector2(p.node.global_position.x, p.node.global_position.z).length() * _scale
			draw_arc(c, r, 0, TAU, 128, Color(1, 1, 1, 0.08), 1.0)
	# asteroid belt
	var br: float = star.belt.radius * _scale
	draw_arc(c, br, 0, TAU, 160, Color(0.8, 0.7, 0.55, 0.18), maxf(4.0, star.belt.width * _scale))
	draw_circle(c, 10.0, star.color)
	draw_circle(c, 18.0, Color(star.color, 0.25))
	var wp: Vector3 = world.waypoint_pos()
	for o in world.system_objects():
		var p := _map(o.pos)
		var rad := clampf(float(o.r) * _scale * 3.0, 4.0, 16.0)
		match o.kind:
			"station":
				draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), o.color)
			"relay":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(7, 0), p + Vector2(0, 9), p + Vector2(-7, 0)]), o.color)
			"derelict":
				draw_line(p - Vector2(6, 6), p + Vector2(6, 6), o.color, 3.0)
				draw_line(p - Vector2(6, -6), p + Vector2(6, -6), o.color, 3.0)
			_:
				draw_circle(p, rad, o.color)
		if not hovered.is_empty() and hovered.kind == o.kind and hovered.id == o.id:
			draw_arc(p, rad + 6, 0, TAU, 24, Color.WHITE, 1.5)
		if wp != Vector3.INF and o.pos.distance_to(wp) < 1.0:
			draw_arc(p, rad + 10, 0, TAU, 24, Color("ffd23f"), 2.5)
		draw_string(font, p + Vector2(rad + 6, 5), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
	# friends: flying here, or beside the planet they're on
	var on_planet := {}
	for id in Net.players:
		var f := Net.friend_spot(id)
		if f.is_empty() or f.star != Game.star_index:
			continue
		var fp := Vector2.INF
		if world.net_view.avatars.has(id):
			fp = _map(world.net_view.avatars[id].global_position)
		elif f.planet >= 0:
			var n: int = on_planet.get(f.planet, 0)
			on_planet[f.planet] = n + 1
			for o in world.system_objects():
				if o.kind == "planet" and int(o.id) == f.planet:
					fp = _map(o.pos) + Vector2(-14 - n * 12, -14)
		if fp == Vector2.INF:
			continue
		var fc := Color("9bd1ff")
		draw_circle(fp, 5.0, fc)
		draw_arc(fp, 8.0, 0, TAU, 20, Color(fc, 0.6), 1.5)
		draw_string(font, fp + Vector2(-80, -12), f.name, HORIZONTAL_ALIGNMENT_RIGHT, 72, 13, fc)
	# player
	var pl: Node3D = world.player
	if pl:
		var pp := _map(pl.global_position)
		var f: Vector3 = -pl.global_basis.z
		var fd := Vector2(f.x, f.z).normalized()
		var sd := Vector2(-fd.y, fd.x)
		draw_colored_polygon(PackedVector2Array([pp + fd * 12, pp - fd * 7 + sd * 7, pp - fd * 7 - sd * 7]), UiKit.ACCENT)
		draw_string(font, pp + Vector2(12, -8), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)


func _pick(pos: Vector2) -> Dictionary:
	var best := {}
	var bd := 20.0
	for o in world.system_objects():
		var d := _map(o.pos).distance_to(pos)
		if d < bd:
			bd = d
			best = o
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _pick(event.position)
		if h.get("name", "") != hovered.get("name", ""):
			hovered = h
			_refresh_info(h)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var o := _pick(event.position)
		if not o.is_empty():
			Game.waypoint = {"kind": o.kind, "id": o.id, "star": Game.star_index, "name": o.name}
			Sound.ui()
			Game.notify.emit("Waypoint: %s" % o.name, Color("ffd23f"))
			_refresh_info(o)


func _refresh_info(o: Dictionary) -> void:
	for ch in _info.get_children():
		ch.queue_free()
	if o.is_empty():
		_info.add_child(UiKit.label("Hover a body for details.", 15, UiKit.MUTED))
		if not Game.waypoint.is_empty():
			_info.add_child(UiKit.label("Current waypoint: %s" % Game.waypoint.get("name", "?"), 15, Color("ffd23f")))
			_info.add_child(UiKit.button("Clear waypoint", func():
				Game.waypoint = {}
				_refresh_info({})
			))
		return
	_info.add_child(UiKit.label(o.name, 24, o.color, true))
	_info.add_child(UiKit.label(o.sub, 15))
	var pl: Node3D = world.player
	if pl:
		_info.add_child(UiKit.label("%d u away" % int(pl.global_position.distance_to(o.pos)), 14, UiKit.MUTED))
	_info.add_child(UiKit.label("Click to set as waypoint", 13, UiKit.MUTED))
