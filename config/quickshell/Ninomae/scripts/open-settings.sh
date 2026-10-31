#!/usr/bin/env bash
# Opens Ninomae Settings, optionally on a page (e.g. `open-settings.sh keybinds`).
# If it's already open, that window comes forward and switches page instead: a second `qs -p`
# instance would just exit (qs refuses duplicates), so the launch looked like it did nothing.
settings="$(realpath "$(dirname "$(realpath "$0")")/../settings.qml")" # Normalised: qs finds instances by path
page="${1:-}"
qs -p "$settings" ipc call settings open "$page" >/dev/null 2>&1 \
    || NINOMAE_SETTINGS_PAGE="$page" exec qs -p "$settings"
