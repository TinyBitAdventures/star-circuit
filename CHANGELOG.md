# Changelog

## Unreleased (v0.4.0)

### Combat
- Every world type is getting a signature enemy with a trick to learn. The first three:
  - **Thornback** (Verdant worlds) paints a lane on the ground, then charges down it. Step aside: a miss leaves it stunned and taking 60% more damage.
  - **Dune Lurker** (Arid worlds) dives into the sand, tunnels toward you under a dust trail and bursts up beneath you from a glowing ring. It can't be hit while it's underground.
  - **Frost Warden** (Glacial worlds) hides behind a shield that blocks everything from the front and turns slowly, so circle behind it (back hits do 25% more). Rail slugs and fire go straight through. Its bolts chill you, and up close it pulses a frost nova.
- Signature enemies lead about half the camps on their own worlds (never on the Cradle) and drop their own parts: Thorn Barbs, Sand Fangs and Rime Cores.
- Status effects: **burn** (damage over time), **chill** (slows you; a fourth stack freezes solid) and **shock** (takes 25% more damage). They work on enemies and on you, show on your HUD and the target frame, and tint whatever they're on. Robots shake off a freeze faster than drones do.
- Enemies can be weak or resistant to kinds of damage (fire, frost, shock).

## v0.3.0 — 2026-09-24

Star Circuit goes multiplayer and comes to Windows. Join a friend's server to explore, dig, dive and fight together.
Step into your Homespace from anywhere, fight through pirate ambushes in hyperspace, race an erupting volcano and grow
cultures in the Micro Lab. Whole planets now look hand-drawn from afar. Saves from v0.2.0 carry over.

### Multiplayer
- Press **P** (or pick Multiplayer in the pause menu) and join a server by LAN address (`192.168.1.20`), public IP or domain (`play.example.com`), or `wss://` behind HTTPS. An optional password keeps it private.
- Everyone plays their own save. Other players' robots walk the same planet and fly in the same system, painted the way they styled them and with name tags. The player list shows where everyone is ("Diving the Deep Sea on Thalassa").
- Chat, and give items straight to another player. Upgrades stay with your frame.
- Drop a crate on a planet for anyone to pick up. Whoever grabs it first gets it, and crates survive server restarts for three days.
- The server is a single small Go program with builds for macOS, Windows and Linux. It now lives in its own repo, [star-circuit-server](https://github.com/TinyBitAdventures/star-circuit-server): this release pairs with server v0.1.0.
- **Shared caves:** go down the same Cave Mouth as a friend and you're in the same dig: you see each other's drill pods, every tile either of you cuts disappears for both, and tunnels you dug on your own visits merge when you meet.
- **Shared Deep Sea:** dive anywhere on a world where a friend is already diving and you join their sea. Cut rock, kelp and opened clams show up for both, and salvaging the wreck pays everyone.
- **Shared fights:** players are one party. Anyone within 80 m of a drone kill (600 m of a pirate kill in space) gets the XP, credits and their own loot roll. Where you both have the same drone (like the camps around the Cradle), your shots and its death sync, so you wear it down together. A kill only ever pays once.
- Gifts and crates can't lose items any more: anything the server turns down (more than 9999 at once, more than 20 kinds in a crate, sending too fast, the other player just left) comes straight back with a reason, and nothing leaves your hold if the connection has dropped.
- When you and a friend finish off a drone together with your shots, you both still get the kill.
- Clams a friend opens stay open next time you dive there, and friends' pirate kills in space can't pay twice.
- Safer servers: a friend's cave map can only open tunnels that connect to ones you can reach, oversized or garbled robot styles are ignored, chat and style changes are rate limited, idle and excess connections are dropped, repeated wrong passwords make that address wait, names can't hide invisible characters, and a password-protected server doesn't list who's online. Game and server must both be this version.
- The game and the server must be the same version to play together; this release pairs with server v0.1.0. Open `http://your-server:7777/` to see how many are online.

### Windows
- Star Circuit now ships for Windows too: one self-contained `StarCircuit.exe` (64-bit). Mac and Windows players can share a multiplayer server.

### The Homespace
- Press **Y** anywhere to step into a small 2D digital home inside your robot. The world pauses, and you step back out exactly where you were.
- **Vault:** 300 units of cloud storage (expandable to 1500). Moving items costs energy based on your uplink: cheap where a relay is lit, weaker in unlit systems, and weaker again underground or underwater.
- **Inbox:** letters and parcels, including a welcome from the Archivist, and trader orders from towns you've visited. Fill orders remotely from the vault for 30-70% over market before they expire.
- **Trophy Wall:** gems, relics, species holograms, milestone badges and the Crown pedestal. A window shows where you are right now.
- **Dispatch Bay:** compile up to three subroutine workers (the first is free, then ⌬ 900 and ⌬ 2800). Send them to visited worlds to Gather, Survey, or Haul & Sell goods from your vault, on 5, 15 or 30 minute play-time jobs. The risk of coming back damaged depends on the world's danger and the worker's level (1-10). Reports and payments arrive in the Inbox.
- **Decor:** 14 pieces to buy and arrange in wall and floor spots, 5 room themes, and two wings to expand into: the Observatory, showing your lit relays as a constellation, and the Garden. The Defrag Pod fully restores you once per in-game day.
- An unread count on the HUD when mail arrives, and the room scrolls as you add wings.
- A cozy lo-fi home theme, plus enter and exit sounds.

### The Micro Lab
- A new station in the Homespace. Load ingredients from your hold or vault and drop into a bowl of primordial soup under the microscope: a warm, swirling broth with fat droplets, flecks and bubbles, tinted by what went in.
- Every ingredient becomes a strain of cells with its own habits: some drift, some dart about, some blink from place to place, some swarm, and some wear shells you have to crack first.
- Steer a tiny probe with WASD, aim with the mouse and zap a cell to tag it, then zap a different strain to fuse the two. Fused cells divide on their own, but red corruption phages drift in to eat them, so zap those on sight. Now and then the soup gets stirred and everything swirls.
- Reach critical mass before the culture goes off. The faster you get there, the better the grade: Stable, Refined or Pristine. A lost culture gives back half its ingredients.
- Eight formulas finally give the rare finds a use: Medic and Warp cultures (more Repair Kits or Warp Cells at better grades), plus six graded upgrades: Mycelium Mesh (cargo), Living Hull Graft (hull), Ember Heart (energy), Growth Lattice (harvest speed), Lustre Symbiote (sell prices) and Void Symbiont (energy and hull). Grow an upgrade again to improve its grade. The top formulas need Engineering 70 and 85, which gives Expert and Artisan training a purpose.
- A new quest, "Primordial Soup", after "Into the Fire", the "Cell Biologist" milestone, a bubbling lab theme and eleven new sounds.

### Hyperspace
- Warps and relay jumps now fly you down a hyperspace tunnel. Calm jumps last a few seconds and can be skipped.
- Pirate interdictions: swarm drones that telegraph and dive, raiders and gunships firing from ahead, and mine fields. Aim with the mouse, fire cannons and homing missiles, and dodge with WASD. Clearing every wave pays a salvage bounty; getting knocked out drops you at the destination with some cargo lost.
- Getting knocked out drops you at the destination with 25% hull. Quitting mid-jump is safe: you load in at the destination.
- The first warp always shows you an interdiction; relit Circuit jumps are rarely attacked.
- A driving hyperspace combat track and a rushing tunnel ambience.

### Volcanoes
- Volcanic worlds and moons now have three Volcanic Vents (one within walking distance of the landing, all on the compass) leading into the **Eruption Run**: a 2D cutaway of the volcano from the crater down through the Lava Tubes, Obsidian Galleries, Magma Chamber and Deep Mantle to the glowing core.
- Volcanoes are solid mountains with a glowing lava-tube doorway at the foot of the cone (or jetpack up and drop in from the rim). What you mine only becomes yours once you're out: quit mid-run and it stays in the volcano.
- The Eruption Run starts with a briefing, and the clock waits until you press a key: dive for crystals, mine them, climb back out the rim before it blows. If it erupts while you're inside you're blasted out with 40% hull and lose half of what you mined.
- Once the clock starts, magma rises and the volcano erupts after 2.5 minutes. Dive for crystals in the side pockets, ride geysers back up, and climb out at the rim in time.
- You can drill now: push into rock to cut through it, hold S to drill down, jetpack into a ceiling to drill up. Deeper rock is tougher, black basalt won't budge, and deep rock sometimes gives Obsidian.
- Under the timer: what you're carrying and how far up the rim is, flashing "GET OUT!" in the last 45 seconds.
- A heat meter and jetpack fuel, plus new materials: Obsidian, Fire Opal and Core Ember.
- "Into the Fire" points the quest star at the nearest vent (and at the volcanic planet from space), and names the nearest volcanic world when you accept it.
- The "Into the Fire" quest, the "Firewalker" milestone, an Obsidian Heat Plating recipe, and a rumbling ambience.

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

### Art style (preview)
- Settings → Display → Art style: **Classic** (default), **Illustrative** (banded light, cool shade, warm rims, painted terrain) or **Storybook** (Illustrative plus ink outlines). Planets only for now.

### Quality of life
- Scanned resource labels are one short line: "Cobalt Vein  L15" (still coloured by how hard they are for you).
- Rename your robot any time from Cargo & Systems (I). In multiplayer you rejoin under the new name.
- Selling (or buying) one at a time no longer jumps the trade list back to the top.

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
