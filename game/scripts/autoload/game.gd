extends Node
## Player state, progression, inventory, quests, save/load and scene flow.

signal inventory_changed
signal energy_changed(value: float, max_value: float)
signal hull_changed
signal player_damaged(amount: float)
signal player_died
signal credits_changed
signal xp_changed
signal skill_changed(skill: String)
signal quest_changed
signal notify(text: String, color: Color)
signal big_notify(title: String, subtitle: String, color: Color)

const SAVE_PATH := "user://star_circuit_save.json"
const RESPAWN_SECONDS := 600

var robot_id := "scout"
var player_name := "Unit"
var level := 1
var xp := 0
var energy := 100.0
var hull := 100.0
var shield := 0.0
var invulnerable := false
var last_hit_time := -100.0
var kills := 0
var discovered_pois: Array = [] # "star:planet:idx"
var looted_pois: Array = []
var codex: Array = [] # lore indices
var surveyed: Array = [] # planet keys fully surveyed
var credits := 0
var skill_tiers := {} # skill -> tier index into Db.SKILL_TIERS
var bounties: Array = [] # accepted bounty dicts
var visited_towns: Array = []
var trader_bought := {} # "town_key:day" -> {item: qty bought}
var _cap_warned := {}
var appearance := {} # shell/accent/glow/flame colours (html) + head/top/pack/finish ids
var owned_cosmetics: Array = []
var weapon := "pulse"
var digs := {} # cave key -> {"dug": base64 bitmap, "chambers": [ids]}
var cave := {} # the cave we're currently in (not saved: caves always resume on the surface)
var relics_found := 0
var inventory := {}
var upgrades: Array = []
var skills := {}
var star_index := 0
var planet_index := 0
var location := "planet" # "planet" | "space"
var visited_planets: Array = []
var visited_stars: Array = [0]
var scanned: Array = []
var harvested := {} # planet_key -> {node_id: unix_time}
var quest_index := 0
var quest_accepted := false
var quest_progress := 0
var quest_baseline := 0
var play_time := 0.0
var land_dir := Vector3.ZERO # where on the planet to spawn next landing
var space_return_pos := Vector3.ZERO

var _fader: ColorRect
var _autosave_timer := 0.0
var in_game := false
var ui_open := false
var arrived_by_warp := false
var arriving_from_space := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input()
	_build_fader()
	_reset_state()


func _process(delta: float) -> void:
	if in_game and not get_tree().paused:
		play_time += delta
		_autosave_timer += delta
		if _autosave_timer > 60.0:
			_autosave_timer = 0.0
			save_game()


# --------------------------------------------------------------------------
# input map (defined in code so project.godot stays readable)
# --------------------------------------------------------------------------

func _register_input() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "descend": [KEY_CTRL, KEY_Z],
		"interact": [KEY_E], "scan": [KEY_Q], "use_cell": [KEY_R],
		"inventory": [KEY_I, KEY_TAB], "crafting": [KEY_C], "skills": [KEY_K],
		"quests": [KEY_J], "map": [KEY_M], "takeoff": [KEY_T], "help": [KEY_H, KEY_F1],
		"pause": [KEY_ESCAPE], "ability": [KEY_F], "repair": [KEY_G], "weapon_cycle": [KEY_X],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)
	if not InputMap.has_action("fire2"):
		InputMap.add_action("fire2")
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("fire2", mb2)


# --------------------------------------------------------------------------
# new game / derived stats
# --------------------------------------------------------------------------

func _reset_state() -> void:
	level = 1
	xp = 0
	inventory = {}
	upgrades = []
	skills = {}
	for s in Db.SKILLS:
		skills[s] = {"level": 1, "xp": 0}
	star_index = 0
	planet_index = 0
	location = "planet"
	visited_planets = []
	visited_stars = [0]
	scanned = []
	harvested = {}
	quest_index = 0
	quest_accepted = false
	quest_progress = 0
	quest_baseline = 0
	play_time = 0.0
	land_dir = Vector3.ZERO
	kills = 0
	discovered_pois = []
	looted_pois = []
	codex = []
	surveyed = []
	credits = 0
	skill_tiers = {}
	bounties = []
	visited_towns = []
	trader_bought = {}
	appearance = {}
	owned_cosmetics = []
	weapon = "pulse"
	digs = {}
	cave = {}
	relics_found = 0


func new_game(robot: String, pname: String) -> void:
	_reset_state()
	robot_id = robot
	player_name = pname if pname.strip_edges() != "" else Db.ROBOTS[robot].name
	for s in Db.ROBOTS[robot].start_skills:
		skills[s].level = Db.ROBOTS[robot].start_skills[s]
	energy = max_energy()
	hull = max_hull()
	shield = max_shield()
	inventory = {"energy_cell": 2, "repair_kit": 2}
	land_dir = Vector3(0.0, 0.25, 1.0).normalized()
	in_game = true
	save_game()
	go_to_planet(0, 0)


func robot() -> Dictionary:
	return Db.ROBOTS[robot_id]


func stat(key: String, default := 1.0) -> float:
	return robot().stats.get(key, default)


func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


func max_energy() -> float:
	var m := 100.0 + stat("max_energy", 0.0) + (level - 1) * 5.0
	if has_upgrade("capacitor"):
		m += 50.0
	return m


func max_hull() -> float:
	var m := 100.0 + stat("hull", 0.0) + (level - 1) * 6.0 + (skill_level("combat") - 1)
	if has_upgrade("hull_plating"):
		m += 60.0
	return m


func max_shield() -> float:
	return 40.0 if has_upgrade("shield_module") else 0.0


func weapon_damage() -> float:
	var d := (12.0 + level * 2.2) * stat("damage", 1.0) * (1.0 + (skill_level("combat") - 1) * 0.01)
	if has_upgrade("blaster_mk3"):
		d *= 2.0
	elif has_upgrade("blaster_mk2"):
		d *= 1.4
	return d


func in_combat() -> bool:
	return Time.get_ticks_msec() / 1000.0 - last_hit_time < 6.0


## Returns true if this hit destroyed the player.
func take_damage(amount: float) -> bool:
	if invulnerable or hull <= 0.0:
		return false
	last_hit_time = Time.get_ticks_msec() / 1000.0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	amount -= absorbed
	hull = maxf(0.0, hull - amount)
	player_damaged.emit(amount + absorbed)
	hull_changed.emit()
	if hull <= 0.0:
		player_died.emit()
		return true
	return false


func repair(amount: float) -> void:
	hull = minf(max_hull(), hull + amount)
	hull_changed.emit()


func recharge_shield(amount: float) -> void:
	if shield < max_shield():
		shield = minf(max_shield(), shield + amount)
		hull_changed.emit()


func use_repair_kit() -> void:
	if count("repair_kit") <= 0:
		notify.emit("No Repair Kits. Fabricate them from Drone Scrap.", Color("ff6b6b"))
		return
	if hull >= max_hull() - 1.0:
		notify.emit("Hull already at full integrity.", Color("9aa0a6"))
		return
	remove_item("repair_kit", 1)
	repair(Db.ITEMS.repair_kit.repair)
	notify.emit("+%d hull" % Db.ITEMS.repair_kit.repair, Color("6ee06a"))


func record_kill(type: String, lvl: int, elite: bool) -> void:
	var e: Dictionary = Db.ENEMIES[type]
	kills += 1
	var xp_amt := int(e.xp[0] + e.xp[1] * lvl)
	var diff := lvl - level
	xp_amt = int(xp_amt * clampf(1.0 + diff * 0.1, 0.1, 1.6))
	gain_xp(xp_amt)
	gain_skill_xp("combat", (18.0 + lvl * 2.0) * (3.0 if elite else 1.0) * clampf(1.0 + diff * 0.1, 0.15, 1.5))
	for item in e.loot:
		var q := randi_range(e.loot[item][0], e.loot[item][1])
		if q > 0:
			add_item(item, q)
	if randf() < 0.12:
		add_item("repair_kit", 1)
	add_credits(int((2 + lvl * 2) * (5 if elite else 1)))
	_bounty_event("kill", 1)
	_quest_event("kill", type)
	if elite:
		_quest_event("kill_elite", type)


func discover_poi(key: String, poi_name: String) -> bool:
	if discovered_pois.has(key):
		return false
	discovered_pois.append(key)
	big_notify.emit("DISCOVERED", poi_name, Color("5ff7ff"))
	gain_skill_xp("exploration", 40)
	return true


func loot_poi(key: String, type: String) -> void:
	if looted_pois.has(key):
		return
	looted_pois.append(key)
	var p: Dictionary = Db.POIS[type]
	for item in p.loot:
		var q := randi_range(p.loot[item][0], p.loot[item][1])
		if q > 0:
			add_item(item, q, false, true)
	gain_skill_xp("exploration", p.xp)
	gain_xp(p.xp)
	add_credits(randi_range(20, 60))
	_bounty_event("loot", 1)


## Returns the lore index learned (or -1 if all known).
func learn_lore(seed_hint: int) -> int:
	var n := Db.LORE.size()
	for k in n:
		var i := (seed_hint + k * 7) % n
		if not codex.has(i):
			codex.append(i)
			return i
	return -1


func complete_survey(planet_key: String, planet_name: String) -> void:
	if surveyed.has(planet_key):
		return
	surveyed.append(planet_key)
	big_notify.emit("WORLD SURVEYED", "%s fully charted  +300 XP  +1 Warp Cell" % planet_name, Color("6ee06a"))
	gain_skill_xp("exploration", 150)
	gain_xp(300)
	add_item("warp_cell", 1, true)


## Danger level of a planet: home world is gentle, it rises with distance.
func planet_level(star_i: int, planet_i: int) -> int:
	if star_i == 0:
		return 1 if planet_i == 0 else 2 + planet_i
	var p: Dictionary = Galaxy.planet(star_i, planet_i)
	var lvl := 4 + int(Galaxy.distance(0, star_i) / 5.0) + (2 if p.biome == "ember" else 0)
	return clampi(lvl, 1, Db.LEVEL_MAX + 2)


func harvest_speed(skill: String) -> float:
	var s := 1.0
	if skill == "mining":
		s *= stat("harvest_mining", 1.0)
	if has_upgrade("drill_mk3"):
		s *= 2.2
	elif has_upgrade("drill_mk2"):
		s *= 1.5
	return s


func warp_range() -> float:
	var r := Galaxy.BASE_WARP_RANGE
	if has_upgrade("warp_drive_mk2"):
		r *= 1.75
	return r


func skill_level(s: String) -> int:
	return skills[s].level


# --------------------------------------------------------------------------
# energy
# --------------------------------------------------------------------------

func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	energy_changed.emit(energy, max_energy())
	return true


func drain_energy(amount: float) -> void:
	energy = maxf(0.0, energy - amount)
	energy_changed.emit(energy, max_energy())


func add_energy(amount: float) -> void:
	energy = minf(max_energy(), energy + amount)
	energy_changed.emit(energy, max_energy())


func use_energy_cell() -> void:
	if count("energy_cell") <= 0:
		notify.emit("No Energy Cells. Craft them from Solar Plasma.", Color("ff6b6b"))
		return
	if energy >= max_energy() - 1.0:
		notify.emit("Energy already full.", Color("9aa0a6"))
		return
	remove_item("energy_cell", 1)
	add_energy(Db.ITEMS.energy_cell.restore)
	notify.emit("+%d energy" % Db.ITEMS.energy_cell.restore, Color("ffe27a"))


# --------------------------------------------------------------------------
# inventory
# --------------------------------------------------------------------------

func count(item: String) -> int:
	return inventory.get(item, 0)


func add_item(item: String, qty: int, silent := false, force := false) -> int:
	if qty <= 0:
		return 0
	if Db.ITEMS.get(item, {}).get("kind", "") == "upgrade":
		if not upgrades.has(item):
			upgrades.append(item)
			if item == "capacitor":
				energy_changed.emit(energy, max_energy())
			if item in ["hull_plating", "shield_module"]:
				shield = max_shield()
				hull_changed.emit()
			big_notify.emit("UPGRADE INSTALLED", Db.item_name(item), Db.item_color(item))
		return qty
	if is_cargo(item) and not force and not silent:
		var free := cargo_free()
		if free <= 0:
			_cargo_full_warning()
			return 0
		qty = mini(qty, free)
	inventory[item] = count(item) + qty
	if not silent:
		notify.emit("+%d %s" % [qty, Db.item_name(item)], Db.item_color(item))
	inventory_changed.emit()
	_quest_event("collect", item, qty)
	return qty


func remove_item(item: String, qty: int) -> bool:
	if count(item) < qty:
		return false
	inventory[item] = count(item) - qty
	if inventory[item] <= 0:
		inventory.erase(item)
	inventory_changed.emit()
	return true


func has_items(req: Dictionary) -> bool:
	for k in req:
		if count(k) < req[k]:
			return false
	return true


# --------------------------------------------------------------------------
# progression
# --------------------------------------------------------------------------

func gain_xp(amount: int) -> void:
	if level >= Db.LEVEL_MAX:
		return
	xp += amount
	while level < Db.LEVEL_MAX and xp >= Db.level_xp_needed(level):
		xp -= Db.level_xp_needed(level)
		level += 1
		energy = max_energy()
		big_notify.emit("LEVEL %d" % level, "Max energy increased", Color("ffe066"))
		energy_changed.emit(energy, max_energy())
		hull = max_hull()
		hull_changed.emit()
	xp_changed.emit()


func gain_skill_xp(skill: String, amount: float) -> void:
	var s: Dictionary = skills[skill]
	if s.level >= Db.SKILL_MAX:
		return
	var mult: float = robot().xp_mult.get(skill, 1.0)
	var cap := skill_cap(skill)
	if s.level >= cap:
		if not _cap_warned.has(skill):
			_cap_warned[skill] = true
			notify.emit("%s capped at %d. Train the next rank with a Profession Trainer in town." % [Db.SKILLS[skill].name, cap], Color("ffb86b"))
		gain_xp(int(amount * 0.6))
		return
	s.xp += int(round(amount * mult))
	var leveled := false
	while s.level < cap and s.xp >= Db.skill_xp_needed(s.level):
		s.xp -= Db.skill_xp_needed(s.level)
		s.level += 1
		leveled = true
	if leveled:
		big_notify.emit("%s %d" % [Db.SKILLS[skill].name, s.level], "Profession skill increased", Db.SKILLS[skill].color)
		_quest_event("skill", skill)
	skill_changed.emit(skill)
	# every profession point also feeds character level
	gain_xp(int(amount * 0.6))


## Harvest a gather node. Returns true on success.
func harvest(node_type: String) -> bool:
	var n: Dictionary = Db.NODES[node_type]
	var sk: int = skill_level(n.skill)
	if sk < n.req:
		notify.emit("Requires %s %d" % [Db.SKILLS[n.skill].name, n.req], Color("ff6b6b"))
		return false
	if cargo_free() <= 0:
		_cargo_full_warning()
		return false
	var rng := randi_range(n.yield[0], n.yield[1])
	rng += robot().yield_bonus.get(n.skill, 0)
	# skilled gatherers get bonus yield
	if sk - n.req >= 25 and randf() < 0.5:
		rng += 1
	add_item(n.item, rng)
	gain_skill_xp(n.skill, n.xp * Db.difficulty_xp_mult(n.req, sk))
	if n.has("restore"):
		add_energy(n.restore)
	return true


func can_craft(r: Dictionary) -> bool:
	return skill_level("engineering") >= r.req and has_items(r.in)


func craft(recipe_id: String) -> bool:
	var r := Db.recipe(recipe_id)
	if r.is_empty():
		return false
	if skill_level("engineering") < r.req:
		notify.emit("Requires Engineering %d" % r.req, Color("ff6b6b"))
		return false
	if Db.ITEMS[r.out].kind == "upgrade" and has_upgrade(r.out):
		notify.emit("Already installed.", Color("9aa0a6"))
		return false
	if not has_items(r.in):
		notify.emit("Missing materials.", Color("ff6b6b"))
		return false
	for k in r.in:
		remove_item(k, r.in[k])
	var qty: int = r.qty
	if Db.ITEMS[r.out].kind != "upgrade" and randf() < stat("double_craft", 0.0):
		qty *= 2
		notify.emit("Inspired fabrication! Double output.", Color("c3a6ff"))
	add_item(r.out, qty, false, true)
	Sound.play("craft", -3.0, 0.03, "UI")
	gain_skill_xp("engineering", r.xp * Db.difficulty_xp_mult(r.req, skill_level("engineering")))
	_quest_event("craft", r.out, qty)
	return true


func record_scan(species_key: String, display: String) -> bool:
	if scanned.has(species_key):
		return false
	scanned.append(species_key)
	notify.emit("Species logged: %s" % display, Color("5ff7ff"))
	_bounty_event("scan", 1)
	gain_skill_xp("exploration", 30)
	_quest_event("scan", species_key)
	return true


func record_landing(key: String) -> void:
	if not visited_planets.has(key):
		visited_planets.append(key)
		if visited_planets.size() > 1:
			gain_skill_xp("exploration", 60)
			big_notify.emit("NEW WORLD", Galaxy.planet(star_index, planet_index).name, Color("5ff7ff"))
	_quest_event("land_unique", key)


func record_warp(to_star: int) -> void:
	if not visited_stars.has(to_star):
		visited_stars.append(to_star)
		gain_skill_xp("exploration", 120)
	_quest_event("warp", str(to_star))


func record_orbit() -> void:
	_quest_event("orbit", "")


# --------------------------------------------------------------------------
# harvest persistence (nodes respawn after RESPAWN_SECONDS)
# --------------------------------------------------------------------------

func is_harvested(planet_key: String, node_id: int) -> bool:
	var h: Dictionary = harvested.get(planet_key, {})
	var k := str(node_id)
	if not h.has(k):
		return false
	if Time.get_unix_time_from_system() - float(h[k]) > RESPAWN_SECONDS:
		h.erase(k)
		return false
	return true


func mark_harvested(planet_key: String, node_id: int) -> void:
	if not harvested.has(planet_key):
		harvested[planet_key] = {}
	harvested[planet_key][str(node_id)] = Time.get_unix_time_from_system()


# --------------------------------------------------------------------------
# quests
# --------------------------------------------------------------------------

func current_quest() -> Dictionary:
	if quest_index >= Db.QUESTS.size():
		return {}
	return Db.QUESTS[quest_index]


func accept_quest() -> void:
	var q := current_quest()
	if q.is_empty() or quest_accepted:
		return
	quest_accepted = true
	quest_progress = 0
	var o: Dictionary = q.obj
	match o.type:
		"collect":
			quest_baseline = 0
		"land_unique":
			quest_progress = visited_planets.size()
		"visit_town":
			quest_progress = visited_towns.size()
		"skill":
			quest_progress = skill_level(o.skill)
		"scan":
			quest_progress = 0
	big_notify.emit("QUEST ACCEPTED", q.title, Color("ffd23f"))
	quest_changed.emit()
	_check_quest_complete()


func quest_target() -> int:
	var q := current_quest()
	return q.obj.count if not q.is_empty() else 0


func _quest_event(kind: String, what: String, amount := 1) -> void:
	var q := current_quest()
	if q.is_empty() or not quest_accepted:
		return
	var o: Dictionary = q.obj
	if o.type != kind:
		return
	match kind:
		"collect", "craft":
			if o.item != what:
				return
			quest_progress = mini(o.count, quest_progress + amount)
		"scan", "warp", "orbit", "kill", "kill_elite", "train", "space_kill", "space_elite", "chamber":
			quest_progress = mini(o.count, quest_progress + 1)
		"land_unique":
			quest_progress = mini(o.count, visited_planets.size())
		"visit_town":
			quest_progress = mini(o.count, visited_towns.size())
		"dig":
			quest_progress = mini(o.count, quest_progress + amount)
		"sell", "station_sell":
			quest_progress = mini(o.count, quest_progress + amount)
		"skill":
			if o.skill == what:
				quest_progress = mini(o.count, skill_level(what))
	quest_changed.emit()
	_check_quest_complete()


func _check_quest_complete() -> void:
	var q := current_quest()
	if q.is_empty() or not quest_accepted:
		return
	if quest_progress < q.obj.count:
		return
	# complete!
	gain_xp(q.xp)
	if q.has("credits"):
		add_credits(q.credits, true)
	for item in q.reward:
		add_item(item, q.reward[item], true)
	var reward_txt := ""
	for item in q.reward:
		reward_txt += "  %dx %s" % [q.reward[item], Db.item_name(item)]
	big_notify.emit("QUEST COMPLETE", "%s  +%d XP%s" % [q.title, q.xp, reward_txt], Color("6ee06a"))
	quest_index += 1
	quest_accepted = false
	quest_progress = 0
	quest_changed.emit()
	# after the first quest the Archivist sends the rest over comms
	if quest_index < Db.QUESTS.size():
		get_tree().create_timer(3.0).timeout.connect(func():
			if not quest_accepted:
				accept_quest()
		)
	save_game()


# --------------------------------------------------------------------------
# scene flow
# --------------------------------------------------------------------------

func _build_fader() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fader = ColorRect.new()
	_fader.color = Color(0, 0, 0, 0)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fader)


func fade_to(scene_path: String) -> void:
	get_tree().paused = false
	var t := create_tween()
	t.tween_property(_fader, "color:a", 1.0, 0.45)
	await t.finished
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	var t2 := create_tween()
	t2.tween_property(_fader, "color:a", 0.0, 0.6)


func go_to_planet(star_i: int, planet_i: int) -> void:
	star_index = star_i
	planet_index = planet_i
	location = "planet"
	save_game()
	fade_to("res://scenes/planet.tscn")


func go_to_space() -> void:
	location = "space"
	save_game()
	fade_to("res://scenes/space.tscn")


func go_to_menu() -> void:
	if in_game:
		save_game()
	in_game = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fade_to("res://scenes/main_menu.tscn")


# --------------------------------------------------------------------------
# save / load
# --------------------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if not in_game:
		return
	var data := {
		"version": 1,
		"robot_id": robot_id, "player_name": player_name,
		"level": level, "xp": xp, "energy": energy, "hull": hull, "kills": kills,
		"discovered_pois": discovered_pois, "looted_pois": looted_pois, "codex": codex, "surveyed": surveyed,
		"credits": credits, "skill_tiers": skill_tiers, "bounties": bounties, "visited_towns": visited_towns,
		"trader_bought": trader_bought, "quest_id": current_quest().get("id", "done"),
		"appearance": appearance, "owned_cosmetics": owned_cosmetics, "weapon": weapon,
		"digs": digs, "relics_found": relics_found,
		"inventory": inventory, "upgrades": upgrades, "skills": skills,
		"star_index": star_index, "planet_index": planet_index, "location": location,
		"visited_planets": visited_planets, "visited_stars": visited_stars,
		"scanned": scanned, "harvested": harvested,
		"quest_index": quest_index, "quest_accepted": quest_accepted, "quest_progress": quest_progress,
		"play_time": play_time,
		"land_dir": [land_dir.x, land_dir.y, land_dir.z],
		"space_pos": [space_return_pos.x, space_return_pos.y, space_return_pos.z],
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func save_summary() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func load_game() -> bool:
	var d := save_summary()
	if d.is_empty():
		return false
	_reset_state()
	robot_id = d.get("robot_id", "scout")
	player_name = d.get("player_name", "Unit")
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	inventory = {}
	for k in d.get("inventory", {}):
		inventory[k] = int(d.inventory[k])
	upgrades = d.get("upgrades", [])
	var sk: Dictionary = d.get("skills", {})
	for s in skills:
		if sk.has(s):
			skills[s] = {"level": int(sk[s].level), "xp": int(sk[s].xp)}
	star_index = int(d.get("star_index", 0))
	planet_index = int(d.get("planet_index", 0))
	location = d.get("location", "planet")
	visited_planets = d.get("visited_planets", [])
	visited_stars = []
	for s in d.get("visited_stars", [0]):
		visited_stars.append(int(s))
	scanned = d.get("scanned", [])
	harvested = d.get("harvested", {})
	quest_index = int(d.get("quest_index", 0))
	quest_accepted = bool(d.get("quest_accepted", false))
	quest_progress = int(d.get("quest_progress", 0))
	play_time = float(d.get("play_time", 0.0))
	var ld: Array = d.get("land_dir", [0, 1, 0])
	land_dir = Vector3(ld[0], ld[1], ld[2])
	var sp: Array = d.get("space_pos", [0, 0, 0])
	space_return_pos = Vector3(sp[0], sp[1], sp[2])
	energy = minf(float(d.get("energy", 100.0)), max_energy())
	hull = clampf(float(d.get("hull", max_hull())), 1.0, max_hull())
	shield = max_shield()
	kills = int(d.get("kills", 0))
	discovered_pois = d.get("discovered_pois", [])
	looted_pois = d.get("looted_pois", [])
	codex = []
	for c in d.get("codex", []):
		codex.append(int(c))
	surveyed = d.get("surveyed", [])
	credits = int(d.get("credits", 0))
	skill_tiers = {}
	var st: Dictionary = d.get("skill_tiers", {})
	for sk_name in skills:
		var t := int(st.get(sk_name, 0))
		# older saves: grandfather whatever rank covers the current level
		while t < Db.SKILL_TIERS.size() - 1 and skills[sk_name].level > Db.SKILL_TIERS[t].cap:
			t += 1
		skill_tiers[sk_name] = t
	bounties = d.get("bounties", [])
	visited_towns = d.get("visited_towns", [])
	trader_bought = d.get("trader_bought", {})
	appearance = d.get("appearance", {})
	owned_cosmetics = d.get("owned_cosmetics", [])
	weapon = d.get("weapon", "pulse")
	digs = d.get("digs", {})
	relics_found = int(d.get("relics_found", 0))
	# quests are saved by id so new quests can be inserted without breaking saves
	var qid: String = d.get("quest_id", "")
	if qid == "done":
		quest_index = Db.QUESTS.size()
	elif qid != "":
		for i in Db.QUESTS.size():
			if Db.QUESTS[i].id == qid:
				quest_index = i
				break
	in_game = true
	if location == "space":
		fade_to("res://scenes/space.tscn")
	else:
		fade_to("res://scenes/planet.tscn")
	return true



# --------------------------------------------------------------------------
# economy: credits, prices, trading
# --------------------------------------------------------------------------

func add_credits(n: int, silent := false) -> void:
	if n == 0:
		return
	credits = maxi(0, credits + n)
	credits_changed.emit()
	if not silent and n > 0:
		notify.emit("+%d credits" % n, Color("ffd23f"))


func skill_tier(skill: String) -> int:
	return int(skill_tiers.get(skill, 0))


func skill_cap(skill: String) -> int:
	return Db.SKILL_TIERS[skill_tier(skill)].cap


func game_day() -> int:
	return int(play_time / 720.0)


## Is `item` produced on this planet (so it's cheap here)?
func _native(item: String, planet: Dictionary) -> int:
	var biome: Dictionary = Db.BIOMES[planet.biome]
	for n in biome.nodes:
		if Db.NODES[n].item == item:
			return 1
	for n in Db.NODES:
		if Db.NODES[n].item == item:
			return -1 # a raw resource from elsewhere
	return 0 # crafted goods: neutral


func sell_price(item: String, planet: Dictionary) -> int:
	if not Db.VALUES.has(item):
		return 0
	var mod: float = {1: 0.75, -1: 1.35, 0: 1.0}[_native(item, planet)]
	var town: Dictionary = planet.get("town", {})
	if town.get("specialty", "") == item:
		mod *= 1.6
	return maxi(1, int(round(Db.VALUES[item] * 0.6 * mod)))


func buy_price(item: String, planet: Dictionary) -> int:
	var mod: float = {1: 0.8, -1: 1.4, 0: 1.0}[_native(item, planet)]
	return maxi(1, int(round(Db.VALUES[item] * 1.25 * mod)))


## Today's trader stock for a town: [{item, qty, price}].
func trader_stock(planet: Dictionary) -> Array:
	var town: Dictionary = planet.town
	var day := game_day()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(town.seed) + day * 7919
	var stock := {"energy_cell": rng.randi_range(6, 12), "repair_kit": rng.randi_range(4, 9), "alloy": rng.randi_range(3, 8)}
	stock["warp_cell"] = rng.randi_range(0, 2) if planet.star != 0 or planet.index != 0 else rng.randi_range(0, 1)
	var biome: Dictionary = Db.BIOMES[planet.biome]
	for n in biome.nodes:
		stock[Db.NODES[n].item] = rng.randi_range(10, 25)
	var foreign := ["cobalt", "lumen", "sporegel", "voidshard", "biofiber", "plasma", "nickel", "cryo_ice"]
	for i in 2:
		var f: String = foreign[rng.randi() % foreign.size()]
		if not stock.has(f):
			stock[f] = rng.randi_range(3, 8)
	if rng.randf() < 0.4:
		stock["circuit"] = rng.randi_range(1, 3)
	var bought: Dictionary = trader_bought.get("%s:%d" % [planet.key, day], {})
	var out := []
	for item in stock:
		var q: int = stock[item] - int(bought.get(item, 0))
		out.append({"item": item, "qty": maxi(0, q), "price": buy_price(item, planet)})
	return out


func buy(item: String, qty: int, planet: Dictionary) -> bool:
	var line := {}
	for l in trader_stock(planet):
		if l.item == item:
			line = l
	if line.is_empty() or line.qty < qty:
		notify.emit("Sold out.", Color("ff6b6b"))
		return false
	if is_cargo(item) and cargo_free() < qty:
		_cargo_full_warning()
		return false
	var cost: int = line.price * qty
	if credits < cost:
		notify.emit("Not enough credits (%d needed)." % cost, Color("ff6b6b"))
		return false
	add_credits(-cost, true)
	var k := "%s:%d" % [planet.key, game_day()]
	if not trader_bought.has(k):
		trader_bought[k] = {}
	trader_bought[k][item] = int(trader_bought[k].get(item, 0)) + qty
	add_item(item, qty)
	Sound.play("coin", -4.0, 0.05, "UI")
	return true


func sell(item: String, qty: int, planet: Dictionary) -> bool:
	qty = mini(qty, count(item))
	if qty <= 0:
		return false
	var price := sell_price(item, planet)
	remove_item(item, qty)
	add_credits(price * qty, true)
	notify.emit("Sold %dx %s for %d credits" % [qty, Db.item_name(item), price * qty], Color("ffd23f"))
	Sound.play("coin", -4.0, 0.05, "UI")
	_quest_event("sell", item, qty)
	return true


# --------------------------------------------------------------------------
# profession training
# --------------------------------------------------------------------------

func can_train(skill: String, max_tier: int) -> Dictionary:
	var next := skill_tier(skill) + 1
	if next >= Db.SKILL_TIERS.size():
		return {"ok": false, "why": "Already an Artisan."}
	var t: Dictionary = Db.SKILL_TIERS[next]
	if next > max_tier:
		return {"ok": false, "why": "This trainer can't teach %s. Seek a trainer farther from home." % t.name, "tier": t}
	if skill_level(skill) < t.req:
		return {"ok": false, "why": "Requires %s %d." % [Db.SKILLS[skill].name, t.req], "tier": t}
	if credits < t.cost:
		return {"ok": false, "why": "Costs %d credits." % t.cost, "tier": t}
	return {"ok": true, "tier": t}


func train(skill: String, max_tier: int) -> bool:
	var c := can_train(skill, max_tier)
	if not c.ok:
		notify.emit(c.why, Color("ff6b6b"))
		return false
	add_credits(-int(c.tier.cost), true)
	skill_tiers[skill] = skill_tier(skill) + 1
	_cap_warned.erase(skill)
	big_notify.emit("%s %s" % [c.tier.name.to_upper(), Db.SKILLS[skill].name.to_upper()], "Skill cap raised to %d" % c.tier.cap, Db.SKILLS[skill].color)
	Sound.play("skill_up", -3.0, 0.0, "UI")
	_quest_event("train", skill)
	skill_changed.emit(skill)
	return true


# --------------------------------------------------------------------------
# towns + bounties
# --------------------------------------------------------------------------

func record_town_visit(key: String) -> void:
	if not visited_towns.has(key):
		visited_towns.append(key)
	_quest_event("visit_town", key)


## Three contracts per board per day, deterministic.
func board_offers(planet: Dictionary) -> Array:
	var town: Dictionary = planet.town
	var day := game_day()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(town.seed) * 31 + day
	var lvl := planet_level(planet.star, planet.index)
	var out := []
	for i in 3:
		var tpl: Dictionary = Db.BOUNTIES[rng.randi() % Db.BOUNTIES.size()]
		var b := {"id": "%s:%d:%d" % [planet.key, day, i], "type": tpl.type, "title": tpl.title, "progress": 0, "town": town.name}
		match tpl.type:
			"deliver":
				var items := ["ferrite", "cobalt", "biofiber", "plasma", "sporegel", "scrap", "alloy", "lumen", "nickel", "cryo_ice"]
				var it: String = items[rng.randi() % items.size()]
				b.item = it
				b.n = rng.randi_range(4, 12) if Db.VALUES[it] < 15 else rng.randi_range(2, 5)
				b.credits = int(Db.VALUES[it] * b.n * 1.9) + 20
			"kill":
				b.n = rng.randi_range(4, 9)
				b.credits = b.n * (10 + lvl * 3)
			"scan":
				b.n = rng.randi_range(2, 4)
				b.credits = b.n * 35
			"loot":
				b.n = rng.randi_range(1, 2)
				b.credits = b.n * 70
			"asteroid":
				b.n = rng.randi_range(4, 10)
				b.credits = b.n * 16
			"space_kill":
				b.n = rng.randi_range(3, 7)
				b.credits = b.n * (22 + lvl * 4)
		b.xp = int(b.credits * 1.2) + 40
		b.text = String(tpl.text).format({"n": b.n, "item": Db.item_name(b.get("item", ""))})
		out.append(b)
	return out


func has_bounty(id: String) -> bool:
	for b in bounties:
		if b.id == id:
			return true
	return false


func accept_bounty(b: Dictionary) -> void:
	if bounties.size() >= 3:
		notify.emit("You can hold 3 contracts at once.", Color("ff6b6b"))
		return
	if has_bounty(b.id):
		return
	bounties.append(b.duplicate())
	Sound.play("quest_accept", -4.0, 0.0, "UI")
	notify.emit("Contract accepted: %s" % b.title, Color("ffd23f"))
	quest_changed.emit()


func bounty_ready(b: Dictionary) -> bool:
	if b.type == "deliver":
		return count(b.item) >= b.n
	return int(b.progress) >= int(b.n)


func turn_in_bounty(b: Dictionary) -> void:
	if not bounty_ready(b):
		return
	if b.type == "deliver":
		remove_item(b.item, b.n)
	bounties.erase(b)
	add_credits(int(b.credits), true)
	gain_xp(int(b.xp))
	big_notify.emit("CONTRACT COMPLETE", "%s  +%d credits  +%d XP" % [b.title, b.credits, b.xp], Color("ffd23f"))
	Sound.play("coin", 0.0, 0.0, "UI")
	quest_changed.emit()


func _bounty_event(kind: String, amount: int) -> void:
	var changed := false
	for b in bounties:
		if b.type == kind and int(b.progress) < int(b.n):
			b.progress = mini(int(b.n), int(b.progress) + amount)
			changed = true
			if int(b.progress) >= int(b.n):
				notify.emit("Contract ready to turn in: %s" % b.title, Color("ffd23f"))
	if changed:
		quest_changed.emit()



# --------------------------------------------------------------------------
# space combat
# --------------------------------------------------------------------------

## Danger level of a star system's pirates.
func space_level(star_i: int) -> int:
	if star_i == 0:
		return 2
	return clampi(4 + int(Galaxy.distance(0, star_i) / 5.0), 1, Db.LEVEL_MAX + 2)


func space_weapon_damage() -> float:
	return weapon_damage() * 0.8 * (1.5 if has_upgrade("twin_cannons") else 1.0)


func record_space_kill(type: String, lvl: int, elite: bool) -> Dictionary:
	var e: Dictionary = Db.SPACE_ENEMIES[type]
	kills += 1
	var diff := lvl - level
	gain_xp(int((e.xp[0] + e.xp[1] * lvl) * clampf(1.0 + diff * 0.1, 0.1, 1.6)))
	gain_skill_xp("combat", (16.0 + lvl * 2.0) * (4.0 if elite else 1.0) * clampf(1.0 + diff * 0.1, 0.15, 1.5))
	add_credits(int((4 + lvl * 3) * (6 if elite else 1)))
	_bounty_event("space_kill", 1)
	_quest_event("space_kill", type)
	if elite:
		_quest_event("space_elite", type)
	var loot := {}
	for item in e.loot:
		var q := randi_range(e.loot[item][0], e.loot[item][1])
		if q > 0:
			loot[item] = q
	return loot



# --------------------------------------------------------------------------
# cargo hold
# --------------------------------------------------------------------------

var _full_warn_t := 0

func is_cargo(item: String) -> bool:
	return Db.ITEMS.get(item, {}).get("kind", "") in Db.CARGO_KINDS


func cargo_used() -> int:
	var n := 0
	for it in inventory:
		if is_cargo(it):
			n += int(inventory[it])
	return n


func cargo_cap() -> int:
	var c := Db.CARGO_BASE + int(stat("cargo", 0.0))
	if has_upgrade("cargo_pods"):
		c += 100
	if has_upgrade("cargo_pods_mk2"):
		c += 200
	return c


func cargo_free() -> int:
	return maxi(0, cargo_cap() - cargo_used())


func _cargo_full_warning() -> void:
	var now := Time.get_ticks_msec()
	if now - _full_warn_t > 2500:
		_full_warn_t = now
		notify.emit("Cargo hold full (%d/%d). Sell at a station or town, or craft Cargo Pods." % [cargo_used(), cargo_cap()], Color("ff6b6b"))


## Lose a share of raw cargo (ship destroyed). Returns {item: qty} that spilled.
func spill_cargo(fraction: float) -> Dictionary:
	var lost := {}
	for it in inventory.keys():
		if Db.ITEMS[it].kind == "resource":
			var q := int(floor(count(it) * fraction))
			if q > 0:
				remove_item(it, q)
				lost[it] = q
	return lost


# --------------------------------------------------------------------------
# orbital stations
# --------------------------------------------------------------------------

func _station_mod(item: String, star_i: int) -> float:
	var st: Dictionary = Galaxy.star(star_i).station
	var mod := 1.0
	if st.demand.has(item):
		mod = 1.7
	elif st.surplus.has(item):
		mod = 0.6
	# prices drift a little every day
	var h: int = hash("%d:%s:%d" % [star_i, item, game_day()])
	mod *= 0.85 + float(h % 1000) / 1000.0 * 0.3
	return mod


func station_sell_price(item: String, star_i: int) -> int:
	if not Db.VALUES.has(item):
		return 0
	return maxi(1, int(round(Db.VALUES[item] * 0.7 * _station_mod(item, star_i))))


func station_buy_price(item: String, star_i: int) -> int:
	return maxi(1, int(round(Db.VALUES[item] * 1.2 * _station_mod(item, star_i))))


func station_stock(star_i: int) -> Array:
	var st: Dictionary = Galaxy.star(star_i).station
	var day := game_day()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(st.seed) + day * 104729
	var stock := {"energy_cell": rng.randi_range(8, 16), "repair_kit": rng.randi_range(6, 12), "warp_cell": rng.randi_range(2, 4)}
	for it in st.surplus:
		stock[it] = rng.randi_range(20, 45)
	var bought: Dictionary = trader_bought.get("station:%d:%d" % [star_i, day], {})
	var out := []
	for item in stock:
		out.append({"item": item, "qty": maxi(0, stock[item] - int(bought.get(item, 0))), "price": station_buy_price(item, star_i)})
	return out


func station_buy(item: String, qty: int, star_i: int) -> bool:
	var line := {}
	for l in station_stock(star_i):
		if l.item == item:
			line = l
	if line.is_empty() or line.qty < qty:
		notify.emit("Sold out.", Color("ff6b6b"))
		return false
	if is_cargo(item) and cargo_free() < qty:
		_cargo_full_warning()
		return false
	var cost: int = line.price * qty
	if credits < cost:
		notify.emit("Not enough credits (%d needed)." % cost, Color("ff6b6b"))
		return false
	add_credits(-cost, true)
	var k := "station:%d:%d" % [star_i, game_day()]
	if not trader_bought.has(k):
		trader_bought[k] = {}
	trader_bought[k][item] = int(trader_bought[k].get(item, 0)) + qty
	add_item(item, qty)
	Sound.play("coin", -4.0, 0.05, "UI")
	return true


func station_sell(item: String, qty: int, star_i: int, quiet := false) -> int:
	qty = mini(qty, count(item))
	if qty <= 0:
		return 0
	var total := station_sell_price(item, star_i) * qty
	remove_item(item, qty)
	add_credits(total, true)
	if not quiet:
		notify.emit("Sold %dx %s for %d credits" % [qty, Db.item_name(item), total], Color("ffd23f"))
		Sound.play("coin", -4.0, 0.05, "UI")
	_quest_event("station_sell", item, qty)
	_quest_event("sell", item, qty)
	return total


## One button to empty the hold of raw goods and components.
func station_sell_all(star_i: int) -> void:
	var total := 0
	var units := 0
	for it in inventory.keys():
		if is_cargo(it) and Db.VALUES.has(it):
			units += count(it)
			total += station_sell(it, count(it), star_i, true)
	if units > 0:
		notify.emit("Sold %d units of cargo for %d credits" % [units, total], Color("ffd23f"))
		Sound.play("coin", 0.0, 0.0, "UI")


func repair_cost() -> int:
	return int(ceil((max_hull() - hull) * 0.5))


func recharge_cost() -> int:
	return int(ceil((max_energy() - energy) * 0.2))


func buy_repair() -> void:
	var c := repair_cost()
	if c <= 0 or credits < c:
		notify.emit("Hull is fine." if c <= 0 else "Not enough credits.", Color("9aa0a6") if c <= 0 else Color("ff6b6b"))
		return
	add_credits(-c, true)
	hull = max_hull()
	shield = max_shield()
	hull_changed.emit()
	Sound.play("respawn", -6.0, 0.0, "UI")


func buy_recharge() -> void:
	var c := recharge_cost()
	if c <= 0 or credits < c:
		notify.emit("Energy is full." if c <= 0 else "Not enough credits.", Color("9aa0a6") if c <= 0 else Color("ff6b6b"))
		return
	add_credits(-c, true)
	add_energy(max_energy())
	Sound.play("siphon_done", -6.0, 0.0, "UI")


## A station looks like a town to the bounty-board code.
func station_as_town(star_i: int) -> Dictionary:
	var st: Dictionary = Galaxy.star(star_i).station
	return {"key": "station:%d" % star_i, "star": star_i, "index": 0, "biome": Galaxy.planet(star_i, 0).biome,
		"town": {"name": st.name, "seed": st.seed, "specialty": st.demand[0], "max_tier": 0}}



# --------------------------------------------------------------------------
# customisation + loadouts
# --------------------------------------------------------------------------

signal appearance_changed

func cosmetic(slot: String, id: String) -> Dictionary:
	for c in Db.COSMETICS[slot]:
		if c.id == id:
			return c
	return Db.COSMETICS[slot][0]


func owns_cosmetic(slot: String, id: String) -> bool:
	return cosmetic(slot, id).price == 0 or owned_cosmetics.has("%s:%s" % [slot, id])


func equipped(slot: String) -> String:
	return appearance.get(slot, Db.COSMETICS[slot][0].id)


## Buy (if needed) and equip a part or finish. Returns true on success.
func equip_cosmetic(slot: String, id: String) -> bool:
	var c := cosmetic(slot, id)
	if not owns_cosmetic(slot, id):
		if credits < c.price:
			notify.emit("%s costs %d credits." % [c.name, c.price], Color("ff6b6b"))
			return false
		add_credits(-int(c.price), true)
		owned_cosmetics.append("%s:%s" % [slot, id])
		notify.emit("Purchased %s" % c.name, Color("ffd23f"))
		Sound.play("coin", -4.0, 0.0, "UI")
	appearance[slot] = id
	appearance_changed.emit()
	return true


func set_paint(channel: String, color: Color) -> void:
	appearance[channel] = color.to_html(false)
	appearance_changed.emit()


func reset_paint() -> void:
	for ch in ["shell", "accent", "glow", "flame"]:
		appearance.erase(ch)
	appearance_changed.emit()


func weapon_def() -> Dictionary:
	return Db.WEAPONS.get(weapon, Db.WEAPONS.pulse)


func weapon_unlocked(id: String) -> bool:
	var u: String = Db.WEAPONS[id].unlock
	return u == "" or has_upgrade(u)


func set_weapon(id: String) -> void:
	if not weapon_unlocked(id):
		notify.emit("%s loadout is locked. Craft the %s first." % [Db.WEAPONS[id].name, Db.item_name(Db.WEAPONS[id].unlock)], Color("ff6b6b"))
		return
	weapon = id
	notify.emit("Weapon: %s" % Db.WEAPONS[id].name, Color("ffb86b"))
	Sound.play("turret_deploy", -10.0, 0.05, "UI")
	appearance_changed.emit()


func cycle_weapon() -> void:
	var ids: Array = Db.WEAPONS.keys()
	var i := ids.find(weapon)
	for k in range(1, ids.size() + 1):
		var nxt: String = ids[(i + k) % ids.size()]
		if weapon_unlocked(nxt):
			if nxt != weapon:
				set_weapon(nxt)
			else:
				notify.emit("Craft a Scatter Emitter or Rail Coil to unlock more loadouts.", Color("9aa0a6"))
			return



# --------------------------------------------------------------------------
# the Deep: caves, digging, chambers
# --------------------------------------------------------------------------

func enter_cave(poi_key: String, dir: Vector3, planet_seed: int, biome: String) -> void:
	cave = {"key": poi_key, "dir": [dir.x, dir.y, dir.z], "seed": hash(poi_key) ^ planet_seed, "biome": biome,
		"star": star_index, "planet": planet_index, "pod": []}
	land_dir = dir
	save_game()
	Sound.play("atmo_entry", -8.0, 0.0)
	fade_to("res://scenes/dig.tscn")


func leave_cave() -> void:
	var d: Array = cave.get("dir", [0, 1, 0])
	land_dir = Vector3(d[0], d[1], d[2])
	cave = {}
	go_to_planet(star_index, planet_index)


func enter_chamber(chamber: Dictionary, pod_pos: Vector2) -> void:
	cave["pod"] = [pod_pos.x, pod_pos.y]
	cave["chamber"] = chamber
	fade_to("res://scenes/grotto.tscn")


func leave_chamber() -> void:
	fade_to("res://scenes/dig.tscn")


func dig_state(key: String) -> Dictionary:
	if not digs.has(key):
		digs[key] = {"dug": "", "chambers": []}
	return digs[key]


func record_dig(n: int) -> void:
	_quest_event("dig", "tile", n)


func record_chamber(key: String, chamber_id: int, theme: String) -> void:
	var st := dig_state(key)
	if st.chambers.has(chamber_id):
		return
	st.chambers.append(chamber_id)
	gain_skill_xp("exploration", 90)
	gain_xp(150)
	_quest_event("chamber", theme)


func collect_relic(item: String) -> void:
	add_item(item, 1, false, true)
	relics_found += 1
	gain_skill_xp("exploration", 60 if item == "fossil" else 120)
