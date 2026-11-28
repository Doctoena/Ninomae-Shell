#!/usr/bin/env bash
# YouTube Music (Pear Desktop, from Terra): a launcher named YouTube Music with the Wayland flags and the themed
# icon, and the shell's colour theme (scripts/colors/generate_youtube_music_theme.sh, which also points the app at
# it). The app makes its settings file the first time it's opened: before that the theme is written but can't be
# selected yet (exit 3), and themes/apply-when-ready.sh finishes it once the app has been opened and closed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(cd "$HERE/../.." && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/YouTube Music/config.json" # Pear kept the old app's settings folder

command -v pear-desktop >/dev/null || { echo "Pear Desktop isn't installed (sudo dnf install pear-desktop)"; exit 1; }
mkdir -p "$APPS"
install -m644 "$HERE/com.github.th-ch.youtube-music.desktop" "$APPS/"
update-desktop-database "$APPS" 2>/dev/null || true
bash "$DOTFILES/config/quickshell/Ninomae/scripts/colors/generate_youtube_music_theme.sh" >/dev/null
[[ -f $CONFIG ]] || exit 3 # Not opened yet
grep -q 'youtube-music-theme\.css' "$CONFIG" # Selected
