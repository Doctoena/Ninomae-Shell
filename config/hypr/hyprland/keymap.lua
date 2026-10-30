-- The keybinds in keybinds.lua are written for Dvorak. With QWERTY picked (keyboard.lua), every
-- key is swapped for the QWERTY key at the same physical position, so each shortcut stays on the
-- same key under your fingers: Super+L (lock) becomes Super+P, Super+O (sidebar) Super+S, and so on.
-- Modifiers, numbers (bound by keycode), arrows, F-keys and media keys are the same on both.

local M = {}

-- Dvorak key → the QWERTY key in the same place (xkb keysym names, lowercase)
local dvorakToQwerty = {
    -- Top row:    ' , . p y f g c r l / =   →   q w e r t y u i o p [ ]
    apostrophe = "Q", comma = "W", period = "E", p = "R", y = "T", f = "Y", g = "U", c = "I",
    r = "O", l = "P", slash = "BracketLeft", equal = "BracketRight",
    -- Home row:   a o e u i d h t n s -     →   a s d f g h j k l ; '
    a = "A", o = "S", e = "D", u = "F", i = "G", d = "H", h = "J", t = "K", n = "L",
    s = "Semicolon", minus = "Apostrophe",
    -- Bottom row: ; q j k x b m w v z       →   z x c v b n m , . /
    semicolon = "Z", q = "X", j = "C", k = "V", x = "B", b = "N", m = "M", w = "Comma",
    v = "Period", z = "Slash",
    -- Number row: [ ]                       →   - =
    bracketleft = "Minus", bracketright = "Equal",
}

-- translate("SUPER + SHIFT + O", "") → "SUPER + SHIFT + S" when not on Dvorak; unchanged on Dvorak
function M.translate(combo, variant)
    if variant == "dvorak" then return combo end
    local mods, key = combo:match("^(.*%+%s*)([^+]-)%s*$")
    if not key then mods, key = "", combo end -- A bare key, no modifiers
    local mapped = dvorakToQwerty[key:lower()]
    return mapped and (mods .. mapped) or combo
end

return M
