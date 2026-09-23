extends Node
## Windowed: average frame time on the home planet meadow for each quality.

func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for q in [2, 1, 0]:
		Sound.gfx_quality = q
		Sound.apply_gfx()
		Game.new_game("scout", "F")
		await get_tree().create_timer(5.0).timeout
		var w := get_tree().current_scene
		Game.invulnerable = true
		w.player.place_at(w._find_land(Vector3(0.5, 0.35, 0.8).normalized()), w.gen)
		w.player.cam_yaw = 0.6
		await get_tree().create_timer(2.0).timeout
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 4000000:
			await get_tree().process_frame
			frames += 1
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
		print("[fps] quality=%d  %.1f fps  (%.2f ms/frame)" % [q, 1000.0 / ms, ms])
	Sound.gfx_quality = 2
	get_tree().quit()
