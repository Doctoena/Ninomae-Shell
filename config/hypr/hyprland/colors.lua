-- The wallpaper's colours (borders, background, pinned windows, hyprbars). matugen writes them outside this
-- folder, to ~/.local/state/quickshell/user/generated/hyprland/colors.lua: a write in here makes Hyprland
-- reload its whole config, which flashed the screen on every wallpaper change. This loads them at start and
-- on reloads; switchwall.sh applies new ones to the running Hyprland itself (colors-live.lua, hyprctl eval).
local ok, err = pcall(dofile, os.getenv("HOME") .. "/.local/state/quickshell/user/generated/hyprland/colors.lua")
if not ok then
    -- Not made yet (a fresh install before the first wallpaper): Hyprland's defaults until then
    hl.config({ general = { col = { active_border = "rgba(888888AA)", inactive_border = "rgba(44444488)" } } })
end
