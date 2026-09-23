#!/usr/bin/env bash
# Copy the theme (source of truth: website/theme/star-circuit) into the
# Cove site at https://starcircuit.localhost. Pass --data to re-export
# game data from Godot first.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
if [[ "${1:-}" == "--data" ]]; then
	godot --headless --path "$REPO/game" -s ../website/tools/export_site_data.gd 2>&1 | grep '\[export\]'
fi
SITE="$(bash /Users/austin/Documents/Cove/cove.sh path starcircuit)"
DEST="$SITE/wp-content/themes/star-circuit"
mkdir -p "$DEST"
rsync -a --delete "$HERE/theme/star-circuit/" "$DEST/"
echo "synced theme -> $DEST"
