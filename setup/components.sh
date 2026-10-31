# shellcheck shell=bash
# ─────────────────────────────────────────────────────────────────────────────
#  What the installer does, one function per component. Sourced by install.sh.
#  Each component prints its own lines and records how it went with `result`;
#  failures are reported rather than stopping the whole install.
# ─────────────────────────────────────────────────────────────────────────────

QS_CONFIG="Ninomae"
VENV="$HOME/.local/state/quickshell/.venv"
STEAM_PLUGIN="${XDG_DATA_HOME:-$HOME/.local/share}/millennium/plugins/me.tysmith.steam-native-notifications.star"

PACKAGES=(
    # Hyprland and its tools (COPR lionheartp/Hyprland, hypridle from Terra)
    hyprland hyprland-uwsm uwsm hyprland-guiutils hypridle hyprpicker hyprsunset
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal-gnome # gnome: Nautilus as the file picker
    # Quickshell (upstream 0.3+, COPR lionheartp/Hyprland) and its Qt runtime modules
    quickshell qt6-qtsvg qt6-qtpositioning qt6-qtwayland
    # Theming: wallpaper colours, GTK/Qt themes
    matugen adw-gtk3-theme qt6ct kvantum
    # Terminal, launcher, shell, and what the app keybinds open (Super+P files, Ctrl+Shift+Esc btop)
    kitty fuzzel fish lsd fastfetch nautilus btop
    # Steam and Vesktop (Discord with Vencord), both from Terra; themed in themes/steam and themes/discord
    steam vesktop
    # Gaming tools the game launcher's per-game "Launch options" can switch on
    gamemode mangohud gamescope
    # Gameplay clips (services/GameClips.qml): the replay recorder, from Terra; Qt Multimedia plays them in the
    # launcher's Clips page (ffmpeg-free, below, makes their thumbnails)
    gpu-screen-recorder qt6-qtmultimedia
    # Clipboard, screenshots, input
    wl-clipboard cliphist grim slurp swappy tesseract wtype
    # Audio, media, hardware (mpvpaper: video wallpapers, it brings mpv's library; nm-connection-editor and
    # blueman: the Wi-Fi and Bluetooth menus' Settings buttons)
    wireplumber pavucontrol playerctl cava mpvpaper ffmpeg-free brightnessctl
    NetworkManager nm-connection-editor bluez blueman upower power-profiles-daemon
    # Compressed swap in RAM, Fedora's default (removing the KDE group took it out once)
    zram-generator-defaults
    # Desktop services and helpers used by the shell (gnome-keyring-pam: login unlocks the keyring)
    gnome-keyring gnome-keyring-pam libsecret geoclue2 libnotify qalculate ImageMagick
    jq curl psmisc xdg-utils inotify-tools zenity
    # sqlite: the game launcher reads Lutris's games (pga.db) with its command line; without it they go undetected
    sqlite
    # Emoji (the shell's emoji picker, notifications, game news); without it they show as boxes
    google-noto-color-emoji-fonts
    # Login screen (sddm-wayland-plasma is swapped in below)
    sddm
    # Building the Ninomae.Blobs plugin and the shell's Python helpers
    git-core cmake ninja-build gcc-c++ qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtshadertools-devel
    python3
    # Settings → Keybinds names keys as your keyboard layout prints them (scripts/keyboard/xkb_layouts.py)
    xkbcomp
    # This installer's interface
    gum
)

# home path (relative to $HOME)  →  path inside this repo
LINKS=(
    ".config/hypr|config/hypr"
    ".config/quickshell|config/quickshell"
    ".config/ninomae-shell|config/ninomae-shell"
    ".config/matugen|config/matugen"
    ".config/kitty|config/kitty"
    ".config/fish|config/fish"
    ".config/fastfetch|config/fastfetch"
    ".config/lsd|config/lsd"
    ".config/btop|config/btop"
    ".config/fuzzel|config/fuzzel"
    ".config/qt6ct|config/qt6ct"
    ".config/Kvantum|config/Kvantum"
    ".config/gtk-3.0|config/gtk-3.0"
    ".config/gtk-4.0|config/gtk-4.0"
    ".config/xdg-desktop-portal|config/xdg-desktop-portal"
    ".config/systemd/user/hyprland-session.target|config/systemd/user/hyprland-session.target" # Lets the portal start (Fedora 44+)
    ".icons|assets/icons"
    ".local/share/icons/Ninomae-Icons-purple|assets/icons/Ninomae-Icons-purple" # KDE/Qt icon lookup skips ~/.icons
    ".local/share/fonts|assets/fonts"
    "Pictures/Wallpapers|assets/wallpapers"
)

# Each machine's own copy of a file the repo ships a default for: "yours|default". Made once from the default,
# then git ignores it: the shell's settings, and configs the apps rewrite themselves (so a change in btop or
# Kvantum Manager never shows up in git, or stops `ninomae update` from pulling)
LOCAL_COPIES=(
    "config/ninomae-shell/config.json|config/ninomae-shell/config.default.json"
    "config/btop/btop.conf|config/btop/btop.default.conf"
    "config/qt6ct/qt6ct.conf|config/qt6ct/qt6ct.default.conf"
    "config/Kvantum/kvantum.kvconfig|config/Kvantum/kvantum.default.kvconfig"
    "config/gtk-3.0/settings.ini|config/gtk-3.0/settings.default.ini"
    "config/gtk-4.0/settings.ini|config/gtk-4.0/settings.default.ini"
    "config/hypr/hyprland/keyboard.lua|config/hypr/hyprland/keyboard.default.lua"
)
# Yours, but in git once: kept across the pull that stops tracking them (the LOCAL_COPIES too)
KEEP_ACROSS_PULL=(config/gtk-3.0/bookmarks)

# The checklist: "label|key|on-by-default". Labels mustn't contain commas
COMPONENTS=(
    "Packages and repositories — Hyprland · the shell · apps (needs sudo)|packages|on"
    "Multimedia codecs — RPM Fusion · full ffmpeg · video drivers (needs sudo)|codecs|on"
    "Configs — linked into ~/.config · fonts · icons · wallpapers|configs|on"
    "Shell extras — Python helpers · gooey drawer plugin · wallpaper colours|shell|on"
    "App themes — VS Code · Zen · Discord (the ones installed)|apps|on"
    "Steam — Material theme · notifications in the shell|steam|on"
    "Login screen — SDDM theme (needs sudo)|sddm|on"
    "Boot splash — Plymouth theme · rebuilds the boot image (needs sudo)|boot|off"
    "fish as your login shell (needs sudo)|fish|on"
)
COMPONENT_KEYS=() # The keys above, in order
for c in "${COMPONENTS[@]}"; do c=${c#*|}; COMPONENT_KEYS+=("${c%%|*}"); done
component_label() { local c; for c in "${COMPONENTS[@]}"; do [[ $c == *"|$1|"* ]] && { echo "${c%%|*}"; return; }; done; }
component_needs_sudo() { [[ $(component_label "$1") == *"(needs sudo)"* ]]; }

# PACKAGES that aren't installed, one per line (one rpm call for all of them)
missing_packages() {
    rpm -q --qf '' "${PACKAGES[@]}" 2>/dev/null | sed -n 's/^package \(.*\) is not installed$/\1/p' |
        # RPM Fusion's full ffmpeg (the codecs component swaps it in) stands in for Fedora's ffmpeg-free
        { if rpm -q ffmpeg >/dev/null 2>&1; then grep -vx 'ffmpeg-free'; else cat; fi; }
}

# ── Keyboard layout (config/hypr/hyprland/keyboard.lua: Hyprland and the login screen read it) ──
# A layout is "layout" or "layout:variant", as xkb names them: us, us:dvorak, de, fr:azerty…
KEYBOARD_LUA="$DOTFILES/config/hypr/hyprland/keyboard.lua"
XKB_RULES=/usr/share/X11/xkb/rules/evdev.lst
keyboard_field() { # keyboard_field FILE layout|variant
    sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" 2>/dev/null | head -n1
}
keyboard_join() { [[ -n $2 ]] && echo "$1:$2" || echo "$1"; }
keyboard_current() { # Yours if set, else this computer's (what Fedora's setup picked), else US
    if [[ -f $KEYBOARD_LUA ]]; then keyboard_join "$(keyboard_field "$KEYBOARD_LUA" layout)" "$(keyboard_field "$KEYBOARD_LUA" variant)"; return; fi
    local status layout variant
    status=$(localectl status 2>/dev/null)
    layout=$(sed -n 's/^ *X11 Layout: *//p' <<<"$status"); layout=${layout%%,*}
    variant=$(sed -n 's/^ *X11 Variant: *//p' <<<"$status"); variant=${variant%%,*}
    local kb; kb=$(keyboard_join "${layout:-us}" "$variant")
    keyboard_valid "$kb" && echo "$kb" || echo us
}
# xkb's name for a layout (and variant): us:dvorak → English (Dvorak). Fails when xkb doesn't know it
keyboard_lookup() {
    local layout=${1%%:*} variant=; [[ $1 == *:* ]] && variant=${1#*:}
    [[ $layout =~ ^[A-Za-z0-9_-]+$ && $variant =~ ^[A-Za-z0-9_-]*$ ]] || return 1
    [[ -r $XKB_RULES ]] || { echo "$1"; return 0; }
    awk -v l="$layout" -v v="$variant" '/^!/ { s = $2; next }
        (s == "layout" && $1 == l && v == "") || (s == "variant" && $1 == v && $2 == l ":") {
            sub(/^ *[^ ]+ +/, ""); if (v != "") sub(/^[^ ]+ +/, ""); print; found = 1; exit }
        END { exit !found }' "$XKB_RULES"
}
keyboard_valid() { keyboard_lookup "$1" >/dev/null; }
keyboard_name() { keyboard_lookup "$1" || echo "$1"; }
keyboard_set() { # keyboard_set us:dvorak (your copy made from the default first)
    local layout=${1%%:*} variant=; [[ $1 == *:* ]] && variant=${1#*:}
    [[ -f $KEYBOARD_LUA ]] || run cp "$DOTFILES/config/hypr/hyprland/keyboard.default.lua" "$KEYBOARD_LUA" || return 1
    run sed -i -e "s/^\([[:space:]]*layout[[:space:]]*=[[:space:]]*\)\"[^\"]*\"/\1\"$layout\"/" \
               -e "s/^\([[:space:]]*variant[[:space:]]*=[[:space:]]*\)\"[^\"]*\"/\1\"$variant\"/" "$KEYBOARD_LUA"
}

# ── Packages ────────────────────────────────────────────────────────────────
has_gpu() { # has_gpu VENDOR_ID: a display controller (PCI class 0x03xxxx) from that vendor is present
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ $(<"$d/vendor") == "$1" && $(<"$d/class") == 0x03* ]] && return 0
    done 2>/dev/null
    return 1
}
# Fixes for hardware only some machines have; install and --update both run them
NV_MODULES_CONF=/etc/modules-load.d/nvidia-drm.conf
# NVIDIA (the laptop's hybrid RTX): load nvidia_drm at sysinit, well before SDDM. RPM Fusion keeps the
# driver out of the initramfs, so udev loads it late, and on some boots it's still initialising when the
# KWin greeter opens the GPU: both stall and the login screen never shows (a black-screen hang roughly
# every other boot). The desktop has no NVIDIA card, so it never raced.
need_nvidia_early() { has_gpu 0x10de && modinfo nvidia_drm >/dev/null 2>&1 && [[ ! -f $NV_MODULES_CONF ]]; }
# Intel iGPU firmware: without it i915 can't load its DMC firmware and turns off the GPU's runtime power
# management (battery drain on the laptop). Fedora doesn't always pull it in.
need_intel_firmware() { has_gpu 0x8086 && ! rpm -q intel-gpu-firmware >/dev/null 2>&1; }
# Desktop monitors (the AMD desktop's ultrawide): no backlight, so brightness goes over the cable (DDC/CI)
# with ddcutil, which the shell's brightness keys and OSD use when it's there (services/Brightness.qml).
# Fedora's package loads i2c-dev and grants access itself. Laptops dim their own panel, so they skip it
need_ddcutil() { ! compgen -G "/sys/class/backlight/*" >/dev/null && ! rpm -q ddcutil >/dev/null 2>&1; }
# Gameplay clips and the Clips page's trim encode H.264 on the GPU through VA-API. Without RPM Fusion
# (the codecs component, below, puts in the full drivers) Intel still gets Fedora's iHD driver here;
# AMD needs RPM Fusion's (Fedora's Mesa leaves H.264 encoding out)
rpmfusion_free() { dnf repolist --enabled 2>/dev/null | grep -q '^rpmfusion-free\b'; }
need_intel_vaapi() { has_gpu 0x8086 && ! rpm -q libva-intel-media-driver >/dev/null 2>&1 && ! rpm -q intel-media-driver >/dev/null 2>&1; }
hardware_fixes_pending() { need_nvidia_early || need_intel_firmware || need_ddcutil || need_intel_vaapi; }
# Older installs used noctalia's Quickshell fork (archived July 2026, no Qt 6.12 support). It owns
# /usr/bin/qs like upstream Quickshell does, so it's swapped rather than installed alongside
old_quickshell() { rpm -q --qf '%{NAME}\n' noctalia-qs-legacy noctalia-qs 2>/dev/null | grep -v 'not installed' | head -n1; }
swap_quickshell() {
    local old; old=$(old_quickshell)
    [[ -n $old ]] || return 0
    spin "Quickshell: $old → upstream quickshell" sudo dnf swap -y "$old" quickshell || return 1
    # The fork kept Qt's cache under its own name: bring over box art, cover art and notification
    # history (-n: never over anything the new build already wrote)
    local from="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia-qs" to="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
    if [[ -d $from ]]; then
        run mkdir -p "$to"
        local d; for d in game-launcher media notifications; do
            [[ -d $from/$d ]] && run cp -rn "$from/$d" "$to/"
        done
        ok "Moved the shell's cache over (box art, cover art, notifications)"
    fi
}
hardware_fixes() {
    local failed=0
    if need_nvidia_early; then
        if printf 'nvidia_drm\n' | run sudo tee "$NV_MODULES_CONF"; then ok "NVIDIA driver loads before the login screen (from the next boot)"
        else failed=1; fi
    fi
    if need_intel_firmware; then spin "Intel GPU firmware" sudo dnf install -y intel-gpu-firmware || failed=1; fi
    if need_ddcutil; then spin "Monitor brightness over DDC (ddcutil)" sudo dnf install -y ddcutil || failed=1; fi
    if need_intel_vaapi; then spin "Intel video encoding (gameplay clips)" sudo dnf install -y libva-intel-media-driver || failed=1; fi
    return $failed
}
comp_packages() {
    step "Packages and repositories"
    local failed=0
    if ! rpm -q dnf5-plugins >/dev/null 2>&1; then run sudo dnf install -y dnf5-plugins || failed=1; fi
    if rpm -q terra-release >/dev/null 2>&1; then ok "Terra repository (already enabled)"
    else
        spin "Terra repository" sudo dnf install -y --nogpgcheck \
            --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" terra-release || failed=1
    fi
    if dnf copr list 2>/dev/null | grep -q "/lionheartp/Hyprland\$"; then ok "COPR lionheartp/Hyprland (already enabled)"
    else spin "COPR lionheartp/Hyprland" sudo dnf copr enable -y lionheartp/Hyprland || failed=1; fi

    swap_quickshell || failed=1
    local missing; mapfile -t missing < <(missing_packages)
    if (( ${#missing[@]} == 0 )); then ok "All ${#PACKAGES[@]} packages already installed"
    else
        info "${#missing[@]} of ${#PACKAGES[@]} packages to install (this is the long part)"
        spin "Installing ${#missing[@]} packages" sudo dnf install -y "${missing[@]}" || failed=1
    fi

    # KWin as the greeter compositor; the default Weston one (sddm-wayland-generic) shows no cursor on
    # amdgpu. The two conflict, so swap rather than install alongside.
    if rpm -q sddm-wayland-plasma >/dev/null 2>&1; then ok "Login screen compositor: KWin (already)"
    elif rpm -q sddm-wayland-generic >/dev/null 2>&1; then
        spin "Login screen compositor: Weston → KWin" sudo dnf swap -y sddm-wayland-generic sddm-wayland-plasma || failed=1
    else spin "Login screen compositor: KWin" sudo dnf install -y sddm-wayland-plasma || failed=1; fi

    hardware_fixes || failed=1

    # Login unlocks the keyring: without pam_gnome_keyring.so, SDDM's "-auth optional pam_gnome_keyring.so"
    # line is skipped silently, the keyring stays locked, and apps (Vesktop, Zen…) pop up gnome-keyring's
    # "The login keyring did not get unlocked" password dialog after login
    if [[ -e /usr/lib64/security/pam_gnome_keyring.so ]] && grep -qE '^-?auth\s+optional\s+pam_gnome_keyring\.so' /etc/pam.d/sddm 2>/dev/null; then
        ok "Login unlocks the keyring"
    elif (( ! DRY_RUN )); then
        warn "SDDM doesn't unlock the keyring at login: check gnome-keyring-pam is installed and /etc/pam.d/sddm calls pam_gnome_keyring.so"
    fi

    # The portal config uses xdg-desktop-portal-gnome for the file picker; KDE's portal isn't used
    if rpm -q xdg-desktop-portal-kde >/dev/null 2>&1 && confirm "Remove xdg-desktop-portal-kde (KDE's file picker, not used here)?"; then
        spin "Removed the KDE portal" sudo dnf remove -y xdg-desktop-portal-kde || failed=1
    fi

    local svc
    for svc in NetworkManager bluetooth power-profiles-daemon; do
        run sudo systemctl enable --now "$svc" || { warn "Couldn't enable $svc"; failed=1; }
    done
    ok "Services enabled (network, bluetooth, power profiles)"

    if (( failed )); then result fail "Some steps failed; see the log"
    else result done "${#PACKAGES[@]} packages · Terra · Hyprland COPR"; fi
}

# ── Multimedia codecs (RPM Fusion) ──────────────────────────────────────────
# Fedora leaves patented codecs out. RPM Fusion's builds put them back:
#  - ffmpeg: H.264/HEVC decoding on the GPU too, so the Clips page's trim runs well over real time
#    (ffmpeg-free decodes H.264 in software only), and full codec support for video in general
#  - AMD: Mesa's VA-API driver with H.264/HEVC encoding, which gameplay clips record with (Fedora's has none)
#  - Intel: the full iHD driver (intel-media-driver; Fedora's libva-intel-media-driver is a cut-down build)
# NVIDIA's driver (RPM Fusion too) has its own encoder; installing it is left to you.
RPMFUSION_URL="https://mirrors.rpmfusion.org"
codec_swaps_pending() {
    rpm -q ffmpeg-free >/dev/null 2>&1 && return 0
    has_gpu 0x1002 && ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1 && return 0
    has_gpu 0x8086 && ! rpm -q intel-media-driver >/dev/null 2>&1 && return 0
    return 1
}
codec_swaps() { # The swaps themselves; RPM Fusion must be enabled
    local failed=0
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
        spin "ffmpeg: Fedora's → RPM Fusion's (full codecs)" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing || failed=1
    else ok "ffmpeg: full codecs (already)"; fi
    if has_gpu 0x1002; then
        if rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then ok "AMD video encoding (already)"
        elif rpm -q mesa-va-drivers >/dev/null 2>&1; then
            spin "AMD video encoding: Mesa's → RPM Fusion's (H.264 for clips)" sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || failed=1
        else spin "AMD video encoding (H.264 for clips)" sudo dnf install -y mesa-va-drivers-freeworld || failed=1; fi
    fi
    if has_gpu 0x8086; then
        if rpm -q intel-media-driver >/dev/null 2>&1; then ok "Intel video driver: full (already)"
        elif rpm -q libva-intel-media-driver >/dev/null 2>&1; then
            spin "Intel video driver: Fedora's → RPM Fusion's (full)" sudo dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing || failed=1
        else spin "Intel video driver (full)" sudo dnf install -y intel-media-driver || failed=1; fi
    fi
    return $failed
}
comp_codecs() {
    step "Multimedia codecs"
    local failed=0 fedora; fedora=$(rpm -E %fedora)
    if rpmfusion_free && dnf repolist --enabled 2>/dev/null | grep -q '^rpmfusion-nonfree\b'; then
        ok "RPM Fusion (already enabled)"
    else
        spin "RPM Fusion repositories (free and nonfree)" sudo dnf install -y \
            "$RPMFUSION_URL/free/fedora/rpmfusion-free-release-$fedora.noarch.rpm" \
            "$RPMFUSION_URL/nonfree/fedora/rpmfusion-nonfree-release-$fedora.noarch.rpm" || failed=1
    fi
    if (( ! failed )) || rpmfusion_free; then codec_swaps || failed=1; fi
    if (( failed )); then result fail "Some steps failed; see the log"
    else result done "RPM Fusion · full ffmpeg · video drivers"; fi
}
update_codecs() { # --update: the swaps, where RPM Fusion is on (it isn't turned on here: that's ./install.sh --only codecs)
    step "Multimedia codecs"
    if ! rpmfusion_free; then
        has_gpu 0x1002 && warn "Gameplay clips can't record on AMD without RPM Fusion: ./install.sh --only codecs sets it up"
        result done "RPM Fusion not enabled; skipped"
        return 0
    fi
    if codec_swaps; then result done "Full codecs and video drivers"; else result fail "See the log"; fi
}

# ── Configs ─────────────────────────────────────────────────────────────────
LINKED=0 BACKED_UP=0
link_one() {
    local target="$HOME/$1" source="$DOTFILES/$2"
    if [[ ! -e $source ]]; then warn "Missing in the repo, skipped: $2"; return 0; fi
    if [[ -L $target && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then return 0; fi
    if [[ -e $target || -L $target ]]; then
        run mkdir -p "$BACKUP_DIR/$(dirname "$1")"
        run mv "$target" "$BACKUP_DIR/$1" || return 1
        BACKED_UP=$((BACKED_UP + 1))
        info "Backed up your existing ~/$1"
    fi
    run mkdir -p "$(dirname "$target")"
    run ln -s "$source" "$target" || return 1
    LINKED=$((LINKED + 1))
}
comp_configs() {
    step "Configs"
    local failed=0 entry
    LINKED=0 BACKED_UP=0
    for entry in "${LINKS[@]}"; do link_one "${entry%%|*}" "${entry#*|}" || { err "Couldn't link ~/${entry%%|*}"; failed=1; }; done
    if (( LINKED )); then ok "Linked $LINKED of ${#LINKS[@]} configs"; else ok "All ${#LINKS[@]} configs already linked"; fi
    (( BACKED_UP )) && warn "$BACKED_UP existing file(s) moved to $BACKUP_DIR"
    run systemctl --user daemon-reload 2>/dev/null # Picks up the linked session target

    # Nautilus: folders open in it, and it's the file picker in other apps (config/xdg-desktop-portal)
    run xdg-mime default org.gnome.Nautilus.desktop inode/directory && ok "Folders open in Nautilus"
    if systemctl --user -q is-active xdg-desktop-portal 2>/dev/null; then
        run systemctl --user restart xdg-desktop-portal
    fi

    # Settings that store absolute paths: point any other user's home in them at this one. Whole-path
    # matches only (followed by / or "), so a re-run changes nothing and /home/ann won't touch /home/anna
    # Each machine's own copies (git ignores them): the first time, from the shipped defaults
    local entry_copy made=()
    for entry_copy in "${LOCAL_COPIES[@]}"; do
        local mine="$DOTFILES/${entry_copy%%|*}" shipped="$DOTFILES/${entry_copy#*|}"
        [[ -f $mine || ! -f $shipped ]] && continue
        run cp "$shipped" "$mine" && made+=("${entry_copy%%|*}")
    done
    (( ${#made[@]} )) && ok "From the defaults: ${made[*]#config/}"

    local f="config/ninomae-shell/config.json" other
    if [[ -f "$DOTFILES/$f" ]]; then
        while IFS= read -r other; do
            [[ $other == "$HOME" ]] && continue
            run sed -i "s|\"$other\([/\"]\)|\"$HOME\1|g" "$DOTFILES/$f" && ok "Home paths in $f: $other → $HOME"
        done < <(grep -oE '"/home/[^/"]+[/"]' "$DOTFILES/$f" | sed -E 's/^"//; s/[/"]$//' | sort -u)
    fi

    # Copying the folder via USB/zip/cloud often drops the executable bit; scripts are run directly
    local fixed=0
    while IFS= read -r -d '' f; do
        if head -c 2 "$f" | grep -q '#!'; then run chmod +x "$f"; fixed=$((fixed + 1)); fi
    done < <(find "$DOTFILES/config" "$DOTFILES/themes" "$DOTFILES/setup" -type f \( -name '*.sh' -o -name '*.py' \) ! -perm -u+x -print0)
    (( fixed )) && ok "Made $fixed script(s) executable"

    spin "Font cache" fc-cache -f || failed=1

    if (( failed )); then result fail "Some links failed; see the log"
    elif (( BACKED_UP )); then result done "$LINKED linked · $BACKED_UP backed up"
    else result done "${#LINKS[@]} configs linked"; fi
}

# ── Shell extras ────────────────────────────────────────────────────────────
python_env() { # python_env [--upgrade]
    if [[ ! -x "$VENV/bin/python" ]]; then
        run mkdir -p "$(dirname "$VENV")"
        spin "Python environment" python3 -m venv "$VENV" || return 1
    fi
    if [[ ${1:-} != --upgrade ]] && "$VENV/bin/python" -c "import materialyoucolor, PIL, numpy, cv2; cv2.ximgproc" 2>/dev/null; then
        ok "Python helpers (already set up)"; return 0
    fi
    run "$VENV/bin/python" -m pip uninstall --quiet -y opencv-python-headless # Clashes with the contrib build
    # opencv contrib: the region selector's image detection needs cv2.ximgproc
    spin "Python helpers (colours, image search)" "$VENV/bin/python" -m pip install --quiet --upgrade \
        pip materialyoucolor pillow numpy opencv-contrib-python-headless
}
build_blobs() { # build_blobs [--if-needed]: with it, skip when the build matches Qt and the sources
    local plugin="$DOTFILES/config/quickshell/plugins/ninomae-blobs"
    local built="$HOME/.local/lib/qt6/qml/Ninomae/Blobs/.built-against"
    if [[ ${1:-} == --if-needed && -f $built && "$("$plugin/ensure-built.sh" --stamp 2>/dev/null)" == "$(cat "$built")" ]]; then
        ok "Gooey drawer plugin (up to date)"
        return 0
    fi
    if command -v cmake >/dev/null && rpm -q qt6-qtshadertools-devel >/dev/null 2>&1; then
        spin "Gooey drawer plugin (Ninomae.Blobs)" "$plugin/build.sh"
    else
        warn "Build tools missing (install the packages first); the shell falls back to plain drawers"
        return 1
    fi
}
# The colour files (theme.conf, matugen.css, …) aren't in git: matugen writes them from the wallpaper.
# The shell step makes them. Theme steps run on their own (--only steam) make them first if they're missing
make_colours() {
    local wall="$DOTFILES/assets/wallpapers/purpgirl.png"
    [[ -f $wall ]] || wall="$(find "$DOTFILES/assets/wallpapers" -maxdepth 1 -type f 2>/dev/null | head -n1)"
    if [[ -z $wall || ! -f $wall ]]; then warn "No wallpaper found in assets/wallpapers"; return 1
    elif spin "Colours from $(basename "$wall")" "$HOME/.config/quickshell/$QS_CONFIG/scripts/colors/switchwall.sh" --image "$wall" --mode dark; then :
    elif spin "Colours with matugen" matugen image "$wall" --type scheme-content --mode dark --source-color-index 0; then :
    else warn "Couldn't generate colours; pick a wallpaper from the shell after logging in"; return 1; fi
    # Safety net: if switchwall.sh failed partway (it works without Hyprland, from a TTY or another desktop),
    # make sure the terminal and Qt colours exist too
    local generated="$HOME/.local/state/quickshell/user/generated"
    if (( ! DRY_RUN )) && [[ ! -f "$generated/terminal/sequences.txt" && -f "$generated/material_colors.scss" ]]; then
        "$HOME/.config/quickshell/$QS_CONFIG/scripts/colors/applycolor.sh" >>"$LOG" 2>&1
    fi
    return 0
}
ensure_colours() {
    [[ -f "$DOTFILES/themes/sddm/Ninomae/theme.conf" ]] && return 0
    info "No colours yet: making them from the wallpaper first"
    make_colours
}
comp_shell() {
    step "Shell extras"
    local failed=0
    python_env || failed=1
    build_blobs || failed=1

    make_colours || failed=1

    if (( failed )); then result fail "Partly done; see the log"; else result done "Helpers, drawer plugin, colours"; fi
}

# ── App themes ──────────────────────────────────────────────────────────────
vesktop_running() { pgrep -x vesktop >/dev/null || pgrep -f "/vesktop/vesktop" >/dev/null; }
# Vesktop has to be closed while its theme is installed: offer to close it, then reopen it afterwards
discord_theme() {
    local reopen=0
    if vesktop_running; then
        if ! confirm "Vesktop is open and has to close for its theme. Close it (it reopens afterwards)?"; then
            needs_you "Discord: quit Vesktop (tray icon → Quit), then run ${c_bold}themes/discord/install-theme.sh${c_off}"
            return 2
        fi
        if (( ! DRY_RUN )); then
            pkill -x vesktop; pkill -f "/vesktop/vesktop"
            local _; for _ in $(seq 20); do vesktop_running || break; sleep 0.5; done
            vesktop_running && { warn "Vesktop didn't close"; return 1; }
        fi
        reopen=1
    fi
    run "$DOTFILES/themes/discord/install-theme.sh" || return 1
    (( reopen && ! DRY_RUN )) && setsid -f vesktop >/dev/null 2>&1
    return 0
}
comp_apps() {
    step "App themes"
    ensure_colours
    local did=() failed=0
    if command -v code >/dev/null || command -v codium >/dev/null; then
        run "$DOTFILES/themes/vscode/install-theme.sh" && { ok "VS Code: Ninomae theme selected"; did+=("VS Code"); } || failed=1
    else info "VS Code isn't installed; skipped"; fi
    if [[ -f "$HOME/.var/app/app.zen_browser.zen/.zen/profiles.ini" || -f "$HOME/.zen/profiles.ini" ]]; then
        run "$DOTFILES/themes/zen/apply-theme.sh" && { ok "Zen: theme copied into your profiles"; did+=("Zen"); } || failed=1
    else
        info "Zen hasn't been opened yet: it's themed by itself the first time it is"
    fi
    if command -v vesktop >/dev/null; then
        discord_theme; case $? in
            0) ok "Discord (Vesktop): theme installed"; did+=("Discord") ;;
            2) info "Discord: left Vesktop open" ;;
            *) err "Discord: theme failed; see the log"; failed=1 ;;
        esac
    else info "Vesktop isn't installed; skipped"; fi
    if (( failed )); then result fail "Some themes failed; see the log"
    elif (( ${#did[@]} )); then result done "$(IFS=,; echo "${did[*]}" | sed 's/,/, /g')"
    else result skip "None of these apps are set up yet"; fi
}

# ── Steam ───────────────────────────────────────────────────────────────────
comp_steam() {
    step "Steam"
    ensure_colours
    if ! command -v steam >/dev/null; then info "Steam isn't installed"; result skip "Steam isn't installed"; return; fi
    if [[ ! -d "$HOME/.steam/steam/ubuntu12_64" ]]; then
        info "Steam hasn't been opened yet. Open it once and sign in, then close it: a notification offers to theme it"
        result skip "Offered once Steam has been opened"; return
    fi
    if pgrep -x steam >/dev/null && ! confirm "Steam is open and will be closed to theme it. Go ahead?"; then
        needs_you "Steam: run ${c_bold}themes/steam/install-theme.sh${c_off} when it's convenient to close Steam"
        result skip "Left Steam open"; return
    fi
    info "Millennium (Steam client patcher), Material theme, notifications plugin:"
    if run_visible "$DOTFILES/themes/steam/install-theme.sh"; then
        result done "Theme and notifications plugin"
    else result fail "See the log"; fi
}

# ── Login screen ────────────────────────────────────────────────────────────
comp_sddm() {
    step "Login screen"
    ensure_colours
    local failed=0
    spin "SDDM theme" sudo "$DOTFILES/themes/sddm/install-theme.sh" || failed=1
    local current_dm
    current_dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null || true)"
    if [[ $current_dm == sddm ]]; then ok "SDDM is the login manager"
    elif confirm "Make SDDM the login manager? (currently: ${current_dm:-none})"; then
        run sudo systemctl enable -f sddm.service && ok "SDDM enabled (from the next boot)" || failed=1
    else
        warn "Left the login manager as ${current_dm:-none}"
    fi
    if (( failed )); then result fail "See the log"; else result done "SDDM theme"; fi
}

# ── Boot splash ─────────────────────────────────────────────────────────────
comp_boot() {
    step "Boot splash"
    ensure_colours
    info "Rebuilding the boot image takes a minute or two"
    if spin "Plymouth theme" sudo "$DOTFILES/themes/boot/install-boot-theme.sh"; then result done "Plymouth theme"
    else result fail "See the log"; fi
}

# ── Login shell ─────────────────────────────────────────────────────────────
comp_fish() {
    step "Login shell"
    local fish_path; fish_path="$(command -v fish || true)"
    if [[ -z $fish_path ]]; then warn "fish isn't installed"; result skip "fish isn't installed"
    elif [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$fish_path" ]]; then ok "Already fish"; result done "fish (already)"
    elif run sudo chsh -s "$fish_path" "$USER"; then ok "fish from your next login"; result done "fish"
    else result fail "chsh failed; see the log"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Update: bring an existing install up to date
# ─────────────────────────────────────────────────────────────────────────────
update_files() {
    step "Latest files"
    if [[ -d "$DOTFILES/.git" ]] && command -v git >/dev/null; then
        # Your own files (config.json, the app configs, bookmarks) aren't in git, or are about to stop being. A
        # pull that stops tracking a file deletes it, and refuses to run at all if you've changed it: keep a copy,
        # set an edited one back to git's version so the pull goes ahead, and put yours back after
        local kept_dir="$LOG_DIR/kept-before-update" f entry_copy reset=() restored=()
        local mine_files=("${KEEP_ACROSS_PULL[@]}")
        for entry_copy in "${LOCAL_COPIES[@]}"; do mine_files+=("${entry_copy%%|*}"); done
        run rm -rf "$kept_dir"
        for f in "${mine_files[@]}"; do
            [[ -f $DOTFILES/$f ]] || continue
            run mkdir -p "$kept_dir/$(dirname "$f")" && run cp -p "$DOTFILES/$f" "$kept_dir/$f" || continue
            if git -C "$DOTFILES" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 \
                && ! git -C "$DOTFILES" diff --quiet -- "$f"; then
                run git -C "$DOTFILES" checkout -- "$f" && reset+=("$f")
            fi
        done
        if spin "git pull" git -C "$DOTFILES" pull --ff-only; then result done "Pulled the latest changes"
        else result fail "git pull failed (local changes?); see the log"; fi
        for f in "${mine_files[@]}"; do
            [[ -f $kept_dir/$f ]] || continue
            # Gone (no longer tracked), or set back above: yours again. Otherwise the pull's update stands
            if [[ ! -f $DOTFILES/$f ]] || [[ " ${reset[*]} " == *" $f "* ]]; then
                run cp -p "$kept_dir/$f" "$DOTFILES/$f" && restored+=("${f#config/}")
            fi
        done
        (( ${#restored[@]} )) && ok "Kept yours: ${restored[*]}"
        # Hyprland may have reloaded while the pull had your keyboard layout out of place: load it again
        [[ " ${restored[*]} " == *" hypr/hyprland/keyboard.lua "* && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
            && run hyprctl reload >/dev/null
    else
        info "This folder isn't a git checkout; using the files as they are"
        result skip "Not a git checkout"
    fi
}
update_packages() {
    step "Missing packages"
    local failed=0 missing
    swap_quickshell || failed=1
    mapfile -t missing < <(missing_packages)
    hardware_fixes || failed=1
    if (( ${#missing[@]} == 0 )); then ok "Nothing new to install"
    else
        info "New: ${missing[*]}"
        spin "Installing ${#missing[@]} package(s)" sudo dnf install -y "${missing[@]}" || failed=1
    fi
    if (( failed )); then result fail "See the log"
    elif (( ${#missing[@]} )); then result done "${#missing[@]} installed"
    else result done "All installed"; fi
}
update_shell() {
    step "Shell extras"
    local failed=0
    python_env --upgrade || failed=1
    build_blobs --if-needed || failed=1 # It has to match the installed Qt
    if (( failed )); then result fail "See the log"; else result done "Python helpers upgraded, plugin up to date"; fi
}
update_steam_plugin() {
    step "Steam notifications plugin"
    if [[ ! -f $STEAM_PLUGIN ]]; then info "Not installed"; result skip "Not installed"; return; fi
    local status
    run_visible "$DOTFILES/themes/steam/install-theme.sh" --update-plugin; status=$?
    case $status in
        0) result done "Already the latest" ;;
        10) result done "Updated"; pgrep -x steam >/dev/null && needs_you "Steam: restart it (Exit Steam, then start it) to load the updated notifications plugin" ;;
        *) result fail "Download failed; see the log" ;;
    esac
}
update_apps() {
    step "App themes"
    local did=()
    [[ -f "$HOME/.var/app/app.zen_browser.zen/.zen/profiles.ini" || -f "$HOME/.zen/profiles.ini" ]] \
        && run "$DOTFILES/themes/zen/apply-theme.sh" && did+=("Zen")
    command -v vesktop >/dev/null && discord_theme && did+=("Discord")
    if (( ${#did[@]} )); then ok "Re-applied: ${did[*]}"; result done "${did[*]}"; else result skip "Nothing to re-apply"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Check: is everything in place? Reads only (./install.sh --check, or `ninomae check`)
# ─────────────────────────────────────────────────────────────────────────────
check_links() {
    step "Config links"
    local entry dst src bad=() broken
    for entry in "${LINKS[@]}"; do
        dst="$HOME/${entry%%|*}"; src="$DOTFILES/${entry#*|}"
        [[ -L $dst && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]] || bad+=("~/${entry%%|*}")
    done
    # Links left pointing at nothing (a moved or deleted folder). Apps' own lock files aside
    broken=$(find "$HOME/.config" -maxdepth 2 -xtype l ! -name 'Singleton*' 2>/dev/null | sed "s|^$HOME|~|" | tr '\n' ' ')
    (( ${#bad[@]} )) && warn "Not linked to this folder: ${bad[*]}"
    [[ -n $broken ]] && warn "Broken links: $broken"
    if (( ${#bad[@]} )); then result fail "${#bad[@]} not linked, run ninomae update"
    elif [[ -n $broken ]]; then result todo "Broken links in ~/.config"
    else result done "${#LINKS[@]} linked"; fi
}
check_settings() {
    step "Shell settings"
    local dir="$DOTFILES/config/ninomae-shell" f bad=0
    for f in config.json config.default.json window-rules.default.json; do
        if [[ ! -f $dir/$f ]]; then
            if [[ $f == config.json ]]; then info "No config.json yet: the shell makes it from the defaults"
            else warn "$f is missing"; bad=1; fi
        elif ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$dir/$f" 2>/dev/null; then
            warn "$f isn't valid JSON"; bad=1
        fi
    done
    if (( bad )); then result fail "See above"; else result done "Readable"; fi
}
check_packages() {
    step "Packages"
    local missing; mapfile -t missing < <(missing_packages)
    if (( ${#missing[@]} )); then info "Missing: ${missing[*]}"; result todo "${#missing[@]} missing, run ninomae update"
    else result done "All installed"; fi
}
check_plugin() {
    step "Gooey drawer plugin"
    local plugin="$DOTFILES/config/quickshell/plugins/ninomae-blobs"
    local built="$HOME/.local/lib/qt6/qml/Ninomae/Blobs/.built-against"
    if [[ ! -f $built ]]; then result todo "Not built, run ninomae update"
    elif [[ "$("$plugin/ensure-built.sh" --stamp 2>/dev/null)" != "$(cat "$built")" ]]; then result todo "Out of date, run ninomae update"
    else result done "Up to date"; fi
}
check_colours() {
    step "Wallpaper colours"
    local gen="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated" f missing=()
    for f in "$gen/material_colors.scss" "$gen/terminal/sequences.txt" "$gen/terminal/kitty-colors.conf" \
             "$DOTFILES/config/gtk-3.0/gtk.css" "$DOTFILES/config/gtk-4.0/gtk.css" \
             "$DOTFILES/config/fuzzel/fuzzel_theme.ini" "$DOTFILES/config/btop/themes/ninomae.theme"; do
        [[ -f $f ]] || missing+=("${f/#$HOME/\~}")
    done
    if (( ${#missing[@]} )); then info "Missing: ${missing[*]}"; result todo "Pick a wallpaper to make them"
    else result done "All there"; fi
}
check_python() {
    step "Python helpers"
    if "$VENV/bin/python" -c "import materialyoucolor, PIL, numpy, cv2; cv2.ximgproc" 2>/dev/null; then result done "Working"
    else result todo "Missing or broken, run ninomae update"; fi
}
check_running() {
    step "Running shell"
    if ! pgrep -f "^qs -c $QS_CONFIG\$" >/dev/null; then result todo "Not running, Super+Ctrl+R starts it"; return; fi
    local log errors=0 pattern='TypeError|ReferenceError|SyntaxError| ERROR '
    log=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$UID}"/quickshell/by-id/*/log.log 2>/dev/null | xargs -r grep -l "$QS_CONFIG/shell.qml" | head -n1)
    [[ -n $log ]] && errors=$(grep -acE "$pattern" "$log")
    if (( errors )); then
        info "Latest: $(grep -aE "$pattern" "$log" | tail -n1 | cut -c1-140)"
        result todo "$errors error line(s) in its log"
    else result done "Running, no errors in its log"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Uninstall: remove the links and put back what they replaced
# ─────────────────────────────────────────────────────────────────────────────
latest_backup_of() { # latest_backup_of ".config/hypr" → newest backup copy of it, if any
    local dir
    while IFS= read -r dir; do
        [[ -e "$dir/$1" || -L "$dir/$1" ]] && { echo "$dir/$1"; return 0; }
    done < <(ls -1d "$HOME"/.dotfiles-backup-* 2>/dev/null | sort -r)
    return 1
}
uninstall_links() {
    step "Configs"
    local entry target removed=0 restored=0 backup
    for entry in "${LINKS[@]}"; do
        target="$HOME/${entry%%|*}"
        # Only links that point into this folder; anything else is yours and stays
        [[ -L $target && "$(readlink -f "$target")" == "$DOTFILES"/* ]] || continue
        run rm "$target" && removed=$((removed + 1))
        if backup=$(latest_backup_of "${entry%%|*}"); then
            run mv "$backup" "$target" && { restored=$((restored + 1)); info "Restored ~/${entry%%|*} from ${backup%/${entry%%|*}}"; }
        fi
    done
    ok "Removed $removed link(s), restored $restored backup(s)"
    result done "$removed removed · $restored restored"
}
uninstall_steam_plugin() {
    step "Steam notifications plugin"
    if [[ ! -f $STEAM_PLUGIN ]]; then info "Not installed"; result skip "Not installed"; return; fi
    if ! confirm "Remove the Steam notifications plugin? (Steam goes back to its own pop-ups)"; then result skip "Kept"; return; fi
    run rm -f "$STEAM_PLUGIN"
    local cfg="$HOME/.config/millennium/config.json"
    if [[ -f $cfg ]] && (( ! DRY_RUN )); then
        python3 - "$cfg" <<'PY' >>"$LOG" 2>&1
import json, sys
p = sys.argv[1]
c = json.load(open(p))
enabled = c.get("plugins", {}).get("enabledPlugins", [])
if "me.tysmith.steam-native-notifications" in enabled:
    enabled.remove("me.tysmith.steam-native-notifications")
    json.dump(c, open(p, "w"), indent=4)
PY
    fi
    ok "Removed (takes effect when Steam restarts)"
    result done "Removed"
}
uninstall_shell() {
    step "Login shell"
    local fish_path bash_path; fish_path="$(command -v fish || true)"; bash_path="$(command -v bash)"
    if [[ -z $fish_path || "$(getent passwd "$USER" | cut -d: -f7)" != "$fish_path" ]]; then result skip "Not fish"; return; fi
    if confirm "Switch your login shell back to bash?"; then
        run sudo chsh -s "$bash_path" "$USER" && { ok "bash from your next login"; result done "Back to bash"; } || result fail "chsh failed"
    else result skip "Kept fish"; fi
}
