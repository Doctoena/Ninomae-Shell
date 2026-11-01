#!/usr/bin/env bash
# A screenshot of the game's screen, from the in-game overlay (modules/gameOverlay). Saved where the launcher
# looks for the game's screenshots, so it's on the game's page with the rest: Steam's F12 folder for a Steam
# game, the game's own screenshots folder for others (find_screenshots.py says which), else
# ~/Pictures/Screenshots/<game>. Says so in a notification.
#   game_screenshot.sh <monitor> <game name> <steam app id or ""> <game folder or ""> <flatpak id or "">
set -u
monitor="$1" game="${2:-Game}" appid="${3:-}" gamedir="${4:-}" flatpak="${5:-}"
here="$(dirname -- "$(readlink -f -- "$0")")"

folder="$(python3 -I "$here/find_screenshots.py" "$appid" "$gamedir" "$flatpak" 2>/dev/null | head -1 | cut -f2)"
if [[ -z $folder ]]; then
    safe="$(printf '%s' "$game" | tr -d '\000-\037' | tr '/' '-' | sed 's/^[. ]*//;s/[. ]*$//')"
    folder="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots/${safe:-Game}"
fi
mkdir -p -- "$folder" || exit 1
file="$folder/$(date +'%Y%m%d%H%M%S')_1.png" # Steam's own naming

if ! grim -o "$monitor" -- "$file"; then
    notify-send -a "Screenshots" -i dialog-warning "Screenshot failed" "Couldn't capture $monitor"
    exit 1
fi
setsid -f bash -c '
    action=$(notify-send -a "Screenshots" -i "$2" --action=open=Open --action=folder="Show folder" \
        "Screenshot saved" "$1" 2>/dev/null)
    case "$action" in
        open) xdg-open "$2" ;;
        folder) xdg-open "$(dirname "$2")" ;;
    esac' screenshot-notify "$game" "$file" >/dev/null 2>&1
