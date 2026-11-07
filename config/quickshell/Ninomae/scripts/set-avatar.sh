#!/usr/bin/env bash
# Sets your picture: the lock screen's (~/.face) and your account's, which the login screen shows.
#   set-avatar.sh [image]   no image: asks for one with a file dialog
# The picture is cropped to the middle square and saved at 512 px. AccountsService takes it for the login
# screen (your own picture needs no password); without it, only the lock screen changes.
set -u
img="${1:-}"
if [[ -z $img ]]; then
    command -v zenity >/dev/null || { notify-send "Your picture" "Install zenity to pick a picture" -a "Ninomae"; exit 1; }
    # "Open File …": the file-dialogs window rule floats it
    img="$(zenity --file-selection --title='Open File · Your picture' --filename="$(xdg-user-dir PICTURES)/" \
        --file-filter='Pictures | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.avif' 2>/dev/null)" || exit 0
fi
[[ -f $img ]] || { notify-send "Your picture" "Couldn't open $img" -a "Ninomae"; exit 1; }

face="$HOME/.face"
tmp="$(mktemp --suffix=.png)"
trap 'rm -f "$tmp"' EXIT
# [0]: the first frame of a GIF. Cropped square from the middle, then 512 px
if ! magick "$img[0]" -auto-orient -gravity center -crop "%[fx:min(w,h)]x%[fx:min(w,h)]+0+0" +repage \
        -resize 512x512 "$tmp" 2>/dev/null; then
    notify-send "Your picture" "That file isn't a picture ImageMagick can read" -a "Ninomae"
    exit 1
fi
cp -f "$tmp" "$face"
ln -sfn .face "$HOME/.face.icon" # Where some login screens look

busctl --system call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
    org.freedesktop.Accounts.User SetIconFile s "$face" >/dev/null 2>&1 \
    || notify-send "Your picture" "Set for the lock screen. The login screen couldn't be updated" -a "Ninomae"
