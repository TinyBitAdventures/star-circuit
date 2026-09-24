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
	"glowcap": {"name": "Glowcap", "kind": "resource", "color": Color("7ef0d8"), "desc": "Bioluminescent fungus that only grows in deep grottos."},
	"fossil": {"name": "Fossil", "kind": "relic", "color": Color("e8dcc4"), "desc": "The bones of something that lived here long before the Circuit. Collectors pay well."},
	"ancient_relic": {"name": "Ancient Relic", "kind": "relic", "color": Color("ffd98a"), "desc": "A humming artefact from a sealed vault. Priceless to archivists, and to merchants."},
	"resonance_crystal": {"name": "Resonance Crystal", "kind": "key", "color": Color("5ff7ff"), "desc": "Still tuned to the Circuit's frequency. Relay beacons need one to relight. Found in derelict ships and deep Ancient Vaults."},
	"relay_coupler": {"name": "Relay Coupler", "kind": "component", "color": Color("9bd1ff"), "desc": "Fabricated power coupling that lets a dead relay accept a Resonance Crystal."},
	"legend_shard": {"name": "Legendary Shard", "kind": "relic", "color": Color("ff7ae6"), "desc": "A fragment from one of the edge worlds. Nothing else in the galaxy looks like it."},
	"obsidian": {"name": "Obsidian", "kind": "resource", "color": Color("4a3f5c"), "desc": "Volcanic glass, razor sharp. Fabricators temper it into heat shielding."},
	"fire_opal": {"name": "Fire Opal", "kind": "relic", "color": Color("ff7a3d"), "desc": "A gem with a flame trapped inside, grown only in the magma chambers under volcanoes."},
	"core_ember": {"name": "Core Ember", "kind": "resource", "color": Color("ffcf6b"), "desc": "A still-glowing shard of a planet's core. Almost nothing survives being carried up from that deep."},
	"kelp": {"name": "Sea Kelp", "kind": "resource", "color": Color("4fbf6a"), "desc": "Long ribbons of kelp from sunlit shallows. Presses into Bio-Polymer."},
	"sea_pearl": {"name": "Sea Pearl", "kind": "relic", "color": Color("f3eef8"), "desc": "Grown in deep-sea clams over lifetimes. Merchants love them."},
	"deep_probe": {"name": "Deep Probe", "kind": "fuel", "color": Color("9bd1ff"), "desc": "A tethered core probe. Launch it from orbit (O near a world) to pull gems out of the deep. Lost if it's crushed or melted."},
	# world gems: 1-3 per world, only reachable by probe from orbit
	"gem_verdant": {"name": "Verdant Emerald", "kind": "gem", "color": Color("3ddc84"), "desc": "Grown slowly in the roots of green worlds. Found only on Verdant planets."},
	"gem_dune": {"name": "Sunstone", "kind": "gem", "color": Color("ffb347"), "desc": "Holds a desert's heat for centuries. Found only on Arid planets."},
	"gem_frost": {"name": "Rime Sapphire", "kind": "gem", "color": Color("5fb4ff"), "desc": "Cold enough to frost your fingers through plating. Found only on Glacial planets."},
	"gem_ember": {"name": "Magma Ruby", "kind": "gem", "color": Color("ff3b3b"), "desc": "Forged where the mantle boils. Found only on Volcanic planets."},
	"gem_prism": {"name": "Prism Diamond", "kind": "gem", "color": Color("e6f2ff"), "desc": "Splits starlight into colours nobody has named. Found only on Crystalline planets."},
	"gem_bloom": {"name": "Spore Opal", "kind": "gem", "color": Color("ff8fd8"), "desc": "Grown, not formed, by fungus older than the Circuit. Found only on Fungal planets."},
	"gem_giant": {"name": "Storm Amber", "kind": "gem", "color": Color("ffd96b"), "desc": "Pressure-fused in a gas giant's core, with lightning trapped inside. Probe a gas giant to find one."},
	"gem_abyss": {"name": "Abyss Pearl", "kind": "gem", "color": Color("6ff3ff"), "desc": "From the floor of the ocean world at the galaxy's edge."},
	"gem_tempest": {"name": "Thunder Quartz", "kind": "gem", "color": Color("b6a4ff"), "desc": "Crackles when held. Only the storm world at the edge grows them."},
	"gem_forge": {"name": "Forgeheart Garnet", "kind": "gem", "color": Color("ff6a2a"), "desc": "A garnet the Machine world made on purpose. Nobody knows why."},
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
	"pressure_hull": {"name": "Pressure Hull", "kind": "upgrade", "color": Color("5fa8ff"), "desc": "Lets you dive into the Abyss without the sea crushing your plating."},
	"crown_of_worlds": {"name": "Crown of Worlds", "kind": "upgrade", "color": Color("ffe9a8"), "desc": "Ten world gems set in one circlet. +50 energy, +50 hull, +20% harvest speed, +10% sell prices, and the galaxy knows your name."},
	"lava_plating": {"name": "Heat Plating", "kind": "upgrade", "color": Color("ff7a3d"), "desc": "Immune to lava and heat drain."},
	# grown in the Micro Lab: the culture's grade (Stable, Refined, Pristine) sets the bonus
	"mycelium_mesh": {"name": "Mycelium Mesh", "kind": "upgrade", "color": Color("7ef0d8"), "desc": "A living net of glowcap threads woven through your hold. More cargo, and more again for a better culture."},
	"hull_graft": {"name": "Living Hull Graft", "kind": "upgrade", "color": Color("f3eef8"), "desc": "Pearl-shell cells that knit into your plating. More maximum hull."},
	"ember_heart": {"name": "Ember Heart", "kind": "upgrade", "color": Color("ff9a4a"), "desc": "A culture that never stops burning. More maximum energy."},
	"growth_lattice": {"name": "Growth Lattice", "kind": "upgrade", "color": Color("6ee06a"), "desc": "Kelp-and-stardust tendrils along your tools. Faster harvesting."},
	"lustre_symbiote": {"name": "Lustre Symbiote", "kind": "upgrade", "color": Color("ffe9a8"), "desc": "A shimmer that makes everything you carry look finer. Better sell prices."},
	"void_symbiont": {"name": "Void Symbiont", "kind": "upgrade", "color": Color("ff7ae6"), "desc": "Something from the Void that decided to live with you. More energy and hull."},
}

# --------------------------------------------------------------------------
# Gatherable node types
# --------------------------------------------------------------------------
const NODES := {
	"ferrite": {"name": "Ferrite Vein", "model": "res://assets/models/res_ferrite.glb", "item": "ferrite", "skill": "mining", "req": 1, "yield": [2, 4], "xp": 18, "time": 2.2, "scale": 1.0},
	"cobalt": {"name": "Cobalt Vein", "model": "res://assets/models/res_cobalt.glb", "item": "cobalt", "skill": "mining", "req": 15, "yield": [2, 3], "xp": 33, "time": 2.8, "scale": 1.0},
	"lumen": {"name": "Lumen Cluster", "model": "res://assets/models/res_crystal.glb", "item": "lumen", "skill": "mining", "req": 30, "yield": [1, 3], "xp": 51, "time": 3.2, "scale": 1.0},
	"void": {"name": "Void Spire", "model": "res://assets/models/res_void.glb", "item": "voidshard", "skill": "mining", "req": 55, "yield": [1, 2], "xp": 82, "time": 4.0, "scale": 1.0},
	"fiber": {"name": "Fiberstalk", "model": "res://assets/models/res_fiber.glb", "item": "biofiber", "skill": "botany", "req": 1, "yield": [2, 4], "xp": 18, "time": 1.8, "scale": 1.0},
	"spore": {"name": "Spore Pod", "model": "res://assets/models/res_spore.glb", "item": "sporegel", "skill": "botany", "req": 20, "yield": [1, 3], "xp": 39, "time": 2.4, "scale": 1.0},
	"glowcap": {"name": "Glowcap Cluster", "model": "res://assets/models/res_spore.glb", "item": "glowcap", "skill": "botany", "req": 10, "yield": [2, 4], "xp": 36, "time": 2.0, "scale": 0.8},
	"salvage": {"name": "Salvage Pile", "model": "res://assets/models/poi_cache.glb", "item": "scrap", "skill": "mining", "req": 1, "yield": [2, 5], "xp": 21, "time": 1.8, "scale": 1.0},
	"exotic": {"name": "Exotic Bloom", "model": "res://assets/models/res_void.glb", "item": "exotic", "skill": "mining", "req": 60, "yield": [1, 2], "xp": 105, "time": 4.0, "scale": 1.1},
	"energy": {"name": "Energy Well", "model": "res://assets/models/res_energy.glb", "item": "plasma", "skill": "siphoning", "req": 1, "yield": [1, 3], "xp": 24, "time": 2.6, "scale": 1.0, "restore": 25},
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
	{"id": "blaster_mk2", "out": "blaster_mk2", "qty": 1, "in": {"scrap": 8, "alloy": 3}, "req": 5, "xp": 70, "cat": "Upgrades"},
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
	{"id": "relay_coupler", "out": "relay_coupler", "qty": 1, "in": {"circuit": 2, "alloy": 4, "plasma": 6}, "req": 20, "xp": 90, "cat": "Components"},
	{"id": "drill_mk2", "out": "drill_mk2", "qty": 1, "in": {"alloy": 4, "biofiber": 4}, "req": 2, "xp": 60, "cat": "Upgrades"},
	{"id": "jet_booster", "out": "jet_booster", "qty": 1, "in": {"alloy": 3, "plasma": 4}, "req": 6, "xp": 60, "cat": "Upgrades"},
	{"id": "capacitor", "out": "capacitor", "qty": 1, "in": {"alloy": 2, "polymer": 2, "plasma": 5}, "req": 15, "xp": 80, "cat": "Upgrades"},
	{"id": "solar_skin", "out": "solar_skin", "qty": 1, "in": {"polymer": 4, "plasma": 6}, "req": 18, "xp": 90, "cat": "Upgrades"},
	{"id": "scanner_mk2", "out": "scanner_mk2", "qty": 1, "in": {"circuit": 2, "polymer": 1}, "req": 25, "xp": 100, "cat": "Upgrades"},
	{"id": "thrusters_mk2", "out": "thrusters_mk2", "qty": 1, "in": {"alloy": 6, "circuit": 2}, "req": 30, "xp": 110, "cat": "Upgrades"},
	{"id": "lava_plating", "out": "lava_plating", "qty": 1, "in": {"alloy": 8, "cobalt": 6}, "req": 35, "xp": 120, "cat": "Upgrades"},
	{"id": "drill_mk3", "out": "drill_mk3", "qty": 1, "in": {"alloy": 6, "circuit": 3, "voidshard": 2}, "req": 55, "xp": 180, "cat": "Upgrades"},
	{"id": "polymer_kelp", "out": "polymer", "qty": 1, "in": {"kelp": 4}, "req": 8, "xp": 20, "cat": "Components"},
	{"id": "pressure_hull", "out": "pressure_hull", "qty": 1, "in": {"alloy": 6, "polymer": 2, "cobalt": 6}, "req": 18, "xp": 110, "cat": "Upgrades"},
	{"id": "lava_plating_obsidian", "out": "lava_plating", "qty": 1, "in": {"obsidian": 8, "alloy": 4}, "req": 25, "xp": 120, "cat": "Upgrades"},
	{"id": "deep_probe", "out": "deep_probe", "qty": 2, "in": {"alloy": 2, "nickel": 3, "plasma": 3}, "req": 10, "xp": 50, "cat": "Consumables"},
	{"id": "crown_of_worlds", "out": "crown_of_worlds", "qty": 1, "in": {"gem_verdant": 1, "gem_dune": 1, "gem_frost": 1, "gem_ember": 1, "gem_prism": 1, "gem_bloom": 1, "gem_giant": 1, "gem_abyss": 1, "gem_tempest": 1, "gem_forge": 1}, "req": 40, "xp": 1500, "cat": "Upgrades"},
	{"id": "warp_drive_mk2", "out": "warp_drive_mk2", "qty": 1, "in": {"void_core": 2, "circuit": 3}, "req": 50, "xp": 220, "cat": "Upgrades"},
]

# --------------------------------------------------------------------------
# Biomes / planet types
# --------------------------------------------------------------------------
# --------------------------------------------------------------------------
# Micro Lab (Homespace): grow cultures in the soup
# --------------------------------------------------------------------------
const LAB_GRADES := ["Stable", "Refined", "Pristine"]
const LAB_GRADE_COLORS := [Color("9bd1ff"), Color("6ee06a"), Color("ffd23f")]
## mass: merged cells needed for critical mass. time: seconds of culture stability.
## qty (consumables) or bonus (upgrades) is indexed by grade.
const LAB_RECIPES := [
	{"id": "medic_culture", "name": "Medic Culture", "out": "repair_kit", "qty": [2, 3, 4], "in": {"biofiber": 4, "plasma": 3}, "skill": "botany", "req": 1, "mass": 24, "time": 100.0, "xp": 60},
	{"id": "warp_culture", "name": "Warp Culture", "out": "warp_cell", "qty": [1, 2, 3], "in": {"cryo_ice": 4, "stardust": 2}, "skill": "engineering", "req": 25, "mass": 28, "time": 100.0, "xp": 90},
	{"id": "mycelium_mesh", "name": "Mycelium Mesh", "out": "mycelium_mesh", "bonus": [{"cargo": 40}, {"cargo": 70}, {"cargo": 100}], "in": {"glowcap": 4, "sporegel": 3, "biofiber": 4}, "skill": "botany", "req": 30, "mass": 32, "time": 110.0, "xp": 160},
	{"id": "hull_graft", "name": "Living Hull Graft", "out": "hull_graft", "bonus": [{"hull": 20}, {"hull": 35}, {"hull": 50}], "in": {"sea_pearl": 2, "fossil": 1, "polymer": 2}, "skill": "engineering", "req": 40, "mass": 36, "time": 110.0, "xp": 210},
	{"id": "ember_heart", "name": "Ember Heart", "out": "ember_heart", "bonus": [{"energy": 20}, {"energy": 35}, {"energy": 50}], "in": {"fire_opal": 2, "core_ember": 1, "plasma": 4}, "skill": "engineering", "req": 50, "mass": 40, "time": 110.0, "xp": 260},
	{"id": "growth_lattice", "name": "Growth Lattice", "out": "growth_lattice", "bonus": [{"harvest": 0.06}, {"harvest": 0.1}, {"harvest": 0.15}], "in": {"kelp": 6, "glowcap": 3, "stardust": 2}, "skill": "botany", "req": 60, "mass": 44, "time": 115.0, "xp": 300},
	{"id": "lustre_symbiote", "name": "Lustre Symbiote", "out": "lustre_symbiote", "bonus": [{"sell": 0.03}, {"sell": 0.05}, {"sell": 0.08}], "in": {"sea_pearl": 2, "obsidian": 4, "ancient_relic": 1}, "skill": "engineering", "req": 70, "mass": 48, "time": 115.0, "xp": 360},
	{"id": "void_symbiont", "name": "Void Symbiont", "out": "void_symbiont", "bonus": [{"energy": 15, "hull": 15}, {"energy": 25, "hull": 25}, {"energy": 40, "hull": 40}], "in": {"exotic": 3, "voidshard": 3, "core_ember": 1}, "skill": "engineering", "req": 85, "mass": 54, "time": 120.0, "xp": 450},
]

## How each ingredient behaves as a strain in the soup.
## move: drift (wanders), dart (sudden dashes), blink (jumps about), swarm (small, in clumps), armor (two hits to tag).
const LAB_STRAINS := {
	"biofiber": {"move": "drift", "speed": 75.0, "r": 28.6},
	"plasma": {"move": "dart", "speed": 150.0, "r": 23.4},
	"cryo_ice": {"move": "drift", "speed": 60.0, "r": 31.2},
	"stardust": {"move": "swarm", "speed": 115.0, "r": 16.9},
	"glowcap": {"move": "drift", "speed": 70.0, "r": 26.0},
	"sporegel": {"move": "dart", "speed": 120.0, "r": 26.0},
	"sea_pearl": {"move": "armor", "speed": 80.0, "r": 33.8},
	"fossil": {"move": "armor", "speed": 60.0, "r": 33.8},
	"polymer": {"move": "drift", "speed": 85.0, "r": 28.6},
	"fire_opal": {"move": "dart", "speed": 185.0, "r": 23.4},
	"core_ember": {"move": "dart", "speed": 210.0, "r": 20.8},
	"kelp": {"move": "drift", "speed": 60.0, "r": 31.2},
	"obsidian": {"move": "armor", "speed": 95.0, "r": 28.6},
	"ancient_relic": {"move": "blink", "speed": 90.0, "r": 28.6},
	"exotic": {"move": "blink", "speed": 130.0, "r": 23.4},
	"voidshard": {"move": "blink", "speed": 110.0, "r": 26.0},
}


func lab_recipe(id: String) -> Dictionary:
	for r in LAB_RECIPES:
		if r.id == id:
			return r
	return {}


func lab_strain(item: String) -> Dictionary:
	return LAB_STRAINS.get(item, {"move": "drift", "speed": 90.0, "r": 26.0})


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
	"abyss": {
		"name": "Abyssal", "legendary": true, "sea": 0.022, "amp": 0.06, "ridge": 0.05,
		"colors": {"deep": Color("0a2a55"), "beach": Color("f0e6c8"), "low": Color("4fc2a0"), "mid": Color("2f8f7a"), "high": Color("6b7f8a"), "peak": Color("e8f4ff"), "rock": Color("3a4a55")},
		"water": Color(0.08, 0.35, 0.75, 0.82), "atmo": Color("6fb8ff"), "horizon": Color("c8ecff"), "ambient": Color("a8d8ff"),
		"flora": {"flora_tree_disc": 70, "flora_mushroom": 30, "prop_boulder": 20},
		"nodes": {"lumen": 20, "cobalt": 18, "energy": 16, "exotic": 8},
		"critters": 14, "fauna_colors": [Color("7ee8fa"), Color("ffffff"), Color("ffd23f")],
	},
	"tempest": {
		"name": "Tempest", "legendary": true, "sea": -1.0, "amp": 0.07, "ridge": 0.08,
		"colors": {"deep": Color("2a2440"), "beach": Color("6a6480"), "low": Color("5a5670"), "mid": Color("46425c"), "high": Color("34304a"), "peak": Color("c8c0ff"), "rock": Color("25222f")},
		"water": Color(0, 0, 0, 0), "atmo": Color("8a7fd8"), "horizon": Color("d8d0ff"), "ambient": Color("b0a8e8"),
		"flora": {"flora_ice": 110, "prop_boulder": 60},
		"nodes": {"void": 20, "lumen": 18, "energy": 26, "exotic": 10},
		"critters": 6, "fauna_colors": [Color("c3a6ff"), Color("5ff7ff")],
	},
	"forge": {
		"name": "Machine", "legendary": true, "sea": -0.006, "amp": 0.05, "ridge": 0.07, "lava": true,
		"colors": {"deep": Color("ff6a1f"), "beach": Color("3a3d45"), "low": Color("4a4e58"), "mid": Color("5a5f6b"), "high": Color("6e7380"), "peak": Color("9aa0ab"), "rock": Color("2a2c33")},
		"water": Color(1.0, 0.45, 0.1, 1.0), "atmo": Color("ff9a5b"), "horizon": Color("ffcfa0"), "ambient": Color("ffc8a0"),
		"flora": {"prop_boulder": 90},
		"nodes": {"salvage": 30, "void": 20, "exotic": 14, "energy": 16},
		"critters": 0, "fauna_colors": [Color("ff6a2a")],
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
## Milestones: permanent small bonuses. metric is read by Game.metric().
## bonus keys: energy, hull (flat), cargo (flat), harvest, sell (fraction).
const MILESTONES := [
	{"id": "wanderer", "name": "Wanderer", "desc": "Set foot on 5 worlds", "metric": "worlds", "n": 5, "bonus": {"energy": 10}},
	{"id": "voyager", "name": "Voyager", "desc": "Set foot on 15 worlds", "metric": "worlds", "n": 15, "bonus": {"energy": 20}},
	{"id": "star_hopper", "name": "Star Hopper", "desc": "Visit 4 star systems", "metric": "stars", "n": 4, "bonus": {"cargo": 20}},
	{"id": "naturalist", "name": "Naturalist", "desc": "Log 20 species", "metric": "species", "n": 20, "bonus": {"harvest": 0.05}},
	{"id": "xenobiologist", "name": "Xenobiologist", "desc": "Log 60 species", "metric": "species", "n": 60, "bonus": {"harvest": 0.1}},
	{"id": "cartographer", "name": "Cartographer", "desc": "Fully survey 3 worlds", "metric": "surveyed", "n": 3, "bonus": {"energy": 15}},
	{"id": "scrapper", "name": "Scrapper", "desc": "Destroy 25 rogue drones", "metric": "kills", "n": 25, "bonus": {"hull": 15}},
	{"id": "ace", "name": "Void Ace", "desc": "Destroy 15 ships in space", "metric": "space_kills", "n": 15, "bonus": {"hull": 15}},
	{"id": "trader", "name": "Well Travelled Trader", "desc": "Visit 4 towns", "metric": "towns", "n": 4, "bonus": {"sell": 0.05}},
	{"id": "archivist", "name": "Keeper of Records", "desc": "Recover 8 Codex entries", "metric": "codex", "n": 8, "bonus": {"sell": 0.05}},
	{"id": "spelunker", "name": "Spelunker", "desc": "Recover 3 relics from the Deep", "metric": "relics", "n": 3, "bonus": {"cargo": 30}},
	{"id": "lamplighter", "name": "Lamplighter", "desc": "Light 4 Circuit relays", "metric": "relays", "n": 4, "bonus": {"energy": 20, "hull": 20}},
	{"id": "deep_diver", "name": "Deep Diver", "desc": "Reach 250 m in the Deep Sea", "metric": "sea_depth", "n": 250, "bonus": {"hull": 20}},
	{"id": "firewalker", "name": "Firewalker", "desc": "Escape 5 volcanoes before they erupt", "metric": "volcano_runs", "n": 5, "bonus": {"energy": 15}},
	{"id": "cell_biologist", "name": "Cell Biologist", "desc": "Grow 3 Pristine cultures in the Micro Lab", "metric": "lab_pristine", "n": 3, "bonus": {"harvest": 0.05}},
	{"id": "gem_hunter", "name": "Gem Hunter", "desc": "Hold 5 different world gems", "metric": "gem_types", "n": 5, "bonus": {"cargo": 30, "sell": 0.05}},
	{"id": "master", "name": "Master of a Craft", "desc": "Reach level 50 in any profession", "metric": "best_skill", "n": 50, "bonus": {"harvest": 0.1}},
]

# --------------------------------------------------------------------------
# The Homespace: decor, themes, workers
# --------------------------------------------------------------------------
## slot "wall" hangs on the back wall; "floor" stands on the floor.
## use: an interaction the piece offers when placed.
const DECOR := {
	"bonsai": {"name": "Data Bonsai", "slot": "floor", "price": 0, "desc": "A little tree grown from spare cycles. Came with the frame."},
	"lamp": {"name": "Arc Lamp", "slot": "floor", "price": 120, "desc": "A tall floor lamp with a warm glow."},
	"cactus": {"name": "Dune Succulent", "slot": "floor", "price": 150, "desc": "A potted plant from an arid world. Very low maintenance."},
	"globe": {"name": "Home Globe", "slot": "floor", "price": 300, "desc": "A spinning hologram of the world you first woke on."},
	"crystal": {"name": "Crystal Cluster", "slot": "floor", "price": 350, "desc": "Lumen crystals that hum a soft chord."},
	"arcade": {"name": "Tiny Arcade", "slot": "floor", "price": 600, "desc": "A cabinet that plays a game about a robot who plays arcade games."},
	"aquarium": {"name": "Sea Tank", "slot": "floor", "price": 900, "desc": "A tank of the sea species you've logged, swimming in holo-water."},
	"charging_pod": {"name": "Defrag Pod", "slot": "floor", "price": 1200, "use": "charge", "desc": "Rest here to fully restore hull and energy. Recharges every in-game day."},
	"neon_home": {"name": "HOME Neon", "slot": "wall", "price": 100, "desc": "It says what it is."},
	"clock": {"name": "Uptime Clock", "slot": "wall", "price": 150, "desc": "Counts every second you've been online."},
	"string_lights": {"name": "String Lights", "slot": "wall", "price": 180, "desc": "Little bulbs in your accent colour."},
	"star_chart": {"name": "Star Chart", "slot": "wall", "price": 250, "desc": "Your lit relays, drawn as a constellation."},
	"poster": {"name": "Frame Poster", "slot": "wall", "price": 200, "desc": "A heroic portrait of your robot. Slightly flattering."},
	"holo_fish": {"name": "Holo Koi", "slot": "wall", "price": 450, "desc": "Two hologram fish circling a wall panel forever."},
}

const HOME_THEMES := {
	"midnight": {"name": "Midnight Neon", "price": 0, "top": Color("0b1030"), "bot": Color("171b44"), "grid": Color(0.4, 0.6, 1.0), "trim": Color(0.4, 0.95, 1.0)},
	"sunset": {"name": "Sunset Arcade", "price": 400, "top": Color("2a0f2e"), "bot": Color("5a2438"), "grid": Color(1.0, 0.5, 0.6), "trim": Color(1.0, 0.7, 0.4)},
	"forest": {"name": "Canopy", "price": 400, "top": Color("0b2218"), "bot": Color("163a26"), "grid": Color(0.4, 1.0, 0.6), "trim": Color(0.6, 1.0, 0.7)},
	"abyss": {"name": "Abyssal", "price": 600, "top": Color("031424"), "bot": Color("08304a"), "grid": Color(0.3, 0.8, 1.0), "trim": Color(0.4, 1.0, 0.9)},
	"gold": {"name": "Gilded", "price": 1500, "top": Color("1e1608"), "bot": Color("3a2a10"), "grid": Color(1.0, 0.85, 0.4), "trim": Color(1.0, 0.9, 0.55)},
}

## Each wing adds room to the right: [name, credits, floor slots, wall slots].
const HOME_WINGS := [["Observatory Wing", 1500, 3, 2], ["Garden Wing", 4000, 3, 2]]

const WORKER_NAMES := ["Pip", "Nib", "Sprocket", "Dot", "Widget", "Tock", "Glim", "Ratchet"]
## Compiling your nth subroutine worker costs this many credits.
const WORKER_COSTS := [0, 900, 2800]
const WORKER_MAX_LEVEL := 10
const JOB_MINUTES := [5, 15, 30]
const JOBS := {
	"gather": {"name": "Gather", "desc": "Harvest what grows and glints on a world you've visited. Returns resources to the vault."},
	"survey": {"name": "Survey", "desc": "Chart a visited world for survey fees, with a chance of fossils and relics."},
	"haul": {"name": "Haul & Sell", "desc": "Carry goods from your vault to a town you've visited and sell them there."},
}

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
	{"id": "undersurface", "title": "Under the Surface", "giver": "Archivist",
		"text": "The crust of every world is riddled with old tunnels. Find a Cave Mouth (the amber lamps give it away), press E to descend, and dig. Your drill cuts through anything in the direction you push; hold W to thrust upward. Dig out 30 tiles.",
		"obj": {"type": "dig", "count": 30}, "xp": 240, "reward": {"energy_cell": 2}, "credits": 50},
	{"id": "chambers", "title": "Hidden Chambers", "giver": "Archivist",
		"text": "Deep down, some hollows glow. Those are sealed chambers from before the Quiet. Dig to one, step inside, and see what the planet has been keeping.",
		"obj": {"type": "chamber", "count": 1}, "xp": 320, "reward": {"repair_kit": 2}, "credits": 80},
	{"id": "blue", "title": "Into the Blue", "giver": "Archivist",
		"text": "Our oceans were never mapped. Swim out, dive until the light starts to fail, then keep going: the Deep Sea opens below. Log three species that live down there.",
		"obj": {"type": "sea_scan", "count": 3}, "xp": 420, "reward": {"energy_cell": 3}, "credits": 120},
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
	{"id": "probe", "title": "Deeper Than Drills", "giver": "Archivist",
		"text": "Drills scratch the crust. The treasures are deeper. Fly close to a world and press O to hold orbit, then drop a Deep Probe down into its core and bring back a gem. I've loaded two probes into your hold; the Fabricator can press more.",
		"obj": {"type": "gem", "count": 1}, "xp": 600, "reward": {"deep_probe": 3}, "credits": 250},
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
	{"id": "fire", "title": "Into the Fire", "giver": "Archivist",
		"text": "Volcanic worlds hide their best treasures under the craters. Find a Volcanic Vent, climb down before it erupts, and bring back a Fire Opal. Watch the magma: it only ever rises.",
		"obj": {"type": "collect", "item": "fire_opal", "count": 1}, "xp": 700, "reward": {"repair_kit": 2}, "credits": 200},
	{"id": "soup", "title": "Primordial Soup", "giver": "Archivist",
		"text": "Your Homespace has grown a Micro Lab. Press Y, walk to the lab and grow a Medic Culture from Biofiber and Plasma. Down there it's all soup: steer your probe with WASD, zap a cell with the left mouse button, then zap a different strain to fuse them. Fused cells divide on their own. Reach critical mass before the culture goes off.",
		"obj": {"type": "lab", "count": 1}, "xp": 650, "reward": {"energy_cell": 2}, "credits": 150},
	{"id": "firstlight", "title": "First Light", "giver": "Archivist",
		"text": "Every system has a dead relay beacon; the Circuit was a chain of them. To relight one you need a Resonance Crystal (derelict wrecks and deep Ancient Vaults still hold them) and a Relay Coupler from your fabricator. Pirates guard the dead relays. Open the system map (M) to find it.",
		"obj": {"type": "relay", "count": 1}, "xp": 900, "reward": {"warp_cell": 1}, "credits": 250},
	{"id": "carto", "title": "Cartographer", "giver": "Archivist",
		"text": "Every world you touch rewrites the map. Set foot on eight different planets.",
		"obj": {"type": "land_unique", "count": 8}, "xp": 900, "reward": {"warp_cell": 2}},
	{"id": "marauder", "title": "Hunt the Marauder", "giver": "Archivist",
		"text": "Far from home, the pirates answer to Marauders: gold-plated flagships with regenerating shields. Break one. Watch its volleys and keep moving.",
		"obj": {"type": "space_elite", "count": 1}, "xp": 1200, "reward": {"power_core": 2, "warp_cell": 1}, "credits": 400},
	{"id": "void", "title": "Touching the Void", "giver": "Archivist",
		"text": "Volcanic worlds hide Void Spires. Master Mining 55 and bring back Void Shards. Only an Expert trainer in a far town can take you that deep.",
		"obj": {"type": "collect", "item": "voidshard", "count": 6}, "xp": 1400, "reward": {"warp_cell": 2}},
	{"id": "network", "title": "The Network", "giver": "Archivist",
		"text": "One relay is a light. Five is a road. Relight four more, and lit relays will let you jump between them without spending a Warp Cell.",
		"obj": {"type": "relay", "count": 5}, "xp": 2000, "reward": {"warp_cell": 3}, "credits": 800},
	{"id": "circuit", "title": "Relight the Circuit", "giver": "Archivist",
		"text": "Build the Void Warp Drive. With it, even the edge of the galaxy is in reach.",
		"obj": {"type": "craft", "item": "warp_drive_mk2", "count": 1}, "xp": 3000, "reward": {"warp_cell": 5}},
	{"id": "edge", "title": "The Edge Worlds", "giver": "Archivist",
		"text": "Three worlds sit at the galaxy's rim: an ocean, a storm, and a machine. The galaxy map marks them in gold. Set foot on one.",
		"obj": {"type": "legendary", "count": 1}, "xp": 3500, "reward": {"warp_cell": 3}, "credits": 1500},
	{"id": "heart", "title": "Heart of the Quiet", "giver": "Archivist",
		"text": "The Machine world's star hides the thing that put the Circuit out: a Corruption Heart. It is shielded by pylons; break them, then break it. This is what I kept the names for, Unit.",
		"obj": {"type": "heart", "count": 1}, "xp": 8000, "reward": {"legend_shard": 1}, "credits": 5000},
	{"id": "gems", "title": "Ten Worlds, Ten Stones", "giver": "Archivist",
		"text": "Every kind of world keeps one kind of gem, and the edge worlds keep the strangest. Bring me five different ones and I'll tell you what the old crowns were for.",
		"obj": {"type": "gem_types", "count": 5}, "xp": 2500, "reward": {"deep_probe": 4}, "credits": 1000},
	{"id": "crown", "title": "The Crown of Worlds", "giver": "Archivist",
		"text": "Before the Quiet, one unit wore a stone from every kind of world. It was called the Crown of Worlds, and it made every world a little kinder to its wearer. Find all ten gems and fabricate it.",
		"obj": {"type": "craft", "item": "crown_of_worlds", "count": 1}, "xp": 6000, "reward": {"legend_shard": 1}, "credits": 4000},
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
	"gem_verdant": 400, "gem_dune": 400, "gem_frost": 400, "gem_ember": 450, "gem_prism": 500, "gem_bloom": 450,
	"kelp": 6, "sea_pearl": 180, "obsidian": 12, "fire_opal": 220, "core_ember": 400,
	"gem_giant": 550, "gem_abyss": 900, "gem_tempest": 900, "gem_forge": 900, "deep_probe": 60,
	"glowcap": 14, "fossil": 90, "ancient_relic": 260, "relay_coupler": 90, "legend_shard": 600,
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
	"pylon": {"name": "Shield Pylon", "model": "res://assets/models/heart_pylon.glb", "hp": [900, 60], "shield": [0, 0],
		"dmg": [10, 2.0], "speed": 0.0, "turn": 1.5, "range": 320.0, "cd": 0.35, "burst": 4, "rest": 2.2, "xp": [200, 30],
		"size": 5.0, "style": "turret", "bolt": Color("ff5d9a"), "loot": {"power_core": [1, 2], "scrap": [4, 8]}},
	"heart": {"name": "Corruption Heart", "model": "res://assets/models/corruption_heart.glb", "hp": [9000, 400], "shield": [0, 0],
		"dmg": [16, 3.0], "speed": 0.0, "turn": 0.8, "range": 420.0, "cd": 0.2, "burst": 10, "rest": 2.6, "xp": [3000, 100],
		"size": 30.0, "style": "turret", "elite": true, "bolt": Color("ff2a55"), "loot": {"exotic": [3, 5], "power_core": [3, 5]}},
	"marauder": {"name": "Pirate Marauder", "model": "res://assets/models/pirate_marauder.glb", "hp": [700, 120], "shield": [220, 40],
		"dmg": [10, 2.5], "speed": 38.0, "turn": 1.2, "range": 280.0, "cd": 0.12, "burst": 7, "rest": 2.4, "xp": [320, 60],
		"size": 8.0, "style": "flagship", "elite": true, "bolt": Color("ff2a55"), "loot": {"scrap": [6, 10], "power_core": [1, 2], "exotic": [0, 1]}},
}


# --------------------------------------------------------------------------
# Asteroids (space mining). hp scales with size; req gates like ground veins.
# --------------------------------------------------------------------------
const ASTEROIDS := {
	"rocky": {"name": "Rocky Asteroid", "req": 1, "items": {"nickel": [2, 4], "ferrite": [1, 3]}, "rock": Color("7d7065"), "vein": Color("c9b8a6"), "xp": 15, "hp": 1.0},
	"metallic": {"name": "Metallic Asteroid", "req": 15, "items": {"nickel": [3, 5], "cobalt": [1, 3]}, "rock": Color("566172"), "vein": Color("3d8bff"), "xp": 30, "hp": 1.4},
	"icy": {"name": "Icy Asteroid", "req": 10, "items": {"cryo_ice": [2, 5], "plasma": [0, 2]}, "rock": Color("cfe6f5"), "vein": Color("7fd8ff"), "xp": 24, "hp": 0.8},
	"crystal": {"name": "Crystalline Asteroid", "req": 30, "items": {"lumen": [1, 3], "stardust": [0, 1]}, "rock": Color("3b3550"), "vein": Color("b98cff"), "xp": 48, "hp": 1.2},
	"void": {"name": "Void-touched Asteroid", "req": 55, "items": {"voidshard": [1, 2], "exotic": [0, 1]}, "rock": Color("18141f"), "vein": Color("ff3d6e"), "xp": 75, "hp": 1.8},
	"comet": {"name": "Comet", "req": 20, "items": {"cryo_ice": [6, 10], "exotic": [1, 3], "stardust": [1, 3]}, "rock": Color("dff4ff"), "vein": Color("9be8ff"), "xp": 120, "hp": 3.0},
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
	"cave": {"name": "Cave Mouth", "model": "res://assets/models/poi_cave.glb", "color": Color("ffb347"),
		"xp": 40, "lore": false, "loot": {}, "verb": "Descend into the cave", "time": 0.0},
	"volcano": {"name": "Volcanic Vent", "model": "", "color": Color("ff6a2a"),
		"xp": 60, "lore": false, "loot": {}, "verb": "Climb down into the volcano", "time": 0.0},
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
	return int(20 + lvl * 5 + pow(lvl, 1.3))


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
