extends Control
## Top-down galaxy map. Click a star to inspect, warp if in range.

var hud: CanvasLayer
var selected := -1
var hovered := -1
var zoom := 7.5
var _info: VBoxContainer
var _pan := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var title := UiKit.label("GALAXY MAP", 30, Color.WHITE, true)
	title.position = Vector2(40, 30)
	add_child(title)
	var sub := UiKit.label("Click a star to inspect  ·  Drag to pan  ·  Wheel to zoom  ·  M / Esc to close", 15, UiKit.MUTED)
	sub.position = Vector2(42, 74)
	add_child(sub)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	pc.position = Vector2(-420, -220)
	pc.custom_minimum_size = Vector2(380, 440)
	add_child(pc)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 10)
	pc.add_child(_info)
	selected = Game.star_index
	# a course plotted to a friend in another system opens on their star
	if String(Game.waypoint.get("kind", "")) == "friend" and int(Game.waypoint.get("star", -1)) >= 0:
		selected = int(Game.waypoint.star)
	_friends = Net.friends_by_star()
	_refresh_info()


var _friends := {} # star -> friend names (multiplayer)


func _center() -> Vector2:
	return size * Vector2(0.4, 0.5) + _pan


func _to_screen(p: Vector3) -> Vector2:
	var cur: Vector3 = Galaxy.star(Game.star_index).pos
	return _center() + Vector2(p.x - cur.x, p.z - cur.z) * zoom


func _draw() -> void:
	var cur := Galaxy.star(Game.star_index)
	var c := _to_screen(cur.pos)
	var rng := Game.warp_range()
	# grid
	for i in range(1, 8):
		draw_arc(c, i * 20.0 * zoom, 0, TAU, 96, Color(0.3, 0.6, 1.0, 0.06), 1.0)
	draw_circle(c, rng * zoom, Color(0.35, 0.95, 1.0, 0.06))
	draw_arc(c, rng * zoom, 0, TAU, 128, Color(0.35, 0.95, 1.0, 0.5), 2.0)
	for s in Galaxy.stars:
		var d := Galaxy.distance(Game.star_index, s.index)
		if s.index != Game.star_index and d <= rng:
			draw_line(c, _to_screen(s.pos), Color(0.35, 0.95, 1.0, 0.18), 1.0)
	# the relit Circuit: lines between every pair of lit relays that are near each other
	var lit: Array = Game.lit_relays
	for i in lit.size():
		for j in range(i + 1, lit.size()):
			var a: Dictionary = Galaxy.star(lit[i])
			var b: Dictionary = Galaxy.star(lit[j])
			if a.pos.distance_to(b.pos) < 30.0:
				draw_line(_to_screen(a.pos), _to_screen(b.pos), Color(0.37, 0.97, 1.0, 0.55), 3.0)
	var font := UiKit.body_font()
	for s in Galaxy.stars:
		var p := _to_screen(s.pos)
		var col: Color = s.color
		var r: float = 4.0 + {"O": 4.0, "B": 3.2, "A": 2.6, "F": 2.0, "G": 1.6, "K": 1.2, "M": 0.8}[s.cls]
		draw_circle(p, r * 2.4, Color(col.r, col.g, col.b, 0.12))
		draw_circle(p, r, col)
		if Game.visited_stars.has(s.index):
			draw_arc(p, r + 4, 0, TAU, 24, Color(0.4, 1.0, 0.6, 0.8), 1.5)
		if Game.relay_lit(s.index):
			draw_circle(p, r + 7, Color(0.37, 0.97, 1.0, 0.18))
		if s.has("legendary"):
			draw_arc(p, r + 17, 0, TAU, 40, Color("ffd23f"), 2.0)
			draw_string(font, p + Vector2(-40, r + 34), "EDGE WORLD", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("ffd23f"))
		if s.index == Game.star_index:
			draw_arc(p, r + 9, 0, TAU, 32, Color.WHITE, 2.0)
		if _friends.has(s.index):
			draw_arc(p, r + 21, 0, TAU, 36, Color("9bd1ff"), 2.0)
			draw_string(font, p + Vector2(-90, -r - 24), ", ".join(_friends[s.index]), HORIZONTAL_ALIGNMENT_CENTER, 180, 13, Color("9bd1ff"))
		if s.index == selected:
			draw_arc(p, r + 13, 0, TAU, 32, Color("ffd23f"), 2.5)
		if s.index == hovered or s.index == selected or s.index == Game.star_index or Game.visited_stars.has(s.index) or s.has("legendary"):
			draw_string(font, p + Vector2(r + 8, 5), s.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			queue_redraw()
		var h := _pick(event.position)
		if h != hovered:
			hovered = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.12, 2.5, 30.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.12, 2.5, 30.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var p := _pick(event.position)
			if p >= 0:
				selected = p
				_refresh_info()
				queue_redraw()
			else:
				_dragging = true
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false


func _pick(pos: Vector2) -> int:
	var best := -1
	var best_d := 16.0
	for s in Galaxy.stars:
		var d := _to_screen(s.pos).distance_to(pos)
		if d < best_d:
			best_d = d
			best = s.index
	return best


func _refresh_info() -> void:
	for c in _info.get_children():
		c.queue_free()
	if selected < 0:
		return
	var s := Galaxy.star(selected)
	var d := Galaxy.distance(Game.star_index, selected)
	_info.add_child(UiKit.label(s.name, 26, s.color, true))
	_info.add_child(UiKit.label("Class %s star  ·  %.1f ly away" % [s.cls, d], 15, UiKit.MUTED))
	_info.add_child(HSeparator.new())
	var known := Game.visited_stars.has(selected)
	for p in s.planets:
		var b: Dictionary = Db.BIOMES[p.biome]
		var row := HBoxContainer.new()
		row.add_child(UiKit.swatch(b.colors.low, 16))
		var visited := Game.visited_planets.has(p.key)
		var txt := "  %s  -  %s" % [p.name if known else "Unknown world", b.name if known or selected == Game.star_index else "?"]
		if known and not p.town.is_empty():
			txt += "  ·  ⌂ " + p.town.name
		row.add_child(UiKit.label(txt + ("  ✓" if visited else ""), 15))
		_info.add_child(row)
	if known:
		var st: Dictionary = s.station
		_info.add_child(UiKit.rich("[color=#ffd98a]⌬ %s[/color]\n[color=#6ee06a]Wants %s, %s[/color]  ·  [color=#8ea3bf]surplus %s, %s[/color]" % [st.name, Db.item_name(st.demand[0]), Db.item_name(st.demand[1]), Db.item_name(st.surplus[0]), Db.item_name(st.surplus[1])], 14))
	if _friends.has(selected):
		_info.add_child(UiKit.label("Friends here: %s" % ", ".join(_friends[selected]), 15, Color("9bd1ff")))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.add_child(sp)
	if selected == Game.star_index:
		_info.add_child(UiKit.label("You are here.", 16, UiKit.ACCENT))
		return
	var relay_jump: bool = Game.relay_lit(Game.star_index) and Game.relay_lit(selected)
	_info.add_child(UiKit.label("Relay: %s" % ("ONLINE" if Game.relay_lit(selected) else "dark"), 15, Color("5ff7ff") if Game.relay_lit(selected) else UiKit.MUTED))
	if s.has("legendary"):
		_info.add_child(UiKit.label("An edge world orbits this star.", 15, Color("ffd23f")))
	if relay_jump:
		var rb := UiKit.button("RELAY JUMP  (free)", _relay_jump)
		rb.custom_minimum_size = Vector2(0, 50)
		rb.add_theme_font_override("font", UiKit.title_font())
		_info.add_child(rb)
		return
	var in_range := d <= Game.warp_range()
	var cells := Game.count("warp_cell")
	_info.add_child(UiKit.label("Warp Cells: %d" % cells, 15, Color("9b6bff") if cells > 0 else Color("ff6b6b")))
	if not in_range:
		_info.add_child(UiKit.label("Out of range (%.0f ly). Upgrade your warp drive." % Game.warp_range(), 14, Color("ff6b6b")))
	var btn := UiKit.button("WARP  (1 Warp Cell)", _warp)
	btn.custom_minimum_size = Vector2(0, 50)
	btn.add_theme_font_override("font", UiKit.title_font())
	btn.disabled = not in_range or cells <= 0
	_info.add_child(btn)


func _warp() -> void:
	if not Game.remove_item("warp_cell", 1):
		return
	var to := selected
	hud.close_panel(false)
	Sound.play("warp", 0.0, 0.0)
	Sound.loop_stop("engine", 2.0)
	Game.start_warp(to, false)



func _relay_jump() -> void:
	var to := selected
	hud.close_panel(false)
	Sound.play("warp", 0.0, 0.0)
	Sound.loop_stop("engine", 2.0)
	Game.start_warp(to, true)
