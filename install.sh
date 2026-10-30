#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Ninomae dotfiles installer (Fedora)
#
#  Usage:  ./install.sh [mode] [options]
#
#  Modes
#    (none)          Install: pick what to set up from a checklist
#    --update        Update an existing install: latest files, missing packages,
#                    new links, Python helpers, drawer plugin, Steam plugin
#    --uninstall     Remove the config links and put back what they replaced
#                    (packages and system themes stay)
#
#  Options
#    --dry-run       Show what would happen, change nothing
#    -y, --yes       No questions: use the defaults (or the --no-* choices)
#    --no-packages   Skip repositories and packages
#    --no-sddm       Skip the login screen theme
#    --no-boot       Skip the boot splash (off by default anyway)
#    --boot          Include the boot splash
#    --no-steam      Skip the Steam theme
#    --no-shell      Don't make fish the login shell (uninstall: don't offer bash)
#    --keyboard K    Keyboard layout for the desktop and login screen: dvorak (default)
#                    or qwerty
#    --only a,b      Only these components (install mode): packages, codecs, configs,
#                    shell, apps, steam, sddm, boot, fish
#    --skip a,b      Everything except these components
#    -h, --help      Show this help
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_HOME="$HOME/Ninomae-Shell" # Where the folder has to live (matugen's config points here)
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
ORIG_ARGS=("$@") # Kept for re-running from $DOTFILES_HOME after the folder is moved there

MODE=install DRY_RUN=0 ASSUME_YES=0 KEYBOARD=
declare -A FORCE=() # Component choices from --no-*/--boot flags: key → on|off

usage() { # The comment header at the top of this file
    awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ? ?/, ""); print }' "${BASH_SOURCE[0]}" | sed '1d;$d'
}
[[ " $* " == *" -h "* || " $* " == *" --help "* ]] && { usage; exit 0; } # Before the library starts a log

source "$DOTFILES/setup/lib.sh"
source "$DOTFILES/setup/components.sh"

while (( $# )); do
    case "$1" in
        --update) MODE=update ;;
        --uninstall) MODE=uninstall ;;
        --dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --no-packages) FORCE[packages]=off ;;
        --no-sddm) FORCE[sddm]=off ;;
        --no-boot) FORCE[boot]=off ;;
        --boot) FORCE[boot]=on ;;
        --no-steam) FORCE[steam]=off ;;
        --no-shell) FORCE[fish]=off ;;
        --keyboard)
            [[ ${2:-} == dvorak || ${2:-} == qwerty ]] || die "--keyboard needs dvorak or qwerty"
            KEYBOARD=$2; shift ;;
        --only|--skip)
            [[ $# -ge 2 ]] || die "$1 needs a list, e.g. $1 configs,apps"
            for k in ${2//,/ }; do
                [[ " ${COMPONENT_KEYS[*]} " == *" $k "* ]] || die "Unknown component: $k (one of: ${COMPONENT_KEYS[*]})"
            done
            for key in "${COMPONENT_KEYS[@]}"; do
                if [[ ",$2," == *",$key,"* ]]; then [[ $1 == --only ]] && FORCE[$key]=on || FORCE[$key]=off
                elif [[ $1 == --only ]]; then FORCE[$key]=off; fi
            done
            shift ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
done
log "install.sh $MODE ${ORIG_ARGS[*]}"

# One run at a time: two at once would install packages and move configs over each other
exec 8>"$LOG_DIR/install.lock"
flock -n 8 || die "The installer is already running in another terminal."

# ── Welcome ─────────────────────────────────────────────────────────────────
screen_size() {
    if command -v hyprctl >/dev/null && hyprctl monitors -j >/dev/null 2>&1; then
        hyprctl monitors -j | python3 -c 'import json, sys; print(" · ".join("%dx%d" % (m["width"], m["height"]) for m in json.load(sys.stdin)))' 2>/dev/null
    fi
}
fedora_version="$(rpm -E %fedora 2>/dev/null || echo '?')"
subtitle="Fedora $fedora_version · $USER"
size="$(screen_size)"; [[ -n $size ]] && subtitle+=" · $size"
case $MODE in
    install) banner "dotfiles installer" "$subtitle" ;;
    update) banner "update" "$subtitle" ;;
    uninstall) banner "uninstall" "$subtitle" ;;
esac
(( DRY_RUN )) && printf '%*s%sDry run: nothing will be changed%s\n' $(( (WIDTH - 32) / 2 + 2 )) "" "$c_warn" "$c_off"

# ── Checks ──────────────────────────────────────────────────────────────────
section "Checking your system"
(( EUID != 0 )) || die "Run this as your normal user, not root (sudo is used where needed)."
grep -q '^ID=fedora' /etc/os-release 2>/dev/null || die "This installer is written for Fedora."
command -v dnf >/dev/null || die "dnf not found."
ok "Fedora $fedora_version, user $USER"
if (( ! INTERACTIVE && ! ASSUME_YES )); then die "Not running in a terminal: add -y to install with the defaults."; fi
if [[ $MODE == install ]]; then
    free_gb=$(( $(df --output=avail -k "$HOME" | tail -1) / 1024 / 1024 ))
    if (( free_gb < 4 )); then warn "Only ${free_gb} GB free in your home; the install needs about 4 GB"
    else ok "${free_gb} GB free"; fi
    if curl -fsS --max-time 5 -o /dev/null https://repos.fyralabs.com 2>/dev/null; then ok "Online"
    else warn "Couldn't reach the package servers; package steps may fail"; fi
fi

# Some configs (matugen's output paths) refer to ~/Ninomae-Shell directly, so the script auto puts the files into that directory and symlinks them
if [[ $DOTFILES != "$DOTFILES_HOME" ]]; then
    [[ $MODE == install ]] || die "Run this from $DOTFILES_HOME (where the installed copy lives)."
    section "Putting Ninomae-Shell at $DOTFILES_HOME"
    [[ $DOTFILES_HOME == "$DOTFILES"/* ]] && die "Can't move $DOTFILES into a folder inside itself."
    if [[ -e $DOTFILES_HOME || -L $DOTFILES_HOME ]]; then
        confirm "$DOTFILES_HOME already exists. Move it to $BACKUP_DIR and use this copy?" \
            || die "Left $DOTFILES_HOME alone. Move or remove it, or run $DOTFILES_HOME/install.sh instead."
        run mkdir -p "$BACKUP_DIR" && run mv "$DOTFILES_HOME" "$BACKUP_DIR/Ninomae-Shell" \
            || die "Couldn't move the old $DOTFILES_HOME aside."
        warn "Previous $DOTFILES_HOME moved to $BACKUP_DIR/Ninomae-Shell"
    fi
    if [[ $DOTFILES == "$HOME"/* ]]; then run mv "$DOTFILES" "$DOTFILES_HOME" || die "Couldn't move the folder."; ok "Moved from $DOTFILES"
    else run cp -a "$DOTFILES" "$DOTFILES_HOME" || die "Couldn't copy the folder."; ok "Copied from $DOTFILES"; fi
    if (( DRY_RUN )); then warn "Dry run continues from $DOTFILES"
    else cd "$DOTFILES_HOME" && exec bash "$DOTFILES_HOME/install.sh" "${ORIG_ARGS[@]}"; fi
fi
ok "Ninomae-Shell at $DOTFILES"

# The nicer interface: offer gum (small, from Fedora's own repos) if it's missing
if (( INTERACTIVE && ! ASSUME_YES && ! DRY_RUN )) && [[ $MODE == install ]] && ! command -v gum >/dev/null; then
    if confirm "Install gum for the nicer installer menus? (small, from Fedora's repos)"; then
        sudo dnf install -y gum >>"$LOG" 2>&1 && ok "gum installed" || warn "Couldn't install gum; using plain menus"
    fi
fi

sudo_keepalive() { # Ask for the password once, and keep sudo alive for the rest of the run
    (( DRY_RUN )) && return 0
    sudo -v || die "sudo is required for the steps you picked."
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
}

# ─────────────────────────────────────────────────────────────────────────────
case $MODE in
install)
    # Pick what to set up (flags preset the checklist; -y takes it as is)
    items=()
    for c in "${COMPONENTS[@]}"; do
        label=${c%%|*} rest=${c#*|}; key=${rest%%|*} state=${rest#*|}
        [[ -n ${FORCE[$key]:-} ]] && state=${FORCE[$key]}
        items+=("$label|$key|$state")
    done
    mapfile -t chosen < <(choose_many "What should be set up?" "${items[@]}")
    (( ${#chosen[@]} )) || die "Nothing picked; nothing to do."

    # Keyboard layout: --keyboard, else ask (preselecting what's set now: Dvorak on a fresh copy)
    if [[ -z $KEYBOARD ]]; then
        KEYBOARD=$(choose_one "Keyboard layout? (desktop and login screen)" "$(keyboard_current)" \
            "US Dvorak|dvorak" "US QWERTY (regular)|qwerty") || die "Cancelled; nothing was changed."
    fi

    needs_sudo=0 plan=()
    for key in "${COMPONENT_KEYS[@]}"; do
        if [[ " ${chosen[*]} " == *" $key "* ]]; then
            plan+=("${c_acc}●${c_off} $(component_label "$key")")
            component_needs_sudo "$key" && needs_sudo=1
        else
            plan+=("${c_dim}○ $(component_label "$key")${c_off}")
        fi
    done
    plan+=("" "${c_acc}⌨${c_off} Keyboard: $(keyboard_name "$KEYBOARD")")
    plan+=("${c_dim}Anything replaced is backed up to ${BACKUP_DIR/#$HOME/\~}${c_off}")
    (( needs_sudo )) && plan+=("${c_dim}You'll be asked for your password once${c_off}")
    echo; box "The plan" "${plan[@]}"; echo
    confirm "Start?" || die "Cancelled; nothing was changed."
    (( needs_sudo )) && sudo_keepalive

    # Write the layout first: the configs and login screen steps both use it
    if [[ $KEYBOARD != "$(keyboard_current)" ]]; then
        keyboard_set "$KEYBOARD" && ok "Keyboard layout: $(keyboard_name "$KEYBOARD")" || warn "Couldn't set the keyboard layout"
    fi
    STEP_TOTAL=${#chosen[@]}
    for key in "${chosen[@]}"; do "comp_$key"; done
    report "Reboot (or log out) and pick the ${c_bold}Hyprland${c_off} session on the login screen" \
           "Re-run any time: ${c_bold}./install.sh${c_off} only changes what isn't set up yet" \
           "Keep up to date with ${c_bold}./install.sh --update${c_off}"
    ;;

update)
    confirm "Update everything?" || die "Cancelled; nothing was changed."
    # Only installing new packages, a hardware fix or a codec swap needs it
    [[ -n $(missing_packages) || -n $(old_quickshell) ]] || hardware_fixes_pending || { rpmfusion_free && codec_swaps_pending; } && sudo_keepalive
    steps=(update_files update_packages update_codecs comp_configs update_shell update_steam_plugin update_apps)
    STEP_TOTAL=${#steps[@]}
    for s in "${steps[@]}"; do "$s"; done
    report "Restart the shell to load everything new: ${c_bold}Super+Ctrl+R${c_off}"
    ;;

uninstall)
    keep_fish=0; [[ ${FORCE[fish]:-} == off ]] && keep_fish=1 # --no-shell
    echo; box "Uninstall will" \
        "• remove the config links that point into ${DOTFILES/#$HOME/\~}" \
        "• put back the files they replaced, from your newest backups" \
        "• offer to remove the Steam notifications plugin$( (( keep_fish )) || echo ' and switch back to bash')" \
        "" "${c_dim}Packages, the login screen and boot themes, and this folder stay${c_off}"
    echo
    confirm "Uninstall?" no || die "Cancelled; nothing was changed."
    STEP_TOTAL=$(( 3 - keep_fish ))
    uninstall_links; uninstall_steam_plugin
    (( keep_fish )) || uninstall_shell
    report "Log out to leave this desktop; the packages are still installed if you come back" \
           "Remove packages yourself if you like, e.g. ${c_bold}sudo dnf remove hyprland quickshell${c_off}"
    ;;
esac
