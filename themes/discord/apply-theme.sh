#!/usr/bin/env bash
# Copies the matugen-generated Discord theme into Vesktop. Vencord watches its themes folder and
# reloads the theme when the file changes, so Discord recolours without a restart. A copy, not a
# symlink: changes to a symlink's target don't trigger the folder watch. Run as matugen's post_hook.
set -u
SRC="$(dirname "$(readlink -f "$0")")/ninomae.theme.css"
THEMES="${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/themes"
[[ -f "$SRC" && -d "$THEMES" ]] || exit 0 # Vesktop not set up yet
cp "$SRC" "$THEMES/ninomae.theme.css"
exit 0
