-- Keyboard layout: the one place it's set. Hyprland reads it (general.lua), the login screen uses
-- the same layout (themes/sddm/install-theme.sh reads this file), and the shortcuts follow it
-- (keymap.lua). This is the default: your own copy is keyboard.lua beside it, which git ignores.
-- ./install.sh and Settings → Input write it.
--   layout  = an xkb layout code: "us", "de", "fr", "gb"… (the list: /usr/share/X11/xkb/rules/evdev.lst)
--   variant = one of its variants, or "" for the standard one: "dvorak", "colemak", "nodeadkeys"…
return {
    layout  = "us",
    variant = "",
}
