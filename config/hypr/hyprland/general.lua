-- .-----------------------------------------.
-- |                                         |
-- |     ____                           _    |
-- |    / ___| ___ _ __   ___ _ __ __ _| |   |
-- |   | |  _ / _ \ '_ \ / _ \ '__/ _` | |   |
-- |   | |_| |  __/ | | |  __/ | | (_| | |   |
-- |    \____|\___|_| |_|\___|_|  \__,_|_|   |
-- |                                         |
-- |                                         |
-- '-----------------------------------------'

-- Monitor layout & per-monitor workspace assignment now live in monitors.lua,
-- since they depend on which machine this is (laptop vs shitbox).

local keyboard = require("hyprland/keyboard")

hl.config({
    -- General settings
    general = {
        -- Gaps
        gaps_in         = 4,
        gaps_out        = 5,
        gaps_workspaces = 50,

        -- Border settings
        border_size      = 2,
        -- Border colors set in colors.lua
        resize_on_border = true,

        no_focus_fallback = true,

        allow_tearing = true, -- Allows the `immediate` window rule to work

        -- Snap settings
        snap = {
            enabled      = true,
            window_gap   = 4,
            monitor_gap  = 5,
            respect_gaps = true,
        },
    },

    -- Tiling settings
    dwindle = {
        preserve_split = true,
    },

    -- Window decoration settings
    decoration = {
        rounding = 8, -- Window Rounding

        blur = {
            enabled                   = true,
            xray                      = false,
            special                   = false,
            size                      = 4,
            passes                    = 2,
            brightness                = 1,
            noise                     = 0.04,
            contrast                  = 1,
            popups                    = true,
            popups_ignorealpha        = 0.6,
            input_methods             = true,
            input_methods_ignorealpha = 0.8,
        },

        shadow = {
            enabled      = true,
            range        = 20,
            offset       = "0 2",
            render_power = 4,
            color        = "rgba(00000010)",
        },

        -- Dim inactive windows
        dim_inactive = true,
        dim_strength = 0.025,
        dim_special  = 0.07,
    },

    animations = {
        enabled = true,
    },

    -- Input settings (keyboard & Mouse). Settings → Input overrides the keyboard repeat, mouse and touchpad
    -- options live (services/DeviceSettings.qml), so change them there; these only apply without the shell
    input = {
        kb_layout          = keyboard.layout,  -- Set in keyboard.lua (Dvorak or QWERTY)
        kb_variant         = keyboard.variant,
        numlock_by_default = true,
        repeat_delay       = 250,
        repeat_rate        = 35,

        accel_profile          = "flat", -- No pointer acceleration (Settings → Input → Mouse can change it)
        follow_mouse           = 1,
        off_window_axis_events = 2,
    },

    -- Miscellaneous settings
    misc = {
        disable_hyprland_logo      = true,
        disable_splash_rendering   = true,
        mouse_move_enables_dpms    = true,
        key_press_enables_dpms     = true,
        allow_session_lock_restore = true,
        session_lock_xray          = true,
        initial_workspace_tracking = 0,
        focus_on_activate          = true,
    },

    -- Debug settings
    debug = {
        vfr = true,
    },

    -- Misc bindings
    binds = {
        scroll_event_delay               = 0,
        hide_special_on_workspace_change = true,
    },

    -- Cursor settings
    cursor = {
        hotspot_padding = 1,
    },
})

-- Animation settings
-- Curves
hl.curve("emphasizedDecel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1}     } })
hl.curve("emphasizedAccel", { type = "bezier", points = { {0.3, 0},    {0.8, 0.15}  } })
hl.curve("menu_decel",      { type = "bezier", points = { {0.1, 1},    {0, 1}       } })
hl.curve("layer_exit",      { type = "bezier", points = { {0.3, 0},    {1, 1}       } }) -- Starts moving at once

-- windows
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 3,  bezier = "emphasizedDecel", style = "popin 80%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2,  bezier = "emphasizedDecel", style = "popin 90%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3,  bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "emphasizedDecel" })

-- layers
hl.animation({ leaf = "layersIn",  enabled = true, speed = 2.7, bezier = "emphasizedDecel", style = "popin 93%" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.6, bezier = "layer_exit",      style = "popin 94%" })

-- fade
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 0.5, bezier = "menu_decel" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.6, bezier = "layer_exit" })

-- workspaces
hl.animation({ leaf = "workspaces", enabled = true, speed = 7, bezier = "menu_decel", style = "slide" })

-- specialWorkspace
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2.8, bezier = "emphasizedDecel", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.2, bezier = "emphasizedAccel", style = "slidevert" })
