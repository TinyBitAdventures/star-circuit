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
signal tip_requested(id: String, text: String)
signal mail_changed

const SAVE_PATH := "user://star_circuit_save.json" # legacy single save (migrated to slot 1)
const SLOTS := 3
var slot := 1
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
var lit_relays: Array = [0]
var heart_defeated := false
var boarded: Array = [] # derelict keys already looted
var milestones: Array = [] # unlocked milestone ids
# the Homespace: a virtual home inside the robot, reachable from anywhere
var vault := {} # item -> qty in cloud storage
var vault_level := 0 # memory expansions bought
var inbox: Array = [] # {id, from, subject, body, items, credits, read, claimed, kind, order: {...}}
var _mail_seq := 0
var _order_t := 240.0 # play seconds until the next trader order
var home_visits := 0
var in_home := false
var workers: Array = [] # {id, name, level, xp, state: idle|job|hurt, job: {}, hurt_left}
var home := {} # {"owned": [decor ids], "slots": {slot id: decor id}, "theme": id, "themes": [owned], "wings": n, "charge_at": play_time}
var crafted_once: Array = [] # recipe ids fabricated at least once (discovery bonus)
var gems_taken := {} # orbit target key -> [gem indices already extracted]
var seas := {} # ocean key -> {"dug": base64, "opened": [clam ids], "wreck": bool}
var sea := {} # the ocean we're diving (not saved: dives always resume on the surface)
var max_sea_depth := 0
var warp := {} # the jump in progress: {from, to, relay, interdict} (not saved: you're already at the destination)
var interdictions := 0 # pirate ambushes survived in hyperspace
var volcano := {} # the volcano we're in (not saved: runs always resume on the surface)
var volcanoes := {} # poi key -> {"escapes": n}
var volcano_runs := 0
var lab := {} # Micro Lab: {"grades": {item: grade}, "runs": n, "pristine": n}
var orbit := {} # the world we're orbiting (not saved: orbit always resumes in space)
var species_names := {} # species key -> display name (species log)
var world_species := {} # planet key -> species on that world (for the log)
var space_kills := 0
var _milestone_t := 0.0
var space_spawn := Vector3.ZERO # override spawn when returning from a derelict
var waypoint := {} # {"kind", "id"} chosen on the system map
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
	Sound.apply_keybinds()
	Sound.apply_display()
	_migrate_legacy_save()
	slot = Sound.last_slot
	_build_fader()
	_reset_state()


func _process(delta: float) -> void:
	if in_game and not get_tree().paused:
		play_time += delta
		_autosave_timer += delta
		_milestone_t += delta
		if _milestone_t > 2.0:
			_milestone_t = 0.0
			check_milestones()
		_update_orders(delta)
		_update_workers(delta)
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
		"pause": [KEY_ESCAPE], "ability": [KEY_F], "repair": [KEY_G], "weapon_cycle": [KEY_X], "orbit": [KEY_O], "home": [KEY_Y],
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
	milestones = []
	vault = {}
	vault_level = 0
	inbox = []
	_mail_seq = 0
	_order_t = 240.0
	home_visits = 0
	workers = []
	home = {}
	lab = {}
	crafted_once = []
	gems_taken = {}
	orbit = {}
	seas = {}
	sea = {}
	max_sea_depth = 0
	species_names = {}
	world_species = {}
	space_kills = 0
	lit_relays = [0]
	heart_defeated = false
	boarded = []
	space_spawn = Vector3.ZERO
	waypoint = {}


func new_game(robot: String, pname: String, slot_n := -1) -> void:
	_reset_state()
	if slot_n > 0:
		slot = slot_n
	Sound.last_slot = slot
	Sound.save_settings()
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
	_welcome_mail()
	save_game()
	go_to_planet(0, 0)


func robot() -> Dictionary:
	return Db.ROBOTS[robot_id]


func stat(key: String, default := 1.0) -> float:
	return robot().stats.get(key, default)


func has_upgrade(id: String) -> bool:
	return upgrades.has(id)


func max_energy() -> float:
	var m := 100.0 + stat("max_energy", 0.0) + (level - 1) * 5.0 + milestone_bonus("energy")
	if has_upgrade("capacitor"):
		m += 50.0
	return m


func max_hull() -> float:
	var m := 100.0 + stat("hull", 0.0) + (level - 1) * 6.0 + (skill_level("combat") - 1) + milestone_bonus("hull")
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
	var s := 1.0 + milestone_bonus("harvest")
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
	var xp_amt: float = r.xp * Db.difficulty_xp_mult(r.req, skill_level("engineering"))
	# the first time you fabricate anything teaches you twice as much
	if not crafted_once.has(recipe_id):
		crafted_once.append(recipe_id)
		xp_amt = r.xp * 2.0
		notify.emit("First fabrication: %s  ·  double Engineering XP" % Db.item_name(r.out), Color("8f9bff"))
	gain_skill_xp("engineering", xp_amt)
	_quest_event("craft", r.out, qty)
	return true


func record_scan(species_key: String, display: String) -> bool:
	if scanned.has(species_key):
		return false
	scanned.append(species_key)
	species_names[species_key] = display
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
	var pl: Dictionary = Galaxy.planet(star_index, planet_index)
	if Db.BIOMES[pl.biome].get("legendary", false):
		if not looted_pois.has("legend:" + key):
			looted_pois.append("legend:" + key)
			add_item("legend_shard", 1, true)
			big_notify.emit("EDGE WORLD", "%s  ·  a Legendary Shard hums in the dust at your feet" % pl.name, Color("ffd23f"))
		_quest_event("legendary", key)


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
	tip("quest_star", "Follow the gold ★ on your compass: it points toward your quest objective. Open the Quest log with %s." % key("quests"))
	var o: Dictionary = q.obj
	match o.type:
		"collect":
			quest_baseline = 0
		"land_unique":
			quest_progress = visited_planets.size()
		"relay":
			quest_progress = lit_relays.size() - 1
		"visit_town":
			quest_progress = visited_towns.size()
		"skill":
			quest_progress = skill_level(o.skill)
		"scan":
			quest_progress = 0
		"gem":
			add_item("deep_probe", 2, true)
			notify.emit("+2 Deep Probes loaded", Color("9bd1ff"))
		"gem_types":
			quest_progress = gem_types()
	_reconcile_quest()
	if o.type == "collect" and o.item in ["fire_opal", "obsidian", "core_ember"]:
		var v := nearest_volcanic_world()
		if not v.is_empty():
			notify.emit("Nearest volcanic world: %s in the %s system (%.1f ly)" % [v.name, v.star_name, v.dist], Color("ff8a3d"))
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
		"scan", "warp", "orbit", "kill", "kill_elite", "train", "space_kill", "space_elite", "chamber", "heart":
			quest_progress = mini(o.count, quest_progress + 1)
		"land_unique":
			quest_progress = mini(o.count, visited_planets.size())
		"visit_town":
			quest_progress = mini(o.count, visited_towns.size())
		"dig":
			quest_progress = mini(o.count, quest_progress + amount)
		"relay":
			quest_progress = mini(o.count, lit_relays.size() - 1)
		"legendary":
			quest_progress = mini(o.count, quest_progress + 1)
		"sell", "station_sell":
			quest_progress = mini(o.count, quest_progress + amount)
		"skill":
			if o.skill == what:
				quest_progress = mini(o.count, skill_level(what))
		"gem", "sea_scan", "lab":
			quest_progress = mini(o.count, quest_progress + 1)
		"gem_types":
			quest_progress = mini(o.count, gem_types())
	quest_changed.emit()
	_check_quest_complete()


## A quest asking for something you already have (an upgrade you installed
## earlier, gems already in the hold) counts as done.
func _reconcile_quest() -> void:
	var q := current_quest()
	if q.is_empty() or not quest_accepted:
		return
	var o: Dictionary = q.obj
	if o.type == "craft" and Db.ITEMS.get(o.item, {}).get("kind", "") == "upgrade" and has_upgrade(o.item):
		quest_progress = int(o.count)
	elif o.type == "gem_types":
		quest_progress = mini(int(o.count), gem_types())
	else:
		return
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

## Dev/test scenes save to a scratch file so they never clobber real slots.
static func is_dev_run() -> bool:
	for a in OS.get_cmdline_args():
		if "scenes/dev_" in a:
			return true
	return false


func slot_path(n: int) -> String:
	return "user://star_circuit_dev.json" if is_dev_run() else "user://star_circuit_slot%d.json" % n


func has_save() -> bool:
	for n in range(1, SLOTS + 1):
		if FileAccess.file_exists(slot_path(n)):
			return true
	return false


func _migrate_legacy_save() -> void:
	if is_dev_run():
		return
	if FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(slot_path(1)))


func delete_slot(n: int) -> void:
	if FileAccess.file_exists(slot_path(n)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(n)))


func save_game() -> void:
	if not in_game:
		return
	var data := {
		"version": 2,
		"saved_at": Time.get_unix_time_from_system(),
		"robot_id": robot_id, "player_name": player_name,
		"level": level, "xp": xp, "energy": energy, "hull": hull, "kills": kills,
		"discovered_pois": discovered_pois, "looted_pois": looted_pois, "codex": codex, "surveyed": surveyed,
		"credits": credits, "skill_tiers": skill_tiers, "bounties": bounties, "visited_towns": visited_towns,
		"trader_bought": trader_bought, "quest_id": current_quest().get("id", "done"),
		"appearance": appearance, "owned_cosmetics": owned_cosmetics, "weapon": weapon,
		"milestones": milestones, "crafted_once": crafted_once,
		"workers": workers, "home": home, "interdictions": interdictions, "volcanoes": volcanoes, "volcano_runs": volcano_runs, "lab": lab,
		"vault": vault, "vault_level": vault_level, "inbox": inbox, "mail_seq": _mail_seq, "order_t": _order_t, "home_visits": home_visits, "gems_taken": gems_taken, "seas": seas, "max_sea_depth": max_sea_depth, "species_names": species_names, "world_species": world_species, "space_kills": space_kills,
		"digs": digs, "relics_found": relics_found, "lit_relays": lit_relays, "heart_defeated": heart_defeated, "boarded": boarded,
		"inventory": inventory, "upgrades": upgrades, "skills": skills,
		"star_index": star_index, "planet_index": planet_index, "location": location,
		"visited_planets": visited_planets, "visited_stars": visited_stars,
		"scanned": scanned, "harvested": harvested,
		"quest_index": quest_index, "quest_accepted": quest_accepted, "quest_progress": quest_progress,
		"play_time": play_time,
		"land_dir": [land_dir.x, land_dir.y, land_dir.z],
		"space_pos": [space_return_pos.x, space_return_pos.y, space_return_pos.z],
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func save_summary(n := -1) -> Dictionary:
	if n < 0:
		n = slot
	if not FileAccess.file_exists(slot_path(n)):
		return {}
	var f := FileAccess.open(slot_path(n), FileAccess.READ)
	if not f:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func load_game(n := -1) -> bool:
	if n > 0:
		slot = n
	Sound.last_slot = slot
	Sound.save_settings()
	var d := save_summary(slot)
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
	milestones = d.get("milestones", [])
	gems_taken = d.get("gems_taken", {})
	crafted_once = d.get("crafted_once", [])
	vault = d.get("vault", {})
	for k in vault.keys():
		vault[k] = int(vault[k])
	vault_level = int(d.get("vault_level", 0))
	inbox = d.get("inbox", [])
	_mail_seq = int(d.get("mail_seq", inbox.size()))
	_order_t = float(d.get("order_t", 240.0))
	home_visits = int(d.get("home_visits", 0))
	workers = d.get("workers", [])
	interdictions = int(d.get("interdictions", 0))
	volcanoes = d.get("volcanoes", {})
	volcano_runs = int(d.get("volcano_runs", 0))
	lab = d.get("lab", {})
	home = d.get("home", {})
	if home_visits == 0 and inbox.is_empty():
		_welcome_mail()
	seas = d.get("seas", {})
	max_sea_depth = int(d.get("max_sea_depth", 0))
	species_names = d.get("species_names", {})
	world_species = d.get("world_species", {})
	space_kills = int(d.get("space_kills", 0))
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
	lit_relays = []
	for x in d.get("lit_relays", [0]):
		lit_relays.append(int(x))
	if not lit_relays.has(0):
		lit_relays.append(0)
	heart_defeated = bool(d.get("heart_defeated", false))
	boarded = d.get("boarded", [])
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
	check_milestones(false) # older saves: grant quietly
	_reconcile_quest.call_deferred()
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
	return maxi(1, int(round(Db.VALUES[item] * 0.6 * mod * (1.0 + milestone_bonus("sell")))))


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
	space_kills += 1
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
	var c := Db.CARGO_BASE + int(stat("cargo", 0.0)) + int(milestone_bonus("cargo"))
	if has_upgrade("cargo_pods"):
		c += 100
	if has_upgrade("cargo_pods_mk2"):
		c += 200
	return c


func cargo_free() -> int:
	return maxi(0, cargo_cap() - cargo_used())


## Ask the HUD for a one-time tip (shown once per profile, can be disabled).
func tip(id: String, text: String) -> void:
	if Sound.show_tips and not Sound.seen_tips.has(id):
		tip_requested.emit(id, text)


## "[E]" style label for an action's current key.
func key(action: String) -> String:
	return "[%s]" % Sound.key_name(action)


func _cargo_full_warning() -> void:
	tip("cargo_full", "Your cargo hold is full. Sell surplus at a town Merchant or an orbital station (dock with %s in space), or craft Cargo Pods at the Fabricator %s." % [key("ability"), key("crafting")])
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
	return maxi(1, int(round(Db.VALUES[item] * 0.7 * _station_mod(item, star_i) * (1.0 + milestone_bonus("sell")))))


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
	if cave.get("origin", "") == "space":
		var r: Array = cave.get("return", [0, 0, 0])
		space_spawn = Vector3(r[0], r[1], r[2])
		cave = {}
		go_to_space()
		return
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



# --------------------------------------------------------------------------
# the Circuit: relays, derelicts, the Heart
# --------------------------------------------------------------------------

func relay_lit(star_i: int) -> bool:
	return lit_relays.has(star_i)


func light_relay(star_i: int) -> bool:
	if relay_lit(star_i):
		return false
	if count("resonance_crystal") < 1 or count("relay_coupler") < 1:
		notify.emit("Relighting needs 1 Resonance Crystal and 1 Relay Coupler.", Color("ff6b6b"))
		return false
	remove_item("resonance_crystal", 1)
	remove_item("relay_coupler", 1)
	lit_relays.append(star_i)
	gain_xp(600)
	gain_skill_xp("exploration", 200)
	big_notify.emit("RELAY RELIT", "%s rejoins the Circuit  ·  %d relays lit" % [Galaxy.star(star_i).name, lit_relays.size()], Color("5ff7ff"))
	_quest_event("relay", str(star_i))
	save_game()
	return true


func enter_derelict(star_i: int, idx: int, return_pos: Vector3) -> void:
	var key := "derelict:%d:%d" % [star_i, idx]
	cave = {"key": key, "origin": "space", "seed": hash(key), "biome": "forge", "star": star_i, "planet": 0,
		"chamber": {"id": idx, "theme": "derelict"}, "return": [return_pos.x, return_pos.y, return_pos.z]}
	save_game()
	Sound.play("atmo_entry", -8.0, 0.0)
	fade_to("res://scenes/grotto.tscn")


func defeat_heart() -> void:
	heart_defeated = true
	_quest_event("heart", "heart")
	save_game()



# --------------------------------------------------------------------------
# milestones + species log
# --------------------------------------------------------------------------

func metric(m: String) -> int:
	match m:
		"worlds": return visited_planets.size()
		"stars": return visited_stars.size()
		"species": return scanned.size()
		"surveyed": return surveyed.size()
		"kills": return kills
		"space_kills": return space_kills
		"towns": return visited_towns.size()
		"codex": return codex.size()
		"relics": return relics_found
		"gem_types": return gem_types()
		"sea_depth": return max_sea_depth
		"volcano_runs": return volcano_runs
		"lab_pristine": return int(lab_state().pristine)
		"relays": return lit_relays.size() - 1 # Solace's relay starts lit
		"best_skill":
			var b := 0
			for s in skills:
				b = maxi(b, int(skills[s].level))
			return b
	return 0


func milestone_bonus(kind: String) -> float:
	var t := 0.0
	if has_upgrade("crown_of_worlds"):
		t += {"energy": 50.0, "hull": 50.0, "harvest": 0.2, "sell": 0.1}.get(kind, 0.0)
	for m in Db.MILESTONES:
		if milestones.has(m.id):
			t += float(m.bonus.get(kind, 0.0))
	return t + lab_bonus(kind)


static func bonus_text(b: Dictionary) -> String:
	var parts: Array[String] = []
	for k in b:
		match k:
			"energy": parts.append("+%d max energy" % int(b[k]))
			"hull": parts.append("+%d max hull" % int(b[k]))
			"cargo": parts.append("+%d cargo" % int(b[k]))
			"harvest": parts.append("+%d%% harvest speed" % int(round(b[k] * 100)))
			"sell": parts.append("+%d%% sell prices" % int(round(b[k] * 100)))
	return ", ".join(parts)


func check_milestones(announce := true) -> void:
	for m in Db.MILESTONES:
		if milestones.has(m.id) or metric(m.metric) < int(m.n):
			continue
		milestones.append(m.id)
		if not announce:
			continue
		big_notify.emit("MILESTONE: " + (m.name as String).to_upper(), "%s  ·  %s" % [m.desc, bonus_text(m.bonus)], Color("ffd23f"))
		Sound.play("quest_complete", -4.0, 0.0, "UI")
		energy_changed.emit(energy, max_energy())
		hull_changed.emit()


## Remember how many species live on a world, for the species log.
func note_world_species(planet_key: String, planet_name: String, biome: String, total: int) -> void:
	world_species[planet_key] = {"name": planet_name, "biome": biome, "total": total}



# --------------------------------------------------------------------------
# orbit + world gems
# --------------------------------------------------------------------------

const GEM_KINDS := ["gem_verdant", "gem_dune", "gem_frost", "gem_ember", "gem_prism", "gem_bloom", "gem_giant", "gem_abyss", "gem_tempest", "gem_forge"]


## How many different world gems you hold (the Crown consumes them).
func gem_types() -> int:
	var n := 0
	for g in GEM_KINDS:
		if count(g) > 0:
			n += 1
	return n


## Everything the orbit view needs to know about a world.
## kind "planet" uses star/index; kind "giant" is the system's gas giant.
func orbit_info(kind: String, star_i: int, index: int) -> Dictionary:
	if kind == "giant":
		var st: Dictionary = Galaxy.star(star_i)
		var g: Dictionary = st.giant
		return {"kind": "giant", "key": "giant:%d" % star_i, "name": g.name, "biome": "giant", "gem": "gem_giant",
			"seed": hash("giant:%d" % star_i), "hue": g.hue, "rings": g.rings, "star": star_i, "index": -1}
	var p: Dictionary = Galaxy.planet(star_i, index)
	return {"kind": "planet", "key": p.key, "name": p.name, "biome": p.biome, "gem": "gem_" + p.biome,
		"seed": int(p.seed), "rings": p.get("rings", false), "star": star_i, "index": index}


## Gems buried in a world: deterministic, 1-3 of them (3 on edge worlds).
func world_gems(info: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(info.key) + ":gems")
	var n := 1 + (1 if rng.randf() < 0.55 else 0) + (1 if rng.randf() < 0.25 else 0)
	if info.biome in ["abyss", "tempest", "forge"]:
		n = 3
	elif info.kind == "giant":
		n = maxi(n, 2)
	var out := []
	for i in n:
		# deeper gems sit nearer the core, where the heat is
		out.append({"idx": i, "angle": rng.randf() * TAU + i * TAU / n, "depth": rng.randf_range(0.35, 0.78)})
	return out


func gems_left(info: Dictionary) -> int:
	var taken: Array = gems_taken.get(info.key, [])
	return world_gems(info).size() - taken.size()


func take_gem(info: Dictionary, idx: int) -> void:
	if not gems_taken.has(info.key):
		gems_taken[info.key] = []
	if (gems_taken[info.key] as Array).has(idx):
		return
	gems_taken[info.key].append(idx)
	add_item(info.gem, 1, true)
	big_notify.emit("GEM EXTRACTED", "%s from %s  ·  %d different gems held" % [Db.item_name(info.gem), info.name, gem_types()], Db.item_color(info.gem))
	gain_skill_xp("exploration", 120)
	gain_skill_xp("mining", 60)
	gain_xp(250)
	_quest_event("gem", info.gem)
	_quest_event("gem_types", info.gem)
	save_game()


func enter_orbit(info: Dictionary, return_pos: Vector3) -> void:
	orbit = info.duplicate()
	orbit["return"] = [return_pos.x, return_pos.y, return_pos.z]
	save_game()
	Sound.play("boost", -6.0, 0.0)
	fade_to("res://scenes/orbit.tscn")


func leave_orbit() -> void:
	var r: Array = orbit.get("return", [0, 0, 0])
	space_spawn = Vector3(r[0], r[1], r[2])
	orbit = {}
	go_to_space()



# --------------------------------------------------------------------------
# the Deep Sea
# --------------------------------------------------------------------------

## Oceans are split into a few regions per world, so different coasts
## lead down into different deeps.
func sea_key(dir: Vector3, planet: Dictionary) -> String:
	var r := Vector3i((dir * 1.5).round())
	return "%s:sea:%d,%d,%d" % [planet.key, r.x, r.y, r.z]


func sea_state(key: String) -> Dictionary:
	if not seas.has(key):
		seas[key] = {"dug": "", "opened": [], "wreck": false}
	return seas[key]


func enter_sea(dir: Vector3, planet: Dictionary) -> void:
	var key := sea_key(dir, planet)
	sea = {"key": key, "dir": [dir.x, dir.y, dir.z], "seed": hash(key) ^ int(planet.seed), "biome": planet.biome,
		"star": star_index, "planet": planet_index, "pos": []}
	land_dir = dir
	save_game()
	Sound.play("atmo_entry", -10.0, 0.0)
	fade_to("res://scenes/sea.tscn")


func leave_sea() -> void:
	var d: Array = sea.get("dir", [0, 1, 0])
	land_dir = Vector3(d[0], d[1], d[2])
	sea = {}
	go_to_planet(star_index, planet_index)


func record_sea_scan(key: String, display: String) -> bool:
	if record_scan(key, display):
		_quest_event("sea_scan", key)
		return true
	return false


func record_sea_depth(m: int) -> void:
	if m > max_sea_depth:
		max_sea_depth = m



# --------------------------------------------------------------------------
# the Homespace: vault, inbox, uplink
# --------------------------------------------------------------------------

const VAULT_BASE := 300
const VAULT_STEP := 300
const VAULT_UPGRADES := [400, 1200, 3000, 6000]


func vault_cap() -> int:
	return VAULT_BASE + VAULT_STEP * vault_level


func vault_used() -> int:
	var n := 0
	for k in vault:
		n += int(vault[k])
	return n


func vault_count(item: String) -> int:
	return int(vault.get(item, 0))


## How good the uplink home is from here. Lit relays carry the signal; the
## rock of a cave or the weight of an ocean muffle it.
func uplink_signal() -> Dictionary:
	var s := 1.0 if relay_lit(star_index) else 0.4
	var where := "Relay lit in this system" if relay_lit(star_index) else "No lit relay in this system"
	if not cave.is_empty() or not sea.is_empty():
		s *= 0.5
		where += ", and you're deep underground" if sea.is_empty() else ", and you're deep underwater"
	return {"strength": s, "label": where}


## Energy to move this many units between the hold and the vault.
func uplink_cost(units: int) -> float:
	var s: float = uplink_signal().strength
	return units * lerpf(0.35, 0.04, clampf(s, 0.0, 1.0))


func can_vault(item: String) -> bool:
	return Db.ITEMS.has(item) and Db.ITEMS[item].kind != "upgrade"


## Hold -> vault. Returns units moved (limited by space and energy).
func vault_deposit(item: String, qty: int) -> int:
	if not can_vault(item):
		return 0
	qty = mini(qty, count(item))
	qty = mini(qty, vault_cap() - vault_used())
	if qty <= 0:
		if vault_used() >= vault_cap():
			notify.emit("Vault full. Expand its memory in the Homespace.", Color("ff6b6b"))
		return 0
	qty = _affordable(qty)
	if qty <= 0:
		return 0
	energy -= uplink_cost(qty)
	energy_changed.emit(energy, max_energy())
	remove_item(item, qty)
	vault[item] = vault_count(item) + qty
	return qty


## Vault -> hold. Cargo items still have to fit in the hold.
func vault_withdraw(item: String, qty: int) -> int:
	qty = mini(qty, vault_count(item))
	if is_cargo(item):
		qty = mini(qty, cargo_free())
		if qty <= 0:
			_cargo_full_warning()
			return 0
	qty = _affordable(qty)
	if qty <= 0:
		return 0
	energy -= uplink_cost(qty)
	energy_changed.emit(energy, max_energy())
	vault[item] = vault_count(item) - qty
	if vault[item] <= 0:
		vault.erase(item)
	add_item(item, qty, true, true)
	return qty


func _affordable(qty: int) -> int:
	var per := uplink_cost(1)
	if per <= 0.0:
		return qty
	var can := int(floor(energy / per))
	if can < qty:
		if can <= 0:
			notify.emit("Not enough energy to uplink. Recharge or find a lit relay.", Color("ff6b6b"))
		qty = can
	return maxi(qty, 0)


func vault_expand() -> bool:
	if vault_level >= VAULT_UPGRADES.size():
		return false
	var cost: int = VAULT_UPGRADES[vault_level]
	if credits < cost:
		notify.emit("Need ⌬ %d to expand the vault." % cost, Color("ff6b6b"))
		return false
	add_credits(-cost, true)
	vault_level += 1
	notify.emit("Vault memory expanded to %d units." % vault_cap(), Color("5ff7ff"))
	return true


func send_mail(from: String, subject: String, body: String, items := {}, cr := 0, kind := "letter", order := {}) -> void:
	_mail_seq += 1
	inbox.push_front({"id": _mail_seq, "from": from, "subject": subject, "body": body, "items": items, "credits": cr,
		"read": false, "claimed": items.is_empty() and cr == 0, "kind": kind, "order": order, "t": play_time})
	while inbox.size() > 40:
		inbox.pop_back()
	mail_changed.emit()
	if home_visits > 0:
		notify.emit("New message in your Homespace (%s)" % key("home"), Color("5ff7ff"))
		Sound.play("notify", -10.0, 0.0, "UI")


func unread_mail() -> int:
	var n := 0
	for m in inbox:
		if not m.read:
			n += 1
	return n


func mail_by_id(id: int) -> Dictionary:
	for m in inbox:
		if int(m.id) == id:
			return m
	return {}


## Take a message's attachments: into the hold, or straight to the vault.
func mail_claim(id: int, to_vault := false) -> void:
	var m := mail_by_id(id)
	if m.is_empty() or m.claimed:
		return
	if int(m.credits) > 0:
		add_credits(int(m.credits))
	for it in m.items:
		var q := int(m.items[it])
		if to_vault and can_vault(it):
			var room := vault_cap() - vault_used()
			var put := mini(q, room)
			vault[it] = vault_count(it) + put
			q -= put
		if q > 0:
			add_item(it, q, true, true)
	m.claimed = true
	mail_changed.emit()


func mail_delete(id: int) -> void:
	var m := mail_by_id(id)
	if not m.is_empty():
		inbox.erase(m)
		mail_changed.emit()


## Standing orders from traders you've met: fill them from the vault (or the
## hold) from anywhere, for more than a merchant would pay.
func order_fillable(m: Dictionary) -> bool:
	var o: Dictionary = m.get("order", {})
	return not o.is_empty() and not o.get("done", false) and vault_count(o.item) + count(o.item) >= int(o.qty) and play_time < float(o.expires)


func order_fulfill(id: int) -> bool:
	var m := mail_by_id(id)
	if m.is_empty() or not order_fillable(m):
		return false
	var o: Dictionary = m.order
	var need := int(o.qty)
	var from_vault := mini(need, vault_count(o.item))
	if from_vault > 0:
		vault[o.item] = vault_count(o.item) - from_vault
		if vault[o.item] <= 0:
			vault.erase(o.item)
	if need - from_vault > 0:
		remove_item(o.item, need - from_vault)
	o["done"] = true
	m.claimed = true
	add_credits(int(o.pay))
	gain_skill_xp("exploration", 20)
	_quest_event("sell", o.item, need)
	Sound.play("coin", -4.0, 0.0, "UI")
	mail_changed.emit()
	return true


func _update_orders(delta: float) -> void:
	# expire old orders
	for m in inbox:
		var o: Dictionary = m.get("order", {})
		if not o.is_empty() and not o.get("done", false) and play_time >= float(o.expires) and not o.get("expired", false):
			o["expired"] = true
			m.claimed = true
	if visited_towns.is_empty():
		return
	_order_t -= delta
	if _order_t > 0.0:
		return
	_order_t = randf_range(420.0, 720.0)
	var open := 0
	for m in inbox:
		var o: Dictionary = m.get("order", {})
		if not o.is_empty() and not o.get("done", false) and not o.get("expired", false):
			open += 1
	if open >= 3:
		return
	var tk: String = visited_towns[randi() % visited_towns.size()]
	var parts := tk.split(":")
	var pl: Dictionary = Galaxy.planet(int(parts[0]), int(parts[1]))
	if pl.get("town", {}).is_empty():
		return
	var pool := ["ferrite", "biofiber", "plasma", "alloy", "nickel", "cryo_ice", "kelp"]
	if level >= 5:
		pool.append_array(["cobalt", "sporegel", "polymer", "scrap"])
	if level >= 10:
		pool.append_array(["lumen", "circuit", "stardust"])
	if level >= 16:
		pool.append_array(["voidshard", "exotic", "sea_pearl"])
	var item: String = pool[randi() % pool.size()]
	var value := int(Db.VALUES.get(item, 5))
	var qty := clampi(int(round(float(randi_range(160, 320)) / value)), 2, 30)
	var pay := int(round(qty * value * randf_range(1.3, 1.7)))
	var town_name: String = pl.town.name
	send_mail(town_name, "Order: %d %s" % [qty, Db.item_name(item)],
		"We're short on %s at %s and can't wait for a caravan. Beam it to us from your vault and we'll pay well over market." % [Db.item_name(item), town_name],
		{}, 0, "order", {"item": item, "qty": qty, "pay": pay, "expires": play_time + 1500.0, "town": tk})


func _welcome_mail() -> void:
	send_mail("The Archivist", "Welcome home, Unit",
		"Every frame in the Circuit carries a little space inside it: your Homespace. Step in from anywhere with %s. The Vault here holds what your cargo hold can't, though uplinking costs energy, and less where a relay is lit. Letters and trader orders arrive in this Inbox. Look after the place. It is the only home a nomad gets." % key("home"),
		{"energy_cell": 2}, 50)


func open_home() -> void:
	if in_home or not in_game or ui_open or get_tree().paused:
		return
	var sc := get_tree().current_scene
	if sc == null or not sc.name in ["Planet", "Space", "Dig", "Sea", "Grotto", "Orbit"]:
		return
	if hull <= 0.0:
		return
	var p = sc.get("player")
	if p and (p.get("dead") == true or p.get("launching") == true):
		return
	var home := preload("res://scripts/home/homespace.gd").new()
	get_tree().root.add_child(home)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("home"):
		open_home()



# --------------------------------------------------------------------------
# Homespace: subroutine workers
# --------------------------------------------------------------------------

func worker_cost() -> int:
	return Db.WORKER_COSTS[workers.size()] if workers.size() < Db.WORKER_COSTS.size() else -1


func worker_compile() -> Dictionary:
	var cost := worker_cost()
	if cost < 0:
		return {}
	if credits < cost:
		notify.emit("Need ⌬ %d to compile another subroutine." % cost, Color("ff6b6b"))
		return {}
	if cost > 0:
		add_credits(-cost, true)
	var used := workers.map(func(w): return w.name)
	var wname: String = Db.WORKER_NAMES[workers.size() % Db.WORKER_NAMES.size()]
	for n in Db.WORKER_NAMES:
		if not used.has(n):
			wname = n
			break
	var w := {"id": workers.size() + 1, "name": wname, "level": 1, "xp": 0, "state": "idle", "job": {}, "hurt_left": 0.0}
	workers.append(w)
	notify.emit("Subroutine %s compiled and ready for work." % wname, Color("5ff7ff"))
	return w


func worker_by_id(id: int) -> Dictionary:
	for w in workers:
		if int(w.id) == id:
			return w
	return {}


## Worlds a worker can be sent to: ones you've landed on (for haul: ones with a town you've visited).
func job_targets(kind: String) -> Array:
	var out := []
	var src: Array = visited_towns if kind == "haul" else visited_planets
	for k in src:
		var parts := (k as String).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int():
			continue
		out.append(k)
	return out


func _planet_of(key: String) -> Dictionary:
	var parts := key.split(":")
	return Galaxy.planet(int(parts[0]), int(parts[1]))


## What a job would do, before committing to it.
func job_preview(w: Dictionary, kind: String, target: String, minutes: int, item := "") -> Dictionary:
	var pl := _planet_of(target)
	var parts := target.split(":")
	var danger := planet_level(int(parts[0]), int(parts[1]))
	var lvl := int(w.level)
	var risk := clampf(4.0 + (danger - lvl * 3) * 6.0, 3.0, 70.0)
	var mult := 1.0 + 0.15 * (lvl - 1)
	var out := {"risk": risk, "danger": danger, "planet": pl.name, "minutes": minutes}
	match kind:
		"gather":
			var items := {}
			var cap := 10 + lvl * 10
			var b: Dictionary = Db.BIOMES.get(pl.biome, Db.BIOMES.verdant)
			var total := 0
			for n in b.nodes:
				if int(Db.NODES[n].req) <= cap:
					total += int(b.nodes[n])
			for n in b.nodes:
				if int(Db.NODES[n].req) <= cap and total > 0:
					var it: String = Db.NODES[n].item
					var q := int(round(3.0 * minutes * mult * float(b.nodes[n]) / total))
					if q > 0:
						items[it] = int(items.get(it, 0)) + q
			out["items"] = items
			out["summary"] = ", ".join(items.keys().map(func(k): return "%d %s" % [items[k], Db.item_name(k)]))
		"survey":
			var cr := int(round(22.0 * minutes * mult))
			out["credits"] = cr
			out["summary"] = "⌬ %d in survey fees, some Exploration XP, a chance of fossils and relics" % cr
		"haul":
			risk = clampf(risk * 0.4, 2.0, 30.0)
			out["risk"] = risk
			var capn := 40 + 20 * lvl + minutes * 2
			var have := vault_count(item)
			var q2 := mini(capn, have)
			var price := sell_price(item, pl) if item != "" else 0
			out["qty"] = q2
			out["capacity"] = capn
			out["credits"] = q2 * price
			out["summary"] = ("Sell %d %s at %s for about ⌬ %d" % [q2, Db.item_name(item), pl.get("town", {}).get("name", pl.name), q2 * price]) if item != "" and q2 > 0 else "Choose something in your vault to haul"
	return out


func job_start(id: int, kind: String, target: String, minutes: int, item := "") -> bool:
	var w := worker_by_id(id)
	if w.is_empty() or w.state != "idle":
		return false
	var pv := job_preview(w, kind, target, minutes, item)
	if kind == "haul":
		if int(pv.qty) <= 0:
			notify.emit("Nothing to haul.", Color("ff6b6b"))
			return false
		vault[item] = vault_count(item) - int(pv.qty)
		if vault[item] <= 0:
			vault.erase(item)
	w.state = "job"
	w.job = {"kind": kind, "target": target, "minutes": minutes, "left": minutes * 60.0, "item": item, "qty": int(pv.get("qty", 0)), "risk": float(pv.risk)}
	notify.emit("%s heads out: %s on %s (%d min)." % [w.name, Db.JOBS[kind].name, pv.planet, minutes], Color("5ff7ff"))
	return true


func job_recall(id: int) -> void:
	var w := worker_by_id(id)
	if w.is_empty() or w.state != "job":
		return
	# hauled goods come back with it
	if w.job.kind == "haul" and int(w.job.qty) > 0:
		vault[w.job.item] = vault_count(w.job.item) + int(w.job.qty)
	w.state = "idle"
	w.job = {}


func worker_repair(id: int) -> bool:
	var w := worker_by_id(id)
	if w.is_empty() or w.state != "hurt":
		return false
	if not remove_item("repair_kit", 1):
		if vault_count("repair_kit") > 0:
			vault["repair_kit"] = vault_count("repair_kit") - 1
			if vault["repair_kit"] <= 0:
				vault.erase("repair_kit")
		else:
			notify.emit("Needs a Repair Kit (hold or vault).", Color("ff6b6b"))
			return false
	w.state = "idle"
	w.hurt_left = 0.0
	return true


func _update_workers(delta: float) -> void:
	for w in workers:
		match w.state:
			"job":
				w.job.left = float(w.job.left) - delta
				if float(w.job.left) <= 0.0:
					_job_done(w)
			"hurt":
				w.hurt_left = float(w.hurt_left) - delta
				if float(w.hurt_left) <= 0.0:
					w.state = "idle"
					notify.emit("%s has patched itself up." % w.name, Color("6ee06a"))


func _job_done(w: Dictionary) -> void:
	var j: Dictionary = w.job
	var pv := job_preview(w, j.kind, j.target, int(j.minutes), j.get("item", ""))
	var hurt := randf() * 100.0 < float(j.risk)
	var k := 0.5 if hurt else 1.0
	var lines: Array[String] = []
	var parcel := {}
	var cr := 0
	match j.kind:
		"gather":
			for it in pv.items:
				var q := int(round(int(pv.items[it]) * k))
				if q > 0:
					parcel[it] = q
		"survey":
			cr = int(round(int(pv.credits) * k))
			gain_skill_xp("exploration", float(j.minutes) * 6.0 * k)
			if randf() < 0.1 * float(j.minutes) / 10.0:
				parcel["fossil"] = 1
			if randf() < 0.04 * float(j.minutes) / 10.0:
				parcel["ancient_relic"] = 1
		"haul":
			var sold := int(round(int(j.qty) * (0.8 if hurt else 1.0)))
			var pl := _planet_of(j.target)
			cr = sold * sell_price(j.item, pl)
			lines.append("Sold %d %s at %s." % [sold, Db.item_name(j.item), pl.get("town", {}).get("name", pl.name)])
			if hurt:
				lines.append("Pirates took %d on the way." % (int(j.qty) - sold))
	# deliver: resources into the vault where they fit, the rest (and credits) by parcel
	var leftover := {}
	for it in parcel:
		var room := vault_cap() - vault_used()
		var put := mini(int(parcel[it]), room)
		if put > 0:
			vault[it] = vault_count(it) + put
			lines.append("%d %s stored in the vault." % [put, Db.item_name(it)])
		if int(parcel[it]) - put > 0:
			leftover[it] = int(parcel[it]) - put
	if cr > 0 and j.kind != "haul":
		lines.append("Earned ⌬ %d." % cr)
	# experience
	w.xp = int(w.xp) + int(j.minutes) * 10
	var leveled := false
	while int(w.level) < Db.WORKER_MAX_LEVEL and int(w.xp) >= 100 * int(w.level):
		w.xp = int(w.xp) - 100 * int(w.level)
		w.level = int(w.level) + 1
		leveled = true
	if leveled:
		lines.append("Level up! %s is now level %d." % [w.name, w.level])
	if hurt:
		w.state = "hurt"
		w.hurt_left = 300.0
		lines.append("Came back damaged: repair it with a Repair Kit, or it will patch itself in 5 minutes.")
	else:
		w.state = "idle"
	w.job = {}
	send_mail("%s (subroutine)" % w.name, "Report: %s on %s" % [Db.JOBS[j.kind].name, pv.planet], "\n".join(lines), leftover, cr, "report")


# --------------------------------------------------------------------------
# Homespace: decor, themes, wings, the defrag pod
# --------------------------------------------------------------------------

func home_state() -> Dictionary:
	if home.is_empty():
		home = {"owned": ["bonsai"], "slots": {"f2": "bonsai"}, "theme": "midnight", "themes": ["midnight"], "wings": 0, "charge_at": -9999.0}
	return home


func decor_buy(id: String) -> bool:
	var h := home_state()
	if (h.owned as Array).has(id):
		return false
	var price: int = Db.DECOR[id].price
	if credits < price:
		notify.emit("Need ⌬ %d." % price, Color("ff6b6b"))
		return false
	add_credits(-price, true)
	h.owned.append(id)
	return true


func decor_place(slot: String, id: String) -> void:
	var h := home_state()
	# floor pieces go in floor spots (f*), wall pieces in wall spots (w*)
	if id != "" and (Db.DECOR[id].slot == "floor") != slot.begins_with("f"):
		return
	# a piece can only stand in one place at a time
	for k in h.slots.keys():
		if h.slots[k] == id:
			h.slots.erase(k)
	if id == "":
		h.slots.erase(slot)
	else:
		h.slots[slot] = id


func theme_buy(id: String) -> bool:
	var h := home_state()
	if not (h.themes as Array).has(id):
		var price: int = Db.HOME_THEMES[id].price
		if credits < price:
			notify.emit("Need ⌬ %d." % price, Color("ff6b6b"))
			return false
		add_credits(-price, true)
		h.themes.append(id)
	h.theme = id
	return true


func wing_buy() -> bool:
	var h := home_state()
	var n := int(h.wings)
	if n >= Db.HOME_WINGS.size():
		return false
	var price: int = Db.HOME_WINGS[n][1]
	if credits < price:
		notify.emit("Need ⌬ %d." % price, Color("ff6b6b"))
		return false
	add_credits(-price, true)
	h.wings = n + 1
	notify.emit("%s compiled. Your Homespace grew." % Db.HOME_WINGS[n][0], Color("5ff7ff"))
	return true


const CHARGE_COOLDOWN := 720.0 # one in-game day

func charge_ready() -> float:
	return maxf(0.0, float(home_state().charge_at) + CHARGE_COOLDOWN - play_time)


func charge_use() -> bool:
	if charge_ready() > 0.0:
		return false
	home_state().charge_at = play_time
	hull = max_hull()
	energy = max_energy()
	shield = max_shield()
	hull_changed.emit()
	energy_changed.emit(energy, max_energy())
	return true



# --------------------------------------------------------------------------
# hyperspace
# --------------------------------------------------------------------------

## Begin a jump. The destination is committed (and saved) now, so quitting
## mid-jump lands you there; the hyperspace run is the trip itself.
func start_warp(to: int, relay := false) -> void:
	var from := star_index
	var dist := Galaxy.distance(from, to)
	var lvl := space_level(to)
	# pirates lurk on long, dangerous lanes; the relit Circuit is mostly safe
	var chance := clampf(0.2 + lvl * 0.025 + dist * 0.004, 0.2, 0.75)
	if relay:
		chance *= 0.3
	var interdict := randf() < chance
	if visited_stars.size() <= 1 and not relay:
		interdict = true # the first warp always shows you what hyperspace is like
	warp = {"from": from, "to": to, "relay": relay, "interdict": interdict, "dist": dist, "level": maxi(1, lvl - (2 if visited_stars.size() <= 1 else 0))}
	star_index = to
	planet_index = 0
	arrived_by_warp = true
	location = "space"
	record_warp(to)
	save_game()
	fade_to("res://scenes/hyperspace.tscn")


func finish_warp(result: Dictionary = {}) -> void:
	if result.get("repelled", false):
		interdictions += 1
	warp = {}
	go_to_space()



# --------------------------------------------------------------------------
# volcanoes: the eruption run
# --------------------------------------------------------------------------

func enter_volcano(poi_key: String, dir: Vector3, planet_seed: int, biome: String) -> void:
	var runs := int(volcanoes.get(poi_key, {}).get("escapes", 0))
	volcano = {"key": poi_key, "dir": [dir.x, dir.y, dir.z], "seed": hash(poi_key) ^ planet_seed ^ (runs * 7919), "biome": biome,
		"star": star_index, "planet": planet_index}
	land_dir = dir
	save_game()
	Sound.play("atmo_entry", -8.0, 0.0)
	fade_to("res://scenes/volcano.tscn")


func leave_volcano(escaped: bool) -> void:
	if escaped:
		var k: String = volcano.get("key", "")
		if not volcanoes.has(k):
			volcanoes[k] = {"escapes": 0}
		volcanoes[k].escapes = int(volcanoes[k].escapes) + 1
		volcano_runs += 1
	var d: Array = volcano.get("dir", [0, 1, 0])
	land_dir = Vector3(d[0], d[1], d[2])
	volcano = {}
	go_to_planet(star_index, planet_index)



## The closest world with lava (and so Volcanic Vents), for quest guidance.
func nearest_volcanic_world() -> Dictionary:
	var best := {}
	for s in Galaxy.stars.size():
		for p in Galaxy.star(s).planets:
			if Db.BIOMES[p.biome].get("lava", false):
				var d := Galaxy.distance(star_index, s)
				if best.is_empty() or d < float(best.dist):
					best = {"name": p.name, "star": s, "index": p.index, "star_name": Galaxy.star(s).name, "dist": d}
	return best


# --------------------------------------------------------------------------
# Micro Lab: cultures grown in the Homespace soup
# --------------------------------------------------------------------------

func lab_state() -> Dictionary:
	if lab.is_empty():
		lab = {"grades": {}, "runs": 0, "pristine": 0}
	return lab


## The best grade grown for a lab upgrade, or -1 if never grown.
func lab_grade(item: String) -> int:
	return int(lab_state().grades.get(item, -1))


func lab_bonus(kind: String) -> float:
	var t := 0.0
	var g: Dictionary = lab_state().grades
	for r in Db.LAB_RECIPES:
		if r.has("bonus") and g.has(r.out) and has_upgrade(r.out):
			t += float(r.bonus[clampi(int(g[r.out]), 0, 2)].get(kind, 0.0))
	return t


## In the Homespace the lab can draw on the hold and the vault together.
func lab_have(item: String) -> int:
	return count(item) + vault_count(item)


## Why a culture can't start yet, or "" if it can.
func lab_block(r: Dictionary) -> String:
	if skill_level(r.skill) < int(r.req):
		return "Requires %s %d" % [Db.SKILLS[r.skill].name, int(r.req)]
	if r.has("bonus") and lab_grade(r.out) >= 2:
		return "Already Pristine"
	for k in r.in:
		if lab_have(k) < int(r.in[k]):
			return "Missing ingredients"
	return ""


## Load the ingredients into the dish (from the hold first, then the vault).
func lab_start(id: String) -> bool:
	var r := Db.lab_recipe(id)
	if r.is_empty() or lab_block(r) != "":
		return false
	for k in r.in:
		var need := int(r.in[k])
		var from_hold := mini(count(k), need)
		if from_hold > 0:
			remove_item(k, from_hold)
		if need > from_hold:
			vault[k] = vault_count(k) - (need - from_hold)
			if int(vault[k]) <= 0:
				vault.erase(k)
	return true


## Finish a culture. grade 0-2 on success, -1 if it went off (half the
## ingredients are recovered). Returns {"ok", "grade", "text"}.
func lab_finish(id: String, grade: int) -> Dictionary:
	var r := Db.lab_recipe(id)
	var st := lab_state()
	if r.is_empty():
		return {"ok": false, "grade": -1, "text": ""}
	if grade < 0:
		var back: Array[String] = []
		for k in r.in:
			var q := int(r.in[k]) >> 1
			if q > 0:
				add_item(k, q, true, true)
				back.append("%d %s" % [q, Db.item_name(k)])
		return {"ok": false, "grade": -1, "text": "The culture went off. Recovered " + (", ".join(back) if not back.is_empty() else "nothing") + "."}
	grade = clampi(grade, 0, 2)
	st.runs = int(st.runs) + 1
	if grade == 2:
		st.pristine = int(st.pristine) + 1
	var text := ""
	if r.has("bonus"):
		var prev := lab_grade(r.out)
		if grade > prev:
			st.grades[r.out] = grade
		if not has_upgrade(r.out):
			add_item(r.out, 1, true, true)
		upgrades_changed()
		var best := lab_grade(r.out)
		text = "%s %s: %s" % [Db.LAB_GRADES[best], Db.item_name(r.out), bonus_text(r.bonus[best])]
		if prev >= 0 and grade <= prev:
			text = "No better than your %s culture. %s" % [Db.LAB_GRADES[prev], text]
	else:
		var q: int = r.qty[grade]
		add_item(r.out, q, true, true)
		text = "+%d %s" % [q, Db.item_name(r.out)]
	gain_skill_xp(r.skill, float(r.xp) * (1.0 + 0.5 * grade))
	_quest_event("lab", id)
	check_milestones()
	return {"ok": true, "grade": grade, "text": text}


## Bonus-carrying upgrades change caps: tell the HUD.
func upgrades_changed() -> void:
	energy_changed.emit(energy, max_energy())
	hull_changed.emit()
	inventory_changed.emit()
