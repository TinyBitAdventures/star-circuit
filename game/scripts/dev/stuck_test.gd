extends Node
## Hunts for spots where the player can't move (or can't lift off).

func _ready() -> void:
	_go.call_deferred()


func _w(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _overlaps(p) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(p.global_basis, p.global_position + p.global_basis.y * 0.95)
	q.exclude = [p.get_rid()]
	q.margin = 0.02
	var out := []
	for r in p.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c = r.collider
		var shp = c.shape_owner_get_owner(c.shape_find_owner(r.shape)) if c is CollisionObject3D else null
		out.append("%s/%s" % [c.name, shp.shape.get_class() if shp else "?"])
	return out


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Game.new_game("scout", "S")
	await _w(4.0)
	var pi := int(OS.get_environment("PLANET")) if OS.get_environment("PLANET") != "" else 2
	Game.land_dir = Vector3.ZERO
	Game.go_to_planet(0, pi)
	await _w(5.0)
	var w := get_tree().current_scene
	var p = w.player
	Game.invulnerable = true
	for e in w.enemies:
		e.set_physics_process(false)
	var centre: Vector3 = w.town.centre if w.town else p.global_position
	var cdir := centre.normalized()
	var b := PlanetGen.align_basis(cdir)
	print("[stuck] planet=", w.planet.name, " town=", w.planet.town.get("name", "-"))
	var stuck := 0
	var tested := 0
	for ring in [3.0, 7.0, 9.0, 11.0, 14.0, 18.0, 22.0, 26.0]:
		for k in 12:
			var a: float = k * TAU / 12.0 + ring
			var d: Vector3 = (cdir + (b.x * cos(a) + b.z * sin(a)) * ring / w.gen.radius).normalized()
			p.place_at(d, w.gen)
			await _w(0.35)
			tested += 1
			var moved := 0.0
			for dir in 8:
				p.cam_yaw = dir * TAU / 8.0
				var s: Vector3 = p.global_position
				Input.action_press("move_forward")
				await _w(0.25)
				Input.action_release("move_forward")
				moved = maxf(moved, s.distance_to(p.global_position))
			if moved < 0.4:
				stuck += 1
				var alt: float = p.global_position.length() - w.gen.surface_radius(p.global_position.normalized())
				print("[stuck] STUCK ring=%.0f k=%d alt=%.2f on_floor=%s overlaps=%s" % [ring, k, alt, p.is_on_floor(), _overlaps(p)])
				var y0: float = p.global_position.length()
				p._start_launch()
				await _w(0.8)
				print("[stuck]   launch rise=%.2f" % (p.global_position.length() - y0))
				p.launching = false
				p.set_physics_process(true)
	print("[stuck] tested=", tested, " stuck=", stuck)
	get_tree().quit()
