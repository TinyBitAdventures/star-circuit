# Star Circuit website

A one-page, interactive WordPress theme for the game, served locally by Cove
at **https://starcircuit.localhost**.

- `theme/star-circuit/`: the theme (source of truth). `index.php` is the whole page;
  `assets/js/site.js` runs the starfield/warp, robot picker, mode carousels,
  galaxy map (with warp route plotting) and the soundtrack player with its visualizer;
  `assets/js/hyperspace-game.js` is the playable mini-game.
- `assets/data/game.json` is exported from the real game data (robots, the
  48-star galaxy, biomes, counts, version) by `tools/export_site_data.gd`.
- `tools/build-assets.sh [--shots]` re-exports data, rebuilds the music
  (OGG + AAC for Safari) and, with `--shots`, re-captures screenshots.
- `sync.sh [--data]` copies the theme into the Cove site.
- `tools/check-site.mjs` drives headless Chromium through every interactive
  piece, checks for console errors and mobile overflow, and writes `shots/`.

    cove add starcircuit                 # once
    website/tools/build-assets.sh        # data + music
    website/sync.sh                      # copy into Cove
    cove wp starcircuit theme activate star-circuit
    node website/tools/check-site.mjs    # verify
