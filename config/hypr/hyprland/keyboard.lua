-- Keyboard layout: the one place it's set. Hyprland reads it (general.lua), the login screen uses
-- the same layout (themes/sddm/install-theme.sh reads this file), and the shortcuts follow it:
-- they're written for Dvorak, and on QWERTY each moves to the key in the same physical place
-- (keymap.lua). ./install.sh asks which one you want and writes it here.
--   variant = "dvorak"  → US Dvorak
--   variant = ""        → regular US QWERTY
return {
    layout  = "us",
    variant = "dvorak",
}
