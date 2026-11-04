#!/usr/bin/env bash
# A screenshot of the game's screen, from the in-game overlay (modules/gameOverlay) or F12 in a game that isn't
# Steam's (services/GameClips.qml; Steam takes its own). Saved where the launcher looks for the game's
# screenshots, so it's on the game's page with the rest: Steam's F12 folder for a Steam game, the game's own
# screenshots folder for others, else ~/Pictures/Screenshots/<game> (find_screenshots.py says which). Says so in
# a notification.
#   game_screenshot.sh <monitor> <game name> <steam app id or ""> <game folder or ""> <flatpak id or "">
set -u
monitor="$1" game="${2:-Game}" appid="${3:-}" gamedir="${4:-}" flatpak="${5:-}"
here="$(dirname -- "$(readlink -f -- "$0")")"

folder="$(python3 -I "$here/find_screenshots.py" "$appid" "$gamedir" "$flatpak" "$game" 2>/dev/null | head -1 | cut -f2)"
[[ -n $folder ]] || folder="$HOME/Pictures/Screenshots/Game" # Only if the finder couldn't run
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
