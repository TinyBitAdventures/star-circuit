extends Node
## Headless: does a raider actually pursue and shoot the player?

func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("scout", "P")
	await get_tree().create_timer(4.0).timeout
	Game.go_to_space()
	await get_tree().create_timer(4.0).timeout
	var s := get_tree().current_scene
	var sp = s.player
	sp.set_physics_process(false)
	Game.invulnerable = false
	var r: SpaceEnemy = s._spawn_pirate(OS.get_environment("PIRATE") if OS.get_environment("PIRATE") != "" else "raider", 2, sp.global_position + Vector3(0, 0, -150), sp.global_position)
	r.aggro()
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		var to: Vector3 = sp.global_position - r.global_position
		print("[pirate] t=%.1f state=%s dist=%.0f facing=%.2f vel=%.0f hull=%d" % [i * 0.5, r.state, to.length(), (-r.global_basis.z).dot(to.normalized()), r.velocity.length(), Game.hull])
	get_tree().quit()
