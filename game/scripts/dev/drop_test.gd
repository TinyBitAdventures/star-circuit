extends Node
func _ready() -> void:
	_go.call_deferred()
func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("scout", "D")
	await get_tree().create_timer(4.0).timeout
	Game.arriving_from_space = true
	Game.land_dir = Vector3(0.5, 0.4, 0.7).normalized()
	Game.go_to_planet(0, 0)
	await get_tree().create_timer(2.2).timeout
	var w := get_tree().current_scene
	for i in 10:
		var p = w.player
		var up: Vector3 = p.global_position.normalized()
		print("[drop] t=%.1f alt=%.1f dropping=%s spring=%.1f" % [i * 0.5, p.global_position.length() - w.gen.surface_radius(up), p._dropping, p.spring.spring_length])
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
