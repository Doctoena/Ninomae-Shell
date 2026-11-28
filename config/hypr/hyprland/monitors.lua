-- ┌─────────────────────────────────────────┐
-- │   __  __             _ _                │
-- │  |  \/  | ___  _ __ (_) |_ ___  _ __ ___ │
-- │  | |\/| |/ _ \| '_ \| | __/ _ \| '__/ __|│
-- │  | |  | | (_) | | | | | || (_) | |  \__ \│
-- │  |_|  |_|\___/|_| |_|_|\__\___/|_|  |___/│
-- │                                          │
-- └─────────────────────────────────────────┘
-- One rule for every screen, on every machine: its highest resolution (at the fastest refresh rate
-- that has), placed next to the others, at 100%. Nothing here to edit per machine.
-- Settings → Display changes a screen from there. It's saved by the monitor's name
-- (ninomae-shell/displays.json), so the settings follow that monitor to any computer, and the shell
-- re-applies them over this after every config reload.

hl.monitor({
    output   = "",
    mode     = "highres",
    position = "auto",
    scale    = 1,
})
