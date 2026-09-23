#!/bin/sh
# Launch Star Circuit (rebuilds Blender assets first with --assets)
cd "$(dirname "$0")"
if [ "$1" = "--assets" ]; then
  blender --background --factory-startup --python blender/build_assets.py
  audio/.venv/bin/python audio/build_music.py
  audio/.venv/bin/python audio/build_sfx.py
  godot --headless --import --path game
fi
exec godot --path game
