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

## Interactive shells

# No greeting (-g: set for this session, not saved into fish_variables)
set -g fish_greeting ""

if status is-interactive
    # Terminal colours from the current wallpaper (Quickshell regenerates this file on wallpaper change;
    # kitty.conf has no palette of its own). string collect: fish's own, so no cat process per shell
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
# -g: add for this session only; without it the path is saved into fish_variables (which is in the repo)
test -d ~/.opencode/bin; and fish_add_path -g ~/.opencode/bin
