extends Node
## Audio manager: buses + volume settings, crossfading music with a combat
## layer, pooled 2D/3D one-shots, and named loops (jetpack, drill, engine...).

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX", "UI", "Ambience"]
const POOL_2D := 16
const POOL_3D := 20
const SILENT_DB := -60.0

## music track per biome
const BIOME_MUSIC := {"verdant": "verdant", "bloom": "verdant", "dune": "arid", "frost": "crystal", "prism": "crystal", "ember": "ember",
	"abyss": "crystal", "tempest": "underground", "forge": "ember"}

var volumes := {"Master": 0.8, "Music": 0.6, "SFX": 0.8, "UI": 0.7, "Ambience": 0.6}
var gfx_quality := 1 # 0 low, 1 medium (default), 2 high
var mouse_sens := 1.0
var invert_y := false
var fov := 70.0
var fullscreen := false
var show_tips := true
var last_slot := 1
var keybinds := {} # action -> physical keycode (overrides the default first key)
var seen_tips: Array = []

var _cache := {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _loops := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _combat: AudioStreamPlayer
var _music_current := ""
var _music_active: AudioStreamPlayer
var _combat_on := false
var _combat_off_timer := 0.0
var _last_play := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_settings()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 14.0
		p.max_distance = 120.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_combat = _make_music_player()
	_music_active = _music_a


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func _setup_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# a gentle limiter on the master keeps stacked explosions polite
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)


# --------------------------------------------------------------------------
# settings
# --------------------------------------------------------------------------

func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volumes[bus], 0.0001)))
		AudioServer.set_bus_mute(idx, volumes[bus] <= 0.001)


func save_settings() -> void:
	if Game.is_dev_run():
		return
	var cfg := ConfigFile.new()
	for b in volumes:
		cfg.set_value("audio", b, volumes[b])
	cfg.set_value("graphics", "quality", gfx_quality)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("controls", "mouse_sens", mouse_sens)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("controls", "keybinds", keybinds)
	cfg.set_value("game", "show_tips", show_tips)
	cfg.set_value("game", "last_slot", last_slot)
	cfg.set_value("game", "seen_tips", seen_tips)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for b in volumes:
			volumes[b] = float(cfg.get_value("audio", b, volumes[b]))
		gfx_quality = int(cfg.get_value("graphics", "quality", gfx_quality))
		fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
		mouse_sens = float(cfg.get_value("controls", "mouse_sens", 1.0))
		invert_y = bool(cfg.get_value("controls", "invert_y", false))
		fov = float(cfg.get_value("controls", "fov", 70.0))
		keybinds = cfg.get_value("controls", "keybinds", {})
		show_tips = bool(cfg.get_value("game", "show_tips", true))
		last_slot = int(cfg.get_value("game", "last_slot", 1))
		seen_tips = cfg.get_value("game", "seen_tips", [])
	apply_gfx()
	for b in volumes:
		set_volume(b, volumes[b])


# --------------------------------------------------------------------------
# streams
# --------------------------------------------------------------------------

func _stream(path: String, loop := false) -> AudioStream:
	var key := path + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		push_warning("Sound missing: " + path)
		_cache[key] = null
		return null
	var s: AudioStream = load(path)
	if loop:
		s = s.duplicate()
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


func sfx_stream(name: String, loop := false) -> AudioStream:
	return _stream(SFX_DIR + name + ".wav", loop)


# --------------------------------------------------------------------------
# one-shots
# --------------------------------------------------------------------------

## Non-positional sound. `min_gap` throttles rapid repeats of the same name.
func play(name: String, vol_db := 0.0, pitch_rand := 0.06, bus := "SFX", min_gap := 0.03) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(name, -1.0)) < min_gap:
		return
	_last_play[name] = now
	var s := sfx_stream(name)
	if s == null:
		return
	var p := _free_player(_pool2d)
	p.stream = s
	p.bus = bus
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + randf_range(-pitch_rand, pitch_rand)
	p.play()


func ui(name := "ui_click", vol_db := -4.0) -> void:
	play(name, vol_db, 0.03, "UI", 0.02)


## Positional sound in the 3D world.
func play_3d(name: String, pos: Vector3, vol_db := 0.0, pitch_rand := 0.08, unit_size := 14.0) -> void:
	var s := sfx_stream(name)
	if s == null:
		return
	var p: AudioStreamPlayer3D = _free_player(_pool3d)
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.unit_size = unit_size
	p.pitch_scale = 1.0 + randf_range(-pitch_rand, pitch_rand)
	p.play()


func _free_player(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	# steal the one closest to finishing
	var best = pool[0]
	var best_left := INF
	for p in pool:
		var left: float = p.stream.get_length() - p.get_playback_position() if p.stream else 0.0
		if left < best_left:
			best_left = left
			best = p
	return best


# --------------------------------------------------------------------------
# loops
# --------------------------------------------------------------------------

func loop_start(key: String, name: String, vol_db := 0.0, bus := "SFX", fade := 0.15) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p and p.playing and p.get_meta("name", "") == name:
		p.set_meta("target_db", vol_db)
		return
	if p == null:
		p = AudioStreamPlayer.new()
		add_child(p)
		_loops[key] = p
	p.stream = sfx_stream(name, true)
	p.bus = bus
	p.set_meta("name", name)
	p.set_meta("target_db", vol_db)
	p.volume_db = SILENT_DB if fade > 0.0 else vol_db
	p.play()
	if fade > 0.0:
		var t := p.create_tween()
		t.tween_property(p, "volume_db", vol_db, fade)


func loop_stop(key: String, fade := 0.2) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null or not p.playing:
		return
	p.set_meta("name", "")
	var t := p.create_tween()
	t.tween_property(p, "volume_db", SILENT_DB, fade)
	t.tween_callback(p.stop)


func loop_set(key: String, vol_db: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p and p.playing:
		p.volume_db = vol_db
		p.pitch_scale = pitch


func stop_all_loops() -> void:
	for k in _loops:
		loop_stop(k, 0.3)


# --------------------------------------------------------------------------
# music
# --------------------------------------------------------------------------

func play_music(track: String, fade := 2.5) -> void:
	if track == _music_current:
		return
	_music_current = track
	var s := _stream(MUSIC_DIR + track + ".ogg", true)
	var old := _music_active
	var new := _music_b if _music_active == _music_a else _music_a
	_music_active = new
	new.stream = s
	new.volume_db = SILENT_DB
	new.play()
	var target := _music_level()
	var t := create_tween().set_parallel()
	_fade(t, new, SILENT_DB, target, fade)
	if old.playing:
		_fade(t, old, old.volume_db, SILENT_DB, fade)
		t.chain().tween_callback(old.stop)


func music_for_biome(biome: String) -> String:
	return BIOME_MUSIC.get(biome, "verdant")


func _music_level() -> float:
	return -14.0 if _combat_on else 0.0


## Crossfade the combat layer in/out. Call every frame or on change.
func set_combat(active: bool) -> void:
	if active:
		_combat_off_timer = 5.0
		if _combat_on:
			return
		_combat_on = true
		if not _combat.playing:
			_combat.stream = _stream(MUSIC_DIR + "combat.ogg", true)
			_combat.volume_db = SILENT_DB
			_combat.play()
		var t := create_tween().set_parallel()
		_fade(t, _combat, _combat.volume_db, -2.0, 0.8)
		_fade(t, _music_active, _music_active.volume_db, -14.0, 0.8)
	elif _combat_on:
		pass # handled by the cooldown in _process


func _process(delta: float) -> void:
	if _combat_on:
		_combat_off_timer -= delta
		if _combat_off_timer <= 0.0:
			_combat_on = false
			var t := create_tween().set_parallel()
			_fade(t, _combat, _combat.volume_db, SILENT_DB, 3.0)
			_fade(t, _music_active, _music_active.volume_db, 0.0, 3.0)
			t.chain().tween_callback(func():
				if not _combat_on:
					_combat.stop()
			)


func stop_combat_now() -> void:
	_combat_off_timer = 0.0


## Equal-power fade: interpolate amplitude along a sine curve, not decibels,
## so crossfades don't dip in the middle.
func _fade(t: Tween, p: AudioStreamPlayer, from_db: float, to_db: float, dur: float) -> void:
	var a := db_to_linear(from_db) if from_db > SILENT_DB else 0.0
	var b := db_to_linear(to_db) if to_db > SILENT_DB else 0.0
	t.tween_method(func(k: float):
		var e := sin(k * PI * 0.5) if b > a else cos((1.0 - k) * PI * 0.5)
		var amp := lerpf(a, b, e)
		p.volume_db = linear_to_db(maxf(amp, 0.00001))
	, 0.0, 1.0, dur)



func apply_gfx() -> void:
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(gfx_quality, 0, 2)]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if gfx_quality == 0 else Viewport.SCREEN_SPACE_AA_DISABLED



# --------------------------------------------------------------------------
# settings: display + controls
# --------------------------------------------------------------------------

const REBINDABLE := [
	["move_forward", "Forward / thrust"], ["move_back", "Back / brake"], ["move_left", "Left"], ["move_right", "Right"],
	["jump", "Jump / jetpack / rise"], ["sprint", "Sprint / boost"], ["descend", "Descend"], ["interact", "Interact / land"],
	["scan", "Scan"], ["ability", "Ability / dock"], ["weapon_cycle", "Swap weapon"], ["use_cell", "Energy cell"],
	["repair", "Repair kit"], ["takeoff", "Take off / emergency lift"], ["orbit", "Hold orbit (probe)"], ["inventory", "Cargo"], ["crafting", "Fabricator"],
	["skills", "Professions"], ["quests", "Quest log"], ["map", "Map"], ["help", "Field manual"],
]


func apply_display() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


## Called once input actions exist: apply saved rebinds.
func apply_keybinds() -> void:
	for action in keybinds:
		_set_key(action, int(keybinds[action]))


func rebind(action: String, keycode: int) -> void:
	keybinds[action] = keycode
	_set_key(action, keycode)
	save_settings()


func reset_keybinds() -> void:
	keybinds = {}
	save_settings()


func _set_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var k := InputEventKey.new()
	k.physical_keycode = keycode
	InputMap.action_add_event(action, k)


func key_name(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	return "-"


func look_delta(rel: Vector2) -> Vector2:
	return Vector2(rel.x, rel.y * (-1.0 if invert_y else 1.0)) * mouse_sens


## One-time contextual tip. Returns true the first time.
func tip_once(id: String) -> bool:
	if not show_tips or seen_tips.has(id):
		return false
	seen_tips.append(id)
	save_settings()
	return true



## Muffle everything but the interface while the camera is underwater.
var _underwater := false
func set_underwater(on: bool) -> void:
	if on == _underwater:
		return
	_underwater = on
	for b in ["SFX", "Ambience", "Music"]:
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			continue
		var fx_i := -1
		for i in AudioServer.get_bus_effect_count(idx):
			if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
				fx_i = i
		if fx_i < 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 900.0
			AudioServer.add_bus_effect(idx, lp)
			fx_i = AudioServer.get_bus_effect_count(idx) - 1
		AudioServer.set_bus_effect_enabled(idx, fx_i, on)
