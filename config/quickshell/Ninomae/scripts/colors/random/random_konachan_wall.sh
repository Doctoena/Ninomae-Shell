#!/usr/bin/env bash

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

PICTURES_DIR=$(get_pictures_dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail() { notify-send -a "Wallpaper switcher" -i dialog-error "Couldn't get a random wallpaper" "$1"; exit 1; }

mkdir -p "$PICTURES_DIR/Wallpapers"
page=$((1 + RANDOM % 1000))
link=$(curl -sf --max-time 20 "https://konachan.net/post.json?tags=rating%3Asafe&limit=1&page=$page" | jq -r '.[0].file_url // empty')
[[ -n $link ]] || fail "konachan.net didn't answer"
ext="${link##*.}"
downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper.$ext"
currentWallpaperPath=$(jq -r '.background.wallpaperPath' "${XDG_CONFIG_HOME:-$HOME/.config}/ninomae-shell/config.json")
# Use the other name when the current wallpaper is the last random one, so the switch really changes something
[[ $downloadPath == "${currentWallpaperPath/#\~\//$HOME/}" ]] && downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper-1.$ext"
curl -sf --max-time 120 "$link" -o "$downloadPath.part" && mv -f "$downloadPath.part" "$downloadPath" \
    || { rm -f "$downloadPath.part"; fail "The download failed"; }
"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"
