extends CanvasLayer
## The Homespace: a small 2D digital home inside the robot, reachable from
## anywhere. Opening it pauses the world underneath, so stepping back out
## drops you exactly where you were. Walk the room and use its stations:
## the Vault (cloud storage over the relay uplink), the Inbox (letters,
## parcels, trader orders), the window onto wherever you are, and the
## Trophy Wall of everything you've collected.

const WALK := 360.0

var room: Node2D
var ui: Control
var panel_root: Control
var _panel: Control
var _panel_kind := ""
var _toasts: VBoxContainer
var _prompt: Label
var _avatar_x := 0.0
var _facing := 1.0
var _walk_t := 0.0
var _t := 0.0
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _prev_music := ""
var _leaving := false
var _fade: ColorRect
var _motes: Array = []
var _sel_mail := -1
var _accent := Color.WHITE
var _shell := Color.WHITE
var _glow := Color.WHITE

var stations := [
	{"id": "vault", "x": 0.14, "label": "Vault"},
	{"id": "inbox", "x": 0.33, "label": "Inbox"},
	{"id": "window", "x": 0.53, "label": "Window"},
	{"id": "trophy", "x": 0.75, "label": "Trophy Wall"},
	{"id": "exit", "x": 0.93, "label": "Step back out"},
]


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prev_mouse = Input.mouse_mode
	_prev_music = Sound._music_current
	get_tree().paused = true
	Game.in_home = true
	Game.home_visits += 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_accent = Color(Game.appearance.accent) if Game.appearance.has("accent") else Game.robot().color
	_shell = Color(Game.appearance.shell) if Game.appearance.has("shell") else Color("e6e8ec")
	_glow = Color(Game.appearance.glow) if Game.appearance.has("glow") else Color("5ff7ff")
	for b in ["SFX", "Ambience"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_mute(i, true)
	Sound.play_music("home", 1.2)
	Sound.play("home_enter", -4.0, 0.0, "UI")
	var bg := ColorRect.new()
	bg.color = Color("05060d")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	room = Node2D.new()
	room.draw.connect(_draw_room)
	add_child(room)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UiKit.theme()
	add_child(ui)
	var title := UiKit.label("HOMESPACE", 30, Color.WHITE, true)
	title.position = Vector2(40, 28)
	ui.add_child(title)
	var sub := UiKit.label("%s's frame  ·  A/D walk  ·  E use  ·  %s or Esc to step back out" % [Game.player_name, Sound.key_name("home")], 14, UiKit.MUTED)
	sub.position = Vector2(42, 70)
	ui.add_child(sub)
	_prompt = UiKit.label("", 17, Color("9bd1ff"), true)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size = Vector2(300, 0)
	ui.add_child(_prompt)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-460, 30)
	_toasts.custom_minimum_size = Vector2(430, 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	ui.add_child(_toasts)
	panel_root = Control.new()
	panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_root.theme = UiKit.theme()
	add_child(panel_root)
	_fade = ColorRect.new()
	_fade.color = Color(0.4, 0.95, 1.0, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	var t := create_tween()
	t.tween_property(_fade, "color:a", 0.0, 0.45)
	_avatar_x = _vs().x * 0.5
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 60:
		_motes.append([r.randf(), r.randf(), r.randf_range(0.2, 1.0)])
	Game.notify.connect(_toast)
	Game.mail_changed.connect(_on_mail)
	if Game.home_visits == 1:
		_toast("Your Homespace. A letter is waiting in the Inbox.", Color("5ff7ff"))


func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size


func _floor_y() -> float:
	return _vs().y * 0.8


func _station_x(s: Dictionary) -> float:
	return _vs().x * float(s.x)


func _near_station() -> Dictionary:
	for s in stations:
		if absf(_station_x(s) - _avatar_x) < 90.0:
			return s
	return {}


func _process(delta: float) -> void:
	_t += delta
	if _leaving:
		room.queue_redraw()
		return
	var busy := _panel != null
	var ix := 0.0 if busy else Input.get_axis("move_left", "move_right")
	if ix != 0.0:
		_facing = signf(ix)
		_walk_t += delta
	else:
		_walk_t = 0.0
	var vs := _vs()
	_avatar_x = clampf(_avatar_x + ix * WALK * delta, vs.x * 0.05, vs.x * 0.97)
	var s := _near_station()
	_prompt.visible = not busy and not s.is_empty()
	if not s.is_empty():
		var txt := "[E] " + String(s.label)
		match s.id:
			"inbox":
				var u := Game.unread_mail()
				if u > 0:
					txt += "  (%d new)" % u
			"exit":
				txt = "[E] Step back out"
			"window":
				txt = "The view from where you are"
		_prompt.text = txt
		_prompt.position = Vector2(_avatar_x - 150.0, _floor_y() + 26.0)
		if not busy and Input.is_action_just_pressed("interact"):
			_use(s.id)
	room.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or _leaving:
		return
	if event.is_action("pause"):
		if _panel:
			_close_panel()
		else:
			leave()
		get_viewport().set_input_as_handled()
	elif event.is_action("home"):
		leave()
		get_viewport().set_input_as_handled()


func _use(id: String) -> void:
	match id:
		"vault":
			_open_panel("vault")
		"inbox":
			_open_panel("inbox")
		"trophy":
			_open_panel("trophy")
		"exit":
			leave()


func leave() -> void:
	if _leaving:
		return
	_leaving = true
	_close_panel()
	Sound.play("home_exit", -4.0, 0.0, "UI")
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, 0.3)
	await t.finished
	for b in ["SFX", "Ambience"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_mute(i, false)
	get_tree().paused = false
	Game.in_home = false
	Input.mouse_mode = _prev_mouse
	var sc := get_tree().current_scene
	if sc and sc.has_method("refresh_music"):
		sc.refresh_music(1.5)
	elif _prev_music != "":
		Sound.play_music(_prev_music, 1.5)
	Game.save_game()
	var t2 := create_tween()
	t2.tween_property(_fade, "color:a", 0.0, 0.35)
	await t2.finished
	queue_free()


func _exit_tree() -> void:
	if Game.in_home:
		# freed without leave() (scene change / quit): never leave the world paused
		get_tree().paused = false
		Game.in_home = false
		for b in ["SFX", "Ambience"]:
			var i := AudioServer.get_bus_index(b)
			if i >= 0:
				AudioServer.set_bus_mute(i, false)


func _toast(text: String, color: Color) -> void:
	var l := UiKit.label(text, 15, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(430, 0)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toasts.add_child(l)
	var t := l.create_tween()
	t.tween_interval(3.0)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))


func _on_mail() -> void:
	if _panel_kind == "inbox":
		_rebuild()


# --------------------------------------------------------------------------
# panels
# --------------------------------------------------------------------------

func _open_panel(kind: String) -> void:
	_close_panel()
	_panel_kind = kind
	Sound.play("ui_open", -8.0, 0.0, "UI")
	_rebuild()


func _close_panel() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
		Sound.play("ui_close", -10.0, 0.0, "UI")
	_panel_kind = ""


func _rebuild() -> void:
	if _panel:
		_panel.queue_free()
	match _panel_kind:
		"vault":
			_panel = _panel_vault()
		"inbox":
			_panel = _panel_inbox()
		"trophy":
			_panel = _panel_trophy()
		_:
			return
	panel_root.add_child(_panel)


func _frame(title: String, size: Vector2) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = size
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.position = -size / 2.0
	pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.03, 0.05, 0.1, 0.96), UiKit.ACCENT, 12, 2, 18))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tl := UiKit.label(title, 26, Color.WHITE, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(UiKit.button("Close [Esc]", _close_panel))
	v.add_child(HSeparator.new())
	_panel_holder = pc
	return v


var _panel_holder: Control


func _signal_text() -> String:
	var sg: Dictionary = Game.uplink_signal()
	var bars := int(round(float(sg.strength) * 4.0))
	var b := ""
	for i in 4:
		b += "▮" if i < bars else "▯"
	return "Uplink %s  ·  %s  ·  %.2f energy per unit" % [b, sg.label, Game.uplink_cost(1)]


func _panel_vault() -> Control:
	var v := _frame("VAULT", Vector2(1040, 640))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	v.add_child(top)
	top.add_child(UiKit.label("Stored %d / %d" % [Game.vault_used(), Game.vault_cap()], 17, Color("5ff7ff"), true))
	top.add_child(UiKit.label("Hold %d / %d" % [Game.cargo_used(), Game.cargo_cap()], 17, UiKit.TEXT))
	top.add_child(UiKit.label("Energy %d / %d" % [int(Game.energy), int(Game.max_energy())], 17, Color("ffd23f")))
	v.add_child(UiKit.label(_signal_text(), 13, UiKit.MUTED))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var hold_items: Array = []
	for it in Game.inventory:
		if int(Game.inventory[it]) > 0 and Game.can_vault(it):
			hold_items.append(it)
	hold_items.sort_custom(func(a, b): return Db.item_name(a) < Db.item_name(b))
	var vault_items: Array = Game.vault.keys()
	vault_items.sort_custom(func(a, b): return Db.item_name(a) < Db.item_name(b))
	cols.add_child(_item_column("YOUR HOLD  →  vault", hold_items, func(it): return Game.count(it), func(it, q):
		var moved := Game.vault_deposit(it, q)
		if moved > 0:
			Sound.play("pickup", -10.0, 0.1, "UI")
		_rebuild()
	))
	cols.add_child(_item_column("VAULT  →  your hold", vault_items, func(it): return Game.vault_count(it), func(it, q):
		var moved := Game.vault_withdraw(it, q)
		if moved > 0:
			Sound.play("pickup", -10.0, 0.1, "UI")
		_rebuild()
	))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	foot.add_child(UiKit.button("Send all raw resources to the vault", func():
		var n := 0
		for it in Game.inventory.keys():
			if Db.ITEMS.get(it, {}).get("kind", "") == "resource":
				n += Game.vault_deposit(it, Game.count(it))
		if n > 0:
			_toast("Uplinked %d units." % n, Color("5ff7ff"))
			Sound.play("craft", -8.0, 0.0, "UI")
		_rebuild()
	))
	if Game.vault_level < Game.VAULT_UPGRADES.size():
		foot.add_child(UiKit.button("Expand memory +%d  (⌬ %d)" % [Game.VAULT_STEP, Game.VAULT_UPGRADES[Game.vault_level]], func():
			if Game.vault_expand():
				Sound.play("quest_complete", -6.0, 0.0, "UI")
			_rebuild()
		))
	else:
		foot.add_child(UiKit.label("Vault memory fully expanded", 14, UiKit.MUTED))
	foot.add_child(UiKit.label("   Credits ⌬ %d" % Game.credits, 17, Color("ffd23f")))
	return _panel_holder


func _item_column(title: String, items: Array, qty_of: Callable, move: Callable) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label(title, 13, UiKit.MUTED, true))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	if items.is_empty():
		list.add_child(UiKit.label("Empty.", 14, UiKit.MUTED))
	for it in items:
		var q: int = qty_of.call(it)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list.add_child(row)
		row.add_child(UiKit.label("●", 14, Db.item_color(it)))
		var nm := UiKit.label("%s  x%d" % [Db.item_name(it), q], 15)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		row.add_child(nm)
		for n in [1, 10]:
			if q >= n:
				var b := UiKit.button(str(n), func(): move.call(it, n))
				b.custom_minimum_size = Vector2(44, 0)
				row.add_child(b)
		var ba := UiKit.button("All", func(): move.call(it, q))
		ba.custom_minimum_size = Vector2(52, 0)
		row.add_child(ba)
	return v


func _panel_inbox() -> Control:
	var v := _frame("INBOX", Vector2(1080, 640))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	cols.add_child(left)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	if Game.inbox.is_empty():
		list.add_child(UiKit.label("No messages.", 15, UiKit.MUTED))
	if _sel_mail < 0 and not Game.inbox.is_empty():
		_sel_mail = int(Game.inbox[0].id)
	for m in Game.inbox:
		var id := int(m.id)
		var icon := "◆" if m.kind == "order" else "✉"
		var status := ""
		if m.kind == "order":
			var o: Dictionary = m.order
			if o.get("done", false):
				status = "  ✓ filled"
			elif o.get("expired", false):
				status = "  expired"
			else:
				status = "  %dm left" % int(ceil((float(o.expires) - Game.play_time) / 60.0))
		elif not m.claimed:
			status = "  ◈ attachment"
		var b := UiKit.button("%s%s  %s\n%s%s" % ["● " if not m.read else "", icon, m["from"], m.subject, status], func():
			_sel_mail = id
			_rebuild()
		)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 56)
		if id == _sel_mail:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
		list.add_child(b)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	var m := Game.mail_by_id(_sel_mail)
	if m.is_empty():
		return _panel_holder
	if not m.read:
		m.read = true
		Game.mail_changed.emit.call_deferred()
	right.add_child(UiKit.label(m.subject, 22, Color("ffd23f") if m.kind == "order" else Color.WHITE, true))
	right.add_child(UiKit.label("From: " + String(m["from"]), 14, UiKit.MUTED))
	var body := UiKit.label(m.body, 16)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(body)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	if m.kind == "order":
		var o: Dictionary = m.order
		var have := Game.vault_count(o.item) + Game.count(o.item)
		right.add_child(UiKit.label("Wants %d x %s  ·  pays ⌬ %d  (you have %d in vault + hold)" % [int(o.qty), Db.item_name(o.item), int(o.pay), have], 16, Color("6ee06a")))
		if o.get("done", false):
			right.add_child(UiKit.label("Order filled. Thank you!", 15, Color("6ee06a")))
		elif o.get("expired", false):
			right.add_child(UiKit.label("This order expired.", 15, UiKit.MUTED))
		else:
			var fb := UiKit.button("Fill order (vault first, then hold)", func():
				if Game.order_fulfill(int(m.id)):
					_toast("Order filled: +⌬ %d" % int(o.pay), Color("ffd23f"))
				_rebuild()
			)
			fb.disabled = not Game.order_fillable(m)
			acts.add_child(fb)
	else:
		var att := ""
		if int(m.credits) > 0:
			att += "⌬ %d   " % int(m.credits)
		for it in m.items:
			att += "%dx %s   " % [int(m.items[it]), Db.item_name(it)]
		if att != "":
			right.add_child(UiKit.label("Attached: " + att, 16, Color("6ee06a") if not m.claimed else UiKit.MUTED))
			if not m.claimed:
				acts.add_child(UiKit.button("Take to hold", func():
					Game.mail_claim(int(m.id), false)
					Sound.play("coin", -6.0, 0.0, "UI")
					_rebuild()
				))
				acts.add_child(UiKit.button("Send to vault", func():
					Game.mail_claim(int(m.id), true)
					Sound.play("coin", -6.0, 0.0, "UI")
					_rebuild()
				))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	acts.add_child(UiKit.button("Delete", func():
		Game.mail_delete(int(m.id))
		_sel_mail = -1
		_rebuild()
	))
	right.add_child(acts)
	return _panel_holder


func _panel_trophy() -> Control:
	var v := _frame("TROPHY WALL", Vector2(900, 600))
	v.add_child(UiKit.label("WORLD GEMS  %d / 10 kinds (hold + vault)" % _gem_kinds(), 14, Color("6ff3ff"), true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 8)
	v.add_child(flow)
	for g in Game.GEM_KINDS:
		var n: int = Game.count(g) + Game.vault_count(g)
		var chip := PanelContainer.new()
		var col := Db.item_color(g)
		chip.add_theme_stylebox_override("panel", UiKit.box(Color(col.darkened(0.8), 0.9) if n > 0 else Color(0.06, 0.08, 0.1, 0.8), col if n > 0 else Color(1, 1, 1, 0.1), 6, 1, 6))
		chip.add_child(UiKit.label(("◆ %s x%d" % [Db.item_name(g), n]) if n > 0 else "◇ unknown", 14, col if n > 0 else UiKit.MUTED))
		flow.add_child(chip)
	v.add_child(HSeparator.new())
	var relics := ""
	for r in ["fossil", "ancient_relic", "sea_pearl", "legend_shard"]:
		relics += "%s x%d     " % [Db.item_name(r), Game.count(r) + Game.vault_count(r)]
	v.add_child(UiKit.label("RELICS", 14, Color("ffd98a"), true))
	v.add_child(UiKit.label(relics, 15))
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("RECORDS", 14, Color("6ee06a"), true))
	v.add_child(UiKit.label("Species logged: %d   ·   Codex entries: %d / %d   ·   Worlds surveyed: %d   ·   Milestones: %d / %d" % [
		Game.scanned.size(), Game.codex.size(), Db.LORE.size(), Game.surveyed.size(), Game.milestones.size(), Db.MILESTONES.size()], 15))
	v.add_child(UiKit.label("Deepest dive: %d m   ·   Relays lit: %d   ·   Worlds visited: %d" % [Game.max_sea_depth, Game.lit_relays.size(), Game.visited_planets.size()], 15))
	if Game.has_upgrade("crown_of_worlds"):
		v.add_child(UiKit.label("✦ The Crown of Worlds rests on its pedestal.", 17, Color("ffe9a8"), true))
	var tip := UiKit.label("The quest log (%s) has the full Species Log, Milestones and World Gems." % Sound.key_name("quests"), 13, UiKit.MUTED)
	v.add_child(tip)
	return _panel_holder


func _gem_kinds() -> int:
	var n := 0
	for g in Game.GEM_KINDS:
		if Game.count(g) + Game.vault_count(g) > 0:
			n += 1
	return n


# --------------------------------------------------------------------------
# the room
# --------------------------------------------------------------------------

func _draw_room() -> void:
	var vs := _vs()
	var fy := _floor_y()
	var wall_top := Color("0b1030")
	var wall_bot := Color("171b44")
	# back wall gradient
	var bands := 18
	for i in bands:
		var t0 := float(i) / bands
		room.draw_rect(Rect2(0, fy * t0, vs.x, fy / bands + 1.0), wall_top.lerp(wall_bot, t0))
	# wall grid, faint and slowly breathing
	var pulse := 0.5 + 0.5 * sin(_t * 0.8)
	for x in range(0, int(vs.x), 64):
		room.draw_line(Vector2(x, 0), Vector2(x, fy), Color(0.4, 0.6, 1.0, 0.05 + 0.02 * pulse), 1.0)
	for y in range(0, int(fy), 64):
		room.draw_line(Vector2(0, y), Vector2(vs.x, y), Color(0.4, 0.6, 1.0, 0.05 + 0.02 * pulse), 1.0)
	# ceiling light strip
	room.draw_rect(Rect2(vs.x * 0.1, 18, vs.x * 0.8, 6), Color(0.6, 0.95, 1.0, 0.6))
	for k in 4:
		room.draw_rect(Rect2(vs.x * 0.1 - k * 6, 18 - k * 4, vs.x * 0.8 + k * 12, 6 + k * 8), Color(0.4, 0.9, 1.0, 0.04))
	# floor with a perspective grid
	room.draw_rect(Rect2(0, fy, vs.x, vs.y - fy), Color("0a0d22"))
	var vp := Vector2(vs.x * 0.5, fy - 260.0)
	for i in range(-12, 13):
		var bx := vs.x * 0.5 + i * vs.x * 0.09
		var a := Vector2(bx, vs.y)
		var b := a.lerp(vp, (vs.y - fy) / (vs.y - vp.y))
		room.draw_line(b, a, Color(0.3, 0.8, 1.0, 0.18), 1.0)
	for k in 7:
		var tt := pow(float(k) / 7.0, 1.8)
		var y := fy + (vs.y - fy) * tt
		room.draw_line(Vector2(0, y), Vector2(vs.x, y), Color(0.3, 0.8, 1.0, 0.12 + 0.1 * tt), 1.0)
	room.draw_line(Vector2(0, fy), Vector2(vs.x, fy), Color(0.4, 0.95, 1.0, 0.7), 2.0)
	# drifting data motes
	for m in _motes:
		var mx: float = m[0] * vs.x + sin(_t * 0.3 + m[1] * 9.0) * 12.0
		var my: float = fmod(m[1] * fy - _t * 14.0 * m[2] + fy * 4.0, fy)
		room.draw_rect(Rect2(mx, my, 2, 2), Color(0.5, 0.95, 1.0, 0.25 * m[2]))
	for s in stations:
		var x := _station_x(s)
		match s.id:
			"vault":
				_draw_vault(x, fy)
			"inbox":
				_draw_inbox(x, fy)
			"window":
				_draw_window(x, fy)
			"trophy":
				_draw_trophy(x, fy)
			"exit":
				_draw_exit(x, fy)
	# a little digital bonsai between the window and the trophies
	var px := vs.x * 0.64
	room.draw_rect(Rect2(px - 18, fy - 26, 36, 26), Color("2a2f4a"))
	room.draw_line(Vector2(px, fy - 26), Vector2(px + 4, fy - 70), Color("5a4a6a"), 4.0)
	for k in 5:
		var lp := Vector2(px + 4 + cos(k * 1.3) * 18.0, fy - 74 + sin(k * 1.7) * 10.0)
		room.draw_circle(lp, 9.0 + sin(_t * 1.5 + k) * 1.0, Color(0.4, 1.0, 0.7, 0.75))
	_draw_avatar(Vector2(_avatar_x, fy))


func _neon_rect(r: Rect2, col: Color, fill: Color) -> void:
	room.draw_rect(r, fill)
	for k in 3:
		room.draw_rect(r.grow(k * 2.0), Color(col, 0.25 - k * 0.07), false, 2.0)
	room.draw_rect(r, col, false, 2.0)


func _draw_vault(x: float, fy: float) -> void:
	var r := Rect2(x - 95, fy - 270, 190, 270)
	_neon_rect(r, Color("5ff7ff"), Color("10183a"))
	var c := r.get_center() + Vector2(0, -30)
	room.draw_arc(c, 46.0, 0.0, TAU, 40, Color("5ff7ff"), 3.0)
	room.draw_arc(c, 30.0, _t * 0.6, _t * 0.6 + PI * 1.4, 24, Color(0.4, 0.95, 1.0, 0.8), 3.0)
	for k in 8:
		var a := TAU * k / 8.0 + _t * 0.2
		room.draw_line(c + Vector2.from_angle(a) * 36.0, c + Vector2.from_angle(a) * 44.0, Color("5ff7ff"), 2.0)
	# fill gauge
	var f := float(Game.vault_used()) / float(maxi(Game.vault_cap(), 1))
	var g := Rect2(r.position.x + 20, r.end.y - 50, r.size.x - 40, 14)
	room.draw_rect(g, Color(1, 1, 1, 0.08))
	room.draw_rect(Rect2(g.position, Vector2(g.size.x * f, g.size.y)), Color("5ff7ff"))
	_label_at(Vector2(x, r.position.y - 16), "VAULT  %d/%d" % [Game.vault_used(), Game.vault_cap()], Color("5ff7ff"))


func _draw_inbox(x: float, fy: float) -> void:
	room.draw_rect(Rect2(x - 8, fy - 120, 16, 120), Color("2a2f4a"))
	var r := Rect2(x - 95, fy - 250, 190, 135)
	var u := Game.unread_mail()
	_neon_rect(r, Color("ff8fd8") if u > 0 else Color("8f9bff"), Color("141436"))
	# envelope
	var e := Rect2(r.get_center() - Vector2(40, 26), Vector2(80, 52))
	room.draw_rect(e, Color(1, 1, 1, 0.85), false, 2.0)
	room.draw_polyline(PackedVector2Array([e.position, e.get_center() + Vector2(0, 6), Vector2(e.end.x, e.position.y)]), Color(1, 1, 1, 0.85), 2.0)
	if u > 0:
		var bp := Vector2(r.end.x - 14, r.position.y + 14)
		room.draw_circle(bp, 16.0 + sin(_t * 5.0) * 2.0, Color("ff4fa0"))
		_label_at(bp + Vector2(0, 6), str(u), Color.WHITE, 16)
	_label_at(Vector2(x, r.position.y - 16), "INBOX", Color("ff8fd8") if u > 0 else Color("8f9bff"))


func _draw_window(x: float, fy: float) -> void:
	var r := Rect2(x - 180, fy - 400, 360, 240)
	# the view outside depends on where the robot actually is
	var sky_a := Color("0a1030")
	var sky_b := Color("1a2a5a")
	var ground := Color(0, 0, 0, 0)
	var loc := Game.location
	if not Game.sea.is_empty():
		sky_a = Color("0c3a5a")
		sky_b = Color("02101e")
	elif not Game.cave.is_empty():
		sky_a = Color("2a1f18")
		sky_b = Color("120c0a")
	elif not Game.orbit.is_empty() or loc == "space":
		sky_a = Color("03040c")
		sky_b = Color("0a0f24")
	else:
		var pl: Dictionary = Galaxy.planet(Game.star_index, Game.planet_index)
		var b: Dictionary = Db.BIOMES.get(pl.biome, Db.BIOMES.verdant)
		sky_a = (b.atmo as Color).darkened(0.1)
		sky_b = (b.horizon as Color)
		ground = b.colors.mid
	for i in 12:
		var t0 := float(i) / 12.0
		room.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t0, r.size.x, r.size.y / 12.0 + 1.0), sky_a.lerp(sky_b, t0))
	if ground.a > 0.0:
		var pts := PackedVector2Array()
		for k in 21:
			var px := r.position.x + r.size.x * k / 20.0
			pts.append(Vector2(px, r.end.y - 50 - sin(k * 0.7 + 1.3) * 16.0 - sin(k * 1.9) * 6.0))
		pts.append(r.end)
		pts.append(Vector2(r.position.x, r.end.y))
		room.draw_colored_polygon(pts, ground)
		room.draw_circle(r.position + Vector2(r.size.x * 0.78, 50), 16.0, Color(1.0, 0.95, 0.8))
	elif not Game.sea.is_empty():
		for k in 5:
			var fx := r.position.x + fmod(_t * 30.0 + k * 83.0, r.size.x)
			room.draw_circle(Vector2(fx, r.position.y + 60 + k * 28), 3.0, Color(1.0, 0.6, 0.5, 0.8))
	else:
		for k in 30:
			var sx := r.position.x + fmod(k * 97.0, r.size.x)
			var sy := r.position.y + fmod(k * 53.0, r.size.y)
			room.draw_rect(Rect2(sx, sy, 2, 2), Color(1, 1, 1, 0.5 + 0.5 * sin(_t * 2.0 + k)))
	room.draw_rect(r, Color("8fa6d8"), false, 6.0)
	room.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("8fa6d8"), 4.0)
	room.draw_rect(Rect2(r.position.x - 12, r.end.y, r.size.x + 24, 10), Color("3a4270"))


func _draw_trophy(x: float, fy: float) -> void:
	var w := 320.0
	var shelves := [fy - 330.0, fy - 220.0, fy - 110.0]
	for sy in shelves:
		room.draw_rect(Rect2(x - w * 0.5, sy, w, 8), Color("3a4270"))
		room.draw_rect(Rect2(x - w * 0.5, sy, w, 2), Color(0.5, 0.9, 1.0, 0.5))
	# gems
	var i := 0
	for g in Game.GEM_KINDS:
		var n: int = Game.count(g) + Game.vault_count(g)
		var p := Vector2(x - w * 0.5 + 18 + i * (w - 36) / 9.0, shelves[0] - 16)
		var col := Db.item_color(g) if n > 0 else Color(1, 1, 1, 0.12)
		if n > 0:
			room.draw_circle(p, 14.0, Color(col, 0.12 + 0.05 * sin(_t * 2.0 + i)))
		room.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(8, 0), p + Vector2(0, 10), p + Vector2(-8, 0)]), col)
		i += 1
	# relics and the crown
	var relic_items := ["fossil", "ancient_relic", "sea_pearl", "legend_shard"]
	for k in relic_items.size():
		var it: String = relic_items[k]
		var n2: int = Game.count(it) + Game.vault_count(it)
		var p2 := Vector2(x - w * 0.5 + 30 + k * 56, shelves[1] - 18)
		room.draw_circle(p2, 12.0, Db.item_color(it) if n2 > 0 else Color(1, 1, 1, 0.1))
		if n2 > 1:
			_label_at(p2 + Vector2(14, 8), "x%d" % n2, UiKit.MUTED, 12)
	var cp := Vector2(x + w * 0.5 - 50, shelves[1] - 22)
	if Game.has_upgrade("crown_of_worlds"):
		var crown := PackedVector2Array([cp + Vector2(-20, 10), cp + Vector2(-20, -8), cp + Vector2(-10, 2), cp + Vector2(0, -14), cp + Vector2(10, 2), cp + Vector2(20, -8), cp + Vector2(20, 10)])
		room.draw_circle(cp, 26.0, Color(1.0, 0.9, 0.6, 0.15 + 0.08 * sin(_t * 2.0)))
		room.draw_colored_polygon(crown, Color("ffe9a8"))
	else:
		room.draw_rect(Rect2(cp - Vector2(16, 4), Vector2(32, 14)), Color(1, 1, 1, 0.08))
	# species holograms: tiny spinning glyphs, one per 5 species logged
	var holo := mini(int(ceil(Game.scanned.size() / 5.0)), 10)
	for k in holo:
		var hp := Vector2(x - w * 0.5 + 20 + k * 30, shelves[2] - 20 + sin(_t * 2.0 + k) * 3.0)
		var sq := absf(sin(_t * 1.5 + k))
		room.draw_rect(Rect2(hp - Vector2(8 * sq, 8), Vector2(16 * sq, 16)), Color(0.4, 1.0, 0.8, 0.6), false, 2.0)
	# milestone badges under the shelves
	for k in Db.MILESTONES.size():
		var bp := Vector2(x - w * 0.5 + 12 + k * (w - 24) / float(Db.MILESTONES.size() - 1), shelves[2] + 30)
		var got: bool = Game.milestones.has(Db.MILESTONES[k].id)
		room.draw_circle(bp, 7.0, Color("ffd23f") if got else Color(1, 1, 1, 0.1))
	_label_at(Vector2(x, shelves[0] - 60), "TROPHY WALL", Color("ffd98a"))


func _draw_exit(x: float, fy: float) -> void:
	var c := Vector2(x, fy - 130)
	for k in 5:
		var rr := 70.0 + k * 6.0 + sin(_t * 2.0 + k) * 3.0
		room.draw_arc(c, rr, 0.0, TAU, 48, Color(0.4, 0.95, 1.0, 0.5 - k * 0.09), 3.0)
	for k in 3:
		var a := _t * (1.5 + k * 0.4)
		room.draw_arc(c, 30.0 + k * 12.0, a, a + PI, 24, Color(0.6, 1.0, 1.0, 0.5), 2.0)
	_label_at(Vector2(x, c.y - 100), "EXIT", Color("5ff7ff"))


func _label_at(p: Vector2, text: String, col: Color, size := 15) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	room.draw_string(font, p - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_avatar(p: Vector2) -> void:
	var f := _facing
	var walk := sin(_walk_t * 12.0) if _walk_t > 0.0 else 0.0
	var bob := absf(walk) * 3.0 + sin(_t * 2.0) * 1.0
	var s := 2.0
	var o := p + Vector2(0, -40 * s - bob)
	# shadow
	room.draw_colored_polygon(_ellipse(p + Vector2(0, -2), 34.0, 7.0), Color(0, 0, 0, 0.45))
	# legs
	room.draw_line(o + Vector2(-6, 14) * s, o + Vector2(-6 + walk * 6.0, 36) * s, Color("2a2f3a"), 5.0 * s)
	room.draw_line(o + Vector2(6, 14) * s, o + Vector2(6 - walk * 6.0, 36) * s, Color("2a2f3a"), 5.0 * s)
	# body
	room.draw_rect(Rect2(o + Vector2(-13, -6) * s, Vector2(26, 22) * s), _shell)
	room.draw_rect(Rect2(o + Vector2(-13, 6) * s, Vector2(26, 4) * s), _accent)
	# arm swing
	room.draw_line(o + Vector2(f * 2, 0) * s, o + Vector2(f * (8 + walk * 6.0), 14) * s, _accent.darkened(0.2), 4.0 * s)
	# head + visor
	room.draw_circle(o + Vector2(f * 2, -16) * s, 11.0 * s, _shell)
	room.draw_rect(Rect2(o + Vector2(f * 6 - 7, -21) * s, Vector2(14, 6) * s), Color("1b1f29"))
	room.draw_rect(Rect2(o + Vector2(f * 6 - 5, -20) * s, Vector2(10, 4) * s), _glow)
	room.draw_line(o + Vector2(f * -3, -26) * s, o + Vector2(f * -6, -34) * s, Color("2a2f3a"), 2.0 * s)
	room.draw_circle(o + Vector2(f * -6, -35) * s, 2.5 * s, _glow)


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
