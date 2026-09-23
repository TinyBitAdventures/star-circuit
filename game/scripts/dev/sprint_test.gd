extends Node
## Headless: measure ground speed walking vs sprinting.

func _ready() -> void:
	_go.call_deferred()


func _speed_over(p, sec: float) -> float:
	var a: Vector3 = p.global_position
	await get_tree().create_timer(sec).timeout
	return a.distance_to(p.global_position) / sec


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("miner", "S")
	await get_tree().create_timer(5.0).timeout
	var w := get_tree().current_scene
	var p = w.player
	for e in w.enemies:
		e.set_physics_process(false)
	for trial in 4:
		var d: Vector3 = w._find_land(Vector3(cos(trial * 1.7), 0.4 - trial * 0.2, sin(trial * 1.7)).normalized())
		p.place_at(d, w.gen)
		p.cam_yaw = trial * 1.3
		await get_tree().create_timer(0.5).timeout
		Input.action_press("move_forward")
		await get_tree().create_timer(0.8).timeout
		var walk: float = await _speed_over(p, 1.0)
		Input.action_press("sprint")
		await get_tree().create_timer(0.8).timeout
		var run: float = await _speed_over(p, 1.0)
		var floor_frac := 0
		for i in 30:
			await get_tree().physics_frame
			if p.is_on_floor():
				floor_frac += 1
		var hits := []
		for ci in p.get_slide_collision_count():
			var c: KinematicCollision3D = p.get_slide_collision(ci)
			var col = c.get_collider()
			var slope: float = rad_to_deg(acos(clampf(c.get_normal().dot(p.global_position.normalized()), -1, 1)))
			hits.append("%s(%s) slope=%.0f" % [col.name if col else "?", col.get_class() if col else "", slope])
		print("[sprint]   collisions: ", hits)
		print("[sprint] trial %d walk=%.2f run=%.2f on_floor %d/30 hv=%.2f" % [trial, walk, run, floor_frac, (p.velocity - p.global_position.normalized() * p.velocity.dot(p.global_position.normalized())).length()])
		Input.action_release("sprint")
		Input.action_release("move_forward")
	get_tree().quit()
