extends Node
## Headless check of the Micro Lab: formulas draw from hold + vault, the
## soup simulation reaches critical mass under autoplay (at 60 fps and at
## choppy 15 fps), an untended culture goes off with half the ingredients
## back, lab upgrades install with graded bonuses, the quest counts, the
## grade survives a save, and a balance sweep over every formula.

const MicroLab = preload("res://scripts/home/micro_lab.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_detach.call_deferred()


func _detach() -> void:
	var root := get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


## Run a culture headless to the end. Returns the lab.
func _sim(id: String, seed_: int, dt: float, auto := true, err := 0.0, rate := 0.45) -> Node:
	var lab = MicroLab.new()
	lab.manual = true
	lab.autoplay = auto
	lab.bot_error = err
	lab.bot_rate = rate
	lab.setup(id, seed_)
	var t := 0.0
	while lab.phase == "play" and t < 400.0:
		lab.step(dt)
		t += dt
	return lab


func _run() -> void:
	Sound.show_tips = false
	Game.new_game("engineer", "Lab")
	await _wait(3.0)
	# quest: jump to Primordial Soup
	for i in Db.QUESTS.size():
		if Db.QUESTS[i].id == "soup":
			Game.quest_index = i
	Game.quest_accepted = true
	Game.quest_progress = 0
	# ingredients split between the hold and the vault
	Game.add_item("biofiber", 2, true)
	Game.vault = {"biofiber": 10, "plasma": 5}
	var r := Db.lab_recipe("medic_culture")
	print("[lab] medic block='", Game.lab_block(r), "' have biofiber=", Game.lab_have("biofiber"), " plasma=", Game.lab_have("plasma"))
	Game.open_home()
	await _wait(1.0)
	var home: Node = null
	for c in get_tree().root.get_children():
		if c.has_method("leave"):
			home = c
	home._start_lab("medic_culture")
	await _wait(0.5)
	var lab = home._lab
	print("[lab] started=", lab != null, " paused=", get_tree().paused, " music=", Sound._music_current, " hold biofiber=", Game.count("biofiber"), " vault=", Game.vault)
	# let it run live for a moment (it processes while the tree is paused)
	lab.autoplay = true
	lab.bot_rate = 0.45
	var t0: float = lab.elapsed
	await _wait(2.0)
	print("[lab] live running: elapsed ", snappedf(t0, 0.1), "->", snappedf(lab.elapsed, 0.1), " cells=", lab.cells.size(), " strains=", lab.strains)
	lab.manual = true
	var steps := 0
	while lab.phase == "play" and steps < 20000:
		lab.step(1.0 / 60.0)
		steps += 1
	var kits0 := Game.count("repair_kit")
	print("[lab] 60fps: phase=", lab.phase, " grade=", lab.grade, " t=", int(lab.elapsed), "s merges=", lab.merges, " zapped=", lab.phages_zapped, " result='", lab.result.text, "' repair_kits=", kits0)
	print("[lab] quest done=", Game.quests_done().has("soup") if Game.has_method("quests_done") else "?", " progress=", Game.quest_progress, " quest now=", Game.current_quest().get("id", "done"))
	lab._close()
	await _wait(0.5)
	print("[lab] closed: home._lab=", home._lab, " music=", Sound._music_current, " panel=", home._panel_kind)
	# choppy frames: same outcome shape at 15 fps
	var l15 = _sim("medic_culture", 7, 1.0 / 15.0)
	print("[lab] 15fps: grade=", l15.grade, " t=", int(l15.elapsed), "s merges=", l15.merges)
	# nobody at the controls: the culture goes off, half comes back
	Game.inventory.erase("biofiber")
	Game.inventory.erase("plasma")
	var idle = _sim("medic_culture", 3, 1.0 / 30.0, false)
	print("[lab] idle: grade=", idle.grade, " t=", int(idle.elapsed), " result='", idle.result.text, "' biofiber back=", Game.count("biofiber"), " plasma back=", Game.count("plasma"))
	# a graded upgrade
	Game.skills["engineering"].level = 45
	var hull0 := Game.max_hull()
	Game.add_item("sea_pearl", 2, true)
	Game.add_item("fossil", 1, true)
	Game.add_item("polymer", 2, true)
	print("[lab] graft block='", Game.lab_block(Db.lab_recipe("hull_graft")), "' started=", Game.lab_start("hull_graft"))
	var lg = _sim("hull_graft", 11, 1.0 / 60.0)
	print("[lab] graft: grade=", lg.grade, " t=", int(lg.elapsed), "s installed=", Game.has_upgrade("hull_graft"), " hull ", hull0, "->", Game.max_hull(), " '", lg.result.text, "'")
	var res: Dictionary = Game.lab_finish("hull_graft", 2)
	print("[lab] graft regrown pristine: hull=", Game.max_hull(), " '", res.text, "' block now='", Game.lab_block(Db.lab_recipe("hull_graft")), "'")
	Game.save_game()
	Game.lab = {}
	Game.load_game(Game.slot)
	print("[lab] after reload: grade=", Game.lab_grade("hull_graft"), " runs=", Game.lab_state().runs, " hull=", Game.max_hull())
	# balance sweep: a sharp bot and a sloppy one over every formula
	for lr in Db.LAB_RECIPES:
		var line := "[lab] sweep %-16s mass=%d time=%d" % [lr.id, int(lr.mass), int(lr.time)]
		for prof in [[0.05, 0.45], [0.15, 0.8]]:
			var err: float = prof[0]
			var grades: Array[String] = []
			var times: Array[String] = []
			for s in 4:
				var l = _sim(lr.id, 100 + s, 1.0 / 30.0, true, err, float(prof[1]))
				grades.append(Db.LAB_GRADES[l.grade][0] if l.grade >= 0 else "x")
				times.append(str(int(l.elapsed)))
			line += "  %s %s (%s s)" % ["sharp" if err < 0.1 else "casual", "".join(grades), ",".join(times)]
		print(line)
	get_tree().quit()
