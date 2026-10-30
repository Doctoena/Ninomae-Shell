#!/usr/bin/env bash
# Sets up the Steam theme: Millennium (Steam client patcher) + the Material-Theme Millennium theme,
# with its colours coming from matugen (see apply-theme.sh). Safe to re-run: each step is skipped
# when it's already done. Run as your user; Millennium's own installer asks for sudo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEAM="$HOME/.local/share/Steam"
THEME_DIR="$STEAM/millennium/themes/Material-Theme" # Folder name matters: the theme loads its colours from /skins/Material-Theme/
MILLENNIUM_CONFIG="$HOME/.config/millennium/config.json"

ok()   { printf '  \e[32m✓\e[0m %s\n' "$*"; }
warn() { printf '  \e[33m!\e[0m %s\n' "$*"; }

NOTIF_ID="me.tysmith.steam-native-notifications"
PLUGINS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/millennium/plugins"
NOTIF_PLUGIN="$PLUGINS_DIR/$NOTIF_ID.star"
NOTIF_PLUGIN_URL="https://github.com/tyvsmith/steam-native-notifications/releases/download/latest/$NOTIF_ID.star"

# Downloads the plugin to $NOTIF_PLUGIN.part (removed again if the download fails)
download_plugin() {
    mkdir -p "$PLUGINS_DIR"
    curl -fsSL -o "$NOTIF_PLUGIN.part" "$NOTIF_PLUGIN_URL" || { rm -f "$NOTIF_PLUGIN.part"; return 1; }
}

# --update-plugin: only refresh the notifications plugin (a rolling pre-release), without closing Steam.
# Exit 0 = already the latest, 10 = updated (Steam needs a restart to load it), 1 = download failed
if [[ ${1:-} == --update-plugin ]]; then
    download_plugin || { warn "Couldn't download the notifications plugin"; exit 1; }
    if [[ -f $NOTIF_PLUGIN ]] && cmp -s "$NOTIF_PLUGIN.part" "$NOTIF_PLUGIN"; then
        rm -f "$NOTIF_PLUGIN.part"; ok "Notifications plugin is already the latest"; exit 0
    fi
    mv "$NOTIF_PLUGIN.part" "$NOTIF_PLUGIN"; ok "Notifications plugin updated"; exit 10
fi

# Steam unpacks its client (ubuntu12_32/64) on first launch; Millennium hooks into those folders
if [[ ! -d "$HOME/.steam/steam/ubuntu12_64" ]]; then
    warn "Steam hasn't been opened yet. Open it once (and sign in), close it, then run: $0"
    exit 0
fi

# Millennium can only be installed, and its config only edited, while Steam is closed
if pgrep -x steam >/dev/null; then
    echo "  Closing Steam…"
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 30); do pgrep -x steam >/dev/null || break; sleep 1; done
    pgrep -x steam >/dev/null && { warn "Steam is still running; close it and run $0 again"; exit 1; }
fi

# 1. Millennium
if [[ -d /usr/lib/millennium && -L "$HOME/.steam/steam/ubuntu12_64/libXtst.so.6" ]]; then
    ok "Millennium already installed"
else
    curl -fsSL "https://steambrew.app/install.sh" | bash
    ok "Millennium installed"
fi

# 2. Material-Theme (what Millennium's theme store would download)
if [[ -f "$THEME_DIR/skin.json" ]]; then
    ok "Material-Theme already installed"
else
    mkdir -p "$(dirname "$THEME_DIR")"
    git clone --quiet --depth 1 https://github.com/kuska1/Material-Theme.git "$THEME_DIR"
    ok "Material-Theme downloaded"
fi

# 3. Steam Native Notifications plugin: Steam's own pop-ups (messages, invites, achievements…) are sent
#    to the desktop notification service instead, so the shell shows them. Rolling pre-release from
#    https://github.com/tyvsmith/steam-native-notifications
if [[ -f "$NOTIF_PLUGIN" ]]; then
    ok "Steam notifications plugin already installed"
elif download_plugin; then
    mv "$NOTIF_PLUGIN.part" "$NOTIF_PLUGIN"
    ok "Steam notifications plugin downloaded"
else
    warn "Couldn't download the Steam notifications plugin; Steam keeps its own pop-ups"
fi

# 4. Select the theme (and enable the plugin), with the saved options (Color: Matugen, font, shapes, …) from millennium-theme.json
mkdir -p "$(dirname "$MILLENNIUM_CONFIG")"
python3 - "$MILLENNIUM_CONFIG" "$HERE/millennium-theme.json" "$NOTIF_PLUGIN" "$NOTIF_ID" <<'PY'
import json, sys, os
config_path, saved_path, notif_plugin, notif_id = sys.argv[1:5]
config = {}
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)
with open(saved_path) as f:
    saved = json.load(f)
themes = config.setdefault("themes", {})
themes["activeTheme"] = saved["activeTheme"]
themes.setdefault("conditions", {})["Material-Theme"] = saved["conditions"]
if saved.get("themeColors"):
    themes.setdefault("themeColors", {})["Material-Theme"] = saved["themeColors"]
themes.setdefault("allowedStyles", True)
themes.setdefault("allowedScripts", True) # The Matugen colour mode is a script
# Turn the notifications plugin on (what the switch in Settings → Millennium → Plugins saves)
if os.path.exists(notif_plugin):
    plugins = config.setdefault("plugins", {})
    enabled = plugins.setdefault("enabledPlugins", [])
    if notif_id not in enabled:
        enabled.append(notif_id)
    # In a game, only the shell's notifications: Steam's overlay toasts off (the plugin's "In game:
    # System only"). Only a default, a choice made later in the plugin's settings is kept
    plugins.setdefault(notif_id, {}).setdefault("config", {}).setdefault("showSteamInGame", False)
# Written beside it and swapped in, so a failed write can't leave Millennium a broken config
with open(config_path + ".tmp", "w") as f:
    json.dump(config, f, indent=4)
os.replace(config_path + ".tmp", config_path)
PY
ok "Material-Theme selected (Color: Matugen)"
[[ -f "$NOTIF_PLUGIN" ]] && ok "Steam notifications plugin enabled (Steam's pop-ups show in the shell, also in games)"

# 5. Current wallpaper colours
"$HERE/apply-theme.sh"
[[ -f "$HERE/matugen.css" ]] && ok "Colours copied" || warn "No colours yet; they're copied on the next wallpaper change"
