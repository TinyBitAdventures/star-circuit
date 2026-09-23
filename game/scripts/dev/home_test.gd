extends Node
## Headless check of the Homespace: open/close from a planet and a cave,
## vault deposit/withdraw with uplink costs, inbox claims, trader orders.

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
	Game.new_game("miner", "Home")
	await _wait(4.0)
	print("[home] inbox=", Game.inbox.size(), " unread=", Game.unread_mail(), " first=", Game.inbox[0].subject)
	Game.add_item("ferrite", 40, true)
	Game.open_home()
	await _wait(1.0)
	var home: Node = null
	for c in get_tree().root.get_children():
		if c.has_method("leave"):
			home = c
	print("[home] open=", home != null, " paused=", get_tree().paused, " in_home=", Game.in_home, " music=", Sound._music_current)
	var sig: Dictionary = Game.uplink_signal()
	var e0 := Game.energy
	var moved := Game.vault_deposit("ferrite", 30)
	print("[home] signal=", sig.strength, " (", sig.label, ") deposited=", moved, " energy ", snappedf(e0, 0.1), "->", snappedf(Game.energy, 0.1), " vault=", Game.vault, " hold ferrite=", Game.count("ferrite"))
	var back := Game.vault_withdraw("ferrite", 5)
	print("[home] withdrew=", back, " vault=", Game.vault, " hold ferrite=", Game.count("ferrite"))
	var cr0 := Game.credits
	Game.mail_claim(int(Game.inbox[0].id), true)
	print("[home] claimed welcome: credits ", cr0, "->", Game.credits, " vault=", Game.vault)
	# a trader order arrives and is filled from the vault
	Game.visited_towns.append("0:0")
	Game._order_t = 0.0
	Game._update_orders(0.1)
	var order: Dictionary = {}
	for m in Game.inbox:
		if m.kind == "order":
			order = m
	print("[home] order=", order.get("subject", "none"), " ", order.get("order", {}))
	if not order.is_empty():
		var o: Dictionary = order.order
		Game.vault[o.item] = int(o.qty)
		var cr1 := Game.credits
		var ok := Game.order_fulfill(int(order.id))
		print("[home] filled=", ok, " credits ", cr1, "->", Game.credits, " vault left=", Game.vault_count(o.item))
	# panels build without errors
	home._open_panel("vault")
	await _wait(0.2)
	home._open_panel("inbox")
	await _wait(0.2)
	home._open_panel("trophy")
	await _wait(0.2)
	home.leave()
	await _wait(1.5)
	print("[home] after leave paused=", get_tree().paused, " in_home=", Game.in_home, " music=", Sound._music_current)
	# the signal is weaker underground
	var pw := get_tree().current_scene
	for p in pw.pois:
		if p.type == "cave":
			p.open_cache()
			break
	await _wait(3.5)
	print("[home] in ", get_tree().current_scene.name, " signal=", Game.uplink_signal().strength, " cost/unit=", snappedf(Game.uplink_cost(1), 0.01))
	Game.open_home()
	await _wait(0.8)
	print("[home] opened in cave paused=", get_tree().paused)
	for c in get_tree().root.get_children():
		if c.has_method("leave"):
			c.leave()
	await _wait(1.5)
	print("[home] cave after leave paused=", get_tree().paused, " scene=", get_tree().current_scene.name)
	Game.save_game()
	var ok2 := Game.load_game(Game.slot)
	print("[home] reload ok=", ok2, " vault=", Game.vault, " inbox=", Game.inbox.size())
	get_tree().quit()
