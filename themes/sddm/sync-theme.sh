#!/usr/bin/env bash
# Keeps the installed login screen in sync with the desktop: copies the matugen colours (theme.conf)
# and the current wallpaper into /usr/share/sddm/themes/Ninomae. Run by matugen after it regenerates
# colours. Needs no sudo: install-theme.sh makes just these two files writable by your user. Until
# that has run, it does nothing.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/usr/share/sddm/themes/Ninomae"
SHELL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ninomae-shell/config.json"
LAST="${XDG_CACHE_HOME:-$HOME/.cache}/ninomae-sddm-wallpaper" # Source of the last synced wallpaper

# Colours
[[ -w "$TARGET/theme.conf" ]] && cp "$HERE/Ninomae/theme.conf" "$TARGET/theme.conf"

# Wallpaper (only when it changed: re-encoding a big image on every light/dark toggle is wasted work).
# switchwall.sh saves the new path to the shell config before running matugen.
[[ -w "$TARGET/wallpaper.jpg" ]] && command -v magick >/dev/null && command -v jq >/dev/null || exit 0
wallpaper="$(jq -r '.background.wallpaperPath // empty' "$SHELL_CONFIG" 2>/dev/null)"
case "${wallpaper,,}" in *.mp4|*.webm|*.mkv|*.avi|*.mov) # Video wallpaper: use its thumbnail
    wallpaper="$(jq -r '.background.thumbnailPath // empty' "$SHELL_CONFIG" 2>/dev/null)" ;;
esac
wallpaper="${wallpaper/#\~\//$HOME/}" # Stored as ~/…
[[ -r "$wallpaper" ]] || exit 0

# The size version made for the main (largest) screen's shape, as the desktop uses one per screen: name_5120x1440.png
# beside name.png (services/WallpaperVariants.qml). The login screen gets one image, so the main screen's
for_main_screen() {
    local path=$1 sw sh dir stem f w h off best="" best_off=1000
    read -r sw sh < <(hyprctl monitors -j 2>/dev/null | jq -r 'max_by(.width * .height) | "\(.width) \(.height)"' 2>/dev/null)
    [[ ${sw:-0} -gt 0 && ${sh:-0} -gt 0 ]] || { echo "$path"; return; }
    dir=${path%/*}; stem=${path##*/}; stem=${stem%.*}
    for f in "$dir/$stem"_*x*.*; do
        [[ -f $f && ${f##*/} =~ _([0-9]+)x([0-9]+)\ ?(\([0-9]+\))?\.[^.]+$ ]] || continue
        w=${BASH_REMATCH[1]}; h=${BASH_REMATCH[2]}
        off=$(awk -v a="$w" -v b="$h" -v c="$sw" -v d="$sh" 'BEGIN { x = log((a / b) / (c / d)); printf "%d", (x < 0 ? -x : x) * 1000 }')
        (( off < best_off )) && { best=$f; best_off=$off; }
    done
    if [[ -n $best ]] && (( best_off < 95 )); then echo "$best"; else echo "$path"; fi # Within 10% of the shape
}
wallpaper="$(for_main_screen "$wallpaper")"
[[ "$(cat "$LAST" 2>/dev/null)" == "$wallpaper" ]] && exit 0
(
    # In the background so theming isn't held up; written over the existing file to keep its permissions
    tmp="$(mktemp --suffix=.jpg)"
    if magick "$wallpaper" -resize '2560x1440^' -quality 90 "$tmp"; then
        cat "$tmp" > "$TARGET/wallpaper.jpg"
        cp "$tmp" "$HERE/Ninomae/wallpaper.jpg" # Keep the repo's copy current for the next install
        mkdir -p "$(dirname "$LAST")" && printf '%s' "$wallpaper" > "$LAST"
    fi
    rm -f "$tmp"
) >/dev/null 2>&1 &
disown
exit 0
