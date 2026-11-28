#!/usr/bin/env bash
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
COLORS_FILE="$XDG_STATE_HOME/quickshell/user/generated/material_colors.scss"
KVANTUM_HOME="$XDG_CONFIG_HOME/Kvantum"
KVANTUM_CONFIG="$KVANTUM_HOME/kvantum.kvconfig"

if [[ ! -s "$COLORS_FILE" || ! -f "$KVANTUM_CONFIG" ]]; then
    echo "Qt theme inputs are missing; skipping Kvantum update" >&2
    exit 0
fi

color() {
    awk -F': ' -v key="\$$1" '$1 == key { gsub(";", "", $2); print $2; exit }' "$COLORS_FILE"
}

theme_name=$(awk -F= '$1 == "theme" { print $2; exit }' "$KVANTUM_CONFIG")
theme_name=${theme_name:-MaterialAdw}
theme_dir="$KVANTUM_HOME/$theme_name"
theme_file="$theme_dir/$theme_name.kvconfig"

if [[ ! -f "$theme_file" ]]; then
    mkdir -p "$theme_dir"
    cp /usr/share/Kvantum/KvantumAlt/KvantumAlt.kvconfig "$theme_file"
    cp /usr/share/Kvantum/KvantumAlt/KvantumAlt.svg "$theme_dir/$theme_name.svg"
fi

background=$(color background)
surface=$(color surface)
surface_container=$(color surfaceContainer)
surface_bright=$(color surfaceBright)
surface_high=$(color surfaceContainerHigh)
surface_lowest=$(color surfaceContainerLowest)
primary=$(color primary)
on_surface=$(color onSurface)
on_primary=$(color onPrimary)
tertiary=$(color tertiary)

replace_color() {
    local key="$1"
    local value="$2"
    [[ -n "$value" ]] || return 0
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$theme_file"
}

replace_color 'window.color' "$background"
replace_color 'base.color' "$surface"
replace_color 'alt.base.color' "$surface_container"
replace_color 'button.color' "$surface_container"
replace_color 'light.color' "$surface_bright"
replace_color 'mid.light.color' "$surface_high"
replace_color 'dark.color' "$surface_lowest"
replace_color 'mid.color' "$surface_high"
replace_color 'highlight.color' "$primary"
replace_color 'inactive.highlight.color' "$primary"
replace_color 'text.color' "$on_surface"
replace_color 'window.text.color' "$on_surface"
replace_color 'button.text.color' "$on_surface"
replace_color 'disabled.text.color' "$on_surface"
replace_color 'tooltip.text.color' "$on_surface"
replace_color 'highlight.text.color' "$on_primary"
replace_color 'link.color' "$tertiary"
replace_color 'link.visited.color' "$tertiary"
replace_color 'progress.indicator.text.color' "$on_surface"
replace_color 'text.normal.color' "$on_surface"
replace_color 'text.focus.color' "$on_surface"
replace_color 'text.press.color' "$on_primary"
replace_color 'text.toggle.color' "$on_primary"

if command -v kvantummanager >/dev/null 2>&1; then
    kvantummanager --set "$theme_name" >/dev/null 2>&1 || true
fi
