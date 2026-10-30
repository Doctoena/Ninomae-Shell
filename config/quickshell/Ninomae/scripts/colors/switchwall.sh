#!/usr/bin/env bash
# Sets the wallpaper and regenerates every colour from it (or from one colour):
#   switchwall.sh [--image] <path> [--mode dark|light] [--type scheme-…|auto]
#   switchwall.sh --color [#rrggbb]   no colour given: pick one from the screen (hyprpicker)
#   switchwall.sh --noswitch          regenerate from the current wallpaper
# With no image and no colour, asks for one with a file dialog.

QUICKSHELL_CONFIG_NAME="Ninomae"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
GENERATED="$STATE_DIR/user/generated"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/ninomae-shell/config.json"
PYTHON="${NINOMAE_SHELL_VIRTUAL_ENV:-$STATE_DIR/.venv}/bin/python"
[[ -x $PYTHON ]] || PYTHON=python3
SCHEMES=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot)

# Every setting used here, read with one jq (it used to be a jq per setting). Missing ones read as "".
# tostring, not `// default`: jq's // also replaces false (so a false setting would read as the default)
read_config() {
    local values=()
    [[ -f $SHELL_CONFIG_FILE ]] && mapfile -t values < <(jq -r '
        .appearance as $a | $a.wallpaperTheming as $w |
        $w.enableQtApps, $w.enableAppsAndShell, $a.themeTransition, $w.terminalGenerationProps.forceDarkMode,
        $a.palette.type, .background.wallpaperPath
        | if . == null then "" else tostring end' "$SHELL_CONFIG_FILE" 2>/dev/null)
    cfg_qt_apps=${values[0]-} cfg_apps_shell=${values[1]-} cfg_transition=${values[2]-} cfg_force_dark=${values[3]-}
    cfg_palette_type=${values[4]-} cfg_wallpaper=${values[5]-}
}

# A file picked in the dialog moves into the Wallpapers folder, so it shows in Settings' wallpaper list.
# Already in there: left where it is. A different file with the same name there: "name (2).jpg".
# The same file there already: that one is used and the picked copy stays. Prints where it ended up.
move_into_wallpapers() {
    local src=$1 dir=$2
    [[ -f $src && -d $dir ]] || { printf '%s\n' "$src"; return; }
    local real_dir; real_dir="$(realpath -- "$dir")"
    if [[ "$(realpath -- "$(dirname -- "$src")")" == "$real_dir"* ]]; then printf '%s\n' "$src"; return; fi
    local name base ext dest n=2
    name="$(basename -- "$src")"
    dest="$dir/$name"
    if [[ -e $dest ]] && cmp -s -- "$src" "$dest"; then printf '%s\n' "$dest"; return; fi
    if [[ $name == *.* ]]; then base=${name%.*} ext=".${name##*.}"; else base=$name ext=""; fi
    while [[ -e $dest ]]; do dest="$dir/$base ($n)$ext"; n=$((n + 1)); done
    if mv -n -- "$src" "$dest" 2>/dev/null; then printf '%s\n' "$dest"
    else printf '%s\n' "$src"; fi # Couldn't move it (read-only, another drive's permissions): use it in place
}

is_scheme() { local s; for s in "${SCHEMES[@]}"; do [[ $1 == "$s" ]] && return 0; done; return 1; }

is_video() {
    case "${1,,}" in *.mp4|*.webm|*.mkv|*.avi|*.mov) return 0 ;; *) return 1 ;; esac # ,,: also .MP4
}

# Offers a terminal that installs what's missing (dnf resolves /usr/bin/x to whichever package has it)
offer_install() {
    local title=$1 body=$2; shift 2
    local action
    action=$(notify-send -a "Wallpaper switcher" -c "im.error" -A "install=Install" "$title" "$body")
    [[ $action == install ]] && kitty -1 sudo dnf install "$@"
}

handle_kde_material_you_colors() {
    # Plasma's colour applier only exists on Plasma; skip when Qt app theming is off
    command -v plasma-apply-colorscheme >/dev/null 2>&1 || return
    [[ $cfg_qt_apps == false ]] && return
    local variant="scheme-tonal-spot"
    is_scheme "$type_flag" && variant="$type_flag"
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$variant"
}

check_and_prompt_upscale() {
    local img="$1" min_w min_h img_w img_h
    command -v identify &>/dev/null && [[ -f $img ]] || return
    is_video "$img" && return # Videos aren't checked
    read -r min_w min_h < <(hyprctl monitors -j | jq -r '"\([.[].width] | max) \([.[].height] | max)"')
    read -r img_w img_h < <(identify -format '%w %h' "${img}[0]" 2>/dev/null) # [0]: first frame (GIFs)
    [[ -n $img_w && -n $min_w ]] || return
    (( img_w < min_w || img_h < min_h )) || return
    local action
    action=$(notify-send -a "Wallpaper switcher" -A "upscale=Open Upscayl" "Upscale?" \
        "Image resolution (${img_w}x${img_h}) is lower than screen resolution (${min_w}x${min_h})")
    [[ $action == upscale ]] || return
    if command -v upscayl &>/dev/null; then
        nohup upscayl >/dev/null 2>&1 &
    elif flatpak info org.upscayl.Upscayl &>/dev/null; then
        nohup flatpak run org.upscayl.Upscayl >/dev/null 2>&1 &
    else
        action=$(notify-send -a "Wallpaper switcher" -A "install=Install from Flathub" "Install Upscayl?" \
            "It's not installed. It's on Flathub as org.upscayl.Upscayl")
        [[ $action == install ]] && kitty -1 flatpak install flathub org.upscayl.Upscayl \
            && nohup flatpak run org.upscayl.Upscayl >/dev/null 2>&1 &
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
# A video's first frame (colours and auto scheme detection read it). Named after the full path, so two
# videos with the same file name never share one, and reused while it's newer than the video
video_thumbnail() { printf '%s/%s.%s.jpg' "$THUMBNAIL_DIR" "$(basename "$1")" "$(printf '%s' "$1" | md5sum | cut -c1-8)"; }
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

# Run at login (execs) to bring a video wallpaper back; empty when the wallpaper is an image
write_restore_script() {
    local video_path=$1
    {
        echo '#!/bin/bash'
        echo "# Generated by switchwall.sh - Don't modify it by yourself."
        if [[ -n $video_path ]]; then
            echo "# Time: $(date)"
            echo
            echo 'pkill -f -9 mpvpaper'
            echo
            echo 'for monitor in $(hyprctl monitors -j | jq -r '"'"'.[] | .name'"'"'); do'
            printf '    mpvpaper -o %q "$monitor" %q &\n' "$VIDEO_OPTS" "$video_path"
            echo '    sleep 0.1'
            echo 'done'
        fi
    } >"$RESTORE_SCRIPT.tmp"
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

# Stores the wallpaper (and, for videos, its first-frame thumbnail) in the shell config, as ~/… paths
set_config_paths() {
    [[ -f $SHELL_CONFIG_FILE ]] || return
    jq --arg wall "${1/#$HOME\//\~/}" --arg thumb "${2/#$HOME\//\~/}" \
        '.background.wallpaperPath = $wall | if $thumb != "" then .background.thumbnailPath = $thumb end' \
        "$SHELL_CONFIG_FILE" >"$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
}

# GTK 4 apps read their colours once, when they start (flipping color-scheme doesn't make a running one
# re-read gtk.css; tested on GTK 4.22 / libadwaita 1.9). Two keep running with no window open, so even
# their next window had the old colours: Nautilus's background service, and the file picker portal (the
# FileChooser backend in xdg-desktop-portal/hyprland-portals.conf). Each is restarted only when nothing of
# its own is on screen. xdg-desktop-portal-gtk is left alone: it also tells apps about light/dark.
refresh_gtk_services() {
    local clients
    clients=$(hyprctl clients -j 2>/dev/null) || return 0
    has_window() { jq -e --arg c "$1" 'any(.[]; .class == $c)' <<<"$clients" >/dev/null; }
    if pgrep -x nautilus >/dev/null && ! has_window org.gnome.Nautilus; then
        nautilus -q 2>/dev/null
    fi
    if systemctl --user -q is-active xdg-desktop-portal-gnome && ! has_window xdg-desktop-portal-gnome; then
        systemctl --user restart xdg-desktop-portal-gnome
    fi
    return 0
}

# Smooth theme change (modules/themeTransition). prepare: the shell keeps its current look while the new
# colours are generated. reveal: the old wallpaper fades off the new one as the shell colours fade.
prepare_theme_transition() {
    [[ $cfg_transition == false ]] && return 0
    command -v qs >/dev/null || return 0
    qs -c "$QUICKSHELL_CONFIG_NAME" ipc call themeTransition prepare >/dev/null 2>&1 && THEME_TRANSITION=1
    return 0
}
reveal_theme_transition() {
    [[ -n "${THEME_TRANSITION:-}" ]] || return 0
    local cx cy
    read -r cx cy < <(hyprctl cursorpos -j 2>/dev/null | jq -r '"\(.x) \(.y)"') || true
    qs -c "$QUICKSHELL_CONFIG_NAME" ipc call themeTransition reveal "${cx:-960}" "${cy:-540}" >/dev/null 2>&1
    return 0
}

switch() {
    local imgpath="$1" mode_flag="$2" type_flag="$3" color_flag="$4" color="$5"
    local matugen_args gcm_args # gcm: generate_colors_material.py

    if [[ $color_flag == 1 ]]; then
        matugen_args=(color hex "$color")
        gcm_args=(--color "$color")
    else
        if [[ -z $imgpath ]]; then
            echo 'Aborted'
            exit 0
        fi
        # --noswitch (a light/dark toggle, say) only regenerates colours: the wallpaper stays as it is, so
        # don't ask about upscaling it again or restart a playing video (that flashed the desktop)
        local keep_wallpaper=""
        [[ -n $noswitch_flag ]] && keep_wallpaper=1
        if [[ -z $keep_wallpaper ]]; then
            check_and_prompt_upscale "$imgpath" &
            pkill -f -9 mpvpaper
        fi

        if is_video "$imgpath"; then
            local missing=() dep
            for dep in mpvpaper ffmpeg; do command -v "$dep" &>/dev/null || missing+=("/usr/bin/$dep"); done
            if (( ${#missing[@]} )); then
                offer_install "Can't switch to video wallpaper" "Missing: ${missing[*]##*/}" "${missing[@]}"
                exit 0
            fi
            local monitor
            if [[ -z $keep_wallpaper ]] || ! pgrep -x mpvpaper >/dev/null; then
                for monitor in $(hyprctl monitors -j | jq -r '.[] | .name'); do
                    mpvpaper -o "$VIDEO_OPTS" "$monitor" "$imgpath" &
                    sleep 0.1
                done
            fi
            # Colours come from the first frame (already extracted if auto scheme detection needed it)
            mkdir -p "$THUMBNAIL_DIR"
            local thumbnail
            thumbnail="$(video_thumbnail "$imgpath")"
            [[ $thumbnail -nt $imgpath ]] || ffmpeg -y -i "$imgpath" -vframes 1 "$thumbnail" 2>/dev/null
            if [[ ! -f $thumbnail ]]; then
                echo "Cannot create image to colorgen"
                set_config_paths "$imgpath"
                write_restore_script ""
                exit 1
            fi
            set_config_paths "$imgpath" "$thumbnail"
            write_restore_script "$imgpath"
            # Only the current video's frame is used: drop the ones from earlier video wallpapers
            find "$THUMBNAIL_DIR" -maxdepth 1 -type f ! -name "$(basename "$thumbnail")" -delete
            matugen_args=(image "$thumbnail")
            gcm_args=(--path "$thumbnail")
        else
            set_config_paths "$imgpath"
            write_restore_script ""
            rm -rf "$THUMBNAIL_DIR" # Image wallpaper: no video frames needed
            matugen_args=(image "$imgpath")
            gcm_args=(--path "$imgpath")
        fi
    fi

    # No mode given: keep the current one
    if [[ -z $mode_flag ]]; then
        [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" == "'prefer-dark'" ]] \
            && mode_flag=dark || mode_flag=light
    fi
    gsettings set org.gnome.desktop.interface color-scheme "prefer-$mode_flag"
    matugen_args+=(--mode "$mode_flag")
    [[ $cfg_force_dark == true ]] && gcm_args+=(--mode dark) || gcm_args+=(--mode "$mode_flag")
    [[ -n $type_flag ]] && matugen_args+=(--type "$type_flag") && gcm_args+=(--scheme "$type_flag")
    gcm_args+=(--termscheme)
    # Pick the first source colour rather than asking
    [[ ${matugen_args[0]} == image ]] && matugen_args+=(--source-color-index 0)

    if [[ $cfg_apps_shell == false ]]; then
        echo "App and shell theming disabled, skipping matugen and color generation"
        return
    fi

    # matugen (shell, apps) and the terminal/Qt palette are independent: generate both at once.
    # Both write color.txt (matugen through its KDE template); the Python one goes in last, as it always has
    mkdir -p "$GENERATED"
    matugen "${matugen_args[@]}" &
    local matugen_pid=$!
    "$PYTHON" "$SCRIPT_DIR/generate_colors_material.py" "${gcm_args[@]}" --cache "$GENERATED/color.txt.new" \
        >"$GENERATED/material_colors.scss.new" \
        && mv -f "$GENERATED/material_colors.scss.new" "$GENERATED/material_colors.scss"
    wait "$matugen_pid"
    [[ -f $GENERATED/color.txt.new ]] && mv -f "$GENERATED/color.txt.new" "$GENERATED/color.txt"
    "$SCRIPT_DIR"/applycolor.sh
    # Hyprland's border and background colours, set on the running Hyprland: they're written outside its config
    # folder (matugen/config.toml), so it doesn't reload everything and flash
    local hypr_live="$GENERATED/hyprland/colors-live.lua"
    # Without its comments: one starting with "--" would be taken as a hyprctl flag
    [[ -f $hypr_live ]] && hyprctl eval "$(grep -v '^[[:space:]]*--' -- "$hypr_live" | tr '\n' ' ')" >/dev/null 2>&1

    handle_kde_material_you_colors &
    refresh_gtk_services &
    # VS Code follows through matugen's hook (themes/vscode/apply-live.sh)
}

main() {
    local imgpath="" mode_flag="" type_flag="" color_flag="" color="" noswitch_flag=""
    read_config

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) mode_flag="$2"; shift 2 ;;
            --type) type_flag="$2"; shift 2 ;;
            --color)
                color_flag="1"
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    color="$2"; shift 2
                else
                    color=$(hyprpicker --no-fancy); shift
                fi
                ;;
            --image) imgpath="$2"; shift 2 ;;
            --noswitch)
                noswitch_flag="1"
                imgpath="${cfg_wallpaper/#\~\//$HOME/}" # Stored as ~/…
                shift
                ;;
            *) [[ -z $imgpath ]] && imgpath="$1"; shift ;;
        esac
    done

    type_flag="${type_flag:-${cfg_palette_type:-auto}}"
    if [[ $type_flag != auto ]] && ! is_scheme "$type_flag"; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    # No wallpaper, colour or --noswitch: ask for a file
    if [[ -z $imgpath && -z $color_flag && -z $noswitch_flag ]]; then
        local pictures wallpaper_dir
        pictures="$(xdg-user-dir PICTURES)"
        for wallpaper_dir in "$pictures/Wallpapers/showcase" "$pictures/Wallpapers" "$pictures"; do
            [[ -d $wallpaper_dir ]] && break
        done
        if command -v zenity &>/dev/null; then # Works better on Wayland than kdialog
            imgpath="$(zenity --file-selection --title='Choose wallpaper' --filename="$wallpaper_dir/")"
        elif command -v kdialog &>/dev/null; then
            cd "$wallpaper_dir" || return 1
            imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
        else
            notify-send "Wallpaper switcher" "No file dialog tool found. Install zenity or kdialog." -a "Wallpaper switcher"
            return 1
        fi
        [[ -n $imgpath ]] && imgpath="$(move_into_wallpapers "$imgpath" "$pictures/Wallpapers")"
    fi

    # From here nothing on screen changes until the reveal: hold the current look first, so the shell can
    # start loading the new wallpaper while the scheme is picked and the colours are made
    prepare_theme_transition

    # auto: pick the scheme that suits the image
    if [[ $type_flag == auto ]]; then
        local detected="" probe="$imgpath"
        if [[ -n $probe ]] && is_video "$probe"; then # The detector reads images: use the first frame
            probe="$(video_thumbnail "$imgpath")"
            [[ $probe -nt $imgpath ]] || { mkdir -p "$THUMBNAIL_DIR" && ffmpeg -y -i "$imgpath" -vframes 1 "$probe" 2>/dev/null; }
        fi
        [[ -n $probe && -f $probe ]] && detected="$("$PYTHON" "$SCRIPT_DIR"/scheme_for_image.py "$probe" 2>/dev/null | tr -d '\n')"
        if is_scheme "$detected"; then
            type_flag="$detected"
        else
            echo "[switchwall] Warning: Could not auto-detect a scheme, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color"
    reveal_theme_transition
}

main "$@"
