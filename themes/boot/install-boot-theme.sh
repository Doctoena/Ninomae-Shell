#!/usr/bin/env bash
# Ninomae boot splash: a Plymouth theme in the desktop's colours and shapes: the Fedora logo in an accent
# squircle badge (the shell's bar and lock screen badge), a progress bar while booting, a spinner and a
# title when shutting down or restarting.
# Colours come from the matugen-generated SDDM theme.conf.
#
#   sudo ./install-boot-theme.sh               install the boot splash
#   sudo ./install-boot-theme.sh --remove-grub undo the old Ninomae GRUB theme (back to the stock menu)
#   sudo ./install-boot-theme.sh --uninstall   remove the splash too (and any GRUB theme leftovers)
#        ./install-boot-theme.sh --build DIR   just render the splash into DIR (no root, for previews)
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dotfiles="$(cd -- "$script_dir/../.." && pwd)"
colors_file="$dotfiles/themes/sddm/Ninomae/theme.conf"
fonts_dir="$dotfiles/assets/fonts"
plymouth_theme_dir="/usr/share/plymouth/themes/ninomae"
state_dir="/var/lib/ninomae-boot-theme"
# Left by the earlier GRUB theme; only used to clean it up
grub_theme_dir="/boot/grub2/themes/ninomae"
grub_default="/etc/default/grub"
grub_backup="/etc/default/grub.before-ninomae"
grub_fonts_script="/etc/grub.d/05_ninomae_fonts"

say() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

color() { # color <key>: a hex colour from theme.conf
    local v
    v="$(sed -n "s/^$1=\"\?\(#[0-9a-fA-F]\{6\}\)\"\?/\1/p" "$colors_file" | head -1)"
    [[ -n "$v" ]] || die "colour '$1' missing from $colors_file"
    printf '%s' "$v"
}

build_plymouth() { # build_plymouth <dir>
    local d="$1" bg surface surface_high primary sym i
    bg="$(color background_color)"; surface="$(color surface_container)"; surface_high="$(color surface_container_high)"
    primary="$(color primary)"
    sym="$fonts_dir/ttf-material-symbols-variable/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"
    mkdir -p "$d"
    sed -e "s/@background_hex@/0x${bg#\#}/g" -e "s/@primary_hex@/0x${primary#\#}/g" \
        -e "s/@track_hex@/0x${surface_high#\#}/g" "$script_dir/plymouth/ninomae.plymouth" > "$d/ninomae.plymouth"
    # The logo in an accent squircle badge, like the shell's distro badge (accent at 18% on the background,
    # radius about a third of the size: 28 px / 9 in the bar)
    magick -background none -density 600 "$dotfiles/themes/sddm/Ninomae/fedora-symbolic.svg" -resize 60x60 \
        -fill "$primary" -colorize 100 "$d/logo.png"
    magick -size 112x112 xc:none -fill "$primary" -draw "roundrectangle 0,0 111,111 36,36" -channel A -evaluate multiply 0.18 +channel \
        "$d/logo.png" -gravity center -composite "$d/watermark.png"
    rm -f "$d/logo.png"
    # Spinner: a rounded lavender arc on a faint track, 36 frames
    magick -size 56x56 xc:none -fill none -strokewidth 5 \
        -stroke "${surface_high}" -draw "circle 28,28 28,6" \
        -stroke "$primary" -draw "stroke-linecap round arc 6,6 50,50 -90,30" "$d/arc.png"
    for i in $(seq 1 36); do
        magick "$d/arc.png" -background none -virtual-pixel transparent -distort SRT "$(( (i - 1) * 10 ))" "$(printf '%s/throbber-%04d.png' "$d" "$i")"
    done
    rm -f "$d/arc.png"
    # Password dialog (needed even without disk encryption: two-step won't start without them). Squircles,
    # not pills: the card like the shell's popups, the field like the lock screen's password field
    magick -size 440x150 xc:none -fill "$surface" -draw "roundrectangle 0,0 439,149 20,20" "$d/box.png"
    magick -size 340x46 xc:none -fill "$surface_high" -draw "roundrectangle 0,0 339,45 14,14" "$d/entry.png"
    magick -size 12x12 xc:none -fill "$primary" -draw "circle 6,6 6,1" "$d/bullet.png"
    magick -size 32x32 xc:none -font "$sym" -pointsize 28 -fill "$primary" -gravity center -annotate +0+0 $'' "$d/lock.png"
}

install_plymouth() {
    say "Installing Plymouth"
    dnf install -y plymouth plymouth-scripts plymouth-plugin-two-step plymouth-plugin-label
    install -d -m 0700 "$state_dir"
    [[ -e "$state_dir/plymouth-theme.before" ]] || (plymouth-set-default-theme 2>/dev/null || echo bgrt) > "$state_dir/plymouth-theme.before"
    say "Building the boot splash"
    rm -rf "$plymouth_theme_dir"
    build_plymouth "$plymouth_theme_dir"
    chown -R root:root "$plymouth_theme_dir"; find "$plymouth_theme_dir" -type f -exec chmod 0644 {} +
    say "Setting the splash and rebuilding the initramfs (this takes a minute)"
    plymouth-set-default-theme -R ninomae
}

remove_grub_theme() {
    local changed=0
    if [[ -e "$grub_backup" ]]; then
        cp -a "$grub_backup" "$grub_default" && rm -f "$grub_backup"
        say "Restored the original $grub_default"; changed=1
    fi
    if [[ -e "$grub_fonts_script" ]]; then rm -f "$grub_fonts_script"; changed=1; fi
    if [[ -e "$grub_theme_dir" ]]; then rm -rf "$grub_theme_dir"; changed=1; fi
    if (( changed )); then
        say "Regenerating the GRUB config"
        grub2-mkconfig -o /boot/grub2/grub.cfg
        say "GRUB is back to the stock menu"
    else
        say "No Ninomae GRUB theme found; nothing to undo"
    fi
}

uninstall() {
    remove_grub_theme
    if [[ -e "$state_dir/plymouth-theme.before" ]] && command -v plymouth-set-default-theme >/dev/null; then
        plymouth-set-default-theme -R "$(<"$state_dir/plymouth-theme.before")" || true
        say "Restored the previous boot splash"
    fi
    rm -rf "$plymouth_theme_dir" "$state_dir"
    say "Plymouth itself is still installed; remove it with: sudo dnf remove plymouth"
}

need_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "run with sudo: sudo $0 ${1:-}"; }
command -v magick >/dev/null || die "ImageMagick (magick) is needed"

case "${1:-install}" in
    install)       need_root; install_plymouth; say "Done. You'll see it on the next boot." ;;
    --remove-grub) need_root "$1"; remove_grub_theme ;;
    --uninstall)   need_root "$1"; uninstall ;;
    --build)       [[ -n "${2:-}" ]] || die "usage: $0 --build DIR"
                   build_plymouth "$2"; say "Rendered into $2" ;;
    -h|--help)     sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)             die "unknown option: $1 (see --help)" ;;
esac
