-- .---------------------------------------------------.
-- |                                                   |
-- |   _   _                  _                    _   |
-- |  | | | |_   _ _ __  _ __| |    __ _ _ __   __| |  |
-- |  | |_| | | | | '_ \| '__| |   / _` | '_ \ / _` |  |
-- |  |  _  | |_| | |_) | |  | |__| (_| | | | | (_| |  |
-- |  |_| |_|\__, | .__/|_|  |_____\__,_|_| |_|\__,_|  |
-- |         |___/|_|                                  |
-- |                                                   |
-- '---------------------------------------------------'

-- Hyprland Main Config (Lua, Hyprland 0.55+)
-- Shared values (like the Quickshell config name) live in hyprland/vars.lua

hl.on("hyprland.start", function()
    -- DO NOT REMOVE THIS OR YOU WON'T BE ABLE TO USE ANY KEYBIND.
    -- All binds live inside the "global" submap (see keybinds.lua),
    -- which is required for the catchall bind to work.
    hl.dispatch(hl.dsp.submap("global"))
end)

-- Load config files
require("hyprland/env")
require("hyprland/execs")
require("hyprland/monitors")
require("hyprland/general")
require("hyprland/Windowrules")
require("hyprland/colors")
require("hyprland/keybinds")
