#!/usr/bin/env bash
# Themes Zen and Steam once they're ready, so nobody has to run their scripts by hand. Both need the app to
# have been opened once first, which a fresh install hasn't done yet.
#   Zen: as soon as it has a profile, the theme is copied in (Zen shows it from its next start)
#   Steam: once it's been opened and is closed again, a notification offers to theme it. Millennium's
#   installer asks for your password, so it runs in a terminal
# Started at login (hypr/hyprland/execs.lua). Looks every 2 minutes while something is left to do and exits
# when nothing is: both themed, not installed, or the Steam offer answered for this session.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ninomae-shell"
DECLINED="$STATE/steam-theme-declined" # "Don't ask again"
ZEN_ROOTS=("$HOME/.var/app/app.zen_browser.zen/.zen" "$HOME/.zen")

mkdir -p "$STATE"
exec 9>"$STATE/apply-when-ready.lock"
flock -n 9 || exit 0 # Already running

zen_installed() { [[ -d $HOME/.var/app/app.zen_browser.zen ]] || command -v zen-browser >/dev/null || command -v zen >/dev/null; }
zen_unthemed() { # A Zen profile without the theme's files
    local root rel
    for root in "${ZEN_ROOTS[@]}"; do
        [[ -f $root/profiles.ini ]] || continue
        while IFS= read -r rel; do
            [[ -d $root/$rel && ! -f $root/$rel/chrome/userChrome.css ]] && return 0
        done < <(sed -n 's/^Path=//p' "$root/profiles.ini")
    done
    return 1
}
zen_opened() { [[ -f ${ZEN_ROOTS[0]}/profiles.ini || -f ${ZEN_ROOTS[1]}/profiles.ini ]]; }

steam_themed() { # The same checks themes/steam/install-theme.sh skips its steps on
    [[ -d /usr/lib/millennium && -L $HOME/.steam/steam/ubuntu12_64/libXtst.so.6 \
        && -f $HOME/.local/share/Steam/millennium/themes/Material-Theme/skin.json ]]
}
steam_pending() { command -v steam >/dev/null && ! steam_themed && [[ ! -f $DECLINED ]]; }
steam_ready() { [[ -d $HOME/.steam/steam/ubuntu12_64 ]] && ! pgrep -x steam >/dev/null; }

steam_offer() {
    local action
    action="$(timeout 10m notify-send -a "Ninomae" -i steam --wait \
        --action=theme="Theme Steam" --action=never="Don't ask again" \
        "Theme Steam to match?" "Installs Millennium and the Material theme, coloured from your wallpaper. It asks for your password in a terminal." \
        2>/dev/null || true)"
    case $action in
        theme) kitty -T "Theme Steam" bash -c '"$1"; echo; read -rsn1 -p "Done. Press any key to close."' \
                   theme-steam "$HERE/steam/install-theme.sh" ;;
        never) touch "$DECLINED" ;;
    esac
}

steam_asked=0 zen_failed=0
while true; do
    if (( ! zen_failed )) && zen_installed && zen_unthemed; then
        if "$HERE/zen/apply-theme.sh" >/dev/null 2>&1; then
            notify-send -a "Ninomae" -i applications-internet "Zen themed" "It matches your wallpaper from the next time you open it." 2>/dev/null
        else zen_failed=1; fi # Not again this session: themes/zen/apply-theme.sh by hand shows why
    fi
    if (( ! steam_asked )) && steam_pending && steam_ready; then
        steam_offer
        steam_asked=1 # Once a session: closing the notification means "not now"
    fi
    # Anything left that could still happen this session?
    zen_left=0; (( ! zen_failed )) && zen_installed && { ! zen_opened || zen_unthemed; } && zen_left=1
    steam_left=0; (( ! steam_asked )) && steam_pending && steam_left=1
    (( zen_left || steam_left )) || exit 0
    sleep 120
done
