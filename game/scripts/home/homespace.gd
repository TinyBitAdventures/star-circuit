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

var stations: Array = [] # {id, x, label} in room pixels
var slots: Array = [] # decor slots: {id, kind: floor|wall, x}
var room_w := 2400.0
var scroll := 0.0
var _sel_worker := -1
var _job_kind := "gather"
var _job_target := ""
var _job_min := 15
var _job_item := ""
const BASE_W := 2400.0
const WING_W := 1000.0


func _build_layout() -> void:
	stations = [
		{"id": "exit", "x": 100.0, "label": "Step back out"},
		{"id": "vault", "x": 300.0, "label": "Vault"},
		{"id": "inbox", "x": 640.0, "label": "Inbox"},
		{"id": "dispatch", "x": 990.0, "label": "Dispatch Bay"},
		{"id": "window", "x": 1480.0, "label": "Window"},
		{"id": "trophy", "x": 1930.0, "label": "Trophy Wall"},
		{"id": "decor", "x": 2300.0, "label": "Decor Console"},
	]
	slots = []
	for p in [["f0", 470.0], ["f1", 800.0], ["f2", 1255.0], ["f3", 1712.0], ["f4", 2150.0]]:
		slots.append({"id": p[0], "kind": "floor", "x": p[1]})
	for p in [["w0", 470.0], ["w1", 800.0], ["w2", 1170.0], ["w3", 1760.0], ["w4", 2150.0]]:
		slots.append({"id": p[0], "kind": "wall", "x": p[1]})
	var wings := int(Game.home_state().wings)
	for i in wings:
		var bx := BASE_W + i * WING_W
		stations.append({"id": ["observatory", "garden"][i], "x": bx + 500.0, "label": ["Observatory", "Garden"][i]})
		for k in 3:
			slots.append({"id": "f%d" % (5 + i * 3 + k), "kind": "floor", "x": bx + [170.0, 330.0, 840.0][k]})
		for k in 2:
			slots.append({"id": "w%d" % (5 + i * 2 + k), "kind": "wall", "x": bx + [200.0, 800.0][k]})
	room_w = BASE_W + wings * WING_W


## Placed decor that can be used (the defrag pod) acts like a station.
func _use_spots() -> Array:
	var out := []
	var h := Game.home_state()
	for sl in slots:
		var id: String = h.slots.get(sl.id, "")
		if id != "" and Db.DECOR.get(id, {}).has("use"):
			out.append({"id": "pod", "x": sl.x, "label": Db.DECOR[id].name})
	return out


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
	_build_layout()
	_avatar_x = 300.0 if Game.home_visits > 1 else 640.0
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
	return float(s.x)


func _near_station() -> Dictionary:
	for s in stations + _use_spots():
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
	_avatar_x = clampf(_avatar_x + ix * WALK * delta, 50.0, room_w - 50.0)
	var want := clampf(_avatar_x - vs.x * 0.5, 0.0, maxf(0.0, room_w - vs.x))
	scroll = lerpf(scroll, want, clampf(delta * 6.0, 0.0, 1.0))
	room.position.x = -scroll
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
			"pod":
				var wait := Game.charge_ready()
				txt = "[E] Rest in the Defrag Pod" if wait <= 0.0 else "Defrag Pod recharging (%dm)" % int(ceil(wait / 60.0))
			"observatory":
				txt = "The Circuit: %d relays lit" % Game.lit_relays.size()
			"garden":
				txt = "The Garden"
		_prompt.text = txt
		_prompt.position = Vector2(_avatar_x - scroll - 150.0, _floor_y() + 26.0)
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
		"dispatch":
			_open_panel("dispatch")
		"decor":
			_open_panel("decor")
		"pod":
			if Game.charge_use():
				Sound.play("respawn", -4.0, 0.0, "UI")
				_toast("Defragmented. Hull and energy fully restored.", Color("6ee06a"))
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
		"dispatch":
			_panel = _panel_dispatch()
		"decor":
			_panel = _panel_decor()
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


func _panel_dispatch() -> Control:
	var v := _frame("DISPATCH BAY", Vector2(1120, 660))
	var intro := UiKit.label("Subroutines are compiled copies of you. Send them to worlds you've visited while you keep playing. Jobs run on play time; results arrive in the vault, with a report in the Inbox.", 14, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(intro)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	if Game.workers.is_empty():
		left.add_child(UiKit.label("No subroutines yet.", 15, UiKit.MUTED))
	if _sel_worker < 0 and not Game.workers.is_empty():
		_sel_worker = int(Game.workers[0].id)
	for w in Game.workers:
		var id := int(w.id)
		var card := PanelContainer.new()
		var sel := id == _sel_worker
		card.add_theme_stylebox_override("panel", UiKit.box(Color(0.08, 0.16, 0.12, 0.95) if sel else Color(0.06, 0.08, 0.1, 0.9), Color("6ee06a") if sel else Color(1, 1, 1, 0.12), 8, 2 if sel else 1, 10))
		left.add_child(card)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var head := HBoxContainer.new()
		cv.add_child(head)
		var nm := UiKit.label("%s  ·  Level %d" % [w.name, int(w.level)], 17, Color.WHITE, true)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		if not sel:
			head.add_child(UiKit.button("Select", func():
				_sel_worker = id
				_rebuild()
			))
		var status := "Idle, awaiting orders"
		match w.state:
			"job":
				var pl := Game._planet_of(w.job.target)
				status = "%s on %s  ·  back in %dm" % [Db.JOBS[w.job.kind].name, pl.name, int(ceil(float(w.job.left) / 60.0))]
			"hurt":
				status = "Damaged  ·  self-repair in %dm" % int(ceil(float(w.hurt_left) / 60.0))
		cv.add_child(UiKit.label(status, 14, Color("ffd98a") if w.state == "job" else (Color("ff6b6b") if w.state == "hurt" else Color("6ee06a"))))
		if int(w.level) < Db.WORKER_MAX_LEVEL:
			var bar := ProgressBar.new()
			bar.max_value = 100 * int(w.level)
			bar.value = int(w.xp)
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 6)
			cv.add_child(bar)
		var acts := HBoxContainer.new()
		cv.add_child(acts)
		if w.state == "job":
			acts.add_child(UiKit.button("Recall", func():
				Game.job_recall(id)
				_rebuild()
			))
		elif w.state == "hurt":
			acts.add_child(UiKit.button("Repair (1 Repair Kit)", func():
				if Game.worker_repair(id):
					Sound.play("craft", -6.0, 0.0, "UI")
				_rebuild()
			))
	var cost := Game.worker_cost()
	if cost >= 0:
		left.add_child(UiKit.button("Compile a new subroutine  (%s)" % ("free" if cost == 0 else "⌬ %d" % cost), func():
			var nw := Game.worker_compile()
			if not nw.is_empty():
				_sel_worker = int(nw.id)
				Sound.play("home_enter", -8.0, 0.0, "UI")
			_rebuild()
		))
	else:
		left.add_child(UiKit.label("All subroutine slots compiled.", 13, UiKit.MUTED))
	# the job builder for the selected worker
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	var w := Game.worker_by_id(_sel_worker)
	if w.is_empty():
		right.add_child(UiKit.label("Compile a subroutine to start dispatching jobs.", 16, UiKit.MUTED))
		return _panel_holder
	if w.state != "idle":
		right.add_child(UiKit.label("%s is busy. Select an idle subroutine to plan a job." % w.name, 16, UiKit.MUTED))
		return _panel_holder
	right.add_child(UiKit.label("PLAN A JOB FOR %s" % String(w.name).to_upper(), 14, Color("6ee06a"), true))
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 8)
	right.add_child(kinds)
	for kd in Db.JOBS:
		var kb := UiKit.button(Db.JOBS[kd].name, func():
			_job_kind = kd
			_job_target = ""
			_rebuild()
		)
		if kd == _job_kind:
			kb.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.3, 0.2, 1), Color("6ee06a"), 8, 2, 8))
		kinds.add_child(kb)
	var jd := UiKit.label(Db.JOBS[_job_kind].desc, 14, UiKit.MUTED)
	jd.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(jd)
	var targets := Game.job_targets(_job_kind)
	if targets.is_empty():
		right.add_child(UiKit.label("No destinations yet: %s" % ("visit a town first." if _job_kind == "haul" else "land on a world first."), 15, Color("ffb86b")))
		return _panel_holder
	if not targets.has(_job_target):
		_job_target = targets[0]
	var trow := HBoxContainer.new()
	right.add_child(trow)
	trow.add_child(UiKit.label("Destination  ", 15))
	var opt := OptionButton.new()
	for k in targets.size():
		var tk: String = targets[k]
		var parts := tk.split(":")
		var pl := Game._planet_of(tk)
		var label: String = pl.get("town", {}).get("name", pl.name) if _job_kind == "haul" else pl.name
		opt.add_item("%s  (%s, danger %d)" % [label, Db.BIOMES.get(pl.biome, {}).get("name", "?"), Game.planet_level(int(parts[0]), int(parts[1]))], k)
		if tk == _job_target:
			opt.select(k)
	opt.item_selected.connect(func(ix):
		_job_target = targets[ix]
		_rebuild()
	)
	trow.add_child(opt)
	if _job_kind == "haul":
		var irow := HBoxContainer.new()
		right.add_child(irow)
		irow.add_child(UiKit.label("Cargo from vault  ", 15))
		var iopt := OptionButton.new()
		var vitems: Array = []
		for it in Game.vault:
			if Db.VALUES.has(it):
				vitems.append(it)
		if not vitems.has(_job_item):
			_job_item = vitems[0] if not vitems.is_empty() else ""
		for k in vitems.size():
			iopt.add_item("%s  x%d" % [Db.item_name(vitems[k]), Game.vault_count(vitems[k])], k)
			if vitems[k] == _job_item:
				iopt.select(k)
		iopt.item_selected.connect(func(ix):
			_job_item = vitems[ix]
			_rebuild()
		)
		irow.add_child(iopt)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	right.add_child(mrow)
	mrow.add_child(UiKit.label("Duration  ", 15))
	for mn in Db.JOB_MINUTES:
		var mb := UiKit.button("%d min" % mn, func():
			_job_min = mn
			_rebuild()
		)
		if mn == _job_min:
			mb.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.3, 0.2, 1), Color("6ee06a"), 8, 2, 8))
		mrow.add_child(mb)
	var pv := Game.job_preview(w, _job_kind, _job_target, _job_min, _job_item)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.1, 0.08, 0.9), Color(0.4, 1.0, 0.5, 0.3), 8, 1, 12))
	right.add_child(box)
	var bv := VBoxContainer.new()
	box.add_child(bv)
	var sm := UiKit.label("Expected: " + String(pv.summary), 16, Color.WHITE)
	sm.autowrap_mode = TextServer.AUTOWRAP_WORD
	bv.add_child(sm)
	var risk: float = pv.risk
	bv.add_child(UiKit.label("Risk of damage: %d%%   (it would bring back half, and need repairs)" % int(risk), 14, Color("ff6b6b") if risk > 30.0 else (Color("ffd23f") if risk > 12.0 else Color("6ee06a"))))
	var go := UiKit.button("Send %s  (%d min)" % [w.name, _job_min], func():
		if Game.job_start(int(w.id), _job_kind, _job_target, _job_min, _job_item):
			Sound.play("probe_launch", -6.0, 0.0, "UI")
		_rebuild()
	)
	go.custom_minimum_size = Vector2(0, 48)
	go.disabled = _job_kind == "haul" and int(pv.get("qty", 0)) <= 0
	right.add_child(go)
	return _panel_holder


func _panel_decor() -> Control:
	var v := _frame("DECOR", Vector2(1120, 680))
	v.add_child(UiKit.label("Credits ⌬ %d" % Game.credits, 16, Color("ffd23f")))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var h := Game.home_state()
	# place
	var place := ScrollContainer.new()
	place.name = "Arrange"
	place.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(place)
	var pl := VBoxContainer.new()
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.add_theme_constant_override("separation", 6)
	place.add_child(pl)
	var n_floor := 0
	var n_wall := 0
	for sl in slots:
		var row := HBoxContainer.new()
		pl.add_child(row)
		var nm: String
		if sl.kind == "floor":
			n_floor += 1
			nm = "Floor spot %d" % n_floor
		else:
			n_wall += 1
			nm = "Wall spot %d" % n_wall
		var l := UiKit.label(nm, 15)
		l.custom_minimum_size = Vector2(180, 0)
		row.add_child(l)
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(320, 0)
		opt.add_item("(empty)", 0)
		var choices: Array = [""]
		for id in h.owned:
			if Db.DECOR[id].slot == sl.kind:
				choices.append(id)
				opt.add_item(Db.DECOR[id].name, choices.size() - 1)
		var cur: String = h.slots.get(sl.id, "")
		opt.select(maxi(choices.find(cur), 0))
		var sid: String = sl.id
		opt.item_selected.connect(func(ix):
			Game.decor_place(sid, choices[ix])
			Sound.play("ui_click", -8.0, 0.0, "UI")
			_rebuild.call_deferred()
		)
		row.add_child(opt)
		var go := UiKit.button("Go there", func():
			_close_panel()
			_avatar_x = float(sl.x)
		)
		row.add_child(go)
	# shop
	var shop := ScrollContainer.new()
	shop.name = "Shop"
	shop.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(shop)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 6)
	shop.add_child(sv)
	for id in Db.DECOR:
		var d: Dictionary = Db.DECOR[id]
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		sv.add_child(row2)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(tv)
		tv.add_child(UiKit.label("%s  ·  %s" % [d.name, "wall" if d.slot == "wall" else "floor"], 16, Color.WHITE, true))
		var dl := UiKit.label(d.desc, 13, UiKit.MUTED)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD
		tv.add_child(dl)
		if (h.owned as Array).has(id):
			row2.add_child(UiKit.label("Owned", 14, Color("6ee06a")))
		else:
			var did: String = id
			var b := UiKit.button("Buy  ⌬ %d" % int(d.price), func():
				if Game.decor_buy(did):
					Sound.play("coin", -4.0, 0.0, "UI")
					# drop it straight into the first free slot of its kind
					for sl2 in slots:
						if sl2.kind == Db.DECOR[did].slot and not Game.home_state().slots.has(sl2.id):
							Game.decor_place(sl2.id, did)
							break
				_rebuild()
			)
			b.disabled = Game.credits < int(d.price)
			row2.add_child(b)
	# themes + wings
	var more := VBoxContainer.new()
	more.name = "Theme & Expand"
	more.add_theme_constant_override("separation", 10)
	tabs.add_child(more)
	more.add_child(UiKit.label("ROOM THEME", 14, Color("ffb86b"), true))
	var tf := HFlowContainer.new()
	tf.add_theme_constant_override("h_separation", 8)
	more.add_child(tf)
	for tid in Db.HOME_THEMES:
		var t: Dictionary = Db.HOME_THEMES[tid]
		var owned: bool = (h.themes as Array).has(tid)
		var tb := UiKit.button(t.name + ("" if owned else "  ⌬ %d" % int(t.price)), func():
			if Game.theme_buy(tid):
				Sound.play("ui_click", -6.0, 0.0, "UI")
			_rebuild()
		)
		if h.theme == tid:
			tb.add_theme_stylebox_override("normal", UiKit.box(Color(t.bot, 1.0), t.trim, 8, 2, 8))
		tf.add_child(tb)
	more.add_child(HSeparator.new())
	more.add_child(UiKit.label("EXPAND THE HOMESPACE", 14, Color("ffb86b"), true))
	var wn := int(h.wings)
	if wn < Db.HOME_WINGS.size():
		var wd: Array = Db.HOME_WINGS[wn]
		var wdesc := UiKit.label("%s: more room to the right, %d floor and %d wall spots, and %s." % [wd[0], wd[2], wd[3], "a dome window onto your relay Circuit" if wn == 0 else "a planter of glowing plants and a big sea tank"], 14, UiKit.MUTED)
		wdesc.autowrap_mode = TextServer.AUTOWRAP_WORD
		more.add_child(wdesc)
		var wb := UiKit.button("Compile %s  (⌬ %d)" % [wd[0], int(wd[1])], func():
			if Game.wing_buy():
				_build_layout()
				Sound.play("quest_complete", -6.0, 0.0, "UI")
			_rebuild()
		)
		wb.disabled = Game.credits < int(wd[1])
		more.add_child(wb)
	else:
		more.add_child(UiKit.label("Fully expanded.", 14, UiKit.MUTED))
	tabs.current_tab = _decor_tab
	tabs.tab_changed.connect(func(tb): _decor_tab = tb)
	return _panel_holder


var _decor_tab := 0


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
	var th: Dictionary = Db.HOME_THEMES.get(Game.home_state().theme, Db.HOME_THEMES.midnight)
	var wall_top: Color = th.top
	var wall_bot: Color = th.bot
	var grid: Color = th.grid
	var trim: Color = th.trim
	var x0 := scroll - 10.0
	var x1 := scroll + vs.x + 10.0
	# back wall gradient
	var bands := 18
	for i in bands:
		var t0 := float(i) / bands
		room.draw_rect(Rect2(x0, fy * t0, x1 - x0, fy / bands + 1.0), wall_top.lerp(wall_bot, t0))
	# wing seams: each wing is a slightly different shade with a doorway arch
	for w in int(Game.home_state().wings):
		var bx := BASE_W + w * WING_W
		room.draw_rect(Rect2(bx, 0, WING_W, fy), Color(1, 1, 1, 0.02 + 0.015 * w))
		room.draw_line(Vector2(bx, 60), Vector2(bx, fy), Color(trim, 0.35), 3.0)
	var pulse := 0.5 + 0.5 * sin(_t * 0.8)
	var gx := floorf(x0 / 64.0) * 64.0
	while gx < x1:
		room.draw_line(Vector2(gx, 0), Vector2(gx, fy), Color(grid, 0.05 + 0.02 * pulse), 1.0)
		gx += 64.0
	for y in range(0, int(fy), 64):
		room.draw_line(Vector2(x0, y), Vector2(x1, y), Color(grid, 0.05 + 0.02 * pulse), 1.0)
	# ceiling light strip along the whole room
	room.draw_rect(Rect2(40, 18, room_w - 80, 6), Color(trim, 0.6))
	for k in 4:
		room.draw_rect(Rect2(40 - k * 6, 18 - k * 4, room_w - 80 + k * 12, 6 + k * 8), Color(trim, 0.04))
	# floor with a perspective grid that follows the view
	room.draw_rect(Rect2(x0, fy, x1 - x0, vs.y - fy), wall_top.darkened(0.3))
	var vp := Vector2(scroll + vs.x * 0.5, fy - 260.0)
	for i in range(-16, 17):
		var bx2 := scroll + vs.x * 0.5 + i * vs.x * 0.09 - fmod(scroll, vs.x * 0.09)
		var a := Vector2(bx2, vs.y)
		var b := a.lerp(vp, (vs.y - fy) / (vs.y - vp.y))
		room.draw_line(b, a, Color(grid, 0.18), 1.0)
	for k in 7:
		var tt := pow(float(k) / 7.0, 1.8)
		var y := fy + (vs.y - fy) * tt
		room.draw_line(Vector2(x0, y), Vector2(x1, y), Color(grid, 0.12 + 0.1 * tt), 1.0)
	room.draw_line(Vector2(0, fy), Vector2(room_w, fy), Color(trim, 0.7), 2.0)
	# drifting data motes
	for m in _motes:
		var mx: float = m[0] * room_w + sin(_t * 0.3 + m[1] * 9.0) * 12.0
		if mx < x0 or mx > x1:
			continue
		var my: float = fmod(m[1] * fy - _t * 14.0 * m[2] + fy * 4.0, fy)
		room.draw_rect(Rect2(mx, my, 2, 2), Color(trim, 0.25 * m[2]))
	# decor on the wall, behind the stations
	var h := Game.home_state()
	for sl in slots:
		if sl.kind == "wall" and h.slots.has(sl.id):
			_draw_decor(h.slots[sl.id], Vector2(sl.x, fy - 500.0))
	for st in stations:
		var x := _station_x(st)
		if x < x0 - 400.0 or x > x1 + 400.0:
			continue
		match st.id:
			"vault":
				_draw_vault(x, fy)
			"inbox":
				_draw_inbox(x, fy)
			"dispatch":
				_draw_dispatch(x, fy)
			"window":
				_draw_window(x, fy)
			"trophy":
				_draw_trophy(x, fy)
			"decor":
				_draw_decor_console(x, fy)
			"exit":
				_draw_exit(x, fy)
			"observatory":
				_draw_observatory(x, fy)
			"garden":
				_draw_garden(x, fy)
	for sl in slots:
		if sl.kind == "floor" and h.slots.has(sl.id):
			_draw_decor(h.slots[sl.id], Vector2(sl.x, fy))
	_draw_avatar(Vector2(_avatar_x, fy))


func _draw_dispatch(x: float, fy: float) -> void:
	# a console with a pod for each subroutine
	var con := Rect2(x - 60, fy - 200, 120, 200)
	_neon_rect(con, Color("6ee06a"), Color("10221a"))
	var scr := Rect2(con.position + Vector2(12, 16), Vector2(96, 64))
	room.draw_rect(scr, Color("0a1a10"))
	var busy := 0
	for w in Game.workers:
		if w.state == "job":
			busy += 1
	for k in 4:
		var yy := scr.position.y + 12 + k * 13
		room.draw_line(Vector2(scr.position.x + 8, yy), Vector2(scr.position.x + 8 + 60 * absf(sin(_t * 0.7 + k)), yy), Color(0.4, 1.0, 0.5, 0.7), 3.0)
	_label_at(Vector2(x, con.position.y - 16), "DISPATCH  %d/%d out" % [busy, Game.workers.size()], Color("6ee06a"))
	for k in 3:
		var px: float = x + [-110.0, 110.0, 180.0][k]
		var pod := Rect2(px - 30, fy - 130, 60, 130)
		room.draw_rect(pod, Color(0.1, 0.2, 0.15, 0.6))
		room.draw_rect(pod, Color(0.4, 1.0, 0.5, 0.35), false, 2.0)
		if k >= Game.workers.size():
			continue
		var w: Dictionary = Game.workers[k]
		match w.state:
			"idle", "hurt":
				_draw_worker(Vector2(px, fy), k, w.state == "hurt")
				_label_at(Vector2(px, fy - 150), "%s  Lv%d" % [w.name, int(w.level)], Color(0.7, 1.0, 0.8), 13)
			"job":
				var left := int(ceil(float(w.job.left) / 60.0))
				room.draw_circle(Vector2(px, fy - 70), 6.0 + sin(_t * 4.0) * 1.5, Color(1.0, 0.8, 0.3))
				_label_at(Vector2(px, fy - 150), "%s  %dm" % [w.name, left], Color(1.0, 0.85, 0.5), 13)


func _draw_worker(p: Vector2, k: int, hurt: bool) -> void:
	var col: Color = [Color("6ee06a"), Color("ffb347"), Color("8f9bff")][k % 3]
	var bob := sin(_t * 3.0 + k) * 2.0
	var o := p + Vector2(0, -40 + bob)
	room.draw_line(o + Vector2(-5, 12), o + Vector2(-5, 38 - bob), Color("2a2f3a"), 5.0)
	room.draw_line(o + Vector2(5, 12), o + Vector2(5, 38 - bob), Color("2a2f3a"), 5.0)
	room.draw_rect(Rect2(o + Vector2(-11, -6), Vector2(22, 18)), col.darkened(0.2))
	room.draw_circle(o + Vector2(0, -14), 9.0, col)
	room.draw_rect(Rect2(o + Vector2(-5, -17), Vector2(10, 4)), Color("1b1f29"))
	if hurt:
		var sp := o + Vector2(randf_range(-10, 10), randf_range(-20, 0))
		room.draw_line(sp, sp + Vector2(4, -4), Color(1.0, 0.9, 0.4), 2.0)


func _draw_decor_console(x: float, fy: float) -> void:
	var r := Rect2(x - 55, fy - 160, 110, 160)
	_neon_rect(r, Color("ffb86b"), Color("241a10"))
	for k in 5:
		var c := Color.from_hsv(fmod(k * 0.2 + _t * 0.05, 1.0), 0.6, 1.0)
		room.draw_circle(r.position + Vector2(22 + (k % 3) * 33, 40 + (k / 3) * 34), 11.0, c)
	_label_at(Vector2(x, r.position.y - 16), "DECOR", Color("ffb86b"))


func _draw_observatory(x: float, fy: float) -> void:
	# a dome window onto the galaxy, with lit relays glowing
	var c := Vector2(x, fy - 260)
	var rr := 240.0
	var pts := PackedVector2Array()
	for i in 33:
		var a := PI + PI * i / 32.0
		pts.append(c + Vector2(cos(a) * rr, sin(a) * rr))
	pts.append(c + Vector2(rr, 120))
	pts.append(c + Vector2(-rr, 120))
	room.draw_colored_polygon(pts, Color("04050f"))
	for k in 90:
		var sp := c + Vector2(fmod(k * 131.0, rr * 2.0) - rr, -fmod(k * 71.0, rr) + 110)
		if sp.distance_to(c) < rr - 6:
			room.draw_rect(Rect2(sp, Vector2(2, 2)), Color(1, 1, 1, 0.3 + 0.4 * absf(sin(_t + k))))
	# relays: lit ones joined as a constellation
	var lit: Array = Game.lit_relays
	var prev := Vector2.INF
	for i in lit.size():
		var st: Dictionary = Galaxy.star(int(lit[i]))
		var sp3: Vector3 = st.pos
		var sp2: Vector2 = c + Vector2(sp3.x, sp3.z * 0.5) * ((rr - 20.0) / 80.0)
		sp2 = c + (sp2 - c).limit_length(rr - 20.0)
		room.draw_circle(sp2, 5.0 + sin(_t * 2.0 + i) * 1.0, Color("5ff7ff"))
		if prev != Vector2.INF:
			room.draw_line(prev, sp2, Color(0.4, 0.95, 1.0, 0.5), 1.5)
		prev = sp2
	room.draw_polyline(pts, Color("8fa6d8"), 5.0)
	_label_at(Vector2(x, c.y - rr - 18), "OBSERVATORY", Color("5ff7ff"))


func _draw_garden(x: float, fy: float) -> void:
	# a long planter of glowing alien plants and a sea tank
	var bed := Rect2(x - 330, fy - 60, 660, 60)
	room.draw_rect(bed, Color("1e2a1e"))
	room.draw_rect(bed, Color(0.5, 1.0, 0.6, 0.4), false, 2.0)
	for k in 14:
		var px := bed.position.x + 30 + k * 46
		var hgt := 60.0 + 40.0 * absf(sin(k * 1.7))
		var sway := sin(_t * 1.3 + k) * 8.0
		room.draw_line(Vector2(px, bed.position.y), Vector2(px + sway, bed.position.y - hgt), Color("3a7a4a"), 4.0)
		room.draw_circle(Vector2(px + sway, bed.position.y - hgt), 9.0, Color.from_hsv(0.3 + 0.05 * sin(k), 0.6, 1.0, 0.85))
	_draw_tank(Vector2(x, fy - 250), 300.0, 150.0)
	_label_at(Vector2(x, fy - 350), "GARDEN", Color("6ee06a"))


func _draw_tank(c: Vector2, w: float, hgt: float) -> void:
	var r := Rect2(c - Vector2(w, hgt) * 0.5, Vector2(w, hgt))
	room.draw_rect(r, Color(0.1, 0.35, 0.55, 0.8))
	# one fish per logged sea species (at least two, so it's never empty)
	var sea_sp := 0
	for k in Game.scanned:
		if ":sea:" in k:
			sea_sp += 1
	for f in maxi(sea_sp, 2):
		var fx := r.position.x + fmod(_t * (30.0 + f * 7.0) + f * 70.0, w)
		var fy2 := r.position.y + 20 + fmod(f * 37.0, hgt - 40) + sin(_t * 2.0 + f) * 5.0
		var col := Color.from_hsv(fmod(f * 0.17, 1.0), 0.6, 1.0)
		room.draw_colored_polygon(PackedVector2Array([Vector2(fx + 8, fy2), Vector2(fx, fy2 - 4), Vector2(fx - 8, fy2), Vector2(fx, fy2 + 4)]), col)
		room.draw_colored_polygon(PackedVector2Array([Vector2(fx - 8, fy2), Vector2(fx - 14, fy2 - 5), Vector2(fx - 14, fy2 + 5)]), col.darkened(0.2))
	for k in 6:
		var bp := Vector2(r.position.x + 20 + k * (w - 40) / 5.0, r.end.y - fmod(_t * 25.0 + k * 40.0, hgt))
		room.draw_circle(bp, 2.0, Color(1, 1, 1, 0.4))
	room.draw_rect(r, Color("8fd8ff"), false, 3.0)


func _draw_decor(id: String, p: Vector2) -> void:
	var trim: Color = Db.HOME_THEMES.get(Game.home_state().theme, Db.HOME_THEMES.midnight).trim
	match id:
		"bonsai":
			room.draw_rect(Rect2(p.x - 18, p.y - 26, 36, 26), Color("2a2f4a"))
			room.draw_line(Vector2(p.x, p.y - 26), Vector2(p.x + 4, p.y - 70), Color("5a4a6a"), 4.0)
			for k in 5:
				var lp := Vector2(p.x + 4 + cos(k * 1.3) * 18.0, p.y - 74 + sin(k * 1.7) * 10.0)
				room.draw_circle(lp, 9.0 + sin(_t * 1.5 + k) * 1.0, Color(0.4, 1.0, 0.7, 0.75))
		"lamp":
			room.draw_line(p, p + Vector2(0, -170), Color("3a3f5a"), 4.0)
			room.draw_circle(p + Vector2(0, -175), 40.0, Color(1.0, 0.85, 0.5, 0.08))
			room.draw_colored_polygon(PackedVector2Array([p + Vector2(-22, -170), p + Vector2(22, -170), p + Vector2(14, -200), p + Vector2(-14, -200)]), Color(1.0, 0.85, 0.55))
			room.draw_rect(Rect2(p.x - 20, p.y - 6, 40, 6), Color("3a3f5a"))
		"cactus":
			room.draw_rect(Rect2(p.x - 16, p.y - 24, 32, 24), Color("6a3a2a"))
			room.draw_rect(Rect2(p.x - 7, p.y - 80, 14, 56), Color("6ab04a"))
			room.draw_rect(Rect2(p.x - 22, p.y - 64, 10, 22), Color("6ab04a"))
			room.draw_rect(Rect2(p.x + 12, p.y - 70, 10, 26), Color("6ab04a"))
			room.draw_circle(p + Vector2(0, -82), 5.0, Color("ff7a9a"))
		"globe":
			room.draw_line(p, p + Vector2(0, -60), Color("3a3f5a"), 4.0)
			var gc := p + Vector2(0, -96)
			var pl: Dictionary = Galaxy.planet(0, 0)
			var b: Dictionary = Db.BIOMES[pl.biome]
			room.draw_circle(gc, 34.0, b.colors.deep)
			for k in 4:
				var ox := fmod(_t * 18.0 + k * 22.0, 80.0) - 40.0
				if absf(ox) < 30.0:
					room.draw_circle(gc + Vector2(ox, -10 + k * 7), 9.0 * cos(ox / 40.0), b.colors.mid)
			room.draw_arc(gc, 36.0, 0.0, TAU, 32, Color(b.atmo, 0.8), 3.0)
		"crystal":
			for k in 4:
				var base := p + Vector2(-24 + k * 16, 0)
				var ht := 40.0 + 30.0 * absf(sin(k * 2.1))
				room.draw_colored_polygon(PackedVector2Array([base + Vector2(-8, 0), base + Vector2(8, 0), base + Vector2(3, -ht), base + Vector2(-3, -ht - 8)]), Color(0.75, 0.55, 1.0, 0.7 + 0.2 * sin(_t * 2.0 + k)))
		"arcade":
			var r := Rect2(p.x - 32, p.y - 140, 64, 140)
			room.draw_rect(r, Color("2a1f4a"))
			room.draw_rect(Rect2(r.position + Vector2(8, 16), Vector2(48, 38)), Color.from_hsv(fmod(_t * 0.3, 1.0), 0.7, 0.8))
			room.draw_circle(r.position + Vector2(20, 76), 5.0, Color("ff4f4f"))
			room.draw_circle(r.position + Vector2(40, 76), 5.0, Color("4fb4ff"))
			room.draw_rect(r, Color(trim, 0.6), false, 2.0)
		"aquarium":
			room.draw_rect(Rect2(p.x - 70, p.y - 30, 140, 30), Color("2a2f4a"))
			_draw_tank(p + Vector2(0, -85), 140.0, 90.0)
		"charging_pod":
			var ready := Game.charge_ready() <= 0.0
			var pod := Rect2(p.x - 50, p.y - 70, 100, 70)
			room.draw_rect(pod, Color("1a2a3a"))
			room.draw_arc(pod.get_center() + Vector2(0, 10), 50.0, PI, TAU, 24, Color("8fd8ff"), 3.0)
			room.draw_rect(Rect2(pod.position.x + 14, pod.end.y - 12, 72, 5), Color("6ee06a") if ready else Color("ffb86b"))
		"neon_home":
			var col := trim.lerp(Color("ff6fd8"), 0.5)
			for k in 3:
				_label_at(p + Vector2(0, 8), "HOME", Color(col, 0.2), 44 + k * 2)
			_label_at(p + Vector2(0, 8), "HOME", col, 42)
		"clock":
			var up := int(Game.play_time)
			room.draw_rect(Rect2(p.x - 70, p.y - 26, 140, 52), Color("0a0d1a"))
			room.draw_rect(Rect2(p.x - 70, p.y - 26, 140, 52), Color(trim, 0.6), false, 2.0)
			_label_at(p + Vector2(0, 10), "%02d:%02d:%02d" % [up / 3600, (up / 60) % 60, up % 60], Color(1.0, 0.4, 0.4), 22)
		"string_lights":
			var acc := _accent
			for k in 11:
				var lp2 := p + Vector2(-150 + k * 30, sin(k * 0.6) * 14.0 - 20)
				if k > 0:
					var pp := p + Vector2(-150 + (k - 1) * 30, sin((k - 1) * 0.6) * 14.0 - 20)
					room.draw_line(pp, lp2, Color("3a3f5a"), 1.5)
				room.draw_circle(lp2, 5.0, Color(acc, 0.6 + 0.4 * sin(_t * 3.0 + k)))
		"star_chart":
			var r2 := Rect2(p.x - 80, p.y - 60, 160, 120)
			room.draw_rect(r2, Color("0a1030"))
			room.draw_rect(r2, Color("c9a86a"), false, 3.0)
			var pts2: Array[Vector2] = []
			for i in mini(Game.lit_relays.size(), 8):
				pts2.append(r2.position + Vector2(20 + fmod(i * 47.0, 120.0), 20 + fmod(i * 29.0, 80.0)))
			for i in pts2.size():
				room.draw_circle(pts2[i], 3.0, Color(1, 1, 0.8))
				if i > 0:
					room.draw_line(pts2[i - 1], pts2[i], Color(1, 1, 0.8, 0.4), 1.0)
		"poster":
			var r3 := Rect2(p.x - 60, p.y - 80, 120, 160)
			room.draw_rect(r3, _accent.darkened(0.6))
			room.draw_rect(r3, Color("e6e8ec"), false, 3.0)
			room.draw_circle(r3.get_center() + Vector2(0, -20), 24.0, _shell)
			room.draw_rect(Rect2(r3.get_center() + Vector2(-14, -26), Vector2(28, 8)), _glow)
			room.draw_rect(Rect2(r3.get_center() + Vector2(-26, 8), Vector2(52, 40)), _shell)
			_label_at(r3.get_center() + Vector2(0, 70), Game.robot().name.to_upper(), Color.WHITE, 13)
		"holo_fish":
			var r4 := Rect2(p.x - 80, p.y - 50, 160, 100)
			room.draw_rect(r4, Color(0.2, 0.6, 1.0, 0.1))
			room.draw_rect(r4, Color(trim, 0.5), false, 2.0)
			for k in 2:
				var a := _t * 0.8 + k * PI
				var fp := r4.get_center() + Vector2(cos(a) * 50.0, sin(a) * 25.0)
				var d := Vector2(-sin(a), cos(a) * 0.5).normalized()
				var col2 := Color(1.0, 0.6, 0.3) if k == 0 else Color(1, 1, 1)
				room.draw_colored_polygon(PackedVector2Array([fp + d * 12, fp + d.orthogonal() * 5, fp - d * 10, fp - d.orthogonal() * 5]), Color(col2, 0.8))


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
