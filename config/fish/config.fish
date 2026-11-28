# Fish Config

## Aliases

# DNF Package Manager Aliases
alias install="sudo dnf install"
alias update="sudo dnf update"
alias remove="sudo dnf remove"
alias search="dnf search"
alias clean="sudo dnf clean all"
alias autoremove="sudo dnf autoremove"

# Ls Replacement
alias ls="lsd"
alias ll="lsd -l"

# fastfetch: in a terminal too narrow for the logo beside the info (116 columns: half a 1080p screen is about
# 105), a 40-column copy of the logo (ascii-narrow.txt) with less padding, so nothing wraps
function fastfetch --wraps fastfetch
    if test "$COLUMNS" -lt 116
        command fastfetch --logo ~/.config/fastfetch/ascii-narrow.txt --logo-padding-left 2 --logo-padding-right 3 $argv
    else
        command fastfetch $argv
    end
end

# ninomae update: pull the latest Ninomae-Shell, install what's new, keep your settings
# ninomae check: see if everything is in place (changes nothing)
function ninomae --description "Update or check Ninomae-Shell"
    switch "$argv[1]"
        case update
            ~/Ninomae-Shell/install.sh --update $argv[2..]
        case check
            ~/Ninomae-Shell/install.sh --check $argv[2..]
        case '*'
            echo "Usage: ninomae update | check"
            return 1
    end
end

## Interactive shells

# No greeting (-g: set for this session, not saved into fish_variables)
set -g fish_greeting ""

if status is-interactive
    # Terminal colours from the current wallpaper (Quickshell regenerates this file on wallpaper change;
    # kitty also loads them from kitty.conf, these update windows already open). string collect: fish's own,
    # so no cat process per shell
    set -l sequences ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    test -f $sequences; and string collect <$sequences

    # Prompt: the user name in the theme's lavender (fish's default, bright green, is a near-white lavender
    # in this palette, too close to the host name). A palette name, so it follows the wallpaper
    set -g fish_color_user green

    # File name colours for lsd, fish completions and anything else reading LS_COLORS, as palette numbers so
    # they follow the theme: folders lavender, executables pink, links grey-lavender, broken links salmon,
    # pipes/sockets/devices light pink. Everything else stays the text colour
    set -gx LS_COLORS "di=1;32:ex=1;35:ln=36:or=31:mi=31:pi=33:so=33:bd=33:cd=33:su=1;35:sg=1;35:tw=1;32:ow=1;32"
end

## Paths and completions

# OpenClaw completions (only if OpenClaw is installed on this machine). Added to fish's completion path
# rather than sourced, so fish loads them the first time openclaw is completed, not on every new shell
test -d ~/.openclaw/completions; and set -g fish_complete_path ~/.openclaw/completions $fish_complete_path

# Rust (rustup, installed with --no-modify-path so it doesn't write into conf.d)
test -d ~/.cargo/bin; and fish_add_path -g ~/.cargo/bin

# opencode
# -g: add for this session only; without it the path is saved into fish_variables
test -d ~/.opencode/bin; and fish_add_path -g ~/.opencode/bin
