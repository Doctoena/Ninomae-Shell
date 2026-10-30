#!/usr/bin/env bash
# Sets up the Discord theme in Vesktop (Discord client with Vencord built in): copies the Ninomae
# theme (midnight, coloured by matugen) into Vesktop's themes folder and turns it on. Safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA="${XDG_CONFIG_HOME:-$HOME/.config}/vesktop"
SETTINGS="$DATA/settings/settings.json"

command -v vesktop >/dev/null || { echo "  Vesktop isn't installed; skipped"; exit 0; }
# Vesktop rewrites its settings on exit, so only edit them while it's closed
if pgrep -x vesktop >/dev/null || pgrep -f "/vesktop/vesktop" >/dev/null; then
    echo "  Close Vesktop first (tray icon → Quit), then run $0 again"; exit 1
fi

mkdir -p "$DATA/themes" "$(dirname "$SETTINGS")"
"$HERE/apply-theme.sh"
[[ -f "$DATA/themes/ninomae.theme.css" ]] || echo "  ! No colours yet; they're generated on the next wallpaper change"

python3 - "$SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
settings = json.load(open(path)) if os.path.exists(path) else {}
themes = settings.setdefault("enabledThemes", [])
if "ninomae.theme.css" not in themes:
    themes.append("ninomae.theme.css")
with open(path, "w") as f:
    json.dump(settings, f, indent=4)
PY
echo "  ✓ Ninomae theme enabled in Vesktop"
