extends Node3D
## Title screen + robot selection, with a live 3D backdrop.

const ORDER := ["scout", "miner", "engineer", "siphon"]

var cam: Camera3D
var planet_node: Node3D
var robots := {}
var pedestals := {}
var selected := 0
var ui: Control
var menu_box: Control
var select_box: Control
var info_box: VBoxContainer
var name_edit: LineEdit
var state := "title"
var _t := 0.0
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_blend := 1.0
var _new_slot := 1
var _overlay: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sound.stop_all_loops()
	Sound.play_music("menu", 1.5)
	_build_world()
	cam.global_transform = _cam_title()
	_build_ui()
	_show_title()


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/space_sky.gdshader")
	sm.set_shader_parameter("seed", 17.0)
	sm.set_shader_parameter("nebula_strength", 0.9)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.8)
	env.ambient_light_energy = 0.5
	UiKit.polish_environment(env)
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.1
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 1.3
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = true
	add_child(sun)

	# hero planet
	var pdata: Dictionary = Galaxy.planet(0, 0)
	var gen := PlanetGen.new(pdata)
	planet_node = Node3D.new()
	add_child(planet_node)
	planet_node.position = Vector3(26, -8, -60)
	var mi := MeshInstance3D.new()
	mi.mesh = gen.build_mesh(48, 0.16)
	mi.material_override = gen.terrain_material(0.16)
	planet_node.add_child(mi)
	var water := MeshInstance3D.new()
	var ws := SphereMesh.new()
	ws.radius = gen.sea_radius() * 0.16
	ws.height = ws.radius * 2.0
	water.mesh = ws
	var wm := StandardMaterial3D.new()
	var wc: Color = Db.BIOMES.verdant.water
	wm.albedo_color = Color(wc.r, wc.g, wc.b, 1.0)
	wm.roughness = 0.15
	water.material_override = wm
	planet_node.add_child(water)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = gen.radius * 0.16 * 1.12
	am.height = am.radius * 2.0
	atmo.mesh = am
	var amat := ShaderMaterial.new()
	amat.shader = load("res://shaders/atmo_rim.gdshader")
	amat.set_shader_parameter("color", Db.BIOMES.verdant.atmo)
	atmo.material_override = amat
	planet_node.add_child(atmo)
	var clouds := gen.cloud_shell(gen.radius * 0.16 * 1.05, 64)
	(clouds.material_override as ShaderMaterial).set_shader_parameter("sun_dir", Vector3(0.6, 0.55, 0.6).normalized())
	planet_node.add_child(clouds)
	UiKit.add_vignette(self, 0.35)

	# robot line-up
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("1b2233")
	pm.metallic = 0.7
	pm.roughness = 0.3
	for i in ORDER.size():
		var id: String = ORDER[i]
		var base := Node3D.new()
		base.position = Vector3((i - 1.5) * 3.2, 0, 0)
		add_child(base)
		var ped := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.35
		cyl.height = 0.4
		ped.mesh = cyl
		ped.material_override = pm
		ped.position.y = -0.2
		base.add_child(ped)
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 1.18
		tor.outer_radius = 1.26
		ring.mesh = tor
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Db.ROBOTS[id].color * 2.0
		ring.material_override = rm
		ring.position.y = 0.01
		base.add_child(ring)
		var rv := RobotVisual.new()
		base.add_child(rv)
		rv.setup(id)
		rv.rotation.y = PI - 0.35
		robots[id] = rv
		pedestals[id] = base
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, 5, 2)
		spot.rotation_degrees = Vector3(-65, 0, 0)
		spot.spot_range = 10
		spot.spot_angle = 28
		spot.light_color = Db.ROBOTS[id].color.lerp(Color.WHITE, 0.5)
		spot.light_energy = 0.0
		base.add_child(spot)
		base.set_meta("spot", spot)

	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.make_current()


func _cam_title() -> Transform3D:
	return Transform3D(Basis(), Vector3(-2.5, 2.2, 13)).looking_at(Vector3(2, 1.2, -6), Vector3.UP)


func _cam_robot(i: int) -> Transform3D:
	var p := Vector3((i - 1.5) * 3.2, 0, 0)
	return Transform3D(Basis(), p + Vector3(0, 1.6, 5.4)).looking_at(p + Vector3(0, 1.0, 0), Vector3.UP)


## Slide the view so the chosen robot sits in the middle of the space left
## of the info panel, whatever shape the window is.
func _select_offset() -> float:
	var vs := get_viewport().get_visible_rect().size
	var free_centre := (vs.x - 560.0) * 0.5
	var fx := free_centre / vs.x
	var dist := 5.43
	var half_h := dist * tan(deg_to_rad(cam.fov) * 0.5)
	var half_w := half_h * vs.x / vs.y
	return (0.5 - fx) * 2.0 * half_w


func _move_cam(t: Transform3D) -> void:
	_cam_from = cam.global_transform
	_cam_to = t
	_cam_blend = 0.0


func _process(delta: float) -> void:
	_t += delta
	planet_node.rotation.y += delta * 0.05
	if _cam_blend < 1.0:
		_cam_blend = minf(1.0, _cam_blend + delta * 1.4)
		var e := 1.0 - pow(1.0 - _cam_blend, 3.0)
		cam.global_transform = _cam_from.interpolate_with(_cam_to, e)
	cam.h_offset = lerpf(cam.h_offset, _select_offset() if state == "select" else 0.0, clampf(delta * 4.0, 0.0, 1.0))
	for i in ORDER.size():
		var id: String = ORDER[i]
		var rv: RobotVisual = robots[id]
		var active := state == "select" and i == selected
		pedestals[id].visible = state == "select"
		var face := PI + (sin(_t * 0.7) * 0.75 if active else -0.35)
		rv.rotation.y = lerp_angle(rv.rotation.y, face, delta * 3.0)
		rv.position.y = sin(_t * 1.6 + i) * 0.06 + (0.15 if active else 0.0)
		rv.working = active and fmod(_t, 6.0) > 4.8
		var spot: SpotLight3D = pedestals[id].get_meta("spot")
		spot.light_energy = lerpf(spot.light_energy, 6.0 if active else 0.0, delta * 5.0)


# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiKit.theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	# title screen
	menu_box = VBoxContainer.new()
	menu_box.position = Vector2(90, 150)
	menu_box.custom_minimum_size = Vector2(520, 0)
	menu_box.add_theme_constant_override("separation", 14)
	ui.add_child(menu_box)
	var title := UiKit.label("STAR CIRCUIT", 76, Color.WHITE, true)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.25, 0.8))
	menu_box.add_child(title)
	var tag := UiKit.label("A robot space-RPG. Fly between stars. Walk strange worlds.\nGather, craft, and master your professions.", 19, Color("b8d8ff"))
	menu_box.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	menu_box.add_child(gap)
	var summary := Game.save_summary(Sound.last_slot)
	if not summary.is_empty():
		var b := _menu_button("CONTINUE", func(): Game.load_game(Sound.last_slot))
		menu_box.add_child(b)
		menu_box.add_child(UiKit.label("   Slot %d  ·  %s" % [Sound.last_slot, _slot_line(summary)], 15, UiKit.MUTED))
	menu_box.add_child(_menu_button("NEW GAME", _show_select))
	if Game.has_save():
		menu_box.add_child(_menu_button("LOAD GAME", func(): _show_overlay("load")))
	menu_box.add_child(_menu_button("SETTINGS", func(): _show_overlay("settings")))
	menu_box.add_child(_menu_button("QUIT", func(): get_tree().quit()))
	var credit := UiKit.label("Models built in Blender · Engine: Godot %s" % Engine.get_version_info().string, 13, UiKit.MUTED)
	credit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credit.position = Vector2(24, -36)
	ui.add_child(credit)

	# robot select
	select_box = Control.new()
	select_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(select_box)
	var hdr := UiKit.label("CHOOSE YOUR FRAME", 38, Color.WHITE, true)
	hdr.position = Vector2(60, 40)
	hdr.add_theme_constant_override("outline_size", 10)
	hdr.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	select_box.add_child(hdr)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	pc.position = Vector2(-560, -300)
	pc.custom_minimum_size = Vector2(500, 600)
	select_box.add_child(pc)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 10)
	pc.add_child(info_box)
	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	nav.position = Vector2(-560, -110)
	nav.add_theme_constant_override("separation", 10)
	select_box.add_child(nav)
	for i in ORDER.size():
		var r: Dictionary = Db.ROBOTS[ORDER[i]]
		var b := UiKit.button("%s\n%s" % [r.name, r.title], func(): _select(i))
		b.custom_minimum_size = Vector2(170, 64)
		nav.add_child(b)
	var back := UiKit.button("< Back", _show_title)
	back.position = Vector2(60, 110)
	select_box.add_child(back)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, cb)
	b.custom_minimum_size = Vector2(340, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UiKit.title_font())
	b.add_theme_font_size_override("font_size", 22)
	return b


func _show_title() -> void:
	state = "title"
	menu_box.visible = true
	select_box.visible = false
	_move_cam(_cam_title())


func _show_select() -> void:
	# default to the first empty slot
	_new_slot = Sound.last_slot
	for n in range(1, Game.SLOTS + 1):
		if Game.save_summary(n).is_empty():
			_new_slot = n
			break
	state = "select"
	menu_box.visible = false
	select_box.visible = true
	_select(selected)


func _select(i: int) -> void:
	selected = i
	Sound.ui("ui_open", -10.0)
	_move_cam(_cam_robot(i))
	var id: String = ORDER[i]
	var r: Dictionary = Db.ROBOTS[id]
	for c in info_box.get_children():
		c.queue_free()
	info_box.add_child(UiKit.label(r.name.to_upper(), 40, r.color.lightened(0.15), true))
	info_box.add_child(UiKit.label(r.title, 18, UiKit.MUTED))
	var d := UiKit.label(r.desc, 17)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_box.add_child(d)
	info_box.add_child(HSeparator.new())
	info_box.add_child(UiKit.label("PERKS", 13, UiKit.MUTED, true))
	for p in r.perks:
		info_box.add_child(UiKit.label("◆  " + p, 16, r.color.lightened(0.35)))
	info_box.add_child(HSeparator.new())
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_box.add_child(sp)
	info_box.add_child(UiKit.label("DESIGNATION", 13, UiKit.MUTED, true))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = r.name
	name_edit.max_length = 18
	name_edit.custom_minimum_size = Vector2(0, 44)
	info_box.add_child(name_edit)
	info_box.add_child(UiKit.label("SAVE SLOT", 13, UiKit.MUTED, true))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	info_box.add_child(slots)
	for n in range(1, Game.SLOTS + 1):
		var used := not Game.save_summary(n).is_empty()
		var sb := UiKit.button("Slot %d\n%s" % [n, "in use" if used else "empty"], func():
			_new_slot = n
			_select(selected)
		)
		sb.custom_minimum_size = Vector2(120, 50)
		if _new_slot == n:
			sb.add_theme_stylebox_override("normal", UiKit.box(Color(0.1, 0.22, 0.34, 1), UiKit.ACCENT, 8, 2, 8))
		slots.add_child(sb)
	if not Game.save_summary(_new_slot).is_empty():
		info_box.add_child(UiKit.label("Starting here overwrites Slot %d." % _new_slot, 13, Color("ffb86b")))
	var go := UiKit.button("ACTIVATE %s" % r.name.to_upper(), func(): Game.new_game(id, name_edit.text, _new_slot))
	go.custom_minimum_size = Vector2(0, 60)
	go.add_theme_font_override("font", UiKit.title_font())
	go.add_theme_font_size_override("font_size", 22)
	go.add_theme_stylebox_override("normal", UiKit.box(r.color.darkened(0.55), r.color, 10, 2, 10))
	go.add_theme_stylebox_override("hover", UiKit.box(r.color.darkened(0.35), r.color.lightened(0.3), 10, 2, 10))
	info_box.add_child(go)


func _unhandled_input(event: InputEvent) -> void:
	if state != "select" or not (event is InputEventKey) or not event.pressed:
		return
	if name_edit and name_edit.has_focus():
		return
	if event.keycode == KEY_RIGHT:
		_select((selected + 1) % ORDER.size())
	elif event.keycode == KEY_LEFT:
		_select((selected + ORDER.size() - 1) % ORDER.size())
	elif event.keycode == KEY_ESCAPE:
		_show_title()



func _slot_line(d: Dictionary) -> String:
	var rname: String = Db.ROBOTS.get(d.get("robot_id", "scout"), Db.ROBOTS.scout).title
	var si := int(d.get("star_index", 0))
	var where: String = Galaxy.planet(si, int(d.get("planet_index", 0))).name if d.get("location", "planet") == "planet" else Galaxy.star(si).name + " orbit"
	var pt := int(d.get("play_time", 0))
	return "%s  ·  %s  ·  Level %d  ·  %s  ·  %d:%02d played" % [d.get("player_name", "Unit"), rname, int(d.get("level", 1)), where, pt / 3600, (pt / 60) % 60]


func _show_overlay(kind: String) -> void:
	if _overlay:
		_overlay.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	_overlay = dim
	var size := Vector2(900, 620) if kind == "settings" else Vector2(860, 480)
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
	head.add_child(UiKit.label("SETTINGS" if kind == "settings" else "LOAD GAME", 26, Color.WHITE, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiKit.button("Close", func():
		_overlay.queue_free()
		_overlay = null
	))
	v.add_child(HSeparator.new())
	if kind == "settings":
		v.add_child(SettingsUI.new())
		return
	for n in range(1, Game.SLOTS + 1):
		var d := Game.save_summary(n)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.box(Color(0.06, 0.09, 0.15, 0.9), UiKit.LINE, 10, 1, 12))
		v.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(UiKit.label("SLOT %d%s" % [n, "  ·  last played" if n == Sound.last_slot and not d.is_empty() else ""], 16, UiKit.ACCENT, true))
		info.add_child(UiKit.label(_slot_line(d) if not d.is_empty() else "Empty", 15, UiKit.TEXT if not d.is_empty() else UiKit.MUTED))
		if not d.is_empty():
			h.add_child(UiKit.button("Load", func(): Game.load_game(n)))
			var del := UiKit.button("Delete", Callable())
			del.pressed.connect(func():
				if del.has_meta("armed"):
					Game.delete_slot(n)
					_show_overlay("load")
				else:
					del.set_meta("armed", true)
					del.text = "Confirm delete"
					del.add_theme_color_override("font_color", Color("ff6b6b"))
			)
			h.add_child(del)
