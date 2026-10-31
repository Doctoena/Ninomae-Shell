#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
theme_source="$script_dir/Ninomae"
fonts_source="$(cd -- "$script_dir/../../assets/fonts" && pwd)"
theme_target="/usr/share/sddm/themes/Ninomae"
cursor_source="$(cd -- "$script_dir/../../assets/icons/BreezeX-RosePine-Linux" && pwd)"
cursor_target="/usr/share/icons/BreezeX-RosePine-Linux"
sddm_override="/etc/sddm.conf.d/99-ninomae-theme.conf"
keyboard_config="/etc/X11/xorg.conf.d/00-keyboard.conf"
keyboard_state="/var/lib/sddm-ninomae"
keyboard_backup="$keyboard_state/00-keyboard.conf.before"
keyboard_was_missing="$keyboard_state/keyboard-config-was-missing"
keyboard_installed_hash="$keyboard_state/00-keyboard.conf.installed.sha256"
# The login screen uses the same layout as the desktop: read it from Hyprland's keyboard.lua (yours, else
# the default beside it). Settings → Input can set it again later, with localectl as here
keyboard_lua="$script_dir/../../config/hypr/hyprland/keyboard.lua"
[[ -r "$keyboard_lua" ]] || keyboard_lua="$script_dir/../../config/hypr/hyprland/keyboard.default.lua"
kb_field() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$keyboard_lua" 2>/dev/null | head -n1; }
kb_layout="$(kb_field layout)"; kb_layout="${kb_layout:-us}"
kb_variant="$(kb_field variant)"

case "${1:-install}" in
    install)
        if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
            printf 'Run with sudo: %s\n' "$0" >&2
            exit 1
        fi
        if [[ -e "$theme_target" && ! -f "$theme_target/.managed-by-dotfiles" ]]; then
            printf 'Refusing to overwrite existing theme: %s\n' "$theme_target" >&2
            exit 1
        fi
        if [[ -e "$sddm_override" ]] && ! grep -qx 'Current=Ninomae' "$sddm_override"; then
            printf 'Refusing to overwrite existing SDDM override: %s\n' "$sddm_override" >&2
            exit 1
        fi
        install -d -o root -g root -m 0700 "$keyboard_state"
        if [[ ! -e "$keyboard_backup" && ! -e "$keyboard_was_missing" ]]; then
            if [[ -e "$keyboard_config" ]]; then
                cp -a "$keyboard_config" "$keyboard_backup"
            else
                touch "$keyboard_was_missing"
            fi
        fi
        localectl set-x11-keymap "$kb_layout" pc105 "$kb_variant"
        # Sync the desktop's current wallpaper (the sddm user cannot read $HOME, so it is copied in)
        user_home="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
        wallpaper_ref="$user_home/.local/state/quickshell/user/generated/wallpaper/path.txt"
        if [[ -r "$wallpaper_ref" ]]; then
            wallpaper="$(<"$wallpaper_ref")"
            if [[ -r "$wallpaper" ]] && command -v magick >/dev/null; then
                magick "$wallpaper" -resize '2560x1440^' -quality 90 "$theme_source/wallpaper.jpg"
                chown --reference="$theme_source" "$theme_source/wallpaper.jpg"
                printf 'Synced wallpaper from %s\n' "$wallpaper"
            fi
        fi
        install -d -o root -g root -m 0755 "$theme_target"
        cp -a "$theme_source"/. "$theme_target"/
        # Fonts come from assets/fonts (the sddm user can't read ~/.local/share/fonts),
        # so they aren't stored twice in the repo
        install -d "$theme_target/fonts"
        install -m 0644 "$fonts_source/ttf-material-symbols-variable/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf" "$theme_target/fonts/MaterialSymbolsRounded.ttf"
        for font in RobotoFlex Rubik SpaceGrotesk; do
            install -m 0644 "$fonts_source/google/$font.ttf" "$theme_target/fonts/$font.ttf"
        done
        install -m 0644 "$fonts_source/google/OFL-licenses.txt" "$theme_target/fonts/OFL-licenses.txt"
        # Cursor theme goes system-wide for the same reason (the greeter can't read ~/.icons)
        if [[ -e "$cursor_target" && ! -f "$cursor_target/.managed-by-dotfiles" ]]; then
            printf 'Refusing to overwrite existing cursor theme: %s\n' "$cursor_target" >&2
            exit 1
        fi
        rm -rf "$cursor_target"
        cp -r "$cursor_source" "$cursor_target"
        touch "$cursor_target/.managed-by-dotfiles"
        chown -R root:root "$cursor_target"
        find "$cursor_target" -type d -exec chmod 0755 {} +
        find "$cursor_target" -type f -exec chmod 0644 {} +
        chown -R root:root "$theme_target"
        find "$theme_target" -type d -exec chmod 0755 {} +
        find "$theme_target" -type f -exec chmod 0644 {} +
        # Let the desktop user keep the colours and wallpaper in sync without sudo (sync-theme.sh, run by
        # matugen on every wallpaper change). Only these two data files; Main.qml and the rest stay root-only.
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
            for synced in theme.conf wallpaper.jpg; do
                [[ -f "$theme_target/$synced" ]] || continue
                chown "root:$(id -gn "$SUDO_USER")" "$theme_target/$synced"
                chmod 0664 "$theme_target/$synced"
            done
        fi
        install -D -o root -g root -m 0644 "$script_dir/99-ninomae-theme.conf" "$sddm_override"
        sha256sum "$keyboard_config" | cut -d' ' -f1 > "$keyboard_installed_hash"
        chmod 0600 "$keyboard_installed_hash"
        printf 'Installed Ninomae SDDM theme. It will be used at the next greeter start.\n'
        printf 'Set the keyboard layout to %s for the greeter.\n' "$kb_layout${kb_variant:+ ($kb_variant)}"
        ;;
    --uninstall)
        if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
            printf 'Run with sudo: %s --uninstall\n' "$0" >&2
            exit 1
        fi
        if [[ -f "$sddm_override" ]] && grep -qx 'Current=Ninomae' "$sddm_override"; then
            rm "$sddm_override"
            printf 'Removed the Ninomae SDDM override.\n'
        else
            printf 'No Ninomae SDDM override found; nothing changed.\n'
        fi
        if [[ -f "$keyboard_installed_hash" && -f "$keyboard_config" ]]; then
            current_hash="$(sha256sum "$keyboard_config" | cut -d' ' -f1)"
            installed_hash="$(<"$keyboard_installed_hash")"
            if [[ "$current_hash" == "$installed_hash" ]]; then
                if [[ -f "$keyboard_backup" ]]; then
                    cp -a "$keyboard_backup" "$keyboard_config"
                elif [[ -f "$keyboard_was_missing" ]]; then
                    rm "$keyboard_config"
                fi
                rm -rf "$keyboard_state"
                printf 'Restored the original system keyboard configuration.\n'
            else
                printf 'Keyboard config changed since install; leaving it untouched. Backup: %s\n' "$keyboard_backup"
            fi
        fi
        printf 'Theme files remain at %s and can be removed separately.\n' "$theme_target"
        ;;
    -h|--help)
        printf 'Usage: sudo %s [install|--uninstall]\n' "$0"
        ;;
    *)
        printf 'Usage: sudo %s [install|--uninstall]\n' "$0" >&2
        exit 2
        ;;
esac
