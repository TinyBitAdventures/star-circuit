extends Node
## Headless balance audit of the quest line. For each quest in order:
## what professions it forces (recipe and gathering requirements, walked
## down to raw materials), whether that needs a new training tier, and
## whether the credits earned from quests so far cover the training.
## Also checks every required item has at least one source.
## Prints FAIL lines for anything unreachable.

const DigWorld = preload("res://scripts/dig/dig_world.gd")
const SeaWorld = preload("res://scripts/sea/sea_world.gd")

var sources := {} # item -> [[skill, req, "where"]]
var fails := 0


func _ready() -> void:
	_build_sources()
	var credits := 0
	var trained := {} # skill -> tier index bought
	var reward_items := {}
	var i := 0
	for q in Db.QUESTS:
		var gates := {} # skill -> level
		var o: Dictionary = q.obj
		match o.type:
			"craft":
				_need_craft(o.item, gates, reward_items)
			"collect":
				_need_item(o.item, gates, reward_items)
			"skill":
				gates[o.skill] = maxi(int(gates.get(o.skill, 0)), int(o.count))
			"relay":
				_need_craft("relay_coupler", gates, reward_items)
			"gem", "gem_types":
				_need_craft("deep_probe", gates, reward_items)
			"sea_scan", "dig", "chamber":
				pass
		var notes: Array[String] = []
		for sk in gates:
			var lvl: int = gates[sk]
			var tier := 0
			for t in Db.SKILL_TIERS.size():
				if lvl > int(Db.SKILL_TIERS[t].cap) and t + 1 < Db.SKILL_TIERS.size():
					tier = t + 1
			if tier > int(trained.get(sk, 0)):
				var cost := 0
				for t in range(int(trained.get(sk, 0)) + 1, tier + 1):
					cost += int(Db.SKILL_TIERS[t].cost)
				notes.append("TRAIN %s to %s (%d cr)" % [sk, Db.SKILL_TIERS[tier].name, cost])
				if cost > credits + 600: # quest credits plus a modest amount from selling
					notes.append("WARN: training costs more than quest credits so far (%d)" % credits)
				credits -= cost
				trained[sk] = tier
		print("[bal] %2d %-12s gates=%s credits_before=%d %s" % [i, q.id, JSON.stringify(gates), credits, "  ".join(notes)])
		credits += int(q.get("credits", 0))
		for k in q.reward:
			reward_items[k] = true
		i += 1
	print("[bal] done, fails=%d" % fails)
	get_tree().quit()


func _build_sources() -> void:
	for n in Db.NODES:
		_src(Db.NODES[n].item, Db.NODES[n].skill, int(Db.NODES[n].req), "node " + n)
	for o in DigWorld.ORES:
		_src(o.item, "mining", int(o.req), "cave")
	for o in SeaWorld.ORES:
		_src(o.item, "mining", int(o.req), "deep sea")
	for a in Db.ASTEROIDS:
		for it in Db.ASTEROIDS[a].items:
			_src(it, "mining", int(Db.ASTEROIDS[a].req), "asteroid " + a)
	# drops and finds that aren't gated by a profession level
	for it in ["scrap", "power_core", "kelp", "sea_pearl", "resonance_crystal", "ancient_relic", "fossil", "legend_shard", "deep_probe", "warp_cell"]:
		_src(it, "", 0, "drop/find")
	for g in ["gem_verdant", "gem_dune", "gem_frost", "gem_ember", "gem_prism", "gem_bloom", "gem_giant", "gem_abyss", "gem_tempest", "gem_forge"]:
		_src(g, "", 0, "orbit probe")
	_src("plasma", "siphoning", 1, "vent/giant skim")
	for it in ["obsidian", "fire_opal", "core_ember"]:
		_src(it, "", 0, "volcano")


func _src(item: String, skill: String, req: int, where: String) -> void:
	if not sources.has(item):
		sources[item] = []
	sources[item].append([skill, req, where])


func _need_item(item: String, gates: Dictionary, rewards: Dictionary) -> void:
	if sources.has(item):
		# easiest source wins
		var best: Array = sources[item][0]
		for s in sources[item]:
			if int(s[1]) < int(best[1]):
				best = s
		if best[0] != "":
			gates[best[0]] = maxi(int(gates.get(best[0], 0)), int(best[1]))
		return
	for rr in Db.RECIPES:
		if rr.out == item:
			_need_craft(item, gates, rewards)
			return
	if rewards.has(item):
		return
	print("[bal] FAIL: no source for ", item)
	fails += 1


func _need_craft(item: String, gates: Dictionary, rewards: Dictionary) -> void:
	var rec := {}
	for rr in Db.RECIPES:
		if rr.out == item and (rec.is_empty() or int(rr.req) < int(rec.req)):
			rec = rr
	if rec.is_empty():
		_need_item(item, gates, rewards)
		return
	gates["engineering"] = maxi(int(gates.get("engineering", 0)), int(rec.req))
	for k in rec.in:
		_need_item(k, gates, rewards)
