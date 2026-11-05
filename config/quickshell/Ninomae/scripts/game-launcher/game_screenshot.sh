#!/usr/bin/env bash
# A screenshot of the game's screen: F12 in any game (services/GameClips.qml; the shell's Steam plugin turns
# Steam's own key off) or the in-game overlay (modules/gameOverlay). Saved where the launcher looks for the
# game's screenshots, so it's on the game's page with the rest: the game's own screenshots folder for a game
# that isn't Steam's and has one, else <Pictures>/Screenshots/Games/<game> (find_screenshots.py says which). Taken
# first, then put there: finding the folder can take a moment, and the shot should be of the moment F12 went.
# Says so in a notification.
#   game_screenshot.sh <monitor> <game name> <steam app id or ""> <game folder or ""> <flatpak id or "">
set -u
monitor="$1" game="${2:-Game}" appid="${3:-}" gamedir="${4:-}" flatpak="${5:-}"
here="$(dirname -- "$(readlink -f -- "$0")")"
stamp="$(date +'%Y%m%d%H%M%S')" # Named as Steam names them: <stamp>_1.png
tmp="$(mktemp --tmpdir="${XDG_RUNTIME_DIR:-/tmp}" game-shot.XXXXXX.png)" || exit 1

if ! grim -o "$monitor" -- "$tmp"; then
    rm -f -- "$tmp"
    notify-send -a "Screenshots" -i dialog-warning "Screenshot failed" "Couldn't capture $monitor"
    exit 1
fi
folder="$(python3 -I "$here/find_screenshots.py" --folder "$appid" "$gamedir" "$flatpak" "$game" 2>/dev/null | cut -f2)"
[[ -n $folder ]] || folder="$HOME/Pictures/Screenshots/Games/${game//\//-}" # Only if the finder couldn't run
n=1
while [[ -e $folder/${stamp}_$n.png ]]; do ((n++)); done # Two in the same second
file="$folder/${stamp}_$n.png"
chmod "$(printf '%o' $((0666 & ~$(umask))))" -- "$tmp" # As a file made there: mktemp's are private
if ! mkdir -p -- "$folder" || ! mv -n -- "$tmp" "$file" || [[ -e $tmp ]]; then
    rm -f -- "$tmp"
    notify-send -a "Screenshots" -i dialog-warning "Screenshot failed" "Couldn't save it in $folder"
    exit 1
fi
setsid -f bash -c '
    action=$(notify-send -a "Screenshots" -i "$2" --action=open=Open --action=folder="Show folder" \
        "Screenshot saved" "$1" 2>/dev/null)
    case "$action" in
        open) xdg-open "$2" ;;
        folder) xdg-open "$(dirname "$2")" ;;
    esac' screenshot-notify "$game" "$file" >/dev/null 2>&1
