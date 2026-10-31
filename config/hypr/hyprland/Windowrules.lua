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

-- Window rules live in Settings → Window rules: the shipped ones in ~/.config/ninomae-shell/window-rules.default.json,
-- your changes to them and your own rules in window-rules.json beside it (not in git). The shell writes them to the
-- Lua file loaded at the end of this one. Workspace and layer rules stay here

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- The shell's drawers and popups (launcher, sidebar, OSD…) animate themselves;
-- Hyprland's layer pop-in on top of that made them look detached.
hl.layer_rule({
    name    = "drawers-no-anim",
    match   = { namespace = [[^quickshell:(overview|barDrawer|sidebarRight|gamelauncher|mediaControls|notificationPopup|onScreenDisplay|trayMenu|reloadPopup|session)$]] },
    no_anim = true,
})

-- The window rules, written by the shell (services/WindowRules.qml)
pcall(dofile, os.getenv("HOME") .. "/.local/state/quickshell/user/window_rules.lua")
