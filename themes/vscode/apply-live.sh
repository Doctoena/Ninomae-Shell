#!/usr/bin/env bash
# VS Code only reads a colour theme's file when the theme loads, so an open window kept its old colours
# after a wallpaper change. It does apply settings.json live, so this copies the Ninomae theme's colours
# into settings.json as overrides scoped to "[Ninomae]" (ignored with any other theme). Run by matugen.
THEME="$(dirname "$(readlink -f "$0")")/ninomae-theme/themes/ninomae-color-theme.json"
[[ -f "$THEME" ]] || exit 0
for settings in "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json" "${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/settings.json"; do
    [[ -f "$settings" ]] || continue
    python3 - "$THEME" "$settings" <<'PY'
import json, os, sys, tempfile
theme_path, settings_path = sys.argv[1], sys.argv[2]
theme = json.load(open(theme_path))
try:
    settings = json.load(open(settings_path))
except ValueError:
    sys.exit(0)  # Has comments or isn't plain JSON: leave the user's file alone
key = "[" + theme.get("name", "Ninomae") + "]"
settings.setdefault("workbench.colorCustomizations", {})[key] = theme.get("colors", {})
settings.setdefault("editor.tokenColorCustomizations", {})[key] = {"textMateRules": theme.get("tokenColors", [])}
if theme.get("semanticTokenColors"):
    settings.setdefault("editor.semanticTokenColorCustomizations", {})[key] = {"enabled": True, "rules": theme["semanticTokenColors"]}
# Write atomically so VS Code never reads a half-written file
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(settings_path), suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(settings, f, indent=4)
    f.write("\n")
os.replace(tmp, settings_path)
PY
done
exit 0
