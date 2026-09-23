extends Node
## Scripted session for audio verification. Record with Movie Maker:
##   godot --path . --write-movie /tmp/tour.avi --fixed-fps 30 res://scenes/dev_audio.tscn
## Prints a timeline of events so the recording can be checked against it.

var t0 := 0

func _ready() -> void:
	_go.call_deferred()


func _mark(what: String) -> void:
	print("[audio] %6.2f %s" % [(Time.get_ticks_msec() - t0) / 1000.0, what])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	t0 = Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	_mark("menu music")
	await _wait(4.0)
	Sound.ui()
	_mark("ui click")
	await _wait(1.0)
	Game.new_game("miner", "Audio")
	_mark("new game -> planet")
	await _wait(5.0)
	var w := get_tree().current_scene
	var p = w.player
	_mark("walk (footsteps)")
	Input.action_press("move_forward")
	await _wait(2.0)
	Input.action_release("move_forward")
	_mark("jump + jet")
	Input.action_press("jump")
	await _wait(1.5)
	Input.action_release("jump")
	await _wait(1.5)
	_mark("scan")
	p._scan()
	await _wait(2.0)
	_mark("harvest node")
	var n: ResourceNode = null
	for c in w._nodes:
		if c.node_type == "ferrite":
			n = c
			break
	p.place_at(n.global_position.normalized(), w.gen)
	await _wait(0.5)
	p._harvest_sound("mining")
	await _wait(1.5)
	p._harvest_sound("")
	n.interact(p)
	await _wait(1.5)
	_mark("fight")
	var e: Enemy = w.enemies[0]
	p.place_at((e.home_dir + (p.global_position.normalized() - e.home_dir).normalized() * 12.0 / w.gen.radius).normalized(), w.gen)
	await _wait(2.5)
	for i in 8:
		Sound.play("blaster", -7.0, 0.1, "SFX", 0.0)
		if is_instance_valid(e) and e.is_alive():
			e.take_hit(Game.weapon_damage())
			Sound.play_3d("hit", e.global_position, -8.0)
		await _wait(0.26)
	p.ability_cd = 0.0
	p._use_ability(p.global_position.normalized())
	await _wait(3.0)
	_mark("open crafting panel")
	w.hud.toggle_panel("crafting")
	await _wait(1.0)
	w.hud.close_panel()
	await _wait(1.0)
	_mark("takeoff")
	Game.last_hit_time = -100.0
	p._start_launch()
	await _wait(6.0)
	_mark("space: thrust + boost")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(3.0)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(2.0)
	_mark("end")
	get_tree().quit()
