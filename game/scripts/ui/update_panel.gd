class_name UpdatePanel
extends VBoxContainer
## Body of the "Update available" dialog (title screen and pause menu):
## version, release notes, download progress, and install / release-page buttons.
## `save_first` runs just before the download starts (the pause menu saves).

var save_first := Callable()
var _status: Label
var _bar: ProgressBar
var _buttons: HBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 12)
	add_child(UiKit.label("Version %s is out. You have %s." % [Updater.latest, Updater.current_version()], 18, UiKit.TEXT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var notes := UiKit.rich(_notes_bbcode(Updater.notes), 15)
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.meta_clicked.connect(func(m): OS.shell_open(str(m)))
	scroll.add_child(notes)
	_status = UiKit.label("", 15, UiKit.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_bar = UiKit.bar(UiKit.ACCENT, 12)
	_bar.max_value = 1.0
	add_child(_bar)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	add_child(_buttons)
	Updater.status_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	if Updater.state == "downloading":
		var p := Updater.progress()
		_bar.value = p if p >= 0.0 else 0.0
		_status.text = "Downloading...  %.0f of %.0f MB" % [Updater.downloaded_mb(), Updater.asset_size / 1048576.0] if Updater.asset_size > 0 else "Downloading...  %.0f MB" % Updater.downloaded_mb()


func _refresh() -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var blocker := Updater.install_blocker() if Updater.state in ["available", "error"] else ""
	_bar.visible = Updater.state in ["downloading", "installing", "ready"]
	match Updater.state:
		"downloading":
			_status.text = "Downloading..."
			_status.add_theme_color_override("font_color", UiKit.MUTED)
		"installing":
			_status.text = "Installing. The game will restart in a moment."
			_bar.value = 1.0
		"ready":
			_status.text = "Updated. Restarting..."
		"error":
			_status.text = Updater.error
			_status.add_theme_color_override("font_color", Color("ff6b6b"))
		_:
			_status.add_theme_color_override("font_color", UiKit.MUTED)
			if blocker != "":
				_status.text = blocker
			else:
				var mb := Updater.asset_size / 1048576.0
				var dl := "the %.0f MB download" % mb if mb > 0 else "the download"
				var rest := "%s installs itself and the game restarts. Saves carry over." % dl
				_status.text = "Your game is saved first, then " + rest if save_first.is_valid() else rest[0].to_upper() + rest.substr(1)
	if Updater.busy() or Updater.state == "ready":
		return
	if blocker == "" and Updater.latest != "":
		var b := UiKit.button("Save & Update" if save_first.is_valid() else "Update Now", _go)
		b.custom_minimum_size = Vector2(200, 46)
		_buttons.add_child(b)
	_buttons.add_child(UiKit.button("Open Release Page", Updater.open_release_page))


func _go() -> void:
	if save_first.is_valid():
		save_first.call()
	Updater.install()


## GitHub release bodies are Markdown; keep headings, bold and bullets readable.
static func _notes_bbcode(md: String) -> String:
	var out := PackedStringArray()
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	for raw in md.replace("\r", "").split("\n"):
		var line := raw if link.search(raw) else raw.replace("[", "\u0001").replace("]", "\u0002").replace("\u0001", "[lb]").replace("\u0002", "[rb]")
		line = link.sub(line, "[url=$2]$1[/url]", true)
		line = bold.sub(line, "[b]$1[/b]", true)
		line = line.replace("`", "")
		var t := line.strip_edges()
		if t.begins_with("### "):
			line = "[b][color=#5ff7ff]%s[/color][/b]" % t.substr(4)
		elif t.begins_with("## "):
			line = "[b][color=#ffd23f]%s[/color][/b]" % t.substr(3)
		elif t.begins_with("- "):
			var indent := raw.length() - raw.strip_edges(true, false).length()
			line = "%s•  %s" % ["      ".repeat(indent / 2), t.substr(2)]
		if line.strip_edges() == "" and (out.is_empty() or out[-1] == ""):
			continue # one blank line at most
		out.append(line if line.strip_edges() != "" else "")
	return "\n".join(out).strip_edges()
