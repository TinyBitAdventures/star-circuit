class_name RemoteDiver
extends Node2D
## Another player in a shared 2D mini game (a cave or the Deep Sea): a little
## robot in their colours with a headlamp and a name tag, smoothed between
## their position updates.

var id := 0
var style := "dig" # dig | sea
var anim := ""
var _shell := Color("e6e8ec")
var _accent := Color("18c2b0")
var _glow := Color("5ff7ff")
var _target := Vector2.ZERO
var _facing := 1.0
var _has := false
var _t := 0.0
var _vel := Vector2.ZERO


func setup(pid: int, info: Dictionary, s: String, light_tex: Texture2D) -> void:
	id = pid
	style = s
	z_index = 5
	var look: Dictionary = info.get("look", {}) if info.get("look") is Dictionary else {}
	var r: Dictionary = Db.ROBOTS.get(String(info.get("robot", "")), {})
	var rc = r.get("color")
	var stock: Color = rc if rc is Color else Color("18c2b0")
	_shell = RobotVisual.look_color(look, "shell", Color("e6e8ec"))
	_accent = RobotVisual.look_color(look, "accent", stock)
	_glow = RobotVisual.look_color(look, "glow", Color("5ff7ff"))
	var lamp := PointLight2D.new()
	lamp.texture = light_tex
	lamp.texture_scale = 2.6
	lamp.energy = 1.1
	lamp.color = Color(1.0, 0.95, 0.85)
	add_child(lamp)
	var tag := Label.new()
	tag.text = String(info.get("name", "Unit"))
	tag.add_theme_font_override("font", UiKit.title_font())
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color("9bd1ff"))
	tag.add_theme_constant_override("outline_size", 5)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(160, 20)
	tag.position = Vector2(-80, -52)
	var um := CanvasItemMaterial.new()
	um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	tag.material = um
	add_child(tag)


func push(pos: Vector2, facing: float, a: String) -> void:
	if not _has or pos.distance_to(_target) > 400.0:
		position = pos
		_has = true
	_target = pos
	if absf(facing) > 0.1:
		_facing = signf(facing)
	anim = a


func _process(delta: float) -> void:
	_t += delta
	var prev := position
	position = position.lerp(_target, 1.0 - exp(-delta * 12.0))
	_vel = _vel.lerp((position - prev) / maxf(delta, 0.001), clampf(delta * 8.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var f := _facing
	var o := Vector2(0, sin(_t * 3.0) * 1.5)
	var drilling := anim == "drill"
	if style == "sea":
		var tilt := clampf(_vel.x / 260.0, -1.0, 1.0) * 0.25
		draw_set_transform(o, tilt, Vector2.ONE)
		var pp := Vector2(-f * 15.0, 2)
		var spin := sin(_t * (40.0 if _vel.length() > 20.0 else 8.0))
		draw_line(pp + Vector2(0, -7 * spin), pp + Vector2(0, 7 * spin), Color("9aa3b0"), 3.0)
		draw_rect(Rect2(Vector2(-12, -8), Vector2(24, 16)), _shell)
		draw_circle(Vector2(f * 6.0, -9), 9.0, _shell)
		draw_rect(Rect2(Vector2(-12, 1), Vector2(24, 4)), _accent)
		draw_rect(Rect2(Vector2(f * 6.0 - 6.0, -13), Vector2(12, 6)), Color("1b1f29"))
		draw_rect(Rect2(Vector2(f * 6.0 - 4.0, -12), Vector2(8, 4)), _glow)
		var k := sin(_t * 8.0) * 4.0
		draw_line(Vector2(-f * 6.0, 7), Vector2(-f * 16.0, 10 + k), Color("2a2f3a"), 4.0)
		draw_line(Vector2(-f * 2.0, 7), Vector2(-f * 14.0, 13 - k), Color("2a2f3a"), 4.0)
	else:
		# the drill pod: a rounded hull on treads with a drill on the front
		draw_set_transform(o, 0.0, Vector2.ONE)
		draw_rect(Rect2(Vector2(-13, -12), Vector2(26, 20)), _shell)
		draw_circle(Vector2(0, -12), 11.0, _shell)
		draw_rect(Rect2(Vector2(-13, 2), Vector2(26, 4)), _accent)
		draw_rect(Rect2(Vector2(f * 3.0 - 7.0, -17), Vector2(14, 6)), Color("1b1f29"))
		draw_rect(Rect2(Vector2(f * 3.0 - 5.0, -16), Vector2(10, 4)), _glow)
		draw_rect(Rect2(Vector2(-14, 8), Vector2(28, 6)), Color("2a2f3a"))
		var tip := Vector2(f * 22.0, 0)
		draw_colored_polygon(PackedVector2Array([Vector2(f * 12.0, -6), tip, Vector2(f * 12.0, 6)]), Color("c9ced6"))
		if drilling:
			draw_circle(tip, 4.0 + sin(_t * 50.0), Color(1.0, 0.7, 0.3))
	draw_line(Vector2(f * 6.0, -19), Vector2(f * 9.0, -26), Color("2a2f3a"), 2.0)
	draw_circle(Vector2(f * 9.0, -27), 2.5, _glow)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
