extends Node
## Headless UI checks: compact node labels, renaming your robot, and the
## trade list keeping its scroll position while you sell one at a time.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _run() -> void:
	Sound.show_tips = false
	Game.new_game("scout", "S")
	await _wait(4.0)
	var pw := get_tree().current_scene
	# node labels: one line, "Name  L15"
	for n in pw._nodes:
		if is_instance_valid(n):
			n.reveal(5.0)
			print("[ui] label='", n._label.text, "'")
			break
	# rename
	print("[ui] rename empty -> '", Game.rename("   "), "' name=", Game.player_name)
	print("[ui] rename -> '", Game.rename("  Austin-7  "), "' name=", Game.player_name, " hud=", pw.hud.find_children("*", "Label", true, false).any(func(l): return l.text == "Austin-7"))
	# selling keeps the list where it was
	for it in ["ferrite", "cobalt", "lumen", "biofiber", "sporegel", "plasma", "nickel", "cryo_ice", "stardust", "kelp", "obsidian", "glowcap", "scrap", "alloy", "circuit", "polymer", "fossil", "sea_pearl"]:
		Game.add_item(it, 20, true, true)
	var hud = pw.hud
	hud._trade_tab = "sell"
	hud._town_planet = Galaxy.planet(0, 0)
	hud.toggle_panel("trade")
	await _wait(0.5)
	var sc: ScrollContainer = hud._panel.find_children("*", "ScrollContainer", true, false)[0]
	sc.scroll_vertical = 400
	await _wait(0.2)
	var before := sc.scroll_vertical
	var fe := Game.count("fossil")
	Game.sell("fossil", 1, hud._town_planet)
	await _wait(0.4)
	var sc2: ScrollContainer = hud._panel.find_children("*", "ScrollContainer", true, false)[0]
	print("[ui] sell: fossil ", fe, " -> ", Game.count("fossil"), " rebuilt=", sc2 != sc, " scroll ", before, " -> ", sc2.scroll_vertical)
	get_tree().quit()
