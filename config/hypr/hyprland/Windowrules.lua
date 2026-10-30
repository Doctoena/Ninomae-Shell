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

-- Transparent windows
hl.window_rule({
    name  = "transparent-apps",
    match = { class = [[^(com\.microsoft\.VSCode|kitty|discord|vesktop|org\.gnome\.(Nautilus|Loupe)|xdg\-desktop-portal-gtk|net\.lutris\.Lutris|steam|com\.github\.th_ch\.youtube_music)$]] },
    opacity = "0.94 override 0.94 override",
})
hl.window_rule({ -- The shell's Settings app, like the apps above (matched by title: its class is Quickshell's)
    name  = "transparent-settings",
    match = { title = [[^(Ninomae Settings)$]] },
    opacity = "0.94 override 0.94 override",
})

-- Disable blur for xwayland context menus
hl.window_rule({
    name  = "xwayland-no-blur",
    match = { xwayland = true },
    no_blur = true,
})

-- Floating dialogs - common file/folder dialogs
hl.window_rule({
    name  = "file-dialogs",
    match = { title = [[^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File Upload)(.*)$]] },
    float  = true,
    center = true,
})
hl.window_rule({
    name  = "wallpaper-chooser-size",
    match = { title = [[^(Choose wallpaper)(.*)$]] },
    size  = "60% 65%",
})
hl.window_rule({
    name  = "browser-save-open-dialogs",
    match = { title = [[^(.*)(wants to save|wants to open)$]] },
    float  = true,
    center = true,
})
hl.window_rule({
    name  = "pavucontrol",
    match = { class = [[^(pavucontrol|org\.pulseaudio\.pavucontrol)$]] },
    float  = true,
    size   = "75% 75%",
    center = true,
})
hl.window_rule({
    name  = "nm-connection-editor",
    match = { class = [[^(nm-connection-editor)$]] },
    float  = true,
    size   = "45% 50%",
    center = true,
})
hl.window_rule({ -- The Bluetooth menu's Settings button
    name   = "blueman-manager",
    match  = { class = [[^(blueman-manager)$]] },
    float  = true,
    size   = "45% 50%",
    center = true,
})
hl.window_rule({ name = "plasmawindowed",   match = { class = [[^.*plasmawindowed.*$]] }, float = true })
hl.window_rule({ name = "kcm",              match = { class = [[^kcm_.*$]] },              float = true })
hl.window_rule({ name = "bluedevilwizard",  match = { class = [[^.*bluedevilwizard$]] },   float = true })
hl.window_rule({ name = "welcome",          match = { title = [[^.*Welcome$]] },           float = true })
hl.window_rule({ name = "shell-conflicts",  match = { title = [[^.*Shell conflicts.*$]] }, float = true })
hl.window_rule({
    name  = "kde-portal",
    match = { class = [[^org\.freedesktop\.impl\.portal\.desktop\.kde$]] },
    float = true,
    size  = "60% 65%",
})


-- kde-material-you-colors spawns a window when changing dark/light theme.
-- This is to make sure it doesn't interfere at all.
hl.window_rule({
    name  = "plasma-changeicons",
    match = { class = [[^(plasma-changeicons)$]] },
    float            = true,
    no_initial_focus = true,
    move             = "999999 999999",
})

-- Steam's "Starting game" dialog: the shell's launch splash (modules/gameLauncher/LaunchSplash.qml)
-- already shows the launch and update progress. Moved off-screen, not closed: closing it may cancel the launch
hl.window_rule({
    name  = "steam-launching-dialog",
    match = { class = [[^steam$]], title = [[^Launching\.\.\.$]] },
    float            = true,
    no_initial_focus = true,
    no_anim          = true,
    move             = "999999 999999",
})

-- Picture-in-Picture
hl.window_rule({
    name  = "picture-in-picture",
    match = { title = [[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]] },
    float             = true,
    keep_aspect_ratio = true,
    move              = "73% 72%",
    size              = "25% 28%",
    pin               = true,
})


-- --- Tearing ---
hl.window_rule({ name = "tearing-exe",       match = { title = [[.*\.exe]] },        immediate = true })
hl.window_rule({ name = "tearing-steam-app", match = { class = [[^(steam_app).*]] }, immediate = true })

-- --- Idle ---
-- Any fullscreen window keeps the screen on: hypridle would otherwise lock after 5 min and suspend after 15
-- during a game played on a controller (Proton/Lutris games don't ask to stay awake) or a video
hl.window_rule({ name = "idle-inhibit-fullscreen", match = { class = [[.*]] }, idle_inhibit = "fullscreen" })


-- Fix Jetbrain IDEs focus/rerendering problem
hl.window_rule({
    name  = "jetbrains-focus-fix",
    match = {
        class = [[^jetbrains-.*$]],
        float = true,
        title = [[^$|^\s$|^win\d+$]],
    },
    no_initial_focus = true,
})

-- No shadow for tiled windows (matches windows that are not floating).
hl.window_rule({
    name  = "tiled-no-shadow",
    match = { float = false },
    no_shadow = true,
})

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- Quickshell launcher (Super + E) animates itself (drawer sliding out of the bar);
-- Hyprland's layer pop-in on top of that made the start look detached.
hl.layer_rule({
    name    = "launcher-no-anim",
    match   = { namespace = [[^quickshell:(overview|barDrawer|sidebarRight|gamelauncher|mediaControls|notificationPopup|onScreenDisplay|trayMenu|reloadPopup|session)$]] }, -- drawers animate themselves
    no_anim = true,
})
