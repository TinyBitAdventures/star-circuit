class_name SettingsUI
extends VBoxContainer
## Settings screen content (display, controls, key bindings, audio).
## Used by the pause menu and the main menu.

signal changed

var _waiting := ""
var _tab := "general"


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	add_child(tabs)
	for t in [["general", "Display & Controls"], ["keys", "Key Bindings"], ["audio", "Audio"]]:
		var b := UiKit.button(t[1], func():
			_tab = t[0]
			_build()
		)
		if _tab == t[0]:
			_mark(b)
		tabs.add_child(b)
	add_child(HSeparator.new())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 380)
	add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	match _tab:
		"general": _general(v)
		"keys": _keys(v)
		"audio": _audio(v)


## Highlight the selected tab / option.
func _mark(b: Button) -> void:
	var st := UiKit.box(Color(UiKit.ACCENT, 0.85), UiKit.ACCENT, 8, 2, 8)
	for k in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(k, st)
	b.add_theme_color_override("font_color", Color("0b1420"))
	b.add_theme_color_override("font_hover_color", Color("0b1420"))


func _row(v: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var l := UiKit.label(label, 16)
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	return h


func _slider(h: HBoxContainer, lo: float, hi: float, step: float, val: float, fmt: String, cb: Callable) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(240, 0)
	s.focus_mode = Control.FOCUS_NONE
	var vl := UiKit.label(fmt % val, 15, UiKit.MUTED)
	vl.custom_minimum_size = Vector2(60, 0)
	s.value_changed.connect(func(x):
		vl.text = fmt % x
		cb.call(x)
		Sound.save_settings()
		changed.emit()
	)
	h.add_child(s)
	h.add_child(vl)


func _toggle(h: HBoxContainer, on: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(x):
		Sound.ui()
		cb.call(x)
		Sound.save_settings()
		changed.emit()
	)
	h.add_child(c)


func _general(v: VBoxContainer) -> void:
	v.add_child(UiKit.label("DISPLAY", 13, UiKit.MUTED, true))
	_toggle(_row(v, "Fullscreen"), Sound.fullscreen, func(x):
		Sound.fullscreen = x
		Sound.apply_display()
	)
	var gq := _row(v, "Graphics quality")
	for qi in 3:
		var b := UiKit.button(["Low", "Medium", "High"][qi], func():
			Sound.gfx_quality = qi
			Sound.apply_gfx()
			Sound.save_settings()
			_build()
		)
		if Sound.gfx_quality == qi:
			_mark(b)
		gq.add_child(b)
	v.add_child(UiKit.label("Grass, shadows and ambient occlusion update on your next landing.", 13, UiKit.MUTED))
	_slider(_row(v, "Field of view"), 55.0, 95.0, 1.0, Sound.fov, "%d°", func(x): Sound.fov = x)
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("CONTROLS", 13, UiKit.MUTED, true))
	_slider(_row(v, "Mouse sensitivity"), 0.2, 3.0, 0.05, Sound.mouse_sens, "%.2fx", func(x): Sound.mouse_sens = x)
	_toggle(_row(v, "Invert vertical look"), Sound.invert_y, func(x): Sound.invert_y = x)
	_toggle(_row(v, "Show tips"), Sound.show_tips, func(x): Sound.show_tips = x)
	var rt := _row(v, "")
	rt.add_child(UiKit.button("Show all tips again", func():
		Sound.seen_tips = []
		Sound.save_settings()
		Game.notify.emit("Tips will show again.", UiKit.ACCENT)
	))


func _keys(v: VBoxContainer) -> void:
	v.add_child(UiKit.label("Click a binding, then press the new key. Esc cancels.", 14, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for pair in Sound.REBINDABLE:
		var action: String = pair[0]
		var l := UiKit.label(pair[1], 15)
		l.custom_minimum_size = Vector2(240, 0)
		grid.add_child(l)
		var b := UiKit.button("Press a key..." if _waiting == action else Sound.key_name(action), func():
			_waiting = action
			_build()
		)
		b.custom_minimum_size = Vector2(170, 36)
		if _waiting == action:
			b.add_theme_stylebox_override("normal", UiKit.box(Color(0.3, 0.2, 0.05, 1), Color("ffd23f"), 8, 2, 8))
		grid.add_child(b)
	v.add_child(UiKit.button("Reset to defaults (applies on restart)", func():
		Sound.reset_keybinds()
		Game.notify.emit("Key bindings reset. Restart to apply.", UiKit.ACCENT)
	))


func _audio(v: VBoxContainer) -> void:
	for row in [["Master", "Master"], ["Music", "Music"], ["Effects", "SFX"], ["Interface", "UI"], ["Ambience", "Ambience"]]:
		var bus: String = row[1]
		_slider(_row(v, row[0]), 0.0, 1.0, 0.05, Sound.volumes[bus], "%.2f", func(x): Sound.set_volume(bus, x))


func _input(event: InputEvent) -> void:
	if _waiting == "" or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode != KEY_ESCAPE:
		Sound.rebind(_waiting, event.physical_keycode)
		Sound.ui()
	_waiting = ""
	_build()
