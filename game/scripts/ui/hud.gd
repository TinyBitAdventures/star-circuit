extends CanvasLayer
## In-game HUD + all modal panels (inventory, crafting, skills, quests, help,
## pause, NPC dialog, galaxy map).

var mode := "planet" # planet | space

var root: Control
var energy_bar: ProgressBar
var energy_label: Label
var xp_bar: ProgressBar
var level_label: Label
var location_label: Label
var quest_box: VBoxContainer
var prompt_label: Label
var prompt_bar: ProgressBar
var toast_box: VBoxContainer
var big_title: Label
var big_sub: Label
var big_box: VBoxContainer
var banner: VBoxContainer
var speed_label: Label
var hull_bar: ProgressBar
var hull_label: Label
var shield_bar: ProgressBar
var crosshair: Label
var target_box: PanelContainer
var target_name: Label
var target_bar: ProgressBar
var target_hp: Label
var ability_label: Label
var ability_bar: ProgressBar
var damage_flash: ColorRect
var death_box: Control
var compass: Control
var survey_label: Label
var _compass_data := {}
var credits_label: Label
var _town_planet := {}
var _trade_tab := "buy"
var threat_layer: Control
var cargo_bar: ProgressBar
var cargo_label: Label
var _station_star := 0
var _station_tab := "sell"
var _outfit_tab := "paint"
var _outfit_channel := "shell"
var _preview_robot: RobotVisual
var _preview_pivot: Node3D
var _preview_fly := false
var _threats: Array = []

var panel_host: Control
var current_panel := ""
var _panel: Control
var _big_queue: Array = []
var _big_busy := false
var _craft_selected := "alloy"
var galaxy_map: Control


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	_build_status()
	_build_quest_tracker()
	_build_prompt()
	_build_toasts()
	_build_big()
	_build_hints()
	_build_combat()
	if mode == "planet":
		_build_compass()
	elif mode == "space":
		threat_layer = Control.new()
		threat_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		threat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		threat_layer.draw.connect(_draw_threats)
		root.add_child(threat_layer)
	panel_host = Control.new()
	panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel_host)

	Game.energy_changed.connect(func(_v, _m): _refresh_status())
	Game.hull_changed.connect(_refresh_status)
	Game.credits_changed.connect(func():
		_refresh_status()
		if current_panel in ["trade", "trainer", "board", "station", "outfitter"]:
			_rebuild_town_panel()
	)
	Game.player_damaged.connect(_on_damaged)
	Game.xp_changed.connect(_refresh_status)
	Game.quest_changed.connect(_refresh_quest)
	Game.notify.connect(toast)
	Game.big_notify.connect(big)
	Game.tip_requested.connect(tip)
	Game.player_damaged.connect(func(_a): Game.tip("combat", "Under attack! Fire with Left Mouse, use your robot's ability with %s, swap weapons with %s, and patch up with a Repair Kit %s." % [Game.key("ability"), Game.key("weapon_cycle"), Game.key("repair")]))
	Game.energy_changed.connect(func(v, m): if m > 0.0 and v / m < 0.2: Game.tip("low_energy", "Energy is low. Stand in daylight to recharge, or burn an Energy Cell with %s." % Game.key("use_cell")))
	Game.inventory_changed.connect(_refresh_open_panel)
	Game.inventory_changed.connect(_refresh_status)
	Game.skill_changed.connect(func(_s): _refresh_open_panel())
	_refresh_status()
	_refresh_quest()
	Game.ui_open = false


# --------------------------------------------------------------------------
# persistent widgets
# --------------------------------------------------------------------------

func _build_status() -> void:
	var pc := PanelContainer.new()
	pc.position = Vector2(20, 20)
	pc.custom_minimum_size = Vector2(340, 0)
	root.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var r: Dictionary = Game.robot()
	top.add_child(UiKit.swatch(r.color, 18))
	var name_l := UiKit.label("%s" % Game.player_name, 20, Color.WHITE, true)
	top.add_child(name_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	credits_label = UiKit.label("", 15, Color("ffd23f"))
	top.add_child(credits_label)
	var sp_c := Control.new()
	sp_c.custom_minimum_size = Vector2(10, 0)
	top.add_child(sp_c)
	level_label = UiKit.label("", 16, Color("ffe066"))
	top.add_child(level_label)
	v.add_child(UiKit.label("%s  -  %s" % [r.name, r.title], 13, UiKit.MUTED))
	hull_label = _bar_header(v, "HULL", Color("7dff9a"))
	hull_bar = UiKit.bar(Color("4cd97b"), 16)
	v.add_child(hull_bar)
	shield_bar = UiKit.bar(Color("39e5ff"), 5)
	v.add_child(shield_bar)
	energy_label = _bar_header(v, "ENERGY", Color("ffe27a"))
	energy_bar = UiKit.bar(Color("ffcf3f"), 12)
	v.add_child(energy_bar)
	cargo_label = _bar_header(v, "CARGO", Color("d9c4a0"))
	cargo_bar = UiKit.bar(Color("c9a36b"), 6)
	v.add_child(cargo_bar)
	xp_bar = UiKit.bar(Color("b98cff"), 6)
	v.add_child(xp_bar)

	var loc := PanelContainer.new()
	loc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	loc.position = Vector2(-360, 20)
	loc.custom_minimum_size = Vector2(340, 0)
	root.add_child(loc)
	var lv := VBoxContainer.new()
	loc.add_child(lv)
	location_label = UiKit.label("", 15, UiKit.ACCENT)
	location_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	lv.add_child(location_label)
	speed_label = UiKit.label("", 13, UiKit.MUTED)
	lv.add_child(speed_label)
	survey_label = UiKit.label("", 13, Color("9be89b"))
	survey_label.visible = false
	lv.add_child(survey_label)
	_refresh_location()


func _bar_header(parent: Control, title: String, color: Color) -> Label:
	var h := HBoxContainer.new()
	parent.add_child(h)
	h.add_child(UiKit.label(title, 12, color))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var l := UiKit.label("", 12, color)
	h.add_child(l)
	return l


func _refresh_location() -> void:
	var star: Dictionary = Galaxy.star(Game.star_index)
	if mode in ["dig", "grotto"]:
		var p0: Dictionary = Galaxy.planet(Game.star_index, Game.planet_index)
		location_label.text = "Beneath %s  ·  %s\n%s system" % [p0.name, "The Deep" if mode == "dig" else "Sealed chamber", star.name]
		if Game.cave.get("origin", "") == "space":
			location_label.text = "Aboard a derelict\n%s system" % star.name
	elif mode == "orbit":
		location_label.text = "Holding orbit  ·  %s\n%s system" % [Game.orbit.get("name", "?"), star.name]
	elif mode == "planet":
		var p: Dictionary = Galaxy.planet(Game.star_index, Game.planet_index)
		location_label.text = "%s  ·  %s\n%s system (class %s)" % [p.name, Db.BIOMES[p.biome].name, star.name, star.cls]
	else:
		location_label.text = "Orbiting %s\nClass %s star  ·  %d worlds" % [star.name, star.cls, star.planets.size()]


func _build_quest_tracker() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.position = Vector2(-360, 132)
	pc.custom_minimum_size = Vector2(340, 0)
	pc.add_theme_stylebox_override("panel", UiKit.box(UiKit.BG_SOFT, Color(1, 0.82, 0.25, 0.4)))
	root.add_child(pc)
	quest_box = VBoxContainer.new()
	pc.add_child(quest_box)


func _refresh_quest() -> void:
	for c in quest_box.get_children():
		c.queue_free()
	var q: Dictionary = Game.current_quest()
	if q.is_empty():
		quest_box.add_child(UiKit.label("All quests complete. The Circuit shines.", 14, Color("6ee06a")))
		_add_bounty_lines()
		return
	if not Game.quest_accepted:
		quest_box.add_child(UiKit.label("! NEW QUEST", 13, Color("ffd23f"), true))
		var t := "Talk to the Archivist at the Cradle outpost." if Game.quest_index == 0 else "Incoming transmission..."
		var l := UiKit.label(t, 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		quest_box.add_child(l)
		_add_bounty_lines()
		return
	quest_box.add_child(UiKit.label(q.title.to_upper(), 13, Color("ffd23f"), true))
	var o := UiKit.label(objective_text(q), 15)
	o.autowrap_mode = TextServer.AUTOWRAP_WORD
	quest_box.add_child(o)
	var b := UiKit.bar(Color("ffd23f"), 6)
	b.max_value = q.obj.count
	b.value = Game.quest_progress
	quest_box.add_child(b)
	_add_bounty_lines()
	quest_box.add_child(UiKit.label("J - quest log", 11, UiKit.MUTED))


static func objective_text(q: Dictionary) -> String:
	var o: Dictionary = q.obj
	var p := Game.quest_progress
	match o.type:
		"collect":
			return "Gather %s: %d / %d" % [Db.item_name(o.item), p, o.count]
		"craft":
			return "Fabricate %s: %d / %d" % [Db.item_name(o.item), p, o.count]
		"scan":
			return "Scan new species (Q): %d / %d" % [p, o.count]
		"orbit":
			return "Break orbit (fly up, press T)"
		"warp":
			return "Warp to another star (M in space)"
		"land_unique":
			return "Worlds visited: %d / %d" % [p, o.count]
		"relay":
			return "Relays relit (beyond home): %d / %d" % [p, o.count]
		"legendary":
			return "Land on an edge world: %d / %d" % [p, o.count]
		"heart":
			return "Destroy the Corruption Heart"
		"dig":
			return "Dig out tiles in a cave: %d / %d" % [p, o.count]
		"gem":
			return "Probe a world from orbit (O) and extract a gem: %d / %d" % [p, o.count]
		"gem_types":
			return "Different world gems held: %d / %d" % [p, o.count]
		"chamber":
			return "Discover a sealed chamber: %d / %d" % [p, o.count]
		"sell":
			return "Sell goods to a merchant: %d / %d" % [p, o.count]
		"train":
			return "Train a profession rank"
		"visit_town":
			return "Trade hubs visited: %d / %d" % [p, o.count]
		"space_kill":
			return "Destroy pirate ships in space: %d / %d" % [p, o.count]
		"station_sell":
			return "Sell cargo at an orbital station: %d / %d" % [p, o.count]
		"space_elite":
			return "Destroy a Pirate Marauder: %d / %d" % [p, o.count]
		"kill":
			return "Destroy rogue drones: %d / %d" % [p, o.count]
		"kill_elite":
			return "Destroy a Rogue Brute (elite): %d / %d" % [p, o.count]
		"skill":
			return "Reach %s %d  (now %d)" % [Db.SKILLS[o.skill].name, o.count, Game.skill_level(o.skill)]
	return ""


func _build_prompt() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	v.position = Vector2(-260, -170)
	v.custom_minimum_size = Vector2(520, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	prompt_label = UiKit.label("", 20)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_constant_override("outline_size", 6)
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(prompt_label)
	prompt_bar = UiKit.bar(UiKit.ACCENT, 10)
	prompt_bar.max_value = 1.0
	prompt_bar.custom_minimum_size = Vector2(320, 10)
	prompt_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(prompt_bar)
	prompt_bar.visible = false


func set_prompt(text: String, color: Color, progress: float) -> void:
	prompt_label.text = text
	prompt_label.add_theme_color_override("font_color", color)
	prompt_bar.visible = progress > 0.0
	prompt_bar.value = progress


func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	toast_box.position = Vector2(-380, -40)
	toast_box.custom_minimum_size = Vector2(360, 0)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func toast(text: String, color: Color = Color.WHITE) -> void:
	if color == Color("ff6b6b"):
		Sound.ui("ui_error", -8.0)
	elif text.begins_with("+") and not text.ends_with("energy") and not text.ends_with("hull"):
		Sound.play("pickup", -10.0, 0.08, "UI", 0.12)
	elif text.begins_with("Species logged"):
		Sound.play("notify", -6.0, 0.05, "UI")
	var l := UiKit.label(text, 17, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast_box.add_child(l)
	while toast_box.get_child_count() > 7:
		toast_box.get_child(0).free()
	var t := l.create_tween()
	t.tween_interval(3.2)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _build_big() -> void:
	big_box = VBoxContainer.new()
	big_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	big_box.position = Vector2(-400, 150)
	big_box.custom_minimum_size = Vector2(800, 0)
	big_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(big_box)
	big_title = UiKit.label("", 34, Color.WHITE, true)
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.add_theme_constant_override("outline_size", 10)
	big_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	big_box.add_child(big_title)
	big_sub = UiKit.label("", 18)
	big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	big_sub.add_theme_constant_override("outline_size", 6)
	big_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	big_box.add_child(big_sub)
	big_box.modulate.a = 0.0

	banner = VBoxContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.position = Vector2(-500, -140)
	banner.custom_minimum_size = Vector2(1000, 0)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	root.add_child(banner)


func big(title: String, sub: String, color: Color) -> void:
	_big_queue.append([title, sub, color])
	if not _big_busy:
		_next_big()


func _next_big() -> void:
	if _big_queue.is_empty():
		_big_busy = false
		return
	_big_busy = true
	var e: Array = _big_queue.pop_front()
	big_title.text = e[0]
	big_title.add_theme_color_override("font_color", e[2])
	big_sub.text = e[1]
	_big_sound(e[0], e[1])
	var t := create_tween()
	t.tween_property(big_box, "modulate:a", 1.0, 0.25)
	t.tween_interval(2.2)
	t.tween_property(big_box, "modulate:a", 0.0, 0.4)
	t.tween_callback(_next_big)


func show_location_banner(title: String, sub: String) -> void:
	for c in banner.get_children():
		c.queue_free()
	var t1 := UiKit.label(title.to_upper(), 56, Color.WHITE, true)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_constant_override("outline_size", 12)
	t1.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	banner.add_child(t1)
	var t2 := UiKit.label(sub, 20, UiKit.ACCENT)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.add_theme_constant_override("outline_size", 6)
	t2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	banner.add_child(t2)
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(banner, "modulate:a", 1.0, 0.8)
	t.tween_interval(3.0)
	t.tween_property(banner, "modulate:a", 0.0, 1.2)


func _build_hints() -> void:
	var l := UiKit.label("", 13, UiKit.MUTED)
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.position = Vector2(20, -34)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	if mode == "planet":
		l.text = "WASD move · Space jump/jetpack · Shift sprint · E interact · LMB fire · F ability · G repair · Q scan · R energy · T take off · I C K J panels · H help"
	elif mode == "dig":
		l.text = "A/D move + drill sideways · S drill down · W/Space thrust (drills up at a ceiling) · E lift / enter chamber · T emergency lift · R energy · G repair · I C K J panels"
	elif mode == "orbit":
		l.text = "A/D orbit / steer probe · Space launch / reel in · S dive · W brake · Q deep scan · R energy · T leave orbit · I C K J panels"
	elif mode == "grotto":
		l.text = "WASD move · Space jump · Shift sprint · E interact · Q scan cave species · R energy cell · I C K J panels"
	else:
		l.text = "Mouse steer · W/S thrust · A/D strafe · Shift boost · LMB cannons (laser on rock) · RMB missiles · Q scan · E land · F dock · O orbit · M map · H help"
	root.add_child(l)


func _refresh_status() -> void:
	var m := Game.max_energy()
	energy_bar.max_value = m
	energy_bar.value = Game.energy
	energy_label.text = "%d / %d" % [int(Game.energy), int(m)]
	level_label.text = "LV %d" % Game.level
	credits_label.text = "⌬ %d" % Game.credits
	var cu := Game.cargo_used()
	var cc := Game.cargo_cap()
	cargo_bar.max_value = cc
	cargo_bar.value = cu
	cargo_label.text = "%d / %d" % [cu, cc]
	cargo_label.add_theme_color_override("font_color", Color("ff6b6b") if cu >= cc else Color("d9c4a0"))
	xp_bar.max_value = Db.level_xp_needed(Game.level)
	xp_bar.value = Game.xp
	xp_bar.tooltip_text = "XP %d / %d" % [Game.xp, Db.level_xp_needed(Game.level)]
	var mh := Game.max_hull()
	hull_bar.max_value = mh
	hull_bar.value = Game.hull
	hull_label.text = "%d / %d" % [int(Game.hull), int(mh)]
	var low := Game.hull / mh < 0.3
	var fill := UiKit.box(Color("e0453a") if low else Color("4cd97b"), Color(0, 0, 0, 0), 5, 0, 0)
	fill.shadow_size = 0
	hull_bar.add_theme_stylebox_override("fill", fill)
	shield_bar.visible = Game.max_shield() > 0.0
	shield_bar.max_value = maxf(1.0, Game.max_shield())
	shield_bar.value = Game.shield


func set_speed_text(t: String) -> void:
	speed_label.text = t


# --------------------------------------------------------------------------
# panels
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action("pause"):
		if current_panel != "":
			close_panel()
		else:
			toggle_panel("pause")
		get_viewport().set_input_as_handled()
		return
	for pair in [["inventory", "inventory"], ["crafting", "crafting"], ["skills", "skills"], ["quests", "quests"], ["help", "help"], ["map", "map"]]:
		if event.is_action(pair[0]):
			if pair[1] == "map" and mode != "space":
				toast("The maps work in space. Press T to break orbit.", UiKit.MUTED)
				return
			if pair[1] == "map" and current_panel == "":
				toggle_panel("sysmap")
				get_viewport().set_input_as_handled()
				return
			if pair[1] == "map" and current_panel in ["sysmap", "map"]:
				close_panel()
				get_viewport().set_input_as_handled()
				return
			toggle_panel(pair[1])
			get_viewport().set_input_as_handled()
			return


func toggle_panel(name: String) -> void:
	if current_panel == name:
		close_panel()
		return
	close_panel(false)
	Sound.ui("ui_open", -6.0)
	current_panel = name
	Game.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _tip_box and is_instance_valid(_tip_box):
		_tip_box.queue_free()
		_tip_box = null
	_build_panel()


func close_panel(recapture := true) -> void:
	if _panel and recapture:
		Sound.ui("ui_close", -8.0)
	if _panel:
		_panel.queue_free()
		_panel = null
	if galaxy_map:
		galaxy_map.queue_free()
		galaxy_map = null
	current_panel = ""
	Game.ui_open = false
	if recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_open_panel() -> void:
	if current_panel in ["inventory", "crafting", "skills"]:
		var keep := current_panel
		if _panel:
			_panel.queue_free()
			_panel = null
		current_panel = keep
		_build_panel()


func _frame(title: String, size := Vector2(980, 640)) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_host.add_child(dim)
	_panel = dim
	var pc := PanelContainer.new()
	pc.custom_minimum_size = size
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.position = -size / 2.0
	pc.add_theme_stylebox_override("panel", UiKit.box(UiKit.BG, UiKit.ACCENT * Color(1, 1, 1, 0.6), 14, 1, 22))
	dim.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiKit.label(title, 26, Color.WHITE, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiKit.button("Close  [Esc]", close_panel))
	var sep := HSeparator.new()
	v.add_child(sep)
	return v


func _build_panel() -> void:
	match current_panel:
		"inventory": _panel_inventory()
		"crafting": _panel_crafting()
		"skills": _panel_skills()
		"quests": _panel_quests()
		"help": _panel_help()
		"pause": _panel_pause()
		"dialog": _panel_dialog()
		"map": _panel_map()
		"lore": _panel_lore()
		"trade": _panel_trade()
		"trainer": _panel_trainer()
		"board": _panel_board()
		"station": _panel_station()
		"outfitter": _panel_outfitter()
		"sysmap": _panel_sysmap()
		"settings": _panel_settings()
		"victory": _panel_victory()


func _panel_inventory() -> void:
	var v := _frame("CARGO & SYSTEMS")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.6
	h.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var kinds := {"resource": "Raw Resources", "component": "Components", "consumable": "Consumables", "fuel": "Fuel & Probes", "key": "Relay Keys", "gem": "World Gems", "relic": "Relics & Fossils"}
	var any := false
	for kind in kinds:
		var items := []
		for id in Game.inventory:
			if Db.ITEMS[id].kind == kind:
				items.append(id)
		if items.is_empty():
			continue
		any = true
		list.add_child(UiKit.label(kinds[kind].to_upper(), 13, UiKit.MUTED, true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		list.add_child(grid)
		for id in items:
			grid.add_child(_item_card(id, Game.count(id)))
		list.add_child(Control.new())
	if not any:
		list.add_child(UiKit.label("Cargo hold is empty. Go break some rocks.", 16, UiKit.MUTED))

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	var r: Dictionary = Game.robot()
	side.add_child(UiKit.label("FRAME", 13, UiKit.MUTED, true))
	side.add_child(UiKit.rich("[b]%s[/b] the %s  ·  Level %d\n[color=#8ea3bf]%s[/color]" % [Game.player_name, r.title, Game.level, r.name]))
	for perk in r.perks:
		side.add_child(UiKit.label("•  " + perk, 14, r.color.lightened(0.2)))
	side.add_child(HSeparator.new())
	side.add_child(UiKit.label("SYSTEMS", 13, UiKit.MUTED, true))
	side.add_child(UiKit.label("Max energy: %d" % Game.max_energy(), 15))
	side.add_child(UiKit.label("Max hull: %d%s  ·  Blaster: %d dmg" % [Game.max_hull(), ("  +%d shield" % Game.max_shield()) if Game.max_shield() > 0 else "", Game.weapon_damage()], 15))
	side.add_child(UiKit.label("Ability: %s  ·  Drones destroyed: %d" % [Game.robot().ability.name, Game.kills], 15))
	side.add_child(UiKit.label("Credits: ⌬ %d  ·  Trade hubs visited: %d" % [Game.credits, Game.visited_towns.size()], 15, Color("ffd23f")))
	side.add_child(UiKit.label("Cargo hold: %d / %d units  (resources + components)" % [Game.cargo_used(), Game.cargo_cap()], 15, Color("d9c4a0")))
	side.add_child(UiKit.label("Gather speed: x%.2f" % Game.harvest_speed(""), 15))
	side.add_child(UiKit.label("Warp range: %.0f ly" % Game.warp_range(), 15))
	side.add_child(UiKit.label("Worlds visited: %d  ·  Stars: %d  ·  Species: %d" % [Game.visited_planets.size(), Game.visited_stars.size(), Game.scanned.size()], 14, UiKit.MUTED))
	side.add_child(HSeparator.new())
	side.add_child(UiKit.label("INSTALLED UPGRADES", 13, UiKit.MUTED, true))
	if Game.upgrades.is_empty():
		side.add_child(UiKit.label("None yet - fabricate some (C).", 14, UiKit.MUTED))
	for u in Game.upgrades:
		var row := HBoxContainer.new()
		row.add_child(UiKit.swatch(Db.item_color(u)))
		var l := UiKit.label(" %s" % Db.item_name(u), 15, Db.item_color(u))
		l.tooltip_text = Db.ITEMS[u].desc
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		side.add_child(row)
	if Game.count("energy_cell") > 0:
		side.add_child(UiKit.button("Use Energy Cell  [R]", Game.use_energy_cell))


func _item_card(id: String, qty: int) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(250, 0)
	pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.07, 0.1, 0.17, 0.9), Db.item_color(id) * Color(1, 1, 1, 0.45), 8, 1, 8))
	pc.tooltip_text = Db.ITEMS[id].desc
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	h.add_child(UiKit.swatch(Db.item_color(id), 22))
	var n := UiKit.label(Db.item_name(id), 15)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiKit.label("x%d" % qty, 17, Db.item_color(id).lightened(0.3), true))
	return pc


func _panel_crafting() -> void:
	var v := _frame("FABRICATOR  ·  Engineering %d" % Game.skill_level("engineering"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 0)
	h.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var eng := Game.skill_level("engineering")
	for cat in ["Components", "Consumables", "Upgrades"]:
		list.add_child(UiKit.label(cat.to_upper(), 13, UiKit.MUTED, true))
		for r in Db.RECIPES:
			if r.cat != cat:
				continue
			var installed: bool = Db.ITEMS[r.out].kind == "upgrade" and Game.has_upgrade(r.out)
			var b := UiKit.button("")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var mark := "✓ " if installed else ("● " if Game.can_craft(r) else "")
			b.text = "%s%s   [%d]" % [mark, Db.item_name(r.out), r.req]
			b.add_theme_color_override("font_color", Color("9aa0a6") if installed else Db.difficulty_color(r.req, eng))
			b.add_theme_color_override("font_hover_color", Color.WHITE)
			var rid: String = r.id
			b.pressed.connect(func():
				_craft_selected = rid
				_refresh_open_panel()
			)
			if r.id == _craft_selected:
				b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
			list.add_child(b)
	# details
	var r := Db.recipe(_craft_selected)
	var d := VBoxContainer.new()
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.add_theme_constant_override("separation", 10)
	h.add_child(d)
	var out_row := HBoxContainer.new()
	out_row.add_child(UiKit.swatch(Db.item_color(r.out), 30))
	out_row.add_child(UiKit.label("  " + Db.item_name(r.out) + ("  x%d" % r.qty if r.qty > 1 else ""), 24, Db.item_color(r.out).lightened(0.2), true))
	d.add_child(out_row)
	var desc := UiKit.label(Db.ITEMS[r.out].desc, 16, UiKit.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.add_child(desc)
	d.add_child(UiKit.label("Requires Engineering %d" % r.req, 15, Color("ff6b6b") if eng < r.req else Color("6ee06a")))
	d.add_child(HSeparator.new())
	d.add_child(UiKit.label("MATERIALS", 13, UiKit.MUTED, true))
	for k in r.in:
		var row := HBoxContainer.new()
		row.add_child(UiKit.swatch(Db.item_color(k), 18))
		var have := Game.count(k)
		var nl := UiKit.label("  " + Db.item_name(k), 17)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		row.add_child(UiKit.label("%d / %d" % [have, r.in[k]], 17, Color("6ee06a") if have >= r.in[k] else Color("ff6b6b")))
		d.add_child(row)
		var src := _source_hint(k)
		if src != "":
			d.add_child(UiKit.label("      " + src, 13, UiKit.MUTED))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_child(sp)
	var btn := UiKit.button("FABRICATE", func():
		if Game.craft(_craft_selected):
			_refresh_open_panel()
	)
	btn.custom_minimum_size = Vector2(0, 52)
	btn.add_theme_font_override("font", UiKit.title_font())
	btn.add_theme_font_size_override("font_size", 20)
	var installed: bool = Db.ITEMS[r.out].kind == "upgrade" and Game.has_upgrade(r.out)
	btn.disabled = not Game.can_craft(r) or installed
	if installed:
		btn.text = "INSTALLED"
	d.add_child(btn)
	d.add_child(UiKit.label("XP: %d Engineering" % r.xp, 13, UiKit.MUTED))


func _source_hint(item: String) -> String:
	for n in Db.NODES:
		var nd: Dictionary = Db.NODES[n]
		if nd.item == item:
			var worlds := []
			for b in Db.BIOMES:
				if Db.BIOMES[b].nodes.has(n):
					worlds.append(Db.BIOMES[b].name)
			return "%s (%s %d) on %s worlds" % [nd.name, Db.SKILLS[nd.skill].name, nd.req, ", ".join(worlds)]
	for r in Db.RECIPES:
		if r.out == item:
			return "Fabricated (Engineering %d)" % r.req
	return ""


func _panel_skills() -> void:
	var v := _frame("PROFESSIONS")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	for s in Db.SKILLS:
		var sd: Dictionary = Db.SKILLS[s]
		var lvl := Game.skill_level(s)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.09, 0.15, 0.9), sd.color * Color(1, 1, 1, 0.4), 10, 1, 14))
		list.add_child(pc)
		var cv := VBoxContainer.new()
		pc.add_child(cv)
		var top := HBoxContainer.new()
		cv.add_child(top)
		top.add_child(UiKit.label(sd.name.to_upper(), 18, sd.color, true))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(sp)
		top.add_child(UiKit.label("%d / %d" % [lvl, Db.SKILL_MAX], 18, Color.WHITE, true))
		var b := UiKit.bar(sd.color, 10)
		b.max_value = Db.skill_xp_needed(lvl)
		b.value = Game.skills[s].xp
		cv.add_child(b)
		cv.add_child(UiKit.label(sd.desc, 14, UiKit.MUTED))
		var unlocks := []
		for n in Db.NODES:
			if Db.NODES[n].skill == s:
				unlocks.append([Db.NODES[n].req, Db.NODES[n].name])
		if s == "engineering":
			for r in Db.RECIPES:
				unlocks.append([r.req, Db.item_name(r.out)])
		unlocks.sort_custom(func(a, c): return a[0] < c[0])
		var txt := ""
		for u in unlocks:
			var c := Db.difficulty_color(u[0], lvl)
			txt += "[color=#%s]%s (%d)[/color]   " % [UiKit.hex(c), u[1], u[0]]
		if txt != "":
			cv.add_child(UiKit.rich(txt, 13))


func _panel_quests() -> void:
	var frame := _frame("QUEST LOG & CODEX", Vector2(980, 680))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(tabs)
	var v := VBoxContainer.new()
	v.name = "Quests & Codex"
	v.add_theme_constant_override("separation", 8)
	tabs.add_child(v)
	var q := Game.current_quest()
	if q.is_empty():
		v.add_child(UiKit.label("Every task is complete. The Circuit is relit.", 18, Color("6ee06a")))
	else:
		v.add_child(UiKit.label(q.title, 24, Color("ffd23f"), true))
		v.add_child(UiKit.label("From: %s" % q.giver, 14, UiKit.MUTED))
		var t := UiKit.label('"%s"' % q.text, 17)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.add_child(t)
		if Game.quest_accepted:
			v.add_child(UiKit.label("Objective:  " + objective_text(q), 18, Color.WHITE))
		else:
			v.add_child(UiKit.label("Not yet accepted - speak with the Archivist.", 16, Color("ffd23f")))
		var rw := "Reward: %d XP" % q.xp
		for k in q.reward:
			rw += "  ·  %dx %s" % [q.reward[k], Db.item_name(k)]
		v.add_child(UiKit.label(rw, 15, Color("6ee06a")))
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("COMPLETED", 13, UiKit.MUTED, true))
	var done := ""
	for i in Game.quest_index:
		done += "✓ " + Db.QUESTS[i].title + "\n"
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UiKit.label(done if done != "" else "Nothing yet.", 15, UiKit.MUTED))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UiKit.label("CODEX  %d / %d" % [Game.codex.size(), Db.LORE.size()], 13, Color("6ff3ff"), true))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 160)
	right.add_child(sc)
	var cl := VBoxContainer.new()
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(cl)
	if Game.codex.is_empty():
		cl.add_child(UiKit.label("Find monoliths and ruins to recover lost records.", 14, UiKit.MUTED))
	for i in Game.codex:
		var b := UiKit.button(Db.LORE[i][0], func(): show_lore(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cl.add_child(b)
	v.add_child(UiKit.label("Worlds surveyed: %d  ·  Sites discovered: %d" % [Game.surveyed.size(), Game.discovered_pois.size()], 13, UiKit.MUTED))
	tabs.add_child(_species_tab())
	tabs.add_child(_milestone_tab())
	tabs.add_child(_gems_tab())
	for ti in tabs.get_tab_count():
		var tc := tabs.get_tab_control(ti)
		if tc.has_meta("title"):
			tabs.set_tab_title(ti, tc.get_meta("title"))
	tabs.current_tab = clampi(_codex_tab, 0, 3)
	tabs.tab_changed.connect(func(t): _codex_tab = t)


var _codex_tab := 0


func _species_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Species"
	v.set_meta("title", "Species Log  %d" % Game.scanned.size())
	v.add_theme_constant_override("separation", 6)
	# group logged species by world
	var by_world := {}
	for k in Game.scanned:
		var parts: PackedStringArray = (k as String).split(":")
		var wk := "%s:%s" % [parts[0], parts[1]] if parts.size() >= 2 else "?"
		if not by_world.has(wk):
			by_world[wk] = []
		by_world[wk].append(k)
	for wk in Game.world_species:
		if not by_world.has(wk):
			by_world[wk] = []
	if by_world.is_empty():
		v.add_child(UiKit.label("No species logged yet. Scan creatures and plants with %s." % Game.key("scan"), 15, UiKit.MUTED))
		return v
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	var keys := by_world.keys()
	keys.sort()
	for wk in keys:
		var info: Dictionary = Game.world_species.get(wk, {})
		var wname: String = info.get("name", "")
		if wname == "":
			var ids: PackedStringArray = (wk as String).split(":")
			if ids.size() == 2 and ids[0].is_valid_int() and ids[1].is_valid_int():
				wname = Galaxy.planet(int(ids[0]), int(ids[1])).name
			elif ids[0] == "derelict":
				wname = "Derelict wreck, " + Galaxy.star(int(ids[1])).name
			else:
				wname = wk
		var total: int = int(info.get("total", 0))
		var got: int = by_world[wk].size()
		var complete := total > 0 and got >= total
		var head := HBoxContainer.new()
		list.add_child(head)
		var biome_name: String = Db.BIOMES[info.biome].name if info.has("biome") and Db.BIOMES.has(info.biome) else ""
		head.add_child(UiKit.label(wname, 18, Color("ffd23f") if complete else Color("6ff3ff"), true))
		if biome_name != "":
			head.add_child(UiKit.label("   " + biome_name, 13, UiKit.MUTED))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		head.add_child(UiKit.label(("✓ complete  " if complete else "") + ("%d / %d" % [got, total] if total > 0 else "%d logged" % got), 14, Color("6ee06a") if complete else UiKit.TEXT))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 6)
		list.add_child(flow)
		for k in by_world[wk]:
			var nm := _species_display(k)
			var is_flora: bool = ":flora:" in k
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.16, 0.2, 0.9), Color("6ee06a") if is_flora else Color("5ff7ff"), 6, 1, 6))
			chip.add_child(UiKit.label(("❀ " if is_flora else "◆ ") + nm, 13))
			flow.add_child(chip)
		for i in maxi(0, total - got):
			var chip2 := PanelContainer.new()
			chip2.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.08, 0.1, 0.8), Color(1, 1, 1, 0.12), 6, 1, 6))
			chip2.add_child(UiKit.label("? unknown", 13, UiKit.MUTED))
			flow.add_child(chip2)
	return v


func _species_display(k: String) -> String:
	var nm: String = Game.species_names.get(k, "")
	if nm == "":
		# older saves didn't keep names: rebuild them from the key
		var parts := k.split(":")
		if parts.size() == 4 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var pl: Dictionary = Galaxy.planet(int(parts[0]), int(parts[1]))
			nm = Galaxy.species_name(pl.seed, ("fauna" + parts[3]) if parts[2] == "fauna" else parts[3])
		else:
			nm = parts[parts.size() - 1].capitalize()
	var cut := nm.find(" (")
	return nm.substr(0, cut) if cut > 0 else nm


func _gems_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Gems"
	v.set_meta("title", "World Gems  %d/10" % Game.gem_types())
	v.add_theme_constant_override("separation", 8)
	var intro := UiKit.label("Each kind of world hides one kind of gem, 1 to 3 per world. Hold orbit near a world (%s) and drop a Deep Probe to extract them. Set all ten into the Crown of Worlds at the Fabricator." % Game.key("orbit"), 14, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	var where := {"gem_verdant": "Verdant worlds", "gem_dune": "Arid worlds", "gem_frost": "Glacial worlds", "gem_ember": "Volcanic worlds",
		"gem_prism": "Crystalline worlds", "gem_bloom": "Fungal worlds", "gem_giant": "Gas giants", "gem_abyss": "The ocean edge world",
		"gem_tempest": "The storm edge world", "gem_forge": "The machine edge world"}
	for g in Game.GEM_KINDS:
		var n := Game.count(g)
		var col := Db.item_color(g)
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(440, 0)
		row.add_theme_stylebox_override("panel", UiKit.box(Color(col.darkened(0.8), 0.9) if n > 0 else Color(0.07, 0.09, 0.12, 0.85), col if n > 0 else Color(1, 1, 1, 0.1), 8, 1, 8))
		grid.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		h.add_child(UiKit.label("◆", 26, col if n > 0 else Color(1, 1, 1, 0.15)))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(UiKit.label(Db.item_name(g) if n > 0 else "Unknown gem", 16, Color.WHITE if n > 0 else UiKit.MUTED, true))
		tv.add_child(UiKit.label(where[g], 12, UiKit.MUTED))
		h.add_child(UiKit.label("x%d" % n if n > 0 else "", 16, col))
	if Game.has_upgrade("crown_of_worlds"):
		v.add_child(UiKit.label("✦ You wear the Crown of Worlds.", 16, Color("ffe9a8"), true))
	return v


func _milestone_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "Milestones"
	v.set_meta("title", "Milestones  %d/%d" % [Game.milestones.size(), Db.MILESTONES.size()])
	v.add_theme_constant_override("separation", 6)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for m in Db.MILESTONES:
		var done: bool = Game.milestones.has(m.id)
		var cur := mini(Game.metric(m.metric), int(m.n))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.box(Color(0.16, 0.14, 0.06, 0.9) if done else Color(0.07, 0.09, 0.12, 0.85), Color("ffd23f") if done else Color(1, 1, 1, 0.1), 8, 1, 10))
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		h.add_child(UiKit.label("★" if done else "☆", 26, Color("ffd23f") if done else UiKit.MUTED))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(UiKit.label(m.name, 17, Color.WHITE if done else UiKit.TEXT, true))
		tv.add_child(UiKit.label("%s  ·  Reward: %s" % [m.desc, Game.bonus_text(m.bonus)], 13, Color("6ee06a") if done else UiKit.MUTED))
		var pv := VBoxContainer.new()
		pv.custom_minimum_size = Vector2(160, 0)
		h.add_child(pv)
		pv.add_child(UiKit.label("%d / %d" % [cur, int(m.n)], 14, Color("ffd23f") if done else UiKit.TEXT))
		var bar := ProgressBar.new()
		bar.max_value = float(m.n)
		bar.value = float(cur)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(160, 8)
		pv.add_child(bar)
	return v


func _panel_help() -> void:
	var v := _frame("FIELD MANUAL", Vector2(900, 640))
	var t := """[b][color=#5ff7ff]On a planet[/color][/b]
WASD move  ·  Mouse look (click to capture)  ·  Wheel zoom
Space jump, hold in the air for [b]jetpack[/b] (uses energy)  ·  Shift sprint  ·  Ctrl descend
[b]E[/b] hold to gather / talk / use  ·  [b]Q[/b] scanner pulse (reveals nodes, logs species)
[b]R[/b] use an Energy Cell  ·  [b]T[/b] break orbit and fly to space

[b][color=#ff5d5d]Combat[/color][/b]
[b]Left mouse[/b] fire blaster at the crosshair (1 energy per shot)  ·  [b]F[/b] class ability  ·  [b]G[/b] Repair Kit
Hull repairs itself once you are out of combat. Rogue drones travel in camps: pull one and its friends come too.
Name colours show danger: [color=#ff3b3b]red[/color] and [color=#ff8c3b]orange[/color] out-level you, [color=#ffe066]yellow[/color] even, [color=#6ee06a]green[/color] easy. [color=#ffd23f]Gold[/color] names are Elites.
Brutes telegraph their slam with a red ring. Get out of it!

[b][color=#5ff7ff]In space[/color][/b]
Mouse steer  ·  W/S thrust  ·  A/D strafe  ·  Space/Ctrl rise/sink  ·  Shift boost
Fly close to a planet and press [b]E[/b] to land ([b]F[/b] to dock at its trade hub, [b]O[/b] to hold orbit and probe for gems)  ·  [b]M[/b] galaxy map to warp (costs a Warp Cell)
[b]Left mouse[/b] pulse cannons, which switch to the mining laser when the crosshair is on rock  ·  [b]Right mouse[/b] homing missiles
Cut asteroids in the belt and fly through the shards  ·  [b]Q[/b] scan the belt  ·  Red arrows at the screen edge point to pirates

[b][color=#5ff7ff]Panels[/color][/b]
I / Tab cargo  ·  C fabricator  ·  K professions  ·  J quest log  ·  X swap weapon  ·  Esc pause
Visit an [b]Outfitter[/b] (towns, or the Outfitting tab at stations) to paint your robot, fit new parts and change loadouts.

[b][color=#ffd23f]Tips[/color][/b]
Energy recharges in sunlight. Night falls - plan your jetpack use.
Node colours follow skill difficulty: [color=#ff4d4d]red[/color] too hard, [color=#ff9f43]orange[/color] best XP, [color=#ffe066]yellow[/color], [color=#6ee06a]green[/color], [color=#9aa0a6]grey[/color] trivial.
Each world type has its own resources. Cold and dry worlds carry Cobalt, crystal worlds Lumen, volcanic worlds Void Shards.
Harvested nodes regrow after ten minutes."""
	v.add_child(UiKit.rich(t, 17))


func _panel_pause() -> void:
	var v := _frame("PAUSED", Vector2(460, 520))
	var played := int(Game.play_time)
	v.add_child(UiKit.label("Play time %d:%02d:%02d" % [played / 3600, (played / 60) % 60, played % 60], 14, UiKit.MUTED))
	for pair in [["Resume", close_panel], ["Save Game", func():
		Game.save_game()
		toast("Game saved.", Color("6ee06a"))
	], ["Settings", func(): toggle_panel("settings")], ["Field Manual", func(): toggle_panel("help")], ["Save & Main Menu", Game.go_to_menu], ["Save & Quit", func():
		Game.save_game()
		get_tree().quit()
	]]:
		var b := UiKit.button(pair[0], pair[1])
		b.custom_minimum_size = Vector2(0, 46)
		v.add_child(b)


func open_dialog() -> void:
	toggle_panel("dialog")


func _panel_dialog() -> void:
	var v := _frame("THE ARCHIVIST", Vector2(820, 460))
	var q := Game.current_quest()
	var text := ""
	var accept := false
	if q.is_empty():
		text = "You have done it, Unit. Every star on my charts sings again. Go - wander. There is always another world over the horizon."
	elif not Game.quest_accepted:
		text = q.text
		accept = true
	else:
		text = "Still working on \"%s\"? %s\n\nMy comms reach you anywhere, so there is no need to return here to report." % [q.title, objective_text(q)]
	v.add_child(UiKit.label(q.get("title", "Farewell"), 22, Color("ffd23f"), true))
	var t := UiKit.label(text, 18)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(t)
	if accept:
		var rw := "Reward: %d XP" % q.xp
		for k in q.reward:
			rw += "  ·  %dx %s" % [q.reward[k], Db.item_name(k)]
		v.add_child(UiKit.label(rw, 15, Color("6ee06a")))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	if accept:
		row.add_child(UiKit.button("Accept Quest", func():
			Game.accept_quest()
			close_panel()
		))
	row.add_child(UiKit.button("Farewell", close_panel))


func _panel_map() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.035, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_host.add_child(dim)
	_panel = dim
	galaxy_map = preload("res://scripts/ui/galaxy_map.gd").new()
	galaxy_map.hud = self
	galaxy_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(galaxy_map)


# --------------------------------------------------------------------------
# combat widgets
# --------------------------------------------------------------------------

func _build_combat() -> void:
	damage_flash = ColorRect.new()
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.color = Color(1, 0.05, 0.05, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_flash)
	root.move_child(damage_flash, 0)

	crosshair = UiKit.label("+", 30, Color(1, 1, 1, 0.8))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-9, -24)
	crosshair.add_theme_constant_override("outline_size", 6)
	crosshair.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	crosshair.visible = mode in ["planet", "space"]
	root.add_child(crosshair)

	target_box = PanelContainer.new()
	target_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	target_box.position = Vector2(-180, 64)
	target_box.custom_minimum_size = Vector2(360, 0)
	target_box.add_theme_stylebox_override("panel", UiKit.box(Color(0.08, 0.03, 0.04, 0.88), Color(1, 0.3, 0.3, 0.5), 10, 1, 10))
	root.add_child(target_box)
	var tv := VBoxContainer.new()
	target_box.add_child(tv)
	var th := HBoxContainer.new()
	tv.add_child(th)
	target_name = UiKit.label("", 16, Color.WHITE, true)
	target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(target_name)
	target_hp = UiKit.label("", 13, UiKit.MUTED)
	th.add_child(target_hp)
	target_bar = UiKit.bar(Color("e0453a"), 12)
	tv.add_child(target_bar)
	target_box.visible = false

	if mode == "planet":
		var ab: Dictionary = Game.robot().ability
		var pc := PanelContainer.new()
		pc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		pc.position = Vector2(-150, -86)
		pc.custom_minimum_size = Vector2(300, 0)
		pc.add_theme_stylebox_override("panel", UiKit.box(UiKit.BG_SOFT, Game.robot().color * Color(1, 1, 1, 0.6), 8, 1, 8))
		root.add_child(pc)
		var av := VBoxContainer.new()
		pc.add_child(av)
		ability_label = UiKit.label("", 14, Game.robot().color.lightened(0.35))
		_update_ability_label()
		Game.appearance_changed.connect(_update_ability_label)
		ability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av.add_child(ability_label)
		ability_bar = UiKit.bar(Game.robot().color, 6)
		ability_bar.max_value = 1.0
		ability_bar.value = 1.0
		av.add_child(ability_bar)

	death_box = VBoxContainer.new()
	death_box.set_anchors_preset(Control.PRESET_CENTER)
	death_box.position = Vector2(-400, -60)
	death_box.custom_minimum_size = Vector2(800, 0)
	death_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_box.visible = false
	root.add_child(death_box)
	var d1 := UiKit.label("UNIT DESTROYED", 60, Color("ff4d4d"), true)
	d1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d1.add_theme_constant_override("outline_size", 14)
	d1.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	death_box.add_child(d1)
	var d2 := UiKit.label("Rebooting at the landing site...", 20)
	d2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_box.add_child(d2)


## Generic target frame (used by space mining).
func set_target_info(title: String, color: Color, value: float, max_value: float, sub: String) -> void:
	if title == "":
		target_box.visible = false
		return
	target_box.visible = true
	target_name.text = title
	target_name.add_theme_color_override("font_color", color)
	target_bar.max_value = max_value
	target_bar.value = maxf(0.0, value)
	target_hp.text = sub


func set_target(e: Enemy) -> void:
	if e == null or not is_instance_valid(e) or not e.is_alive():
		target_box.visible = false
		return
	target_box.visible = true
	target_name.text = "%s   %d%s" % [e.def.name, e.level, "  ELITE" if e.elite else ""]
	target_name.add_theme_color_override("font_color", Color("ffd23f") if e.elite else Db.con_color(e.level, Game.level))
	target_bar.max_value = e.max_hp
	target_bar.value = maxf(0.0, e.hp)
	target_hp.text = "%d / %d" % [int(maxf(0.0, e.hp)), int(e.max_hp)]


func set_crosshair_hot(hot: bool) -> void:
	crosshair.add_theme_color_override("font_color", Color("ff5d5d") if hot else Color(1, 1, 1, 0.8))


func set_ability_cooldown(cd: float, max_cd: float) -> void:
	if ability_bar == null:
		return
	ability_bar.value = 1.0 - cd / max_cd if max_cd > 0.0 else 1.0
	ability_bar.modulate.a = 1.0 if cd <= 0.0 else 0.5


func _on_damaged(amount: float) -> void:
	var a := clampf(amount / Game.max_hull() * 2.5, 0.12, 0.45)
	damage_flash.color.a = a
	var t := create_tween()
	t.tween_property(damage_flash, "color:a", 0.0, 0.45)


func show_death() -> void:
	death_box.visible = true
	damage_flash.color.a = 0.5


func hide_death() -> void:
	death_box.visible = false
	damage_flash.color.a = 0.0


func _big_sound(title: String, sub: String) -> void:
	if title.begins_with("LEVEL"):
		Sound.play("level_up", -2.0, 0.0, "UI")
	elif title == "QUEST COMPLETE":
		Sound.play("quest_complete", -2.0, 0.0, "UI")
	elif title == "QUEST ACCEPTED":
		Sound.play("quest_accept", -4.0, 0.0, "UI")
	elif sub == "Profession skill increased":
		Sound.play("skill_up", -5.0, 0.0, "UI")
	elif title in ["NEW WORLD", "UPGRADE INSTALLED", "REBOOTED"]:
		Sound.play("notify", -4.0, 0.0, "UI")


# --------------------------------------------------------------------------
# audio settings (pause menu)
# --------------------------------------------------------------------------

func _volume_row(parent: Control, label: String, bus: String) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := UiKit.label(label, 15)
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Sound.volumes[bus]
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v):
		Sound.set_volume(bus, v)
		Sound.save_settings()
	)
	sl.drag_ended.connect(func(_c): Sound.ui())
	h.add_child(sl)


# --------------------------------------------------------------------------
# exploration: compass, survey, lore
# --------------------------------------------------------------------------

func _build_compass() -> void:
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-320, 14)
	compass.custom_minimum_size = Vector2(640, 40)
	compass.size = Vector2(640, 40)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)


## Called by the player each frame with its camera frame.
func set_compass(pos: Vector3, up: Vector3, fwd: Vector3, markers: Array) -> void:
	_compass_data = {"pos": pos, "up": up, "fwd": fwd, "markers": markers}
	if compass:
		compass.queue_redraw()


func _bearing(to: Vector3, up: Vector3, fwd: Vector3) -> float:
	var t := to - up * to.dot(up)
	if t.length() < 0.001:
		return 0.0
	var right := fwd.cross(up)
	return atan2(t.dot(right), t.dot(fwd))


func _draw_compass() -> void:
	if _compass_data.is_empty():
		return
	var w := compass.size.x
	var cx := w * 0.5
	var bg := UiKit.box(Color(0.03, 0.05, 0.1, 0.65), Color(0.35, 0.85, 1.0, 0.3), 8, 1, 0)
	compass.draw_style_box(bg, Rect2(Vector2.ZERO, compass.size))
	var up: Vector3 = _compass_data.up
	var fwd: Vector3 = _compass_data.fwd
	var pos: Vector3 = _compass_data.pos
	var font := UiKit.body_font()
	var span := PI * 0.6 # half-width of the visible arc
	# cardinal directions relative to the planet's pole
	var north := Vector3.UP - up * Vector3.UP.dot(up)
	if north.length() < 0.01:
		north = Vector3.FORWARD
	north = north.normalized()
	var east := north.cross(up).normalized() # facing north, east is to the right
	for c in [["N", north], ["E", east], ["S", -north], ["W", -east]]:
		var b := _bearing(c[1], up, fwd)
		if absf(b) < span:
			var x := cx + b / span * cx
			compass.draw_string(font, Vector2(x - 6, 26), c[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85) if c[0] == "N" else Color(1, 1, 1, 0.5))
	for k in range(-12, 13):
		var ang := float(k) / 12.0 * span
		var x2 := cx + ang / span * cx
		compass.draw_line(Vector2(x2, 32), Vector2(x2, 36), Color(1, 1, 1, 0.2), 1.0)
	var label_best := -1
	var label_b := 0.12
	for i in _compass_data.markers.size():
		var mm: Dictionary = _compass_data.markers[i]
		if mm.get("quest", false):
			continue
		var bb := absf(_bearing(mm.pos - pos, up, fwd))
		if bb < label_b:
			label_b = bb
			label_best = i
	var mi := -1
	for m in _compass_data.markers:
		mi += 1
		var to: Vector3 = m.pos - pos
		var dist := to.length()
		var b2 := _bearing(to, up, fwd)
		var x3 := cx + clampf(b2 / span, -1.0, 1.0) * cx
		var col: Color = m.color
		if m.done:
			col = col.darkened(0.5)
		var edge := absf(b2) >= span
		if m.get("quest", false):
			var qp := Vector2(x3, 12)
			compass.draw_colored_polygon(PackedVector2Array([qp + Vector2(0, -8), qp + Vector2(3, -2), qp + Vector2(8, -2), qp + Vector2(4, 2), qp + Vector2(6, 8), qp + Vector2(0, 4), qp + Vector2(-6, 8), qp + Vector2(-4, 2), qp + Vector2(-8, -2), qp + Vector2(-3, -2)]), col)
			# the quest label gets its own row under the compass, pinned to the edge when off-screen
			var qt := "%s  %dm" % [m.label, int(dist)]
			if edge:
				qt = ("◀ " + qt) if b2 < 0.0 else (qt + " ▶")
			var lx := clampf(x3 - 110.0, 0.0, cx * 2.0 - 220.0)
			compass.draw_string(font, Vector2(lx, 70), qt, HORIZONTAL_ALIGNMENT_CENTER, 220, 14, col)
			continue
		compass.draw_circle(Vector2(x3, 12), 5.0 if not edge else 3.5, col)
		if mi == label_best:
			compass.draw_string(font, Vector2(x3 - 60, 52), "%s  %dm" % [m.label, int(dist)], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, col.lightened(0.3))
	compass.draw_line(Vector2(cx, 2), Vector2(cx, 8), Color(1, 1, 1, 0.8), 2.0)


func refresh_survey(st: Dictionary) -> void:
	if survey_label == null:
		return
	survey_label.visible = true
	if st.done:
		survey_label.text = "✓ World surveyed"
	else:
		survey_label.text = "Survey  ·  species %d/%d  ·  sites %d/%d" % [st.species, st.species_total, st.sites, st.sites_total]


var _lore_index := -1
func show_lore(i: int) -> void:
	_lore_index = i
	if current_panel == "lore":
		close_panel(false)
	toggle_panel("lore")


func _panel_lore() -> void:
	var v := _frame("CODEX ENTRY", Vector2(760, 380))
	if _lore_index < 0:
		return
	var e: Array = Db.LORE[_lore_index]
	v.add_child(UiKit.label(e[0], 24, Color("6ff3ff"), true))
	var t := UiKit.label(e[1], 19)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(t)
	v.add_child(UiKit.label("Record %d of %d recovered  ·  J to review the Codex" % [Game.codex.size(), Db.LORE.size()], 13, UiKit.MUTED))



# --------------------------------------------------------------------------
# towns: trade, training, bounty board
# --------------------------------------------------------------------------

func _add_bounty_lines() -> void:
	if Game.bounties.is_empty():
		return
	quest_box.add_child(UiKit.label("CONTRACTS", 12, Color("ffb86b"), true))
	for b in Game.bounties:
		var ready := Game.bounty_ready(b)
		var prog := "%d/%d" % [Game.count(b.item) if b.type == "deliver" else int(b.progress), int(b.n)]
		var l := UiKit.label(("✓ " if ready else "• ") + "%s  %s" % [b.title, prog] + ("  -  turn in at a board" if ready else ""), 13, Color("6ee06a") if ready else UiKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		quest_box.add_child(l)


func open_town_panel(kind: String, planet: Dictionary) -> void:
	_town_planet = planet
	toggle_panel(kind)


func _rebuild_town_panel() -> void:
	var keep := current_panel
	if _panel:
		_panel.queue_free()
		_panel = null
	current_panel = keep
	_build_panel()


func _panel_trade() -> void:
	var town: Dictionary = _town_planet.town
	var v := _frame("%s  ·  GENERAL GOODS" % town.name.to_upper(), Vector2(1080, 680))
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UiKit.label("Credits  ⌬ %d" % Game.credits, 20, Color("ffd23f"), true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UiKit.label("Pays extra for %s  ·  local goods sell cheap, imports sell high" % Db.item_name(town.specialty), 14, UiKit.MUTED))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in [["buy", "Buy"], ["sell", "Sell"]]:
		var b := UiKit.button(t[1], func():
			_trade_tab = t[0]
			_rebuild_town_panel()
		)
		b.custom_minimum_size = Vector2(140, 40)
		if _trade_tab == t[0]:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if _trade_tab == "buy":
		for line in Game.trader_stock(_town_planet):
			var it: String = line.item
			var row := _trade_row(it, "%d in stock" % line.qty, line.price, Color("ff9f43"))
			for q in [1, 5]:
				var btn := UiKit.button("Buy %d" % q, func(): Game.buy(it, q, _town_planet))
				btn.disabled = line.qty < q or Game.credits < line.price * q
				row.add_child(btn)
			list.add_child(row)
	else:
		var any := false
		for it in Game.inventory.keys():
			if not Db.VALUES.has(it):
				continue
			any = true
			var price := Game.sell_price(it, _town_planet)
			var have := Game.count(it)
			var hint := "you have %d" % have
			if it == town.specialty:
				hint += "  ·  in demand here!"
			var row := _trade_row(it, hint, price, Color("6ee06a"))
			var b1 := UiKit.button("Sell 1", func(): Game.sell(it, 1, _town_planet))
			row.add_child(b1)
			var ball := UiKit.button("Sell all (%d)" % (price * have), func(): Game.sell(it, have, _town_planet))
			row.add_child(ball)
			list.add_child(row)
		if not any:
			list.add_child(UiKit.label("Nothing to sell. Gather resources or craft components.", 16, UiKit.MUTED))


func _trade_row(item: String, hint: String, price: int, price_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UiKit.swatch(Db.item_color(item), 22))
	var n := UiKit.label(Db.item_name(item), 17)
	n.custom_minimum_size = Vector2(220, 0)
	row.add_child(n)
	var h := UiKit.label(hint, 14, UiKit.MUTED)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(h)
	var p := UiKit.label("⌬ %d" % price, 17, price_color, true)
	p.custom_minimum_size = Vector2(90, 0)
	row.add_child(p)
	return row


func _panel_trainer() -> void:
	var town: Dictionary = _town_planet.town
	var max_tier: int = town.max_tier
	var v := _frame("%s  ·  PROFESSION TRAINER" % town.name.to_upper(), Vector2(980, 640))
	v.add_child(UiKit.label("Credits  ⌬ %d   ·   This trainer teaches up to %s" % [Game.credits, Db.SKILL_TIERS[max_tier].name], 17, Color("ffd23f")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for sk in Db.SKILLS:
		var sd: Dictionary = Db.SKILLS[sk]
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.09, 0.15, 0.9), sd.color * Color(1, 1, 1, 0.4), 10, 1, 12))
		list.add_child(pc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		pc.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var tier: Dictionary = Db.SKILL_TIERS[Game.skill_tier(sk)]
		info.add_child(UiKit.label("%s  ·  %s" % [sd.name.to_upper(), tier.name], 17, sd.color, true))
		info.add_child(UiKit.label("Skill %d  ·  cap %d" % [Game.skill_level(sk), tier.cap], 14, UiKit.MUTED))
		var c := Game.can_train(sk, max_tier)
		if c.has("tier"):
			var t: Dictionary = c.tier
			var btn := UiKit.button("Train %s  (⌬ %d, needs %d)" % [t.name, t.cost, t.req], func(): Game.train(sk, max_tier))
			btn.disabled = not c.ok
			btn.custom_minimum_size = Vector2(330, 44)
			btn.tooltip_text = "" if c.ok else c.why
			row.add_child(btn)
			if not c.ok:
				info.add_child(UiKit.label(c.why, 13, Color("ffb86b")))
		else:
			row.add_child(UiKit.label("Mastered", 16, Color("6ee06a")))


func _panel_board() -> void:
	var town: Dictionary = _town_planet.town
	var v := _frame("%s  ·  BOUNTY BOARD" % town.name.to_upper(), Vector2(980, 660))
	v.add_child(UiKit.label("New contracts are posted every day. You can hold 3 at a time; turn them in at any board.", 15, UiKit.MUTED))
	# turn-ins first
	for b in Game.bounties.duplicate():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var ready := Game.bounty_ready(b)
		var prog := "%d/%d" % [Game.count(b.item) if b.type == "deliver" else int(b.progress), int(b.n)]
		var l := UiKit.label("%s  (%s)  ·  %s  ·  from %s" % [b.title, prog, b.text, b.town], 15, Color("6ee06a") if ready else UiKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(l)
		var btn := UiKit.button("Turn in  (⌬ %d)" % b.credits, func():
			Game.turn_in_bounty(b)
			_rebuild_town_panel()
		)
		btn.disabled = not ready
		row.add_child(btn)
		var ab := UiKit.button("Abandon", func():
			Game.bounties.erase(b)
			Game.quest_changed.emit()
			_rebuild_town_panel()
		)
		row.add_child(ab)
		v.add_child(row)
	if not Game.bounties.is_empty():
		v.add_child(HSeparator.new())
	v.add_child(UiKit.label("TODAY'S CONTRACTS", 13, Color("ffb86b"), true))
	for offer in Game.board_offers(_town_planet):
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.08, 0.05, 0.9), Color(1, 0.72, 0.4, 0.4), 10, 1, 12))
		v.add_child(pc)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 14)
		pc.add_child(row2)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(info)
		info.add_child(UiKit.label(offer.title, 18, Color("ffd98a"), true))
		info.add_child(UiKit.label(offer.text, 15))
		info.add_child(UiKit.label("Reward: ⌬ %d  ·  %d XP" % [offer.credits, offer.xp], 14, Color("6ee06a")))
		var taken := Game.has_bounty(offer.id)
		var btn2 := UiKit.button("Accepted" if taken else "Accept", func():
			Game.accept_bounty(offer)
			_rebuild_town_panel()
		)
		btn2.disabled = taken or Game.bounties.size() >= 3
		btn2.custom_minimum_size = Vector2(140, 44)
		row2.add_child(btn2)



# --------------------------------------------------------------------------
# space: threat markers
# --------------------------------------------------------------------------

func set_threats(list: Array) -> void:
	_threats = list
	if threat_layer:
		threat_layer.queue_redraw()


func _draw_threats() -> void:
	var vp := threat_layer.size
	var c := vp * 0.5
	for t in _threats:
		if t.get("waypoint", false):
			_draw_waypoint(t, vp, c)
			continue
		var col := Color("ffd23f") if t.elite else (Color("ff4d4d") if t.attacking else Color(1, 0.6, 0.5, 0.7))
		if t.on:
			# bracket around the ship, tighter when far
			var r := clampf(900.0 / maxf(t.dist, 1.0), 10.0, 34.0)
			var p: Vector2 = t.pos
			for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var corner: Vector2 = p + q * r
				threat_layer.draw_line(corner, corner - Vector2(q.x * r * 0.45, 0), col, 2.0)
				threat_layer.draw_line(corner, corner - Vector2(0, q.y * r * 0.45), col, 2.0)
		else:
			# arrow on an ellipse at the screen edge
			var d: Vector2 = (t.pos - c)
			if d.length() < 1.0:
				d = Vector2(0, 1)
			var ang := d.angle()
			var edge := c + Vector2(cos(ang) * (vp.x * 0.44), sin(ang) * (vp.y * 0.40))
			var fwd := Vector2(cos(ang), sin(ang))
			var side := Vector2(-fwd.y, fwd.x)
			var sz := 14.0 if not t.elite else 20.0
			threat_layer.draw_colored_polygon(PackedVector2Array([edge + fwd * sz, edge - fwd * sz * 0.6 + side * sz * 0.7, edge - fwd * sz * 0.6 - side * sz * 0.7]), col)



# --------------------------------------------------------------------------
# orbital station
# --------------------------------------------------------------------------

func open_station_panel(star_i: int) -> void:
	_station_star = star_i
	_town_planet = Game.station_as_town(star_i)
	toggle_panel("station")


func _panel_station() -> void:
	var st: Dictionary = Galaxy.star(_station_star).station
	if _station_tab == "contracts":
		_panel_board()
		_station_tabs_into(_panel_body())
		return
	if _station_tab == "outfit":
		_panel_outfitter()
		_station_tabs_into(_panel_body())
		return
	var v := _frame("⌬ %s" % st.name.to_upper(), Vector2(1080, 700))
	_station_tabs_into(v)
	var info := HBoxContainer.new()
	v.add_child(info)
	info.add_child(UiKit.label("Credits ⌬ %d   ·   Cargo %d / %d" % [Game.credits, Game.cargo_used(), Game.cargo_cap()], 18, Color("ffd23f"), true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(sp)
	info.add_child(UiKit.label("Wanted: %s, %s" % [Db.item_name(st.demand[0]), Db.item_name(st.demand[1])], 15, Color("6ee06a")))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	info.add_child(gap)
	info.add_child(UiKit.label("Surplus: %s, %s" % [Db.item_name(st.surplus[0]), Db.item_name(st.surplus[1])], 15, UiKit.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	match _station_tab:
		"sell":
			var total := 0
			for it in Game.inventory.keys():
				if not Db.VALUES.has(it):
					continue
				var price := Game.station_sell_price(it, _station_star)
				var have := Game.count(it)
				if Game.is_cargo(it):
					total += price * have
				var tag := "  ·  WANTED" if st.demand.has(it) else ("  ·  surplus" if st.surplus.has(it) else "")
				var row := _trade_row(it, "you have %d%s" % [have, tag], price, Color("6ee06a") if st.demand.has(it) else Color("ffd23f"))
				row.add_child(UiKit.button("Sell 1", func(): Game.station_sell(it, 1, _station_star)))
				row.add_child(UiKit.button("Sell all (%d)" % (price * have), func(): Game.station_sell(it, have, _station_star)))
				list.add_child(row)
			if list.get_child_count() == 0:
				list.add_child(UiKit.label("Your hold is empty. Mine the belt or gather on a planet.", 16, UiKit.MUTED))
			else:
				var all := UiKit.button("SELL ALL CARGO  (⌬ %d)" % total, func(): Game.station_sell_all(_station_star))
				all.custom_minimum_size = Vector2(0, 48)
				all.add_theme_font_override("font", UiKit.title_font())
				all.disabled = total <= 0
				v.add_child(all)
		"buy":
			for line in Game.station_stock(_station_star):
				var it2: String = line.item
				var row2 := _trade_row(it2, "%d in stock" % line.qty, line.price, Color("ff9f43"))
				for q in [1, 5]:
					var b := UiKit.button("Buy %d" % q, func(): Game.station_buy(it2, q, _station_star))
					b.disabled = line.qty < q or Game.credits < line.price * q
					row2.add_child(b)
				list.add_child(row2)
		"services":
			var rc := Game.repair_cost()
			var ec := Game.recharge_cost()
			var r1 := HBoxContainer.new()
			r1.add_child(UiKit.label("Hull  %d / %d" % [int(Game.hull), int(Game.max_hull())], 17))
			var s1 := Control.new()
			s1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r1.add_child(s1)
			var rb := UiKit.button("Repair hull  (⌬ %d)" % rc, func():
				Game.buy_repair()
				_rebuild_town_panel()
			)
			rb.disabled = rc <= 0 or Game.credits < rc
			r1.add_child(rb)
			list.add_child(r1)
			var r2 := HBoxContainer.new()
			r2.add_child(UiKit.label("Energy  %d / %d" % [int(Game.energy), int(Game.max_energy())], 17))
			var s2 := Control.new()
			s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r2.add_child(s2)
			var eb := UiKit.button("Recharge  (⌬ %d)" % ec, func():
				Game.buy_recharge()
				_rebuild_town_panel()
			)
			eb.disabled = ec <= 0 or Game.credits < ec
			r2.add_child(eb)
			list.add_child(r2)
			list.add_child(HSeparator.new())
			var tip := UiKit.label("Cargo hold %d / %d. Craft Cargo Pods (+100) and Cargo Pods Mk II (+200) at a fabricator to haul more. Losing your ship spills a fifth of your raw cargo, so stations are a safe place to cash in: their guns keep pirates away." % [Game.cargo_used(), Game.cargo_cap()], 15, UiKit.MUTED)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD
			list.add_child(tip)


func _panel_body() -> VBoxContainer:
	# the VBox inside the current frame (for adding tabs to the reused board panel)
	return _panel.get_child(0).get_child(0) as VBoxContainer


func _station_tabs_into(v: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for t in [["sell", "Sell"], ["buy", "Buy"], ["services", "Services"], ["contracts", "Contracts"], ["outfit", "Outfitting"]]:
		var b := UiKit.button(t[1], func():
			_station_tab = t[0]
			_rebuild_town_panel()
		)
		b.custom_minimum_size = Vector2(140, 40)
		if _station_tab == t[0]:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
		tabs.add_child(b)
	v.add_child(tabs)
	v.move_child(tabs, 2)


func _update_ability_label() -> void:
	if ability_label:
		ability_label.text = "[F] %s  ·  LMB %s (X swap)  ·  G repair" % [Game.robot().ability.name, Game.weapon_def().name]


# --------------------------------------------------------------------------
# outfitter: paint, parts, loadout with a live preview
# --------------------------------------------------------------------------

func open_outfitter() -> void:
	toggle_panel("outfitter")


func _panel_outfitter() -> void:
	var v := _frame("OUTFITTER  ·  %s" % Game.player_name.to_upper(), Vector2(1180, 720))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	h.add_child(_build_preview())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	right.add_child(tabs)
	for t in [["paint", "Paint"], ["parts", "Parts"], ["loadout", "Loadout"]]:
		var b := UiKit.button(t[1], func():
			_outfit_tab = t[0]
			_rebuild_town_panel()
		)
		b.custom_minimum_size = Vector2(130, 40)
		if _outfit_tab == t[0]:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
		tabs.add_child(b)
	right.add_child(UiKit.label("Credits ⌬ %d" % Game.credits, 16, Color("ffd23f")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	match _outfit_tab:
		"paint": _outfit_paint(body)
		"parts": _outfit_parts(body)
		"loadout": _outfit_loadout(body)


func _build_preview() -> Control:
	var box := VBoxContainer.new()
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(420, 540)
	svc.stretch = true
	box.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.06, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.8)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = Color("7ad7ff")
	vp.add_child(rim)
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.3
	cyl.height = 0.2
	ped.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("1b2233")
	pm.metallic = 0.7
	pm.roughness = 0.3
	ped.material_override = pm
	ped.position.y = -0.1
	vp.add_child(ped)
	_preview_pivot = Node3D.new()
	vp.add_child(_preview_pivot)
	_preview_robot = RobotVisual.new()
	_preview_pivot.add_child(_preview_robot)
	_preview_robot.setup(Game.robot_id)
	_preview_robot.apply_look(Game.appearance)
	_preview_robot.flying = _preview_fly
	if _preview_fly:
		_preview_robot.rotation = Vector3(-PI * 0.45, 0, 0)
		_preview_robot.position = Vector3(0, 1.3, 0.9)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 6.2), Vector3(0, 1.15, 0), Vector3.UP)
	svc.gui_input.connect(func(ev):
		if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_preview_pivot.rotation.y += ev.relative.x * 0.01
	)
	_preview_pivot.rotation.y = 0.6
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(UiKit.label("Drag to rotate", 13, UiKit.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(UiKit.button("Flight pose" if not _preview_fly else "Standing pose", func():
		_preview_fly = not _preview_fly
		_rebuild_town_panel()
	))
	return box


func _process(delta: float) -> void:
	if is_instance_valid(_preview_pivot) and _preview_pivot.is_inside_tree():
		_preview_pivot.rotation.y += delta * 0.35


func _outfit_paint(body: VBoxContainer) -> void:
	var chans := [["shell", "Hull"], ["accent", "Accent"], ["glow", "Glow / eyes"], ["flame", "Thruster flame"]]
	var ch_row := HBoxContainer.new()
	ch_row.add_theme_constant_override("separation", 8)
	body.add_child(ch_row)
	for c in chans:
		var b := UiKit.button(c[1], func():
			_outfit_channel = c[0]
			_rebuild_town_panel()
		)
		if _outfit_channel == c[0]:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
		ch_row.add_child(b)
	body.add_child(UiKit.label("Pick a colour for %s. Paint is free." % _channel_name(_outfit_channel), 14, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for col in Db.PAINT_SWATCHES:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(64, 44)
		sw.focus_mode = Control.FOCUS_NONE
		var cur: String = Game.appearance.get(_outfit_channel, "")
		var selected: bool = cur != "" and Color(cur).is_equal_approx(col)
		sw.add_theme_stylebox_override("normal", UiKit.box(col, Color.WHITE if selected else col.lightened(0.3), 8, 3 if selected else 1, 0))
		sw.add_theme_stylebox_override("hover", UiKit.box(col.lightened(0.15), Color.WHITE, 8, 2, 0))
		sw.add_theme_stylebox_override("pressed", UiKit.box(col.darkened(0.1), Color.WHITE, 8, 2, 0))
		sw.pressed.connect(func():
			Sound.ui()
			Game.set_paint(_outfit_channel, col)
			_rebuild_town_panel()
		)
		grid.add_child(sw)
	var custom := HBoxContainer.new()
	custom.add_theme_constant_override("separation", 10)
	body.add_child(custom)
	custom.add_child(UiKit.label("Custom:", 15))
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(120, 40)
	picker.edit_alpha = false
	picker.color = Color(Game.appearance.get(_outfit_channel, "#ffffff"))
	picker.popup_closed.connect(func():
		Game.set_paint(_outfit_channel, picker.color)
		_rebuild_town_panel()
	)
	custom.add_child(picker)
	custom.add_child(UiKit.button("Factory colours", func():
		Game.reset_paint()
		_rebuild_town_panel()
	))
	body.add_child(HSeparator.new())
	body.add_child(UiKit.label("FINISH", 13, UiKit.MUTED, true))
	_cosmetic_grid(body, "finish")


func _channel_name(ch: String) -> String:
	return {"shell": "the hull", "accent": "the accents", "glow": "eyes and lights", "flame": "the thruster flame"}.get(ch, ch)


func _outfit_parts(body: VBoxContainer) -> void:
	for slot in [["head", "HEAD"], ["top", "TOPPER"], ["pack", "FLIGHT RIG"]]:
		body.add_child(UiKit.label(slot[1], 13, UiKit.MUTED, true))
		_cosmetic_grid(body, slot[0])


func _cosmetic_grid(body: VBoxContainer, slot: String) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for c in Db.COSMETICS[slot]:
		var owned: bool = Game.owns_cosmetic(slot, c.id)
		var on: bool = Game.equipped(slot) == c.id
		var label := "%s\n%s" % [c.name, "Equipped" if on else ("Owned" if owned else "⌬ %d" % c.price)]
		var b := UiKit.button(label, func():
			if Game.equip_cosmetic(slot, c.id):
				_rebuild_town_panel()
		)
		b.custom_minimum_size = Vector2(180, 58)
		if on:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.26, 0.2, 1), Color("6ee06a"), 8, 2, 8))
		elif not owned and Game.credits < int(c.price):
			b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		grid.add_child(b)


func _outfit_loadout(body: VBoxContainer) -> void:
	body.add_child(UiKit.label("Your weapon fires on foot and in flight. Press X anywhere to cycle unlocked loadouts.", 14, UiKit.MUTED))
	for id in Db.WEAPONS:
		var w: Dictionary = Db.WEAPONS[id]
		var pc := PanelContainer.new()
		var on: bool = Game.weapon == id
		pc.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.09, 0.15, 0.95), Color("6ee06a") if on else UiKit.LINE, 10, 2 if on else 1, 12))
		body.add_child(pc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		pc.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiKit.label(String(w.name).to_upper(), 18, Color("ffb86b"), true))
		info.add_child(UiKit.label(w.desc, 15))
		var dps := float(w.dmg) * float(w.pellets) / float(w.rate)
		var stats := UiKit.label("Damage/shot x%.1f  ·  Pellets %d  ·  Rate x%.2f  ·  Range x%.1f  ·  DPS x%.2f  ·  Energy x%.1f%s" % [w.dmg, w.pellets, 1.0 / float(w.rate), w.range, dps, w.cost, "  ·  pierces" if w.pierce else ""], 13, UiKit.MUTED)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD
		info.add_child(stats)
		if on:
			row.add_child(UiKit.label("Equipped", 16, Color("6ee06a")))
		elif Game.weapon_unlocked(id):
			row.add_child(UiKit.button("Equip", func():
				Game.set_weapon(id)
				_rebuild_town_panel()
			))
		else:
			row.add_child(UiKit.label("Craft the %s\nto unlock" % Db.item_name(w.unlock), 14, Color("ff9f43")))



func _panel_sysmap() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.035, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_host.add_child(dim)
	_panel = dim
	var m := preload("res://scripts/ui/system_map.gd").new()
	m.hud = self
	m.world = get_parent()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(m)


func _draw_waypoint(t: Dictionary, vp: Vector2, c: Vector2) -> void:
	var col := Color("ffd23f")
	var font := UiKit.body_font()
	if t.on:
		var p: Vector2 = t.pos
		threat_layer.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(9, 0), p + Vector2(0, 12), p + Vector2(-9, 0)]), Color(col, 0.35))
		threat_layer.draw_polyline(PackedVector2Array([p + Vector2(0, -12), p + Vector2(9, 0), p + Vector2(0, 12), p + Vector2(-9, 0), p + Vector2(0, -12)]), col, 2.0)
		threat_layer.draw_string(font, p + Vector2(-80, 30), "%s  %d u" % [t.name, int(t.dist)], HORIZONTAL_ALIGNMENT_CENTER, 160, 14, col)
	else:
		var d: Vector2 = t.pos - c
		var ang := d.angle()
		var edge := c + Vector2(cos(ang) * (vp.x * 0.42), sin(ang) * (vp.y * 0.38))
		threat_layer.draw_circle(edge, 9.0, Color(col, 0.35))
		threat_layer.draw_arc(edge, 9.0, 0, TAU, 20, col, 2.0)
		threat_layer.draw_string(font, edge + Vector2(-80, 26), "%s  %d u" % [t.name, int(t.dist)], HORIZONTAL_ALIGNMENT_CENTER, 160, 13, col)


func show_victory() -> void:
	toggle_panel("victory")


func _panel_victory() -> void:
	var v := _frame("THE CIRCUIT SHINES", Vector2(860, 560))
	var t := UiKit.label("The Heart is gone. One relay after another, the old light runs from star to star again. The Archivist speaks your designation to every beacon, and every beacon answers.", 19)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(t)
	v.add_child(HSeparator.new())
	var pt := int(Game.play_time)
	for line in [
		"Time played  %d:%02d" % [pt / 3600, (pt / 60) % 60],
		"Relays lit  %d" % Game.lit_relays.size(),
		"Worlds visited  %d  ·  Stars  %d" % [Game.visited_planets.size(), Game.visited_stars.size()],
		"Species logged  %d  ·  Relics  %d" % [Game.scanned.size(), Game.relics_found],
		"Machines destroyed  %d" % Game.kills,
		"Level  %d  ·  Credits  %d" % [Game.level, Game.credits],
	]:
		v.add_child(UiKit.label(line, 18, Color("ffd98a")))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	v.add_child(UiKit.label("The galaxy is still yours to wander. Unlit relays, unnamed species and sealed vaults remain.", 15, UiKit.MUTED))
	v.add_child(UiKit.button("Keep exploring", close_panel))



func _panel_settings() -> void:
	var v := _frame("SETTINGS", Vector2(900, 640))
	v.add_child(SettingsUI.new())



# --------------------------------------------------------------------------
# one-time tips
# --------------------------------------------------------------------------

var _tip_box: PanelContainer

func tip(id: String, text: String) -> void:
	if not Sound.tip_once(id):
		return
	if _tip_box:
		_tip_box.queue_free()
	_tip_box = PanelContainer.new()
	_tip_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tip_box.position = Vector2(20, -190)
	_tip_box.custom_minimum_size = Vector2(430, 0)
	_tip_box.add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.1, 0.16, 0.92), UiKit.ACCENT, 10, 2, 12))
	root.add_child(_tip_box)
	var v := VBoxContainer.new()
	_tip_box.add_child(v)
	v.add_child(UiKit.label("TIP", 12, UiKit.ACCENT, true))
	var l := UiKit.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(l)
	v.add_child(UiKit.label("Turn tips off in Settings", 11, UiKit.MUTED))
	Sound.play("notify", -8.0, 0.0, "UI")
	var box := _tip_box
	_tip_box.modulate.a = 0.0
	var t := box.create_tween()
	t.tween_property(box, "modulate:a", 1.0, 0.3)
	t.tween_interval(10.0)
	t.tween_property(box, "modulate:a", 0.0, 0.8)
	t.tween_callback(box.queue_free)
