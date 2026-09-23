extends SceneTree
## Exports real game data for the website: robots, the galaxy, biomes,
## counts. Run: godot --headless --path game -s ../website/tools/export_site_data.gd
## Writes website/theme/star-circuit/assets/data/game.json

func _process(_d):
	var db = root.get_node("Db")
	var gal = root.get_node("Galaxy")
	var out := {}
	var robots := []
	for id in ["scout", "miner", "engineer", "siphon"]:
		var r: Dictionary = db.ROBOTS[id]
		robots.append({"id": id, "name": r.name, "title": r.title, "color": "#" + (r.color as Color).to_html(false),
			"desc": r.desc, "perks": r.perks, "ability": r.ability.name, "ability_desc": r.ability.desc})
	out["robots"] = robots
	var biomes := {}
	for b in db.BIOMES:
		biomes[b] = {"name": db.BIOMES[b].name, "color": "#" + (db.BIOMES[b].colors.mid as Color).to_html(false),
			"atmo": "#" + (db.BIOMES[b].atmo as Color).to_html(false), "legendary": db.BIOMES[b].get("legendary", false)}
	out["biomes"] = biomes
	var stars := []
	for s in gal.stars:
		var planets := []
		for p in s.planets:
			if p.has("moon_of"):
				continue
			planets.append({"name": p.name, "biome": p.biome, "town": p.get("town", {}).get("name", ""), "rings": p.get("rings", false)})
		var moons := 0
		for p in s.planets:
			if p.has("moon_of"):
				moons += 1
		stars.append({"name": s.name, "x": snappedf(s.pos.x, 0.1), "z": snappedf(s.pos.z, 0.1), "cls": s.cls,
			"color": "#" + (s.color as Color).to_html(false), "planets": planets, "moons": moons,
			"giant": s.has("giant"), "station": s.get("station", {}).get("name", "")})
	out["stars"] = stars
	var planet_count := 0
	for s in gal.stars:
		planet_count += s.planets.size()
	out["counts"] = {"stars": gal.stars.size(), "worlds": planet_count, "quests": db.QUESTS.size(), "recipes": db.RECIPES.size(),
		"milestones": db.MILESTONES.size(), "items": db.ITEMS.size(), "decor": db.DECOR.size()}
	var ver: String = ProjectSettings.get_setting("application/config/version")
	out["version"] = ver
	var path := ProjectSettings.globalize_path("res://").path_join("../website/theme/star-circuit/assets/data/game.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	print("[export] wrote ", path, " stars=", stars.size(), " worlds=", planet_count)
	quit()
	return true
