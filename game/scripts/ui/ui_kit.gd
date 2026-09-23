class_name UiKit
extends RefCounted
## Shared sci-fi UI styling + small widget factories.

const BG := Color(0.035, 0.05, 0.1, 0.9)
const BG_SOFT := Color(0.06, 0.09, 0.16, 0.85)
const LINE := Color(0.35, 0.85, 1.0, 0.45)
const ACCENT := Color("5ff7ff")
const TEXT := Color("e6f1ff")
const MUTED := Color("8ea3bf")

static var _theme: Theme
static var _body_font: FontVariation
static var _title_font: FontVariation


static func body_font() -> Font:
	if _body_font == null:
		_body_font = FontVariation.new()
		_body_font.base_font = load("res://assets/fonts/Exo2.ttf")
		_body_font.variation_opentype = {"wght": 500}
	return _body_font


static func title_font() -> Font:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = load("res://assets/fonts/Orbitron.ttf")
		_title_font.variation_opentype = {"wght": 700}
	return _title_font


static func box(bg: Color, border: Color = LINE, radius := 10, border_w := 1, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(BG))
	t.set_stylebox("panel", "Panel", box(BG))
	var bn := box(Color(0.08, 0.14, 0.24, 0.95), Color(0.35, 0.85, 1.0, 0.6), 8, 1, 10)
	var bh := box(Color(0.12, 0.24, 0.38, 0.98), ACCENT, 8, 2, 10)
	var bp := box(Color(0.05, 0.4, 0.5, 1.0), ACCENT, 8, 2, 10)
	var bd := box(Color(0.06, 0.08, 0.12, 0.8), Color(0.3, 0.35, 0.45, 0.5), 8, 1, 10)
	for s in [bn, bh, bp, bd]:
		s.shadow_size = 0
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		s.content_margin_left = 16
		s.content_margin_right = 16
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.62))
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.05, 0.09, 0.95), LINE, 8, 1, 10))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.05, 0.09, 0.95), ACCENT, 8, 2, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	var bg_bar := box(Color(0.02, 0.03, 0.06, 0.9), Color(1, 1, 1, 0.12), 5, 1, 0)
	t.set_stylebox("background", "ProgressBar", bg_bar)
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color(0, 0, 0, 0), 5, 0, 0))
	t.set_stylebox("panel", "TooltipPanel", box(BG, ACCENT, 6, 1, 8))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 4, 0, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Color(0.35, 0.85, 1.0, 0.4), Color(0, 0, 0, 0), 4, 0, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(0.35, 0.85, 1.0, 0.7), Color(0, 0, 0, 0), 4, 0, 2))
	_theme = t
	return t


static func label(text: String, size := 17, color := TEXT, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font())
	return l


static func rich(text: String, size := 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_override("normal_font", body_font())
	r.add_theme_color_override("default_color", TEXT)
	return r


static func bar(color: Color, h := 14) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, h)
	var fill := box(color, Color(0, 0, 0, 0), 5, 0, 0)
	fill.shadow_size = 0
	p.add_theme_stylebox_override("fill", fill)
	return p


static func button(text: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): Sound.ui())
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func swatch(color: Color, size := 14) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	var s := box(color, color.lightened(0.4), size / 3, 1, 0)
	s.shadow_size = 0
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func hex(c: Color) -> String:
	return c.to_html(false)
