extends Node
func _ready() -> void:
	_go.call_deferred()
func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout
func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("scout", "S")
	await _w(4.0)
	Game.go_to_space()
	await _w(4.0)
	var s := get_tree().current_scene
	var pidx := int(OS.get_environment("PIDX")) if OS.get_environment("PIDX") != "" else 2
	for trial in 4:
		s = get_tree().current_scene
		s.land_at_town(s.planets[pidx])
		await _w(7.0)
		var w := get_tree().current_scene
		var p = w.player
		Game.invulnerable = true
		print("[s2] trial %d arrived: pos finite=%s vel=%s dropping=%s on_floor=%s alt=%.2f" % [trial, p.global_position.is_finite(), p.velocity, p._dropping, p.is_on_floor(), p.global_position.length() - w.gen.surface_radius(p.global_position.normalized())])
		var stuck_t := 0.0
		for i in 120:
			p.cam_yaw = randf() * TAU
			var st: Vector3 = p.global_position
			Input.action_press("move_forward")
			await _w(0.3)
			Input.action_release("move_forward")
			if st.distance_to(p.global_position) < 0.3:
				stuck_t += 0.3
				if stuck_t > 1.5:
					for ci in p.get_slide_collision_count():
						var c: KinematicCollision3D = p.get_slide_collision(ci)
						var col = c.get_collider()
						var up: Vector3 = p.global_position.normalized()
						var own = col.shape_owner_get_owner(col.shape_find_owner(c.get_collider_shape_index())) if col is CollisionObject3D else null
						print("[s2]    hit %s parent=%s shape=%s normal.up=%.2f dist_from_centre=%.1f depth=%.3f" % [col.name, col.get_parent().name, own.shape.get_class() if own else "?", c.get_normal().dot(up), p.global_position.distance_to(w.town.centre), c.get_depth()])
					print("[s2]  STUCK at step %d pos=%s vel=%s basis_ok=%s dropping=%s floor=%s" % [i, p.global_position, p.velocity, p.global_basis.x.is_finite(), p._dropping, p.is_on_floor()])
					break
			else:
				stuck_t = 0.0
		p._start_launch()
		var y0: float = p.global_position.length()
		await _w(1.0)
		print("[s2]  launch rise=%.2f" % (p.global_position.length() - y0))
		await _w(5.0)
	get_tree().quit()
