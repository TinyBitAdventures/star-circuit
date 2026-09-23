extends Node
## Headless end-to-end test of the Deep: cave -> dig -> chamber -> grotto -> back.

func _ready() -> void:
	_go.call_deferred()


func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("miner", "Dig")
	await _w(5.0)
	var w := get_tree().current_scene
	var cave: Poi = null
	for p in w.pois:
		if p.type == "cave":
			cave = p
			break
	print("[dig] caves on Cradle: ", w.pois.filter(func(p): return p.type == "cave").size(), "  dist from spawn: ", int(cave.global_position.distance_to(w.player.global_position)))
	w.player.place_at(cave.dir, w.gen)
	await _w(0.5)
	print("[dig] prompt at cave: ", w.hud.prompt_label.text)
	cave.open_cache()
	await _w(3.0)
	var d := get_tree().current_scene
	print("[dig] scene=", d.name, " grid=", d.W, "x", d.H, " chambers=", d.chambers.size(), " themes=", d.chambers.map(func(c): return c.theme))
	var counts := {}
	for c in d.cells:
		counts[c] = counts.get(c, 0) + 1
	print("[dig] air=", counts.get(0, 0), " ore cells=", counts.keys().filter(func(k): return k >= 32).map(func(k): return "%s:%d" % [d.ORES[k - 32].item, counts[k]]))
	var pod: DigPod = d.pod
	var y0 := pod.position.y
	Input.action_press("move_back")
	await _w(6.0)
	Input.action_release("move_back")
	print("[dig] drilled down: depth ", int((pod.position.y - y0) / d.CS), " cells, energy=", int(Game.energy), " quest=", Game.current_quest().get("id"), " inv=", Game.inventory)
	Input.action_press("move_right")
	await _w(2.0)
	Input.action_release("move_right")
	print("[dig] drilled sideways to x=", int(pod.position.x / d.CS))
	# teleport next to the first chamber and walk in
	var ch: Dictionary = d.chambers[0]
	pod.position = ch.centre + Vector2(0, -8)
	await _w(0.5)
	print("[dig] chamber prompt: ", d.hud.prompt_label.text)
	d.save_dug()
	Game.enter_chamber(ch, pod.position)
	await _w(3.0)
	var g := get_tree().current_scene
	print("[dig] grotto scene=", g.name, " theme=", g.theme, " interactables=", g._interactables.size(), " critters=", g.critters.size(), " chambers found=", Game.dig_state(Game.cave.key).chambers)
	var ped: Node = null
	for n in g._interactables:
		if n is RelicPedestal:
			ped = n
	if ped:
		ped.interact(g.player)
		print("[dig] relic taken, relics_found=", Game.relics_found, " inv relic=", Game.count(ped.item))
	g.scan(g.player.global_position, 60.0)
	print("[dig] cave species scanned: ", Game.scanned.filter(func(k): return ":cave:" in k).size())
	Game.leave_chamber()
	await _w(3.0)
	d = get_tree().current_scene
	print("[dig] back in dig: ", d.name, " pod at chamber=", d.pod.position.distance_to(ch.centre) < 60.0, " dug cells restored=", Array(d.dug).count(1))
	d._exit_to_surface()
	await _w(6.0)
	w = get_tree().current_scene
	print("[dig] surfaced: ", w.name, " near cave=", int(w.player.global_position.distance_to(cave.global_position)) if is_instance_valid(cave) else -1)
	get_tree().quit()
