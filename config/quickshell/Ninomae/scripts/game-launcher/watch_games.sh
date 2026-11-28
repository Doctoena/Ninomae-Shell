#!/usr/bin/env bash
# File watcher for game launcher auto-refresh
# Watches Steam manifests and the Lutris database/configs for changes.
# Prints one inotify event per line ("dir/ EVENT file"); GameLauncherService debounces them.
#
# Watches are NOT recursive: everything we care about sits directly in these folders,
# and a recursive watch on steamapps/ would cover every installed game's files.
# `exec` makes inotifywait the process Quickshell started, so it dies with the shell.

set -euo pipefail

# Find Steam directory (try common locations)
STEAM_DIR=""
for potential_dir in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam"; do
    if [[ -d "$potential_dir/steamapps" ]]; then
        STEAM_DIR="$potential_dir"
        break
    fi
done

WATCH_PATHS=()

# Steam library folders (manifests live directly in each steamapps/)
if [[ -n "$STEAM_DIR" ]]; then
    WATCH_PATHS+=("$STEAM_DIR/steamapps")
    if [[ -f "$STEAM_DIR/steamapps/libraryfolders.vdf" ]]; then
        while IFS= read -r lib_path; do
            [[ -n "$lib_path" ]] && [[ -d "$lib_path/steamapps" ]] && [[ "$lib_path/steamapps" != "$STEAM_DIR/steamapps" ]] \
                && WATCH_PATHS+=("$lib_path/steamapps")
        done < <(awk -F'"' '/"path"/{print $4}' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null)
    fi
fi

# Lutris database and game configs
for d in "$HOME/.local/share/lutris" "$HOME/.local/share/lutris/games" "$HOME/.config/lutris/games"; do
    [[ -d "$d" ]] && WATCH_PATHS+=("$d")
done

if [[ ${#WATCH_PATHS[@]} -eq 0 ]]; then
    echo "NO_PATHS" >&2
    exit 1
fi

if ! command -v inotifywait &>/dev/null; then
    echo "MISSING_INOTIFYWAIT" >&2
    exit 1
fi

exec inotifywait -m -q \
    --include '(appmanifest_[0-9]+\.acf|pga\.db|\.yml|libraryfolders\.vdf)$' \
    -e create -e modify -e delete -e moved_to -e moved_from \
    "${WATCH_PATHS[@]}"
