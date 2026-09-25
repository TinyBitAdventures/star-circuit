#!/usr/bin/env bash
# Regenerate the website's derived assets from the game:
#   data   game.json exported from Godot (robots, galaxy, counts, version)
#   music  every soundtrack OGG copied, plus an AAC (.m4a) copy for Safari
#   shots  (--shots) re-run the game's screenshot tours and rebuild the
#          portraits and gallery JPGs (slow: ~10 minutes, opens windows)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(dirname "$HERE")"
T="$HERE/theme/star-circuit/assets"
mkdir -p "$T/music" "$T/img" "$T/data"
( cd "$REPO/game" && godot --headless --path . -s ../website/tools/export_site_data.gd 2>&1 | grep '\[export\]' )
TRACKS="menu verdant arid crystal ember town space orbit ocean abyss underground hyperspace home lab combat titan"
for tr in $TRACKS; do
	cp "$REPO/game/assets/audio/music/$tr.ogg" "$T/music/$tr.ogg"
	ffmpeg -loglevel error -y -i "$T/music/$tr.ogg" -c:a aac -b:a 128k "$T/music/$tr.m4a"
done
echo "music: $(ls "$T/music" | wc -l | tr -d ' ') files"
if [[ "${1:-}" == "--shots" ]]; then
	CAP="$(mktemp -d)"
	cd "$REPO/game"
	for tour in portraits atmo mine orbit sea volcano warp home lab net bestiary titans weapons; do
		rm -rf "$REPO/shots"
		SHOTS=$tour godot --path . --resolution 1600x900 res://scenes/dev_shots.tscn >/dev/null 2>&1 || true
		mkdir -p "$CAP/$tour" && cp "$REPO/shots/"*.png "$CAP/$tour/" 2>/dev/null || true
	done
	i=1
	for id in scout miner engineer siphon; do
		ffmpeg -loglevel error -y -i "$CAP/portraits/0${i}_portrait_$((i - 1)).png" -vf "crop=560:700:260:150" -q:v 4 "$T/img/robot-$id.jpg"
		i=$((i + 1))
	done
	# shots are matched by name, not number: tours gain shots and renumber.
	# Where a tour repeats a name (the volcano zones), the last one wins.
	missing=0
	while read -r tour name dst; do
		src=$(ls "$CAP/$tour/"[0-9][0-9]_"$name".png 2>/dev/null | tail -1 || true)
		if [[ -z $src ]]; then
			echo "missing shot: $tour/$name" >&2
			missing=1
			continue
		fi
		ffmpeg -loglevel error -y -i "$src" -vf "scale=1280:-2" -q:v 5 "$T/img/$dst.jpg"
	done <<'LIST'
atmo atmo_verdant_dusk planet-dusk
atmo atmo_dune_noon planet-desert
atmo atmo_prism_sunset planet-crystal
atmo atmo_frost_night planet-frost
mine mine_mining_late mining
orbit orb_verdant_scanned orbit
orbit orb_giant_probe orbit-giant
sea sea3d_under sea-3d
sea sea2d_twilight sea-twilight
sea sea2d_midnight sea-midnight
volcano vol_zone_3 volcano-chamber
volcano vol_crater volcano-crater
volcano vol_vent_3d volcano-vent
warp warp_firefight warp-fight
warp warp_tunnel warp-tunnel
warp warp_relay warp-relay
home home_dispatch_room home-room
home home_observatory home-observatory
home home_dispatch_panel home-dispatch
lab lab_soup_fusing lab-soup
lab lab_station lab-station
lab lab_result lab-result
net net_bob_and_crate net-planet
net net_cave net-cave
net net_sea net-sea
titans titan_colossus_lanes fight-colossus
titans titan_sentinel_expose fight-sentinel
bestiary foe_warden fight-warden
bestiary foe_thornback fight-thornback
weapons weapon_cinder fight-cinder
LIST
	[[ $missing == 0 ]] || { echo "some shots were missing; the old images were kept" >&2; exit 1; }
	echo "shots: rebuilt $(ls "$T/img" | wc -l | tr -d ' ') images"
fi
