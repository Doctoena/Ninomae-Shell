#!/usr/bin/env bash
# Copies the Ninomae Zen theme into every Zen profile (Flatpak and native), and keeps the live theme
# extension's colours current. Copies rather than symlinks because the Flatpak can't read ~/Ninomae-Shell.
# Run by matugen after it regenerates colours.
#
# Zen only reads userChrome.css at startup, so the colours also go to the Ninomae live theme extension
# (live-theme/), which sets them as the browser theme while Zen runs. It's loaded unpacked from a
# folder Zen can see (a proxy file in each profile points at it), so rewriting its colors.json there
# is all a colour change takes. Zen asks once, at its next start, whether to enable it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/chrome"
EXT_ID="ninomae-live-theme@ninomae"

# The palette as JSON for the extension: {"bg": "#14121c", "surface-2": …} from ninomae-colors.css
colors_json() {
    sed -n 's/^ *--nino-\([a-z0-9-]*\): *\(#[0-9a-fA-F]\{6\}\);.*/"\1": "\2"/p' "$SRC/ninomae-colors.css" |
        paste -sd, | sed 's/^/{/; s/$/}/'
}
# Immich's server (host[:port]) for chrome/immich.css.in, or "": from the keyring, where Settings → Games
# keeps its URL, so the address isn't in the dotfiles. The keyring can be locked when this runs (matugen
# at login): then the last one found, kept in local state (also outside the dotfiles)
immich_host() {
    local cache="${XDG_STATE_HOME:-$HOME/.local/state}/ninomae-shell/immich-host"
    local unlocked="$HERE/../../config/quickshell/Ninomae/scripts/keyring/is_unlocked.sh"
    if "$unlocked" 2>/dev/null; then
        local host
        host=$(secret-tool lookup application ninomae-shell 2>/dev/null | python3 -c '
import json, re, sys, urllib.parse
try:
    url = json.load(sys.stdin).get("gameLauncher", {}).get("immichUrl", "").strip()
except ValueError:
    sys.exit()
host = urllib.parse.urlsplit(url if "//" in url else "https://" + url).netloc if url else ""
print(host if re.fullmatch(r"[A-Za-z0-9.:-]+", host) else "")  # It goes inside a CSS string
' 2>/dev/null) || host=""
        mkdir -p "$(dirname "$cache")"
        if [ -n "$host" ]; then printf '%s\n' "$host" > "$cache"; else rm -f "$cache"; fi
    fi
    [ -f "$cache" ] && head -1 "$cache"
    return 0
}
IMMICH_HOST="$(immich_host)"

# Adds a pref to a profile's user.js unless it already sets it
add_pref() {
    grep -qs "\"$2\"" "$1/user.js" || echo "user_pref(\"$2\", $3);" >> "$1/user.js"
}

for root in "$HOME/.var/app/app.zen_browser.zen/.zen" "$HOME/.zen"; do
    [ -f "$root/profiles.ini" ] || continue
    # The extension's folder, next to the profiles (for the Flatpak, inside the folder it can see)
    ext="$root/ninomae-live-theme"
    mkdir -p "$ext"
    cp -f "$HERE/live-theme/manifest.json" "$HERE/live-theme/background.js" "$ext/"
    if [ -f "$SRC/ninomae-colors.css" ]; then
        colors_json > "$ext/colors.json.tmp"
        mv -f "$ext/colors.json.tmp" "$ext/colors.json" # Whole, never half-written
    fi
    while IFS= read -r rel; do
        prof="$root/$rel"
        [ -d "$prof" ] || continue
        mkdir -p "$prof/chrome" "$prof/extensions"
        cp -f "$SRC/userChrome.css" "$SRC/userContent.css" "$prof/chrome/"
        # Immich's styles, for your server only (the host is checked to be plain [A-Za-z0-9.:-] above)
        [ -n "$IMMICH_HOST" ] && sed "s/@IMMICH_HOST@/$IMMICH_HOST/g" "$SRC/immich.css.in" >> "$prof/chrome/userContent.css"
        [ -f "$SRC/ninomae-colors.css" ] && cp -f "$SRC/ninomae-colors.css" "$prof/chrome/"
        # Proxy file: the extension is loaded from the folder it names
        printf '%s\n' "$ext" > "$prof/extensions/$EXT_ID"
        # userChrome.css is only read with this on
        add_pref "$prof" toolkit.legacyUserProfileCustomizations.stylesheets true
        # The live theme extension isn't signed; Zen allows that with this off
        add_pref "$prof" xpinstall.signatures.required false
        # Zen ignores browser themes (the extension's included) unless this is off
        add_pref "$prof" zen.theme.disable-lightweight false
    done < <(sed -n 's/^Path=//p' "$root/profiles.ini")
done
