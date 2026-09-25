extends Node
## Headless check of combat: statuses (burn, chill, freeze, shock) on drones and
## on the player, and the drone behaviours (melee, ranged, slam).


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## A point on the surface this many metres from the player, off to one side.
func _near(w: Node3D, metres: float, side := 0.0) -> Vector3:
	var up: Vector3 = w.player.global_position.normalized()
	var b := PlanetGen.align_basis(up, side)
	return (up + b.z * metres / w.gen.radius).normalized()


func _clear(w: Node3D) -> void:
	for e in w.enemies.duplicate():
		w.enemies.erase(e)
		e.queue_free()


func _run() -> void:
	Sound.show_tips = false
	Game.new_game("miner", "Combat")
	await _wait(4.0)
	var w := get_tree().current_scene
	_clear(w)
	await _wait(0.2)
	Game.invulnerable = true

	# burn: 10 a second for 3 seconds
	var a: Enemy = w._spawn_enemy("brute", 5, _near(w, 30.0), 900)
	var hp0 := a.hp
	a.apply_status("burn", 3.0, 10.0)
	await _wait(3.3)
	print("[combat] burn: hp %d -> %d (want about -30) burning=%s" % [hp0, a.hp, a.status.burning()])

	# shock: +25% damage taken
	a.apply_status("shock", 2.0)
	var h1 := a.hp
	a.take_hit(40.0)
	print("[combat] shock: took %d from a 40 hit (want 50)" % int(h1 - a.hp))
	_clear(w)
	await _wait(0.2)

	# chill slows, a fourth stack freezes, then a short immunity
	var fast: Enemy = w._spawn_enemy("scrapper", 3, _near(w, 18.0, 0.0), 901)
	var slow: Enemy = w._spawn_enemy("scrapper", 3, _near(w, 18.0, PI), 902)
	fast.aggro()
	slow.aggro()
	slow.apply_status("chill", 5.0, 3.0)
	var f0 := fast.global_position
	var s0 := slow.global_position
	await _wait(1.0)
	var fd := fast.global_position.distance_to(f0)
	var sd := slow.global_position.distance_to(s0)
	print("[combat] chill x%d: moved %.1f vs %.1f m (ratio %.2f, want about %.2f)" % [slow.status.chill, sd, fd, sd / maxf(fd, 0.01), slow.status.speed_mult()])
	var got := slow.apply_status("chill", 5.0, 1.0)
	var p0 := slow.global_position
	await _wait(1.0)
	print("[combat] freeze: got=%s frozen=%s moved %.2f m while frozen" % [got, slow.status.frozen(), slow.global_position.distance_to(p0)])
	await _wait(0.8)
	var again := slow.apply_status("chill", 5.0, 4.0)
	print("[combat] thawed: frozen=%s refreeze right away=%s" % [slow.status.frozen(), again == "freeze"])
	# leashing clears it all
	slow.apply_status("burn", 5.0, 1.0)
	slow._leash()
	print("[combat] leash clears: any=%s" % slow.status.any())
	_clear(w)
	await _wait(0.2)

	# the player: chilled, frozen (briefly), burning
	var pl: Node3D = w.player
	Game.invulnerable = false
	Game.hull = Game.max_hull()
	w.damage_player(1.0, null, "chill", 4.0, 2.0)
	print("[combat] player chill: stacks=%d speed x%.2f hud='%s'" % [pl.status.chill, pl.status.speed_mult(), w.hud.effects_label.text])
	w.damage_player(1.0, null, "chill", 4.0, 2.0)
	var frozen_for: float = pl.status.frozen_t
	print("[combat] player freeze: frozen=%s for %.2fs (drones get %.1fs)" % [pl.status.frozen(), frozen_for, Status.FREEZE_TIME])
	await _wait(1.3)
	print("[combat] player thawed=%s" % (not pl.status.frozen()))
	var hull0 := Game.hull
	w.damage_player(0.0, null, "burn", 2.0, 10.0)
	await _wait(2.3)
	print("[combat] player burn: hull %d -> %d (want about -20) hud visible=%s" % [hull0, Game.hull, w.hud.effects_label.visible])

	# the three drones still fight the way they did
	Game.hull = Game.max_hull()
	var sc: Enemy = w._spawn_enemy("scrapper", 1, _near(w, 5.0), 910)
	sc.aggro()
	await _wait(2.5)
	print("[combat] scrapper melee: hull %d -> %d" % [Game.max_hull(), Game.hull])
	_clear(w)
	Game.hull = Game.max_hull()
	var se: Enemy = w._spawn_enemy("sentinel", 1, _near(w, 14.0), 911)
	se.aggro()
	await _wait(4.0)
	print("[combat] sentinel bolts: hull %d -> %d" % [Game.max_hull(), Game.hull])
	_clear(w)
	Game.hull = Game.max_hull() * 3.0
	var br: Enemy = w._spawn_enemy("brute", 1, _near(w, 3.0), 912)
	br.aggro()
	var raised := false
	for i in 40:
		await _wait(0.1)
		raised = raised or br.behavior.raised()
	print("[combat] brute slam: raised=%s hull %d -> %d" % [raised, Game.max_hull() * 3.0, Game.hull])
	_clear(w)
	get_tree().quit()
