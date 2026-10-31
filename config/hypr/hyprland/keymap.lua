-- The keyboard layout (keyboard.lua, else keyboard.default.lua) and how the shortcuts follow it.
--
-- The keybinds in keybinds.lua are written for US Dvorak. On any other layout, every key is swapped
-- for the US QWERTY key at the same physical position, so each shortcut stays on the same key under
-- your fingers: Super+L (lock) becomes Super+P, Super+O (sidebar) Super+S, and so on.
-- Letters are bound by name, so on German or French they're the key with that letter printed on it.
-- Punctuation (- = [ ] ; ' , . /) is bound by position (code:NN) away from plain US layouts, as many
-- layouts don't have those keys without AltGr: Settings → Keybinds shows them as your layout prints them.
-- Modifiers, numbers (bound by keycode), arrows, F-keys and media keys are the same everywhere.

local M = {}

local dir = os.getenv("HOME") .. "/.config/hypr/hyprland/"
-- dofile, not require: a Hyprland reload must see a layout Settings has just written
function M.load()
    for _, file in ipairs({ "keyboard.lua", "keyboard.default.lua" }) do
        local ok, kb = pcall(dofile, dir .. file)
        if ok and type(kb) == "table" and kb.layout then
            return { layout = kb.layout, variant = kb.variant or "" }
        end
    end
    return { layout = "us", variant = "" }
end

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
-- QWERTY punctuation → its xkb keycode (the same physical key on every layout)
local positions = {
    minus = 20, equal = 21, bracketleft = 34, bracketright = 35, semicolon = 47,
    apostrophe = 48, comma = 59, period = 60, slash = 61,
}

local function isDvorak(kb) return kb.layout == "us" and kb.variant == "dvorak" end
-- Plain US keyboards have every punctuation key on its own: no need to bind by position
local function isPlainUs(kb) return kb.layout == "us" and kb.variant == "" end

-- translate("SUPER + SHIFT + O", kb) → "SUPER + SHIFT + S" off Dvorak; unchanged on Dvorak
function M.translate(combo, kb)
    if isDvorak(kb) then return combo end
    local mods, key = combo:match("^(.*%+%s*)([^+]-)%s*$")
    if not key then mods, key = "", combo end -- A bare key, no modifiers
    local mapped = dvorakToQwerty[key:lower()]
    if not mapped then return combo end
    local code = positions[mapped:lower()]
    if code and not isPlainUs(kb) then return mods .. "code:" .. code end
    return mods .. mapped
end

return M
