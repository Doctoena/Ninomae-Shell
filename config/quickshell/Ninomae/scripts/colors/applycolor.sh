#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="Ninomae"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 # Below 100 makes every terminal transparent
mkdir -p "$STATE_DIR"/user/generated
cd "$CONFIG_DIR" || exit

# material_colors.scss lines look like "$primary: #CFBDFE;"
colorlist=() colorvalues=()
while IFS=': ;' read -r name value _; do
  [[ $name == \$* && $value == \#* ]] || continue
  colorlist+=("$name") colorvalues+=("${value#\#}")
done <"$STATE_DIR/user/generated/material_colors.scss"

apply_term() {
  local template="$SCRIPT_DIR/terminal/sequences.txt" out="$STATE_DIR/user/generated/terminal/sequences.txt"
  if [ ! -f "$template" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  mkdir -p "$(dirname "$out")"
  # One sed for every colour (it used to be one sed -i per colour), written beside the result and then
  # moved over it, so a new shell (fish prints this file at startup) never reads it half-written
  local exprs=() i
  for i in "${!colorlist[@]}"; do
    exprs+=(-e "s/${colorlist[$i]} #/${colorvalues[$i]}/g")
  done
  sed "${exprs[@]}" -e "s/\$alpha/$term_alpha/g" "$template" >"$out.tmp" && mv -f "$out.tmp" "$out" || return

  # The same palette as a kitty config (kitty.conf includes it), so kitty windows that never start fish
  # (btop from app search, kitty -e) get it too. Same colours as the sequences above
  local -A c
  for i in "${!colorlist[@]}"; do c[${colorlist[$i]#\$}]=${colorvalues[$i]}; done
  local kitty_out="$(dirname "$out")/kitty-colors.conf"
  {
    for i in {0..15}; do echo "color$i #${c[term$i]}"; done
    echo "foreground #${c[termfg]}"
    echo "background #${c[termbg]}"
    echo "cursor #${c[term15]}"
    echo "selection_foreground #${c[termbg]}"
    echo "selection_background #${c[term7]}"
  } >"$kitty_out.tmp" && mv -f "$kitty_out.tmp" "$kitty_out"
  pkill -USR1 -x kitty # Running kitty instances reload it, so new windows in them (kitty -1) match too

  local file
  for file in /dev/pts/[0-9]*; do
    [[ -w $file ]] && { cat "$out" >"$file" & } 2>/dev/null
  done
}

apply_qt() {
  sh "$CONFIG_DIR/scripts/kvantum/materialQT.sh" # Generates the Kvantum theme colours from material_colors.scss
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/ninomae-shell/config.json"
if [ -f "$CONFIG_FILE" ]; then
  read -r enable_terminal enable_qt_apps < <(jq -r '.appearance.wallpaperTheming | "\(.enableTerminal) \(.enableQtApps)"' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

if [ "${enable_qt_apps:-true}" = "true" ]; then
  apply_qt &
fi

# YouTube Music theme
"$SCRIPT_DIR/generate_youtube_music_theme.sh" &

# Icons: the folders (Ninomae-Icons-accent) and GNOME's accent-color follow the new accent
python3 -I "$SCRIPT_DIR/recolor_icons.py" &
