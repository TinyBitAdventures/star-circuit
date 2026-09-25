extends Node
## Headless check of safe saves: temp-then-rename with a .bak of the last good
## save, a damaged save restored from the backup (or a temp file a crash left),
## no backup at all, saving on window close, and deleting a slot. Uses the dev
## save file only.


func _ready() -> void:
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _path(ext := "") -> String:
	return ProjectSettings.globalize_path(Game.slot_path(1)) + ext


func _corrupt(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"robot_id\": \"scout\", \"lev")
	f.close()


func _run() -> void:
	Sound.show_tips = false
	Game.delete_slot(1)
	Game.new_game("miner", "Saver", 1)
	await _wait(4.0)
	Game.credits = 1234
	Game.save_game()
	var bak := Game._read_save(_path(".bak"))
	print("[save] write: main ok=", not Game._read_save(_path()).is_empty(), " bak after 2nd=", not bak.is_empty(), " tmp left=", FileAccess.file_exists(_path(".tmp")))

	# a damaged save loads the backup
	Game.credits = 5555
	Game.save_game() # main 5555, bak 1234
	_corrupt(_path())
	var d := Game.save_summary(1)
	print("[save] damaged: flagged=", d.get("damaged", false), " backup credits=", int(d.get("backup", {}).get("credits", -1)))
	var ok := Game.load_game(1)
	await _wait(4.5)
	print("[save] restored: loaded=", ok, " credits=", Game.credits, " (want 1234) damaged kept=", FileAccess.file_exists(_path(".damaged")), " main ok=", not Game._read_save(_path()).is_empty())

	# a crash between the renames: the main file is gone, the temp file is newest
	Game.credits = 7777
	Game.save_game()
	var txt := FileAccess.get_file_as_string(_path())
	DirAccess.remove_absolute(_path())
	var f := FileAccess.open(_path(".tmp"), FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	var d2 := Game.save_summary(1)
	Game.load_game(1)
	await _wait(4.5)
	print("[save] crash recovery: flagged=", d2.get("damaged", false), " credits=", Game.credits, " (want 7777) tmp gone=", not FileAccess.file_exists(_path(".tmp")))

	# nothing to fall back on
	DirAccess.remove_absolute(_path(".bak"))
	_corrupt(_path())
	var d3 := Game.save_summary(1)
	var ok3 := Game.load_game(1)
	print("[save] no backup: flagged=", d3.get("damaged", false), " backup empty=", (d3.get("backup", {}) as Dictionary).is_empty(), " load refused=", not ok3, " has_save=", Game.has_save())

	# closing the window saves
	Game.load_game(1) # still damaged: start fresh instead
	Game.delete_slot(1)
	Game.new_game("miner", "Saver", 1)
	await _wait(4.0)
	Game.credits = 4242
	Game.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	print("[save] close saves: credits on disk=", int(Game._read_save(_path()).get("credits", -1)), " (want 4242)")

	Game.delete_slot(1)
	var left := 0
	for ext in ["", ".bak", ".tmp", ".damaged"]:
		if FileAccess.file_exists(_path(ext)):
			left += 1
	print("[save] delete: files left=", left, " summary empty=", Game.save_summary(1).is_empty())
	get_tree().quit()
