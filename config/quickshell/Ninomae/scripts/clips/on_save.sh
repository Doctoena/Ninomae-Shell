#!/usr/bin/env bash
# Run by gpu-screen-recorder after it saves a clip (its -sc option): $1 is the file, $2 the kind.
# Moves the clip into a folder per game with a readable name and says so in a notification.
# The game's name and the clips folder come from the shell through the environment
# (CLIP_GAME, CLIPS_DIR), set on the recorder (services/GameClips.qml).
set -u
src="$1"
[[ -f $src ]] || exit 0
game="${CLIP_GAME:-Game}"
# Safe as a folder and file name: no slashes or control characters
safe="$(printf '%s' "$game" | tr -d '\000-\037' | tr '/' '-' | sed 's/^[. ]*//;s/[. ]*$//')"
[[ -n $safe ]] || safe="Game"
dir="${CLIPS_DIR:-$HOME/Videos/Clips}/$safe"
mkdir -p -- "$dir"
dest="$dir/$safe $(date +'%Y-%m-%d %H-%M-%S').${src##*.}"
mv -f -- "$src" "$dest" || dest="$src"

# The notification's picture: the game's own icon. Steam keeps a small square one per game in its library
# cache (a jpg named by its hash, beside the art folders); else the game's cover art (shown cropped
# square); else the film icon
icon=""
if [[ -n ${CLIP_APPID:-} ]]; then
    for steam in "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
        for f in "$steam/appcache/librarycache/$CLIP_APPID"/*.jpg; do
            [[ -f $f && $(basename "$f") =~ ^[0-9a-f]{40}\.jpg$ ]] && { icon="$f"; break 2; }
        done
    done
fi
[[ -z $icon && -n ${CLIP_ART:-} && -f ${CLIP_ART} ]] && icon="$CLIP_ART"
icon="${icon:-video-x-generic}"

# How long it really is, as the Clips page's tiles show it (0:58): shorter than the setting when the game
# hadn't been running that long
raw=$(ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$dest" 2>/dev/null)
if [[ $raw =~ ^[0-9]+(\.[0-9]+)?$ ]]; then secs=$(LC_ALL=C printf '%.0f' "$raw") # Rounded, as the tiles do
else secs=${CLIP_SECONDS:-60}; fi
length=$(printf '%d:%02d' $((secs / 60)) $((secs % 60)))

# The notification waits for a click, so it goes off on its own (the recorder doesn't wait on it)
setsid -f bash -c '
    action=$(notify-send -a "Clips" -i "$4" --action=play=Play --action=folder="Show folder" \
        "Clip saved" "$1 · $3" 2>/dev/null)
    case "$action" in
        play) xdg-open "$2" ;;
        folder) xdg-open "$(dirname "$2")" ;;
    esac' clip-notify "$game" "$dest" "$length" "$icon" >/dev/null 2>&1
