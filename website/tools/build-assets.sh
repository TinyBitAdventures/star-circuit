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
TRACKS="menu verdant arid crystal ember town space orbit ocean abyss underground hyperspace home combat"
for tr in $TRACKS; do
	cp "$REPO/game/assets/audio/music/$tr.ogg" "$T/music/$tr.ogg"
	ffmpeg -loglevel error -y -i "$T/music/$tr.ogg" -c:a aac -b:a 128k "$T/music/$tr.m4a"
done
echo "music: $(ls "$T/music" | wc -l | tr -d ' ') files"
if [[ "${1:-}" == "--shots" ]]; then
	CAP="$(mktemp -d)"
	cd "$REPO/game"
	for tour in portraits atmo mine orbit sea volcano warp home; do
		rm -rf "$REPO/shots"
		SHOTS=$tour godot --path . --resolution 1600x900 res://scenes/dev_shots.tscn >/dev/null 2>&1 || true
		mkdir -p "$CAP/$tour" && cp "$REPO/shots/"*.png "$CAP/$tour/" 2>/dev/null || true
	done
	i=1
	for id in scout miner engineer siphon; do
		ffmpeg -loglevel error -y -i "$CAP/portraits/0${i}_portrait_$((i - 1)).png" -vf "crop=560:700:260:150" -q:v 4 "$T/img/robot-$id.jpg"
		i=$((i + 1))
	done
	while read -r src dst; do
		ffmpeg -loglevel error -y -i "$CAP/$src" -vf "scale=1280:-2" -q:v 5 "$T/img/$dst.jpg"
	done <<'LIST'
atmo/01_atmo_verdant_dusk.png planet-dusk
atmo/02_atmo_dune_noon.png planet-desert
atmo/04_atmo_prism_sunset.png planet-crystal
atmo/03_atmo_frost_night.png planet-frost
mine/02_mine_mining_late.png mining
orbit/03_orb_verdant_scanned.png orbit
orbit/14_orb_giant_probe.png orbit-giant
sea/02_sea3d_under.png sea-3d
sea/06_sea2d_twilight.png sea-twilight
sea/07_sea2d_midnight.png sea-midnight
volcano/05_vol_zone_3.png volcano-chamber
volcano/02_vol_crater.png volcano-crater
volcano/01_vol_vent_3d.png volcano-vent
warp/03_warp_firefight.png warp-fight
warp/01_warp_tunnel.png warp-tunnel
warp/06_warp_relay.png warp-relay
home/07_home_dispatch_room.png home-room
home/11_home_observatory.png home-observatory
home/08_home_dispatch_panel.png home-dispatch
LIST
	echo "shots: rebuilt $(ls "$T/img" | wc -l | tr -d ' ') images"
fi
