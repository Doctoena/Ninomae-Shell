#!/usr/bin/env bash
# Rebuilds Ninomae.Blobs when the installed plugin no longer matches the system's Qt or its own
# sources. Without this, a Qt update leaves a stale plugin and the shell quietly falls back to plain
# drawers. Run at login and on shell restart (hypr/hyprland/execs.lua, keybinds.lua); it's a no-op
# (two rpm queries and a hash) when the plugin is current.
#   ensure-built.sh           rebuild if needed, then offer to restart the shell
#   ensure-built.sh --stamp   print what the plugin is built against (build.sh saves this)
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dest="$HOME/.local/lib/qt6/qml/Ninomae/Blobs"
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
log="$cache/ninomae-blobs-build.log"
qs_config=Ninomae

# Exact Qt package builds (a Fedora rebuild of the same version can still change what the plugin
# links against) plus a hash of the sources, with relative paths so moving the dotfiles doesn't count
stamp() {
    rpm -q qt6-qtbase qt6-qtdeclarative
    (cd "$here" && find CMakeLists.txt src -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum)
}
if [[ ${1:-} == --stamp ]]; then stamp; exit; fi

notify() { notify-send -a "Ninomae" -i applications-development "$@" 2>/dev/null || true; }

want="$(stamp)"
[[ -f $dest/libninomae-blobs.so && "$(cat "$dest/.built-against" 2>/dev/null)" == "$want" ]] && exit 0

# Login and a shell restart can both start this; only one builds
mkdir -p "$cache"
exec 9>"$cache/ninomae-blobs-build.lock"
flock -n 9 || exit 0

if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null || ! rpm -q qt6-qtshadertools-devel >/dev/null 2>&1; then
    # Warn once per Qt version, not every login
    warned="$cache/ninomae-blobs-missing-deps"
    if [[ "$(cat "$warned" 2>/dev/null)" != "$want" ]]; then
        notify "Gooey drawers need rebuilding" \
            "Build tools are missing. Install them with: sudo dnf install cmake ninja-build qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtshadertools-devel"
        printf '%s\n' "$want" >"$warned"
    fi
    exit 1
fi

if ! nice -n 10 "$here/build.sh" >"$log" 2>&1; then
    notify -u critical "Gooey drawer plugin failed to build" "The shell uses plain drawers for now. Log: $log"
    exit 1
fi

# A running shell keeps the old plugin loaded; it picks up the new build when it restarts
pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null || exit 0
action="$(timeout 10m notify-send -a "Ninomae" -i applications-development --wait \
    --action=restart="Restart shell" \
    "Gooey drawers rebuilt" "Qt or the plugin changed. Restart the shell to use the new build." 2>/dev/null || true)"
if [[ $action == restart ]]; then
    "$HOME/.config/hypr/hyprland/scripts/restart_shell.sh" "$qs_config"
fi
