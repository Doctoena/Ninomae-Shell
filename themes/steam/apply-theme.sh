#!/usr/bin/env bash
# Copies the matugen-generated colours into the Material-Theme Millennium theme.
# The theme re-reads matugen.css every 1.5 s, so open windows update without a restart.
# Runs as matugen's post_hook; does nothing until Millennium + Material-Theme are installed.
set -u
SRC="$(dirname "$(readlink -f "$0")")/matugen.css"
[[ -f "$SRC" ]] || exit 0

# Every installed copy of the theme (Millennium has used different theme folders over time)
find "$HOME/.steam/steam/millennium/themes" "$HOME/.local/share/Steam/steamui/skins" "$HOME/.steam/steam/steamui/skins" \
    -maxdepth 2 -name skin.json 2>/dev/null | while read -r skin; do
    grep -q '"repo_name": *"Material-Theme"' "$skin" || continue
    dest="$(dirname "$skin")/css/main/colors/matugen.css"
    mkdir -p "$(dirname "$dest")" && cp "$SRC" "$dest"
    # The theme's mods.css ("Use Modifications File") = the colours + our tweaks. The Matugen colour mode
    # fetches matugen.css with a script after each window opens, so new windows (friends list, …) were
    # black for a moment; as plain CSS the colours are there from the first frame.
    cat "$SRC" "$(dirname "$SRC")/mods.css" > "$(dirname "$skin")/mods.css"
done
exit 0
