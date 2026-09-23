extends Node
## Static game data: robots, items, professions, gatherable nodes, recipes,
## biomes and the quest chain. Everything tunable lives here.

const SKILL_MAX := 100
const LEVEL_MAX := 30

# --------------------------------------------------------------------------
# Playable robots
# --------------------------------------------------------------------------
const ROBOTS := {
	"scout": {
		"name": "Vesper", "title": "Scout Unit",
		"model": "res://assets/models/robot_scout.glb",
		"color": Color("18c2b0"),
		"desc": "A nimble hover-frame built for charting the unknown. Moves faster, flies farther and learns more from every discovery.",
		"perks": ["Ability: Phase Dash (F)", "+20% move speed", "+35% jetpack efficiency", "+50% Exploration XP", "Scanner range +25%"],
		"start_skills": {"exploration": 5},
		"stats": {"speed": 1.2, "jet": 1.35, "max_energy": 0, "scan": 1.25, "space_speed": 1.15, "hull": 0, "damage": 1.0},
		"ability": {"id": "dash", "name": "Phase Dash", "cd": 5.0, "cost": 10, "desc": "Blink forward, untouchable for a moment."},
		"xp_mult": {"exploration": 1.5},
		"yield_bonus": {},
	},
	"miner": {
		"name": "Grit", "title": "Excavator Unit",
		"model": "res://assets/models/robot_miner.glb",
		"color": Color("f29a2e"),
		"desc": "A tread-footed rock breaker with a drill for an arm. Rips ore out of the ground faster than anything in the sector.",
		"perks": ["Ability: Seismic Slam (F)", "Mining speed +40%", "+1 ore per node", "+50% Mining XP", "Heavy frame: +20 energy, +40 hull, +60 cargo"],
		"start_skills": {"mining": 5},
		"stats": {"speed": 0.95, "jet": 0.9, "max_energy": 20, "harvest_mining": 1.4, "hull": 40, "damage": 1.0, "cargo": 60},
		"ability": {"id": "slam", "name": "Seismic Slam", "cd": 8.0, "cost": 15, "desc": "Smash the ground, damaging and hurling back nearby foes."},
		"xp_mult": {"mining": 1.5},
		"yield_bonus": {"mining": 1},
	},
	"engineer": {
		"name": "Cog", "title": "Fabricator Unit",
		"model": "res://assets/models/robot_engineer.glb",
		"color": Color("8f6cf0"),
		"desc": "A tinkerer with a wrench in one hand and a schematic in the other. Crafts cheaper and occasionally makes two of everything.",
		"perks": ["Ability: Deploy Turret (F)", "25% chance of double crafts", "+50% Engineering XP", "Starts with Engineering 5", "Balanced frame"],
		"start_skills": {"engineering": 5},
		"stats": {"speed": 1.0, "jet": 1.0, "max_energy": 0, "double_craft": 0.25, "hull": 10, "damage": 1.0},
		"ability": {"id": "turret", "name": "Deploy Turret", "cd": 18.0, "cost": 20, "desc": "Drop an auto-turret that shoots enemies for 15 seconds."},
		"xp_mult": {"engineering": 1.5},
		"yield_bonus": {},
	},
	"siphon": {
		"name": "Halo", "title": "Siphon Unit",
		"model": "res://assets/models/robot_siphon.glb",
		"color": Color("e8b93a"),
		"desc": "A radiant energy-drinker that bottles starlight. Huge reserves, fast recharge, and extra plasma from every well.",
		"perks": ["Ability: Drain Nova (F)", "+40 max energy", "Solar recharge x1.75", "+1 plasma per well", "+50% Siphoning & Botany XP"],
		"start_skills": {"siphoning": 5, "botany": 3},
		"stats": {"speed": 1.05, "jet": 1.1, "max_energy": 40, "regen": 1.75, "hull": 0, "damage": 1.1},
		"ability": {"id": "nova", "name": "Drain Nova", "cd": 10.0, "cost": 15, "desc": "A burst of stolen starlight: damages nearby foes and repairs your hull."},
		"xp_mult": {"siphoning": 1.5, "botany": 1.5},
		"yield_bonus": {"siphoning": 1},
	},
}

# --------------------------------------------------------------------------
# Professions (WoW-style gathering + crafting skills)
# --------------------------------------------------------------------------
const SKILLS := {
	"mining": {"name": "Mining", "color": Color("d9a066"), "desc": "Break ore and crystal from the ground. Higher skill unlocks rarer veins and mines faster."},
	"botany": {"name": "Botany", "color": Color("6ee06a"), "desc": "Harvest alien plants for fibers and gels."},
	"siphoning": {"name": "Siphoning", "color": Color("ffcf3f"), "desc": "Draw raw stellar plasma out of energy wells."},
	"engineering": {"name": "Engineering", "color": Color("8f9bff"), "desc": "Fabricate components, fuel and robot upgrades."},
	"exploration": {"name": "Exploration", "color": Color("5ff7ff"), "desc": "Scan species, land on new worlds and jump between stars."},
	"combat": {"name": "Combat", "color": Color("ff5d5d"), "desc": "Destroy rogue drones. Each level adds 1% weapon damage and 1 hull."},
}

# --------------------------------------------------------------------------
# Items
# --------------------------------------------------------------------------
const ITEMS := {
	# raw resources
	"ferrite": {"name": "Ferrite Ore", "kind": "resource", "color": Color("c9b8a6"), "desc": "Common iron-rich ore. The backbone of every build."},
	"cobalt": {"name": "Cobalt Ore", "kind": "resource", "color": Color("3d8bff"), "desc": "Conductive blue ore found on cold and arid worlds."},
	"lumen": {"name": "Lumen Crystal", "kind": "resource", "color": Color("b98cff"), "desc": "A crystal that hums with trapped light. Needed for warp tech."},
	"voidshard": {"name": "Void Shard", "kind": "resource", "color": Color("ff3d6e"), "desc": "Rare obsidian charged with something that should not exist."},
	"biofiber": {"name": "Biofiber", "kind": "resource", "color": Color("8be86a"), "desc": "Tough plant fiber. Makes excellent flexible polymers."},
	"sporegel": {"name": "Spore Gel", "kind": "resource", "color": Color("ff6fa8"), "desc": "Sticky bioluminescent gel from spore pods."},
	"plasma": {"name": "Solar Plasma", "kind": "resource", "color": Color("ffcf3f"), "desc": "Raw stellar energy siphoned from wells."},
	"nickel": {"name": "Nickel-Iron", "kind": "resource", "color": Color("c7b299"), "desc": "Dense metal cut from asteroids. The workhorse of space industry."},
	"cryo_ice": {"name": "Cryo Ice", "kind": "resource", "color": Color("a8e6ff"), "desc": "Ancient ice from icy asteroids and comets. Packed with volatile fuel."},
	"stardust": {"name": "Stardust", "kind": "resource", "color": Color("fff2b0"), "desc": "Glittering grains that settle in asteroid seams. Rare, and loved by warp engineers."},
	"exotic": {"name": "Exotic Matter", "kind": "resource", "color": Color("ff7ae6"), "desc": "Found in comet cores. It weighs less than nothing, which is very useful."},
	"scrap": {"name": "Drone Scrap", "kind": "resource", "color": Color("b0a9a0"), "desc": "Twisted plating salvaged from destroyed rogue drones."},
	"power_core": {"name": "Rogue Power Core", "kind": "resource", "color": Color("ff4d6d"), "desc": "A still-humming drone core. Elites always carry one."},
	# intermediates
	"alloy": {"name": "Alloy Plate", "kind": "component", "color": Color("dfe3ea"), "desc": "Pressed ferrite plating."},
	"circuit": {"name": "Circuit Board", "kind": "component", "color": Color("4cf3a0"), "desc": "Cobalt traces etched around a lumen core."},
	"polymer": {"name": "Bio-Polymer", "kind": "component", "color": Color("a6ffcb"), "desc": "Flexible, self-healing organic composite."},
	"void_core": {"name": "Void Core", "kind": "component", "color": Color("ff7aa0"), "desc": "A stabilised void shard. Bends space when powered."},
	# consumables
	"energy_cell": {"name": "Energy Cell", "kind": "consumable", "color": Color("ffe27a"), "desc": "Restores 50 energy. Press R to use.", "restore": 50},
	"repair_kit": {"name": "Repair Kit", "kind": "consumable", "color": Color("6ee06a"), "desc": "Restores 60 hull. Press G to use.", "repair": 60},
	"warp_cell": {"name": "Warp Cell", "kind": "fuel", "color": Color("9b6bff"), "desc": "Fuel for one jump to another star."},
	# upgrades (crafted once, installed permanently)
	"drill_mk2": {"name": "Harvester Mk II", "kind": "upgrade", "color": Color("ff9f43"), "desc": "All gathering is 50% faster."},
	"drill_mk3": {"name": "Harvester Mk III", "kind": "upgrade", "color": Color("ff6b3d"), "desc": "All gathering is 120% faster."},
	"capacitor": {"name": "Energy Capacitor", "kind": "upgrade", "color": Color("ffe27a"), "desc": "+50 maximum energy."},
	"jet_booster": {"name": "Jet Booster", "kind": "upgrade", "color": Color("5ff7ff"), "desc": "Jetpack uses 40% less energy and lifts harder."},
	"solar_skin": {"name": "Solar Skin", "kind": "upgrade", "color": Color("ffd23f"), "desc": "Doubles solar recharge in daylight."},
	"scanner_mk2": {"name": "Deep Scanner", "kind": "upgrade", "color": Color("39e5ff"), "desc": "Scan radius doubled, reveals rare nodes."},
	"thrusters_mk2": {"name": "Ion Thrusters", "kind": "upgrade", "color": Color("7ad7ff"), "desc": "+60% flight speed in space."},
	"warp_drive_mk2": {"name": "Void Warp Drive", "kind": "upgrade", "color": Color("ff3d6e"), "desc": "Warp range +75%."},
	"blaster_mk2": {"name": "Pulse Blaster", "kind": "upgrade", "color": Color("ff8a5b"), "desc": "Blaster damage +40%."},
	"blaster_mk3": {"name": "Void Lance", "kind": "upgrade", "color": Color("ff3d6e"), "desc": "Blaster damage +100% and shots pierce armour."},
	"hull_plating": {"name": "Reinforced Hull", "kind": "upgrade", "color": Color("c9ced6"), "desc": "+60 maximum hull."},
	"shield_module": {"name": "Deflector Shield", "kind": "upgrade", "color": Color("39e5ff"), "desc": "A 40-point shield that recharges quickly out of combat."},
	"space_laser_mk2": {"name": "Prospector Laser", "kind": "upgrade", "color": Color("ffb86b"), "desc": "Space mining laser cuts 80% faster."},
	"tractor_beam": {"name": "Tractor Beam", "kind": "upgrade", "color": Color("7ad7ff"), "desc": "Pulls ore shards in from 2.5x farther."},
	"exotic_reactor": {"name": "Exotic Reactor", "kind": "upgrade", "color": Color("ff7ae6"), "desc": "Energy recharges 50% faster everywhere, even at night."},
	"twin_cannons": {"name": "Twin Pulse Cannons", "kind": "upgrade", "color": Color("ff8a5b"), "desc": "Space cannons deal 50% more damage."},
	"missile_rack": {"name": "Missile Rack", "kind": "upgrade", "color": Color("ffb86b"), "desc": "Fires two homing missiles per volley and reloads 40% faster."},
	"cargo_pods": {"name": "Cargo Pods", "kind": "upgrade", "color": Color("c9b8a6"), "desc": "+100 cargo capacity."},
	"cargo_pods_mk2": {"name": "Cargo Pods Mk II", "kind": "upgrade", "color": Color("e8c890"), "desc": "+200 cargo capacity."},
	"scatter_mod": {"name": "Scatter Emitter", "kind": "upgrade", "color": Color("ffb347"), "desc": "Unlocks the Scatter weapon loadout (Outfitter or X to swap)."},
	"rail_mod": {"name": "Rail Coil", "kind": "upgrade", "color": Color("9bd1ff"), "desc": "Unlocks the Rail weapon loadout (Outfitter or X to swap)."},
	"lava_plating": {"name": "Heat Plating", "kind": "upgrade", "color": Color("ff7a3d"), "desc": "Immune to lava and heat drain."},
}

# --------------------------------------------------------------------------
# Gatherable node types
# --------------------------------------------------------------------------
const NODES := {
	"ferrite": {"name": "Ferrite Vein", "model": "res://assets/models/res_ferrite.glb", "item": "ferrite", "skill": "mining", "req": 1, "yield": [2, 4], "xp": 12, "time": 2.2, "scale": 1.0},
	"cobalt": {"name": "Cobalt Vein", "model": "res://assets/models/res_cobalt.glb", "item": "cobalt", "skill": "mining", "req": 15, "yield": [2, 3], "xp": 22, "time": 2.8, "scale": 1.0},
	"lumen": {"name": "Lumen Cluster", "model": "res://assets/models/res_crystal.glb", "item": "lumen", "skill": "mining", "req": 30, "yield": [1, 3], "xp": 34, "time": 3.2, "scale": 1.0},
	"void": {"name": "Void Spire", "model": "res://assets/models/res_void.glb", "item": "voidshard", "skill": "mining", "req": 55, "yield": [1, 2], "xp": 55, "time": 4.0, "scale": 1.0},
	"fiber": {"name": "Fiberstalk", "model": "res://assets/models/res_fiber.glb", "item": "biofiber", "skill": "botany", "req": 1, "yield": [2, 4], "xp": 12, "time": 1.8, "scale": 1.0},
	"spore": {"name": "Spore Pod", "model": "res://assets/models/res_spore.glb", "item": "sporegel", "skill": "botany", "req": 20, "yield": [1, 3], "xp": 26, "time": 2.4, "scale": 1.0},
	"energy": {"name": "Energy Well", "model": "res://assets/models/res_energy.glb", "item": "plasma", "skill": "siphoning", "req": 1, "yield": [1, 3], "xp": 16, "time": 2.6, "scale": 1.0, "restore": 25},
}

# --------------------------------------------------------------------------
# Recipes (Engineering)
# --------------------------------------------------------------------------
const RECIPES := [
	{"id": "alloy", "out": "alloy", "qty": 1, "in": {"ferrite": 3}, "req": 1, "xp": 14, "cat": "Components"},
	{"id": "energy_cell", "out": "energy_cell", "qty": 1, "in": {"plasma": 2}, "req": 1, "xp": 12, "cat": "Consumables"},
	{"id": "polymer", "out": "polymer", "qty": 1, "in": {"biofiber": 3, "sporegel": 1}, "req": 10, "xp": 22, "cat": "Components"},
	{"id": "circuit", "out": "circuit", "qty": 1, "in": {"cobalt": 2, "lumen": 1}, "req": 20, "xp": 30, "cat": "Components"},
	{"id": "warp_cell", "out": "warp_cell", "qty": 1, "in": {"circuit": 1, "plasma": 3}, "req": 20, "xp": 40, "cat": "Consumables"},
	{"id": "void_core", "out": "void_core", "qty": 1, "in": {"voidshard": 2, "circuit": 1}, "req": 50, "xp": 70, "cat": "Components"},
	{"id": "repair_kit", "out": "repair_kit", "qty": 1, "in": {"scrap": 2, "biofiber": 2}, "req": 1, "xp": 14, "cat": "Consumables"},
	{"id": "blaster_mk2", "out": "blaster_mk2", "qty": 1, "in": {"scrap": 8, "alloy": 3}, "req": 6, "xp": 70, "cat": "Upgrades"},
	{"id": "hull_plating", "out": "hull_plating", "qty": 1, "in": {"scrap": 10, "alloy": 6}, "req": 12, "xp": 85, "cat": "Upgrades"},
	{"id": "shield_module", "out": "shield_module", "qty": 1, "in": {"scrap": 12, "power_core": 1, "polymer": 2}, "req": 22, "xp": 110, "cat": "Upgrades"},
	{"id": "blaster_mk3", "out": "blaster_mk3", "qty": 1, "in": {"power_core": 3, "void_core": 1, "circuit": 2}, "req": 52, "xp": 200, "cat": "Upgrades"},
	{"id": "tractor_beam", "out": "tractor_beam", "qty": 1, "in": {"nickel": 8, "cryo_ice": 6}, "req": 12, "xp": 90, "cat": "Upgrades"},
	{"id": "space_laser_mk2", "out": "space_laser_mk2", "qty": 1, "in": {"nickel": 12, "circuit": 1}, "req": 18, "xp": 100, "cat": "Upgrades"},
	{"id": "warp_cell_cryo", "out": "warp_cell", "qty": 1, "in": {"cryo_ice": 5, "stardust": 2}, "req": 25, "xp": 45, "cat": "Consumables"},
	{"id": "exotic_reactor", "out": "exotic_reactor", "qty": 1, "in": {"exotic": 3, "circuit": 2, "alloy": 4}, "req": 45, "xp": 180, "cat": "Upgrades"},
	{"id": "twin_cannons", "out": "twin_cannons", "qty": 1, "in": {"alloy": 6, "scrap": 10, "circuit": 1}, "req": 16, "xp": 100, "cat": "Upgrades"},
	{"id": "missile_rack", "out": "missile_rack", "qty": 1, "in": {"scrap": 12, "power_core": 1, "circuit": 2}, "req": 26, "xp": 130, "cat": "Upgrades"},
	{"id": "cargo_pods", "out": "cargo_pods", "qty": 1, "in": {"alloy": 6, "polymer": 2}, "req": 8, "xp": 80, "cat": "Upgrades"},
	{"id": "cargo_pods_mk2", "out": "cargo_pods_mk2", "qty": 1, "in": {"alloy": 10, "nickel": 12, "circuit": 2}, "req": 28, "xp": 140, "cat": "Upgrades"},
	{"id": "scatter_mod", "out": "scatter_mod", "qty": 1, "in": {"scrap": 10, "alloy": 4, "circuit": 1}, "req": 14, "xp": 90, "cat": "Upgrades"},
	{"id": "rail_mod", "out": "rail_mod", "qty": 1, "in": {"power_core": 1, "circuit": 2, "cobalt": 8}, "req": 24, "xp": 120, "cat": "Upgrades"},
	{"id": "drill_mk2", "out": "drill_mk2", "qty": 1, "in": {"alloy": 4, "biofiber": 4}, "req": 3, "xp": 60, "cat": "Upgrades"},
	{"id": "jet_booster", "out": "jet_booster", "qty": 1, "in": {"alloy": 3, "plasma": 4}, "req": 6, "xp": 60, "cat": "Upgrades"},
	{"id": "capacitor", "out": "capacitor", "qty": 1, "in": {"alloy": 2, "polymer": 2, "plasma": 5}, "req": 15, "xp": 80, "cat": "Upgrades"},
	{"id": "solar_skin", "out": "solar_skin", "qty": 1, "in": {"polymer": 4, "plasma": 6}, "req": 18, "xp": 90, "cat": "Upgrades"},
	{"id": "scanner_mk2", "out": "scanner_mk2", "qty": 1, "in": {"circuit": 2, "polymer": 1}, "req": 25, "xp": 100, "cat": "Upgrades"},
	{"id": "thrusters_mk2", "out": "thrusters_mk2", "qty": 1, "in": {"alloy": 6, "circuit": 2}, "req": 30, "xp": 110, "cat": "Upgrades"},
	{"id": "lava_plating", "out": "lava_plating", "qty": 1, "in": {"alloy": 8, "cobalt": 6}, "req": 35, "xp": 120, "cat": "Upgrades"},
	{"id": "drill_mk3", "out": "drill_mk3", "qty": 1, "in": {"alloy": 6, "circuit": 3, "voidshard": 2}, "req": 55, "xp": 180, "cat": "Upgrades"},
	{"id": "warp_drive_mk2", "out": "warp_drive_mk2", "qty": 1, "in": {"void_core": 2, "circuit": 3}, "req": 60, "xp": 220, "cat": "Upgrades"},
]

# --------------------------------------------------------------------------
# Biomes / planet types
# --------------------------------------------------------------------------
const BIOMES := {
	"verdant": {
		"name": "Verdant", "sea": 0.0, "amp": 0.055, "ridge": 0.03,
		"colors": {"deep": Color("2a6f97"), "beach": Color("e9d8a6"), "low": Color("7bc950"), "mid": Color("4f9d3a"), "high": Color("8c7a5b"), "peak": Color("f4f4f4"), "rock": Color("7a6e62")},
		"water": Color(0.2, 0.55, 0.85, 0.72), "atmo": Color("7ec8ff"), "horizon": Color("ffd9b0"), "ambient": Color("b8d8ff"),
		"flora": {"flora_tree_round": 150, "flora_tree_disc": 60, "prop_boulder": 40},
		"nodes": {"ferrite": 34, "fiber": 34, "energy": 14, "spore": 12, "cobalt": 6},
		"critters": 16, "fauna_colors": [Color("ffb347"), Color("ff7eb6"), Color("7ee8fa")],
	},
	"dune": {
		"name": "Arid", "sea": -1.0, "amp": 0.05, "ridge": 0.045,
		"colors": {"deep": Color("b5651d"), "beach": Color("e7c07a"), "low": Color("e3b26b"), "mid": Color("d0904f"), "high": Color("a8623a"), "peak": Color("f0d9b5"), "rock": Color("8c5a3c")},
		"water": Color(0, 0, 0, 0), "atmo": Color("f2c47e"), "horizon": Color("ffe8c7"), "ambient": Color("ffe0b8"),
		"flora": {"flora_cactus": 110, "prop_boulder": 90},
		"nodes": {"ferrite": 26, "cobalt": 30, "energy": 18, "fiber": 8},
		"critters": 8, "fauna_colors": [Color("e2c290"), Color("c86b3c")],
	},
	"frost": {
		"name": "Glacial", "sea": 0.0, "amp": 0.05, "ridge": 0.035,
		"colors": {"deep": Color("1f4e79"), "beach": Color("dfefff"), "low": Color("e8f4ff"), "mid": Color("bcd7ee"), "high": Color("8fb3d1"), "peak": Color("ffffff"), "rock": Color("6f8193")},
		"water": Color(0.55, 0.8, 0.95, 0.85), "atmo": Color("bfe6ff"), "horizon": Color("f0f8ff"), "ambient": Color("d8ecff"),
		"flora": {"flora_ice": 130, "prop_boulder": 40},
		"nodes": {"cobalt": 30, "ferrite": 18, "lumen": 12, "energy": 12},
		"critters": 8, "fauna_colors": [Color("ffffff"), Color("a8d8ff")],
	},
	"ember": {
		"name": "Volcanic", "sea": -0.004, "amp": 0.065, "ridge": 0.06, "lava": true,
		"colors": {"deep": Color("ff5a1f"), "beach": Color("2b2327"), "low": Color("3a2f33"), "mid": Color("4a3a3a"), "high": Color("6b4a3a"), "peak": Color("a83a1a"), "rock": Color("1f1a1d")},
		"water": Color(1.0, 0.35, 0.05, 1.0), "atmo": Color("ff8a5b"), "horizon": Color("ffb38a"), "ambient": Color("ffb08a"),
		"flora": {"prop_boulder": 120, "flora_ice": 0},
		"nodes": {"void": 22, "ferrite": 22, "energy": 26, "lumen": 8},
		"critters": 0, "fauna_colors": [Color("ff5a1f")],
	},
	"prism": {
		"name": "Crystalline", "sea": 0.004, "amp": 0.05, "ridge": 0.05,
		"colors": {"deep": Color("3a1f6b"), "beach": Color("c9b6ff"), "low": Color("7d5fc9"), "mid": Color("5a3fa8"), "high": Color("392a6b"), "peak": Color("e6dcff"), "rock": Color("2c2447")},
		"water": Color(0.6, 0.35, 1.0, 0.7), "atmo": Color("c49bff"), "horizon": Color("ffc4f2"), "ambient": Color("d9c4ff"),
		"flora": {"flora_mushroom": 90, "flora_ice": 50, "prop_boulder": 20},
		"nodes": {"lumen": 36, "spore": 24, "energy": 16, "cobalt": 12},
		"critters": 12, "fauna_colors": [Color("ff9bf0"), Color("9bd1ff"), Color("fff08a")],
	},
	"bloom": {
		"name": "Fungal", "sea": 0.0, "amp": 0.045, "ridge": 0.02,
		"colors": {"deep": Color("2f6b5e"), "beach": Color("f3e6d8"), "low": Color("c96bb0"), "mid": Color("9e4a92"), "high": Color("6b3a6b"), "peak": Color("ffd6f0"), "rock": Color("4a3547")},
		"water": Color(0.3, 0.9, 0.7, 0.7), "atmo": Color("ff9bd6"), "horizon": Color("fff0c4"), "ambient": Color("ffd0ec"),
		"flora": {"flora_mushroom": 140, "flora_tree_round": 40},
		"nodes": {"spore": 40, "fiber": 26, "energy": 14, "ferrite": 16},
		"critters": 18, "fauna_colors": [Color("7ee8fa"), Color("c3ff6b"), Color("ffffff")],
	},
}

# --------------------------------------------------------------------------
# Quest chain (the Archivist's storyline)
# objective types: collect / craft / scan / orbit / warp / land_unique / skill / talk
# --------------------------------------------------------------------------
const QUESTS := [
	{"id": "wake", "title": "Wake Up, Unit", "giver": "Archivist",
		"text": "Ah, you are finally online. The Circuit went dark long ago, and every star since has been a stranger. Before you wander, prove your frame still works. Break some Ferrite from the veins around the outpost.",
		"obj": {"type": "collect", "item": "ferrite", "count": 6}, "xp": 120, "reward": {"energy_cell": 2}},
	{"id": "spark", "title": "Spark of Life", "giver": "Archivist",
		"text": "Energy is everything out here. Find a golden Energy Well and siphon it. Plasma keeps your cells full and your thrusters honest.",
		"obj": {"type": "collect", "item": "plasma", "count": 4}, "xp": 150, "reward": {"energy_cell": 1}},
	{"id": "hands", "title": "Hands That Build", "giver": "Archivist",
		"text": "A robot who cannot build is just a very expensive rock. Open your fabricator (C) and press some Alloy Plates.",
		"obj": {"type": "craft", "item": "alloy", "count": 3}, "xp": 180, "reward": {"biofiber": 4}},
	{"id": "curious", "title": "Curious Circuits", "giver": "Archivist",
		"text": "This world teems with life nobody has named. Pulse your scanner (Q) near plants and creatures and log three species.",
		"obj": {"type": "scan", "count": 3}, "xp": 200, "reward": {"plasma": 4}},
	{"id": "tools", "title": "Better Tools", "giver": "Archivist",
		"text": "That standard-issue harvester is an insult. Fabricate a Harvester Mk II and feel the difference.",
		"obj": {"type": "craft", "item": "drill_mk2", "count": 1}, "xp": 260, "reward": {"energy_cell": 2}},
	{"id": "rogues", "title": "Rogue Signals", "giver": "Archivist",
		"text": "Something has corrupted the old maintenance drones. They roam in packs now and attack anything with a spark. Aim with the mouse, fire with the left button, and use your frame's ability (F). Destroy five of them.",
		"obj": {"type": "kill", "count": 5}, "xp": 300, "reward": {"repair_kit": 3}},
	{"id": "arms", "title": "Arms Race", "giver": "Archivist",
		"text": "Their plating makes fine material. Salvage Drone Scrap and fabricate a Pulse Blaster.",
		"obj": {"type": "craft", "item": "blaster_mk2", "count": 1}, "xp": 320, "reward": {"energy_cell": 2}},
	{"id": "market", "title": "Market Day", "giver": "Archivist",
		"text": "The Cradle has grown while you slept. Visit Mar at the General Goods stall and sell some of what you've gathered. Credits open every door out here.",
		"obj": {"type": "sell", "count": 10}, "xp": 220, "reward": {"energy_cell": 1}, "credits": 60},
	{"id": "trainer", "title": "Rank and File", "giver": "Archivist",
		"text": "Your professions stop at 25 until someone teaches you more. Talk to Tutor Voss, the Profession Trainer, and train Journeyman in any skill.",
		"obj": {"type": "train", "count": 1}, "xp": 260, "reward": {"repair_kit": 2}, "credits": 40},
	{"id": "sky", "title": "Beyond the Sky", "giver": "Archivist",
		"text": "Now the real journey. Fly high and press T to break orbit. Other worlds circle this star. Go and see them.",
		"obj": {"type": "orbit", "count": 1}, "xp": 250, "reward": {}},
	{"id": "worlds", "title": "Neighbouring Worlds", "giver": "Archivist",
		"text": "Land on two other planets in this system. Cold and dry worlds hold Cobalt; crystal worlds hold Lumen.",
		"obj": {"type": "land_unique", "count": 3}, "xp": 320, "reward": {"energy_cell": 2}},
	{"id": "brute", "title": "Heavy Metal", "giver": "Archivist",
		"text": "The big ones, the Brutes, are the corruption's lieutenants. Their name glows gold. Bring one down. Watch for the red ring before it slams.",
		"obj": {"type": "kill_elite", "count": 1}, "xp": 600, "reward": {"repair_kit": 3, "power_core": 1}},
	{"id": "hubs", "title": "Friends in Far Places", "giver": "Archivist",
		"text": "Other robots survived. Find a trade hub on another world. From orbit, press F near a planet with a hub to land right at its pad.",
		"obj": {"type": "visit_town", "count": 2}, "xp": 420, "reward": {"warp_cell": 1}, "credits": 150},
	{"id": "belt", "title": "Belt Prospector", "giver": "Archivist",
		"text": "Every star keeps a belt of rock. Fly out to it, hold the left mouse button to cut with your mining laser, and fly through the shards to scoop them up. Bring in Nickel-Iron.",
		"obj": {"type": "collect", "item": "nickel", "count": 12}, "xp": 380, "reward": {"energy_cell": 2}, "credits": 80},
	{"id": "pirates", "title": "Pirate Problem", "giver": "Archivist",
		"text": "Miners in the belt report corrupted pirate craft. Your frame can fight in the void too: left mouse fires pulse cannons at ships, right mouse launches homing missiles. Destroy five of them.",
		"obj": {"type": "space_kill", "count": 5}, "xp": 480, "reward": {"repair_kit": 2}, "credits": 120},
	{"id": "hauler", "title": "Hauler", "giver": "Archivist",
		"text": "Every system keeps an orbital trade station, and each one hungers for different goods. Fill your hold, fly to a station, press E to dock, and sell 25 units of cargo. Find what a station wants and it pays well.",
		"obj": {"type": "station_sell", "count": 25}, "xp": 420, "reward": {"repair_kit": 2}, "credits": 100},
	{"id": "deep", "title": "Deeper Veins", "giver": "Archivist",
		"text": "Warp tech needs Lumen, and Lumen answers only to a skilled miner. Reach Mining 30. You will need Journeyman training first.",
		"obj": {"type": "skill", "skill": "mining", "count": 30}, "xp": 400, "reward": {"plasma": 6}},
	{"id": "fuel", "title": "Fuel for the Void", "giver": "Archivist",
		"text": "Craft a Warp Cell. Circuit Board plus plasma, and the stars open up.",
		"obj": {"type": "craft", "item": "warp_cell", "count": 1}, "xp": 450, "reward": {"energy_cell": 3}},
	{"id": "jump", "title": "First Jump", "giver": "Archivist",
		"text": "Open the galaxy map (M) in space, choose a star in range and jump. I will be listening on the comms.",
		"obj": {"type": "warp", "count": 1}, "xp": 600, "reward": {"warp_cell": 1}},
	{"id": "carto", "title": "Cartographer", "giver": "Archivist",
		"text": "Every world you touch rewrites the map. Set foot on eight different planets.",
		"obj": {"type": "land_unique", "count": 8}, "xp": 900, "reward": {"warp_cell": 2}},
	{"id": "marauder", "title": "Hunt the Marauder", "giver": "Archivist",
		"text": "Far from home, the pirates answer to Marauders: gold-plated flagships with regenerating shields. Break one. Watch its volleys and keep moving.",
		"obj": {"type": "space_elite", "count": 1}, "xp": 1200, "reward": {"power_core": 2, "warp_cell": 1}, "credits": 400},
	{"id": "void", "title": "Touching the Void", "giver": "Archivist",
		"text": "Volcanic worlds hide Void Spires. Master Mining 55 and bring back Void Shards. Only an Expert trainer in a far town can take you that deep.",
		"obj": {"type": "collect", "item": "voidshard", "count": 6}, "xp": 1400, "reward": {"warp_cell": 2}},
	{"id": "circuit", "title": "Relight the Circuit", "giver": "Archivist",
		"text": "Build the Void Warp Drive. With it, no star is out of reach. The Circuit is yours to relight, Unit.",
		"obj": {"type": "craft", "item": "warp_drive_mk2", "count": 1}, "xp": 3000, "reward": {"warp_cell": 5}},
]

# --------------------------------------------------------------------------
# Economy
# --------------------------------------------------------------------------
## Base value in credits. Upgrades are not tradeable.
const VALUES := {
	"ferrite": 4, "cobalt": 10, "lumen": 22, "voidshard": 45, "biofiber": 4, "sporegel": 9, "plasma": 6,
	"scrap": 5, "power_core": 60, "alloy": 16, "circuit": 60, "polymer": 24, "void_core": 150,
	"energy_cell": 18, "repair_kit": 20, "warp_cell": 120,
	"nickel": 7, "cryo_ice": 9, "stardust": 30, "exotic": 120,
}

## WoW-style profession ranks. Skill can't exceed the cap until trained.
## Items that take up cargo space (consumables and fuel ride in equipment slots).
const CARGO_KINDS := ["resource", "component"]
const CARGO_BASE := 150

# --------------------------------------------------------------------------
# Customisation
# --------------------------------------------------------------------------
const COSMETICS := {
	"head": [
		{"id": "default", "name": "Factory Head", "price": 0},
		{"id": "dome", "name": "Visor Dome", "price": 150, "model": "res://assets/models/head_dome.glb"},
		{"id": "box", "name": "Scanner Box", "price": 150, "model": "res://assets/models/head_box.glb"},
		{"id": "crest", "name": "Crested Helm", "price": 300, "model": "res://assets/models/head_crest.glb"},
		{"id": "mono", "name": "Mono-Eye", "price": 300, "model": "res://assets/models/head_mono.glb"},
	],
	"top": [
		{"id": "none", "name": "Bare", "price": 0},
		{"id": "antenna", "name": "Signal Antenna", "price": 50, "model": "res://assets/models/top_antenna.glb"},
		{"id": "flower", "name": "Space Daisy", "price": 80, "model": "res://assets/models/top_flower.glb"},
		{"id": "horns", "name": "Horns", "price": 120, "model": "res://assets/models/top_horns.glb"},
		{"id": "dish", "name": "Satellite Dish", "price": 150, "model": "res://assets/models/top_dish.glb"},
		{"id": "tophat", "name": "Top Hat", "price": 200, "model": "res://assets/models/top_tophat.glb"},
		{"id": "crown", "name": "Circuit Crown", "price": 500, "model": "res://assets/models/top_crown.glb"},
	],
	"pack": [
		{"id": "default", "name": "Factory Thruster", "price": 0},
		{"id": "rockets", "name": "Twin Rockets", "price": 200, "model": "res://assets/models/pack_rockets.glb"},
		{"id": "wings", "name": "Glider Wings", "price": 350, "model": "res://assets/models/pack_wings.glb"},
		{"id": "ring", "name": "Jet Ring", "price": 400, "model": "res://assets/models/pack_ring.glb"},
	],
	"finish": [
		{"id": "standard", "name": "Standard", "price": 0},
		{"id": "matte", "name": "Matte", "price": 60},
		{"id": "chrome", "name": "Chrome", "price": 250},
		{"id": "neon", "name": "Neon Trim", "price": 300},
		{"id": "gold", "name": "Gold Plate", "price": 600},
	],
}

const PAINT_SWATCHES := [
	Color("f4f4f2"), Color("2a2d36"), Color("e0453a"), Color("ff9f43"), Color("ffd23f"), Color("6ee06a"),
	Color("18c2b0"), Color("39a0ff"), Color("5a5fd8"), Color("b06bff"), Color("ff7eb6"), Color("8c6a4f"),
]

## Weapon loadouts: used on foot and in flight.
const WEAPONS := {
	"pulse": {"name": "Pulse", "desc": "Balanced rapid fire.", "rate": 1.0, "dmg": 1.0, "pellets": 1, "spread": 0.0, "range": 1.0, "cost": 1.0, "pierce": false, "unlock": ""},
	"scatter": {"name": "Scatter", "desc": "Close-range spread of 6 pellets. Shreds swarms.", "rate": 1.8, "dmg": 0.32, "pellets": 6, "spread": 0.07, "range": 0.4, "cost": 2.2, "pierce": false, "unlock": "scatter_mod"},
	"rail": {"name": "Rail", "desc": "Slow, heavy slug that pierces everything in a line.", "rate": 4.0, "dmg": 3.4, "pellets": 1, "spread": 0.0, "range": 1.8, "cost": 4.5, "pierce": true, "unlock": "rail_mod"},
}

const STATION_SUFFIX := ["Exchange", "Station", "Waypoint", "Depot", "Harbor", "Ring"]

const SKILL_TIERS := [
	{"name": "Apprentice", "cap": 25, "req": 0, "cost": 0},
	{"name": "Journeyman", "cap": 50, "req": 15, "cost": 150},
	{"name": "Expert", "cap": 75, "req": 45, "cost": 1200},
	{"name": "Artisan", "cap": 100, "req": 70, "cost": 4000},
]

const TOWN_PRE := ["Rust", "Copper", "Lantern", "Dusk", "Kettle", "Bright", "Hollow", "Gear", "Ember", "Frost", "Moss", "Signal", "Harbor", "Quiet", "Tin"]
const TOWN_SUF := ["haven", "ford", "reach", "works", "market", "crossing", "rest", "spire", "yard", "hollow", "point", "gate"]

const CHATTER := [
	"Fresh cobalt in from the dry worlds! Well, fresh-ish.",
	"Did you hear? A Brute took out the relay on the ridge again.",
	"My servos creak when it rains. Rains a lot here.",
	"The Archivist says the Circuit will shine again. I'd like to see it.",
	"Buy low on the world that digs it up, sell high where they don't.",
	"Careful out past the lamps. The drones come right up to the edge.",
	"I traded my spare arm for a Warp Cell once. Worth it.",
	"Trainers in the far towns teach things they won't teach here.",
	"Those crystal worlds hum at night. Gives me the shivers.",
	"Bounty board's got work if your cells are running low.",
	"Hello, traveller! Mind the crates.",
	"Every morning the market restocks. Early robots get the good plasma.",
	"I used to be a mining drone. Then I found out about hats.",
	"Some say the monoliths still talk, if you listen with the right frequency.",
]

## Bounty templates. {n} and {item} get filled in; rewards scale with them.
const BOUNTIES := [
	{"type": "deliver", "title": "Supply Run", "text": "Deliver {n} {item} to any bounty board."},
	{"type": "kill", "title": "Drone Culling", "text": "Destroy {n} rogue drones anywhere."},
	{"type": "scan", "title": "Field Survey", "text": "Log {n} new species on any world."},
	{"type": "loot", "title": "Salvage Rights", "text": "Salvage {n} caches, pods or monoliths."},
	{"type": "space_kill", "title": "Pirate Hunt", "text": "Destroy {n} pirate ships in space."},
	{"type": "asteroid", "title": "Belt Contract", "text": "Break {n} asteroids in any asteroid belt."},
]


# --------------------------------------------------------------------------
# Space pirates. Stats scale with level: [base, per level].
# --------------------------------------------------------------------------
const SPACE_ENEMIES := {
	"raider": {"name": "Pirate Raider", "model": "res://assets/models/pirate_raider.glb", "hp": [60, 18], "shield": [0, 0],
		"dmg": [5, 1.5], "speed": 58.0, "turn": 2.2, "range": 170.0, "cd": 0.3, "burst": 3, "rest": 1.4, "xp": [40, 12],
		"size": 3.0, "style": "fighter", "bolt": Color("ff6a2a"), "loot": {"scrap": [1, 3]}},
	"gunship": {"name": "Pirate Gunship", "model": "res://assets/models/pirate_gunship.glb", "hp": [220, 50], "shield": [0, 0],
		"dmg": [9, 2.2], "speed": 22.0, "turn": 0.9, "range": 230.0, "cd": 0.45, "burst": 3, "rest": 3.0, "xp": [90, 25],
		"size": 4.5, "style": "brawler", "bolt": Color("ff3d6e"), "loot": {"scrap": [3, 6], "power_core": [0, 1]}},
	"swarmer": {"name": "Swarm Drone", "model": "res://assets/models/pirate_swarmer.glb", "hp": [22, 6], "shield": [0, 0],
		"dmg": [16, 4.0], "speed": 78.0, "turn": 3.5, "range": 6.0, "cd": 0.0, "burst": 0, "rest": 0.0, "xp": [18, 5],
		"size": 1.6, "style": "kamikaze", "bolt": Color("ff7a2a"), "loot": {"scrap": [0, 1]}},
	"marauder": {"name": "Pirate Marauder", "model": "res://assets/models/pirate_marauder.glb", "hp": [700, 120], "shield": [220, 40],
		"dmg": [10, 2.5], "speed": 38.0, "turn": 1.2, "range": 280.0, "cd": 0.12, "burst": 7, "rest": 2.4, "xp": [320, 60],
		"size": 8.0, "style": "flagship", "elite": true, "bolt": Color("ff2a55"), "loot": {"scrap": [6, 10], "power_core": [1, 2], "exotic": [0, 1]}},
}


# --------------------------------------------------------------------------
# Asteroids (space mining). hp scales with size; req gates like ground veins.
# --------------------------------------------------------------------------
const ASTEROIDS := {
	"rocky": {"name": "Rocky Asteroid", "req": 1, "items": {"nickel": [2, 4], "ferrite": [1, 3]}, "rock": Color("7d7065"), "vein": Color("c9b8a6"), "xp": 10, "hp": 1.0},
	"metallic": {"name": "Metallic Asteroid", "req": 15, "items": {"nickel": [3, 5], "cobalt": [1, 3]}, "rock": Color("566172"), "vein": Color("3d8bff"), "xp": 20, "hp": 1.4},
	"icy": {"name": "Icy Asteroid", "req": 10, "items": {"cryo_ice": [2, 5], "plasma": [0, 2]}, "rock": Color("cfe6f5"), "vein": Color("7fd8ff"), "xp": 16, "hp": 0.8},
	"crystal": {"name": "Crystalline Asteroid", "req": 30, "items": {"lumen": [1, 3], "stardust": [0, 1]}, "rock": Color("3b3550"), "vein": Color("b98cff"), "xp": 32, "hp": 1.2},
	"void": {"name": "Void-touched Asteroid", "req": 55, "items": {"voidshard": [1, 2], "exotic": [0, 1]}, "rock": Color("18141f"), "vein": Color("ff3d6e"), "xp": 50, "hp": 1.8},
	"comet": {"name": "Comet", "req": 20, "items": {"cryo_ice": [6, 10], "exotic": [1, 3], "stardust": [1, 3]}, "rock": Color("dff4ff"), "vein": Color("9be8ff"), "xp": 80, "hp": 3.0},
}

## Belt composition weights by star class.
const BELT_MIX := {
	"O": {"rocky": 25, "metallic": 20, "icy": 10, "crystal": 25, "void": 20},
	"B": {"rocky": 30, "metallic": 20, "icy": 10, "crystal": 25, "void": 15},
	"A": {"rocky": 35, "metallic": 25, "icy": 15, "crystal": 18, "void": 7},
	"F": {"rocky": 40, "metallic": 25, "icy": 18, "crystal": 12, "void": 5},
	"G": {"rocky": 45, "metallic": 25, "icy": 20, "crystal": 8, "void": 2},
	"K": {"rocky": 40, "metallic": 20, "icy": 30, "crystal": 7, "void": 3},
	"M": {"rocky": 35, "metallic": 15, "icy": 40, "crystal": 6, "void": 4},
}


# --------------------------------------------------------------------------
# Points of interest
# --------------------------------------------------------------------------
const POIS := {
	"monolith": {"name": "Circuit Monolith", "model": "res://assets/models/poi_monolith.glb", "color": Color("6ff3ff"),
		"xp": 80, "lore": true, "loot": {}, "verb": "Read the glyphs", "time": 1.5},
	"ruin": {"name": "Ancient Ruins", "model": "res://assets/models/poi_ruin.glb", "color": Color("ffcf6b"),
		"xp": 60, "lore": true, "guards": true, "loot": {"circuit": [0, 1], "alloy": [2, 4], "plasma": [2, 4]}, "verb": "Open the data cache", "time": 2.0},
	"crash": {"name": "Crashed Pod", "model": "res://assets/models/poi_crash.glb", "color": Color("ff7a3d"),
		"xp": 50, "lore": false, "loot": {"energy_cell": [1, 2], "repair_kit": [1, 2], "scrap": [2, 5], "alloy": [1, 3]}, "verb": "Salvage the pod", "time": 2.0},
	"geode": {"name": "Crystal Geode", "model": "res://assets/models/poi_geode.glb", "color": Color("7ff0ff"),
		"xp": 40, "lore": false, "hotspot": true, "loot": {}, "verb": "", "time": 0.0},
}

## Fragments of the Circuit's history, found at monoliths and ruins.
const LORE := [
	["The First Spark", "Before the dark, every star in this arm was linked by a lattice of light we called the Circuit. Machines walked between worlds as easily as you cross a field."],
	["Maintenance Log 1", "Drone swarm 7 reports nominal. Swarm 8 has stopped answering pings. Swarm 8 is now pinging us back with something that is not our code."],
	["The Archivist's Oath", "One unit shall remain awake to remember. When the others sleep, it will keep the names of every world, so they can be spoken again."],
	["On Lumen", "Lumen is not a mineral. It is starlight that forgot how to leave. Warp tech only works because the crystals still remember the way home."],
	["The Quiet", "Relays went silent one system at a time, like lamps along a road being put out by someone walking away from us."],
	["Brute Protocol", "Loader frames were never meant to fight. The corruption taught them to lift the ground and drop it on whatever moved."],
	["Garden Worlds", "We seeded the verdant planets with life we designed to be kind. They are still kind. The creatures there have never learned to fear a robot."],
	["Void Shards", "Where the lava runs, space is thin. Obsidian spires grow at the tears, and hold a little of the nothing between the stars."],
	["A Child's Note", "If you find this, my name was Pim-7 and I liked the purple planets best. The crystals hum when it rains."],
	["Engineer's Margin Notes", "Double the alloy, halve the pride. Every upgrade I made failed once before it worked forever."],
	["The Long Orbit", "Some of us chose to circle a single world for a thousand years rather than risk the jump. I understand them now."],
	["Siphon Hymn", "We drink the light and give it back as motion. Nothing is taken, only borrowed for a while."],
	["Last Transmission", "Beacon array failing. If any unit hears this: relight the Circuit from the edges inward. Start where it is darkest."],
	["Survey Doctrine", "Name every creature. Walk every ridge. A world is not truly known until someone has been foolish enough to love it."],
	["Scrap Philosophy", "Nothing out here is waste. A broken drone is simply a future blaster that has not been introduced to an engineer yet."],
	["Rings", "The ringed giants were quarries once. The debris never settled. From the surface the rings look like a road across the sky."],
]


# --------------------------------------------------------------------------
# Enemies (rogue drones). Stats scale with level.
# --------------------------------------------------------------------------
const ENEMIES := {
	"scrapper": {"name": "Rogue Scrapper", "model": "res://assets/models/enemy_scrapper.glb",
		"hp": [40, 14], "dmg": [6, 2.0], "speed": 6.5, "range": 2.4, "cd": 1.1, "aggro": 20.0, "xp": [30, 10],
		"hover": 0.0, "scale": 0.9, "style": "melee", "loot": {"scrap": [1, 3]}},
	"sentinel": {"name": "Rogue Sentinel", "model": "res://assets/models/enemy_sentinel.glb",
		"hp": [30, 10], "dmg": [8, 2.5], "speed": 3.5, "range": 18.0, "cd": 2.0, "aggro": 26.0, "xp": [34, 11],
		"hover": 0.0, "scale": 0.9, "style": "ranged", "loot": {"scrap": [1, 2], "plasma": [0, 1]}},
	"brute": {"name": "Rogue Brute", "model": "res://assets/models/enemy_brute.glb",
		"hp": [170, 42], "dmg": [18, 4.0], "speed": 3.8, "range": 4.2, "cd": 3.2, "aggro": 18.0, "xp": [110, 30],
		"hover": 0.0, "scale": 1.1, "style": "slam", "elite": true, "loot": {"scrap": [4, 7], "power_core": [1, 1]}},
}


## WoW-style "con" colour: enemy level relative to the player.
func con_color(enemy_lvl: int, player_lvl: int) -> Color:
	var d := enemy_lvl - player_lvl
	if d >= 5:
		return Color("ff3b3b")
	if d >= 3:
		return Color("ff8c3b")
	if d >= -2:
		return Color("ffe066")
	if d >= -6:
		return Color("6ee06a")
	return Color("9aa0a6")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

func item_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id)


func item_color(id: String) -> Color:
	return ITEMS.get(id, {}).get("color", Color.WHITE)


func recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r.id == id:
			return r
	return {}


## XP needed to go from skill level `lvl` to `lvl + 1`.
func skill_xp_needed(lvl: int) -> int:
	return int(30 + lvl * 9 + pow(lvl, 1.35))


## XP needed to go from character level `lvl` to `lvl + 1`.
func level_xp_needed(lvl: int) -> int:
	return int(150 * pow(lvl, 1.45))


## WoW-style difficulty colour for a gather/craft requirement vs current skill.
func difficulty_color(req: int, skill: int) -> Color:
	if skill < req:
		return Color("ff4d4d")
	var d := skill - req
	if d < 10:
		return Color("ff9f43")
	if d < 20:
		return Color("ffe066")
	if d < 35:
		return Color("6ee06a")
	return Color("9aa0a6")


func difficulty_xp_mult(req: int, skill: int) -> float:
	var d := skill - req
	if d < 10:
		return 1.0
	if d < 20:
		return 0.75
	if d < 35:
		return 0.45
	return 0.15
