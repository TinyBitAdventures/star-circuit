# Changelog

## Unreleased (v0.3.0)

### Quality of life
- Scanned resource labels are one short line: "Cobalt Vein  L15" (still coloured by how hard they are for you).
- Rename your robot any time from Cargo & Systems (I). In multiplayer you rejoin under the new name.
- Selling (or buying) one at a time no longer jumps the trade list back to the top.

### Windows
- Star Circuit now ships for Windows too: one self-contained `StarCircuit.exe` (64-bit). Mac and Windows players can share a multiplayer server.

### Multiplayer
- Press **P** (or pick Multiplayer in the pause menu) and join a server by LAN address (`192.168.1.20`), public IP or domain (`play.example.com`), or `wss://` behind HTTPS. An optional password keeps it private.
- Everyone plays their own save. Other players' robots walk the same planet and fly in the same system, painted the way they styled them and with name tags. The player list shows where everyone is ("Diving the Deep Sea on Thalassa").
- Chat, and give items straight to another player. Upgrades stay with your frame.
- Drop a crate on a planet for anyone to pick up. Whoever grabs it first gets it, and crates survive server restarts for three days.
- The server is a single small Go program (`server/`), with builds for macOS, Windows and Linux.
- **Shared caves:** go down the same Cave Mouth as a friend and you're in the same dig: you see each other's drill pods, every tile either of you cuts disappears for both, and tunnels you dug on your own visits merge when you meet.
- **Shared Deep Sea:** dive anywhere on a world where a friend is already diving and you join their sea. Cut rock, kelp and opened clams show up for both, and salvaging the wreck pays everyone.
- **Shared fights:** players are one party. Anyone within 80 m of a drone kill (600 m of a pirate kill in space) gets the XP, credits and their own loot roll. Where you both have the same drone (like the camps around the Cradle), your shots and its death sync, so you wear it down together. A kill only ever pays once.

### Fixes
- Recalling a hauler into a vault that had filled up behind it could push the vault over its limit, which then duplicated items on later worker reports and parcel claims. Whatever doesn't fit now comes back as a parcel.
- Claiming a parcel into a full hold or vault leaves the rest attached instead of overfilling the hold.
- A full inbox no longer deletes parcels you haven't opened; old read messages go first.
- Quitting or saving in the middle of an Eruption Run no longer lets you keep the haul: it only becomes yours once you're out (or half of it, if the volcano blows).
- Crystal spots in a volcano stay the same each time you go in, until you escape it.
- Leaving a volcano at 0 hull after a hard landing on the way out could leave you unable to die or open the Homespace.
- Pressing the Homespace key again during its exit fade could unpause the world while you were still inside.
- Starting a new game no longer carries over the last save's volcano and hyperspace records (which could hand out Firewalker for free).
- Opening a panel or the pause menu during a hyperspace interdiction now freezes the fight, and the crosshair works again when you close it.
- Hyperspace shots no longer slip through mines and swarm drones at lower frame rates.
- The Micro Lab quest shows your actual Homespace key if you've rebound it.
- Volcanoes were impossible to enter: the cone had no collision (you walked straight through it) and its entry point sat at a fixed height that ended up buried in, or floating above, the surrounding hills. Volcanoes are now solid, their base sinks into the ground, and a glowing lava-tube doorway sits at the foot of the cone on the actual ground. You can also enter from the crater rim if you jetpack up. The quest star points at the doorway.

### Illustrated planets
- Whole planets now look hand-drawn wherever you see them in full: the title screen, flying through a star system, and sister worlds hanging in the sky. Each is drawn from the world's real terrain: inked coastlines, a shallow-water band with a dashed wave line offshore, contour lines up the hills, flat painted land colours, a single crisp sun glint on the sea, halftone dots across the terminator, a violet night side and a clean two-step halo. Clouds become separate puffs with inked edges, lit on top. Lava worlds glow with a cracked crust.
- The rest of the game looks exactly as before. Settings > Display > Planets from afar switches back to Classic.

### Skies and ground detail
- Skies are a deeper colour overhead and only hazy near the horizon, with a soft glow around the sun and orange and pink dusk colours on the sun's side. Deserts now have a dusty blue sky over the sand, and glacial, crystal, volcanic and storm worlds get their own skies too.
- Fog is tuned per world (clear on green and icy worlds, thicker on dusty and volcanic ones), matches the sky's haze, glows warm when you look toward the sun, and turns grey in storms.
- Grass is much fuller near you, with colour variation and drier patches, and it parts around your robot's feet as you walk. Deserts have sparse dry tufts.
- Pebbles and small stones are scattered across every world.
- The ground drifts between dry and lush patches with darker soil, and dunes, snowfields and storm worlds show wind ripples.
- Low quality now shows a lighter layer of grass and stones instead of none.

### The Micro Lab
- A new station in the Homespace. Load ingredients from your hold or vault and drop into a bowl of primordial soup under the microscope: a warm, swirling broth with fat droplets, flecks and bubbles, tinted by what went in.
- Every ingredient becomes a strain of cells with its own habits: some drift, some dart about, some blink from place to place, some swarm, and some wear shells you have to crack first.
- Steer a tiny probe with WASD, aim with the mouse and zap a cell to tag it, then zap a different strain to fuse the two. Fused cells divide on their own, but red corruption phages drift in to eat them, so zap those on sight. Now and then the soup gets stirred and everything swirls.
- Reach critical mass before the culture goes off. The faster you get there, the better the grade: Stable, Refined or Pristine. A lost culture gives back half its ingredients.
- Eight formulas finally give the rare finds a use: Medic and Warp cultures (more Repair Kits or Warp Cells at better grades), plus six graded upgrades: Mycelium Mesh (cargo), Living Hull Graft (hull), Ember Heart (energy), Growth Lattice (harvest speed), Lustre Symbiote (sell prices) and Void Symbiont (energy and hull). Grow an upgrade again to improve its grade. The top formulas need Engineering 70 and 85, which gives Expert and Artisan training a purpose.
- A new quest, "Primordial Soup", after "Into the Fire", the "Cell Biologist" milestone, a bubbling lab theme and eleven new sounds.

### Volcanoes
- The Eruption Run starts with a briefing, and the clock waits until you press a key: dive for crystals, mine them, climb back out the rim before it blows. If it erupts while you're inside you're blasted out with 40% hull and lose half of what you mined.
- You can drill now: push into rock to cut through it, hold S to drill down, jetpack into a ceiling to drill up. Deeper rock is tougher, black basalt won't budge, and deep rock sometimes gives Obsidian.
- The lava tube can no longer pinch into a corner you can't squeeze past.
- Crystals deep in the volcano are never sitting in (or right beside) a lava pool any more.
- Under the timer: what you're carrying and how far up the rim is, flashing "GET OUT!" in the last 45 seconds.
- Volcanic worlds and moons now have three Volcanic Vents (one within walking distance of the landing, all on the compass) leading into the **Eruption Run**: a 2D cutaway of the volcano from the crater down through the Lava Tubes, Obsidian Galleries, Magma Chamber and Deep Mantle to the glowing core.
- Magma rises the whole time and the volcano erupts after 2.5 minutes. Dive for crystals in the side pockets, ride geysers back up, and climb out at the rim in time. Getting caught in the eruption costs half your haul.
- A heat meter and jetpack fuel, plus new materials: Obsidian, Fire Opal and Core Ember.
- "Into the Fire" points the quest star at the nearest vent (and at the volcanic planet from space), and names the nearest volcanic world when you accept it.
- The "Into the Fire" quest, the "Firewalker" milestone, an Obsidian Heat Plating recipe, and a rumbling ambience.

### Art style (preview)
- Settings → Display → Art style: **Classic** (default), **Illustrative** (banded light, cool shade, warm rims, painted terrain) or **Storybook** (Illustrative plus ink outlines). Planets only for now.

### Hyperspace
- Warps and relay jumps now fly you down a hyperspace tunnel. Calm jumps last a few seconds and can be skipped.
- Pirate interdictions: swarm drones that telegraph and dive, raiders and gunships firing from ahead, and mine fields. Aim with the mouse, fire cannons and homing missiles, and dodge with WASD. Clearing every wave pays a salvage bounty; getting knocked out drops you at the destination with some cargo lost.
- The first warp always shows you an interdiction; relit Circuit jumps are rarely attacked.
- A driving hyperspace combat track and a rushing tunnel ambience.

### The Homespace
- Press **Y** anywhere to step into a small 2D digital home inside your robot. The world pauses, and you step back out exactly where you were.
- **Vault:** 300 units of cloud storage (expandable to 1500). Moving items costs energy based on your uplink: cheap where a relay is lit, weaker in unlit systems, and weaker again underground or underwater.
- **Inbox:** letters and parcels, including a welcome from the Archivist, and trader orders from towns you've visited. Fill orders remotely from the vault for 30-70% over market before they expire.
- **Trophy Wall:** gems, relics, species holograms, milestone badges and the Crown pedestal. A window shows where you are right now.
- A cozy lo-fi home theme, plus enter and exit sounds.
- **Dispatch Bay:** compile up to three subroutine workers (the first is free, then ⌬ 900 and ⌬ 2800). Send them to visited worlds to Gather, Survey, or Haul & Sell goods from your vault, on 5, 15 or 30 minute play-time jobs. The risk of coming back damaged depends on the world's danger and the worker's level (1-10). Reports and payments arrive in the Inbox.
- **Decor:** 14 pieces to buy and arrange in wall and floor spots, 5 room themes, and two wings to expand into: the Observatory, showing your lit relays as a constellation, and the Garden. The Defrag Pod fully restores you once per in-game day.

## v0.2.0 — 2026-09-23

A big expansion: new places to explore above, below and beneath the waves, a real endgame, and a lot of polish.
Saves from v0.1.0 carry over (they move into Slot 1 automatically).

### New places to explore
- **The Deep:** every planet has Cave Mouths that drop you into a 2D digging mode through five rock layers,
  with ore veins, gas pockets, magma, and sealed chambers that open into small walkable 3D grottos full of
  rare nodes, glowing cave species, fossils and relics.
- **Oceans and the Deep Sea:** oceans are deep enough to swim now. Underwater the view turns murky with
  caustics and light shafts, and sound goes muffled. Dive deeper and you drop into the Deep Sea: a 2D slice
  of the ocean through the Sunlit, Twilight and Midnight zones and into the Abyss. It has kelp, pearl clams,
  hot vents, a sunken wreck, fish schools, stinging jellies, hunting anglerfish and a leviathan. The Abyss
  needs a Pressure Hull.
- **Orbit and Deep Probes:** hold orbit over any planet, moon or gas giant (O) to see the world cut open,
  crust to core. Drop tethered probes past faultstone and molten heat to extract **world gems**: ten kinds,
  1-3 per world, gone once taken.
- **Richer star systems:** planets and moons really orbit, and about 50 small moons can be landed on.
  Gas giants can be skimmed for plasma, derelict ships can be boarded, solar flares roll through,
  and there's a system map with waypoints.

### Endgame
- **Relight the Circuit:** relight relay beacons with Resonance Crystals to open free relay jumps, reach the
  three legendary edge worlds, and face the shielded Corruption Heart.
- **The Crown of Worlds:** after the Heart, collect all ten world gems and fabricate the Crown.

### Progression
- A 33-quest storyline, with new quests for caves, the sea, probes and the endgame; quests you've already done
  by owning the upgrade now complete themselves.
- Species Log (every creature and plant you've scanned, by world) and 15 Milestones with small permanent bonuses.
- World Gems collection tab.
- Pacing pass: a gentler profession curve, more XP per gather, a double-XP bonus the first time you fabricate
  anything, and lower requirements on a few recipes that were blocking the story.

### Customisation and combat
- Outfitter at trade hubs: paint your robot and ship, and pick heads, toppers, backpacks and finishes.
- Weapon loadouts: Pulse, Scatter and Rail (X to swap).
- Sprint on planets with a camera kick and dust.

### Feel and polish
- Settings screen: key rebinding, mouse sensitivity, invert-Y, field of view, fullscreen, graphics quality, volume.
- Three save slots with Continue, Load and Delete.
- First-hour guidance: a gold quest star on the compass (and a waypoint in space), plus one-time tips you can turn off.
- Gathering animations: a mining laser with sparks and chips, a botany tractor beam, a golden siphon stream,
  and resource orbs flying into the robot.
- Softer shadows at every quality level, and an atmosphere pass: heat shimmer on hot worlds, sun shafts,
  frost on glacial nights, and a colour grade for each world type.
- Graphics: better sky, clouds, water, grass, lighting and drop-pod landings.
- New music (ocean, abyss, orbit) and new effects (sonar, splashes, leviathan calls, probe launch and winch, gem lock and more).

### Fixes
- Robots could get wedged at landing-pad edges and fail to lift off.
- Probes sometimes reeled straight back without launching.
- Ocean music could cut out after switching tracks quickly.
- The robot select screen now frames each robot properly at any window shape.

## v0.1.0 — 2026-09-22

First release: four robots, a procedural galaxy of 48 stars, walkable spherical planets, professions,
crafting, combat, towns and traders, space mining, space combat, cargo and orbital stations, and and a quest storyline.
