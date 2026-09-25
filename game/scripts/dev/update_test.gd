extends Node
## Headless check of the self-updater against a fake GitHub release served from
## a local python http.server: version compare, notes, check, download, the
## in-place swap of a stand-in app bundle, cleanup on the next launch, and the
## failure paths (404, translocated copy). Never touches the real game.

const PORT := 47863
var _server := -1
var _dir := ""


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _fake_app(root: String, marker: String) -> String:
	var app := root.path_join("Star Circuit.app")
	_write(app.path_join("Contents/Info.plist"), marker)
	_write(app.path_join("Contents/MacOS/Star Circuit"), "#!/bin/sh\n")
	return app


func _olds(dir: String) -> int:
	var d := DirAccess.open(dir)
	d.include_hidden = true
	return Array(d.get_directories()).filter(func(n): return ".old" in n).size()


func _run() -> void:
	# version compare
	var ok := Updater.is_newer("v0.4.0", "0.3.0") and Updater.is_newer("0.10.0", "0.9.9") and not Updater.is_newer("v0.3.0", "0.3.0") \
		and not Updater.is_newer("0.2.9", "0.3.0") and Updater.is_newer("1.0.0-beta", "0.9")
	print("[update] compare ", "ok" if ok else "FAIL")
	var bb := UpdatePanel._notes_bbcode("## v9\n### Combat\n- **Titans** are [here](https://x.y).\n  - nested [thing]")
	print("[update] notes ", "ok" if "[b]Titans[/b]" in bb and "[url=https://x.y]here[/url]" in bb and "[lb]thing[rb]" in bb else "FAIL " + bb.replace("\n", " | "))

	if Updater.platform() != "macOS":
		print("[update] skipped install test (macOS only)")
		get_tree().quit()
		return
	_dir = ProjectSettings.globalize_path("user://update_test")
	OS.execute("/bin/rm", ["-rf", _dir])
	# the new release: a stand-in app zipped like the real export
	var build := _dir.path_join("build")
	_fake_app(build, "NEW 9.9.9")
	var srv := _dir.path_join("srv")
	DirAccess.make_dir_recursive_absolute(srv)
	OS.execute("/usr/bin/ditto", ["-c", "-k", "--keepParent", build.path_join("Star Circuit.app"), srv.path_join("StarCircuit-macOS.zip")])
	var size := FileAccess.get_file_as_bytes(srv.path_join("StarCircuit-macOS.zip")).size()
	var base := "http://127.0.0.1:%d/" % PORT
	_write(srv.path_join("latest.json"), JSON.stringify({"tag_name": "v9.9.9", "html_url": base, "body": "## v9.9.9\n- New things.",
		"assets": [{"name": "StarCircuit-Windows.zip", "browser_download_url": base + "nope.zip", "size": 1},
			{"name": "StarCircuit-macOS.zip", "browser_download_url": base + "StarCircuit-macOS.zip", "size": size}]}))
	_write(srv.path_join("old.json"), JSON.stringify({"tag_name": "v0.0.1", "assets": []}))
	_server = OS.create_process("python3", ["-m", "http.server", str(PORT), "--bind", "127.0.0.1", "--directory", srv])
	await _wait(1.5)

	# the "installed" game
	var app := _fake_app(_dir.path_join("install"), "OLD")
	OS.set_environment("STAR_CIRCUIT_UPDATE_TARGET", app)
	OS.set_environment("STAR_CIRCUIT_UPDATE_NO_RELAUNCH", "1")

	OS.set_environment("STAR_CIRCUIT_UPDATE_URL", base + "old.json")
	Updater.check()
	await _until(func(): return not Updater.busy())
	print("[update] older release -> %s has_update=%s" % [Updater.state, Updater.has_update()])

	OS.set_environment("STAR_CIRCUIT_UPDATE_URL", base + "missing.json")
	Updater.check()
	await _until(func(): return not Updater.busy())
	print("[update] missing -> %s (%s)" % [Updater.state, Updater.error])

	OS.set_environment("STAR_CIRCUIT_UPDATE_URL", base + "latest.json")
	Updater.check()
	await _until(func(): return not Updater.busy())
	print("[update] check -> %s latest=%s size=%d blocker='%s'" % [Updater.state, Updater.latest, Updater.asset_size, Updater.install_blocker()])

	OS.set_environment("STAR_CIRCUIT_UPDATE_TARGET", "/private/var/folders/x/AppTranslocation/ABC/d/Star Circuit.app")
	print("[update] translocated blocker ", "ok" if "Applications" in Updater.install_blocker() else "FAIL")
	OS.set_environment("STAR_CIRCUIT_UPDATE_TARGET", app)

	var saw_progress := false
	Updater.install()
	while Updater.busy():
		saw_progress = saw_progress or Updater.state == "downloading"
		await get_tree().process_frame
	var plist := FileAccess.get_file_as_string(app.path_join("Contents/Info.plist"))
	print("[update] installed -> %s swapped=%s old_kept=%s exec=%s" % [Updater.state, plist == "NEW 9.9.9", _olds(_dir.path_join("install")) == 1,
		FileAccess.file_exists(app.path_join("Contents/MacOS/Star Circuit"))])
	if Updater.state == "error":
		print("[update] error: ", Updater.error)

	# next launch: this binary is still 0.x, so it must not claim an update or delete anything
	Updater._cleanup_previous()
	var still := _olds(_dir.path_join("install"))
	print("[update] same-version relaunch just_updated='%s' old_kept=%s" % [Updater.just_updated, still == 1])
	# simulate the new version launching: it came from 0.0.1, so it cleans up
	Updater.install()
	await _until(func(): return not Updater.busy())
	print("[update] reinstall -> %s %s old_path=%s" % [Updater.state, Updater.error, FileAccess.get_file_as_string(Updater.work_dir.path_join("old_path.txt"))])
	var f := FileAccess.open(Updater.work_dir.path_join("updated_from.txt"), FileAccess.WRITE)
	f.store_string("0.0.1")
	f.close()
	Updater._cleanup_previous()
	var left := _olds(_dir.path_join("install"))
	print("[update] cleanup just_updated=%s old_removed=%s stage_gone=%s" % [Updater.just_updated, left == 0,
		not DirAccess.dir_exists_absolute(_dir.path_join("install/.star-circuit-update"))])

	OS.kill(_server)
	OS.execute("/bin/rm", ["-rf", _dir])
	get_tree().quit()


func _until(cond: Callable, limit := 15.0) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
