extends Node
## Renders consecutive frames of a ringed planet from a static camera and
## reports how many pixels change between frames (flicker detector).

func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	var target_star := -1
	var target_planet := -1
	for s in Galaxy.stars:
		for p in s.planets:
			if p.rings and target_star < 0:
				target_star = s.index
				target_planet = p.index
	print("[flicker] ringed planet at star ", target_star, " planet ", target_planet)
	Game.new_game("scout", "F")
	await get_tree().create_timer(4.0).timeout
	Game.star_index = target_star
	Game.planet_index = target_planet
	Game.arrived_by_warp = true
	Game.go_to_space()
	await get_tree().create_timer(4.0).timeout
	var w := get_tree().current_scene
	var pl: Dictionary = w.planets[target_planet]
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 6.0
	w.player.set_physics_process(false)
	w.player.global_position = pl.node.global_position + Vector3(0.3, 0.35, 1.0).normalized() * pl.radius * dist
	w.player.look_at(pl.node.global_position, Vector3.UP)
	w.player.snap_camera()
	w.hud.visible = false
	w.hud.root.visible = false
	await get_tree().create_timer(1.0).timeout
	var imgs := []
	for i in 6:
		await RenderingServer.frame_post_draw
		imgs.append(get_viewport().get_texture().get_image())
	var out := ProjectSettings.globalize_path("res://").path_join("../shots")
	DirAccess.make_dir_recursive_absolute(out)
	imgs[0].save_png(out.path_join("flicker_frame0_d%d.png" % int(dist)))
	var sz: Vector2i = imgs[0].get_size()
	for i in range(1, imgs.size()):
		var diff := Image.create(sz.x, sz.y, false, Image.FORMAT_RGB8)
		var changed := 0
		for y in range(0, sz.y, 2):
			for x in range(0, sz.x, 2):
				var a: Color = imgs[i - 1].get_pixel(x, y)
				var b: Color = imgs[i].get_pixel(x, y)
				var d := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				if d > 0.25:
					changed += 1
					diff.set_pixel(x, y, Color.WHITE)
		print("[flicker] frame %d->%d big-change pixels: %d" % [i - 1, i, changed])
		if i == 1:
			diff.save_png(out.path_join("flicker_diff_d%d.png" % int(dist)))
	get_tree().quit()
