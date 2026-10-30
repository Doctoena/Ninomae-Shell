-- ┌────────────────────────────────────────────────────────────────────┐
-- │                                                                    │
-- │   __        ___           _                          _             │
-- │   \ \      / (_)_ __   __| | _____      ___ __ _   _| | ___  ___   │
-- │    \ \ /\ / /| | '_ \ / _` |/ _ \ \ /\ / / '__| | | | |/ _ \/ __|  │
-- │     \ V  V / | | | | | (_| | (_) \ V  V /| |  | |_| | |  __/\__ \  │
-- │      \_/\_/  |_|_| |_|\__,_|\___/ \_/\_/ |_|   \__,_|_|\___||___/  │
-- │                                                                    │
-- │                                                                    │
-- └────────────────────────────────────────────────────────────────────┘

-- Window rules live in Settings → Window rules: ~/.config/ninomae-shell/window-rules.json (yours, not in git),
-- first copied from window-rules.default.json beside it (the shipped ones). The shell writes them to the Lua
-- file loaded at the end of this one. Workspace and layer rules stay here

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- Quickshell launcher (Super + E) animates itself (drawer sliding out of the bar);
-- Hyprland's layer pop-in on top of that made the start look detached.
hl.layer_rule({
    name    = "launcher-no-anim",
    match   = { namespace = [[^quickshell:(overview|barDrawer|sidebarRight|gamelauncher|mediaControls|notificationPopup|onScreenDisplay|trayMenu|reloadPopup|session)$]] }, -- drawers animate themselves
    no_anim = true,
})

-- The window rules, written by the shell (services/WindowRules.qml) from window-rules.json
pcall(dofile, os.getenv("HOME") .. "/.local/state/quickshell/user/window_rules.lua")
