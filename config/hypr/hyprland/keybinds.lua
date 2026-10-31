-- ┌─────────────────────────────────────────────┐
-- │                                             │
-- │    _  __          _     _           _       │
-- │   | |/ /___ _   _| |__ (_)_ __   __| |___   │
-- │   | ' // _ \ | | | '_ \| | '_ \ / _` / __|  │
-- │   | . \  __/ |_| | |_) | | | | | (_| \__ \  │
-- │   |_|\_\___|\__, |_.__/|_|_| |_|\__,_|___/  │
-- │             |___/                           │
-- │                                             │
-- └─────────────────────────────────────────────┘

local qs      = require("hyprland/vars").qsConfig
local scripts = "~/.config/hypr/hyprland/scripts/"

-- Binds are written for Dvorak. On any other layout (keyboard.lua), each key moves to the QWERTY key
-- in the same physical place (keymap.lua), so the shortcuts stay where your fingers expect them
local keymap = require("hyprland/keymap")
local keyboard = keymap.load()
-- Your changes from Settings → Keybinds (the shell writes them: services/KeybindOverrides.qml). `changed` maps a
-- bind's description to new keys (as Hyprland sees them, so not translated) or to false for turned off.
-- `added` are your own shortcuts that run a command
local user = (function()
    local ok, t = pcall(dofile, os.getenv("HOME") .. "/.local/state/quickshell/user/keybinds.lua")
    return (ok and type(t) == "table") and t or {}
end)()
local changed = user.changed or {}
local function bind(combo, dispatcher, opts)
    local new = opts and opts.description and changed[opts.description]
    if new == false then return end
    if type(new) == "string" then return hl.bind(new, dispatcher, opts) end
    return hl.bind(keymap.translate(combo, keyboard), dispatcher, opts)
end

-- Small helpers to keep the binds readable
local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
local function global(name) return hl.dsp.global("quickshell:" .. name) end
-- Run cmd only when the shell isn't running (`ipc show` exits non-zero without an instance)
local function qsAliveOr(cmd) return exec("qs -c " .. qs .. " ipc show >/dev/null 2>&1 || " .. cmd) end

-- Workspace groups of 10: pressing N goes to workspace N *within the current
-- group of 10*. This replaces scripts/workspace_action.sh, done natively in Lua.
local function wsInGroup(n)
    local ws  = hl.get_active_workspace()
    local cur = (ws and ws.id) or 1
    if cur < 1 then cur = 1 end -- special workspaces have negative ids
    return math.floor((cur - 1) / 10) * 10 + n
end

local function goToWorkspace(n)
    return function() hl.dispatch(hl.dsp.focus({ workspace = wsInGroup(n) })) end
end

local function moveToWorkspace(n, follow)
    return function() hl.dispatch(hl.dsp.window.move({ workspace = wsInGroup(n), follow = follow })) end
end

-- Keycodes for the number keys 1..0: top row and keypad
local numberRow = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local keypad    = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }

local fuzzelFallback = [[pkill fuzzel || fuzzel -m $(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')]]

-- Everything lives in the "global" submap (activated on startup in hyprland.lua).
-- catchall binds are only allowed inside a submap.
hl.define_submap("global", function()

    ---- Shell Binds: these absolutely need to be on top, or they won't work consistently ----
    -- Lets Quickshell show the Caps Lock OSD without polling (key still reaches apps)
    bind("Caps_Lock", global("capsLock"), { non_consuming = true, ignore_mods = true, description = "[hidden] Caps Lock OSD" })
    -- The gameplay clip key (` by default), as Settings → Games sets it: the shell (services/GameClips.qml)
    -- writes it to ~/.local/state/quickshell/user/clip_key.lua ("" with clips off) and reloads Hyprland
    -- when it changes. Never bound or unbound at runtime: removing a bind through hyprctl eval crashed
    -- Hyprland (0.56.2, keybindRemove). Pass-through: the key still types everywhere; dont_inhibit: it
    -- works while a game holds the keyboard
    do
        local ok, key = pcall(dofile, os.getenv("HOME") .. "/.local/state/quickshell/user/clip_key.lua")
        if not ok or type(key) ~= "string" then key = "grave" end
        if key ~= "" then
            hl.bind(key, global("clipSave"), { non_consuming = true, dont_inhibit = true,
                description = "Shell: Save gameplay clip (while a game runs)" })
        end
    end

    -- Crosshair overlay (services/Crosshair.qml): dont_inhibit, so it works while a game holds the keyboard
    bind("SUPER + G", global("crosshairToggle"), { dont_inhibit = true, description = "Shell: Show/hide crosshair" })
    bind("SUPER + E",       global("overviewToggle"), { description = "Shell: Toggle overview/launcher" })
    bind("SUPER + Super_R", global("overviewToggle"), { description = "[hidden] Toggle overview/launcher (alt)" })
    -- Use fallback launch logic when Quickshell is unavailable.
    bind("SUPER + E",       qsAliveOr(fuzzelFallback), { description = "[hidden] Launch overview/launcher" })
    bind("SUPER + Super_R", qsAliveOr(fuzzelFallback), { description = "[hidden] Launch overview/launcher (alt)" })
    -- Interrupt overview toggle on any Super combo (catchall, ctrl, mouse buttons, scroll)
    -- NOTE: the old `Super, catchall` bind was removed. In the Lua config, catchall
    -- can't be combined with modifiers, and a bare catchall would swallow ALL
    -- typing. (Upstream dropped it too.)
    bind("CTRL + Super_L",   global("overviewToggleReleaseInterrupt"))
    bind("CTRL + Super_R",   global("overviewToggleReleaseInterrupt"))
    for button = 272, 277 do
        bind("SUPER + mouse:" .. button, global("overviewToggleReleaseInterrupt"))
    end
    bind("SUPER + mouse_up",   global("overviewToggleReleaseInterrupt"))
    bind("SUPER + mouse_down", global("overviewToggleReleaseInterrupt"))


    -- Workspace number binds
    bind("Super_L", global("workspaceNumber"))
    bind("Super_R", global("workspaceNumber"))

    -- Game launcher
    bind("SUPER + SHIFT + O", global("gameLauncher"), { description = "Shell: Toggle game launcher" })


    -- Quickshell toggles & binds
    bind("SUPER + J", global("barToggle"),          { description = "Shell: Toggle bar" })
    bind("SUPER + O", global("sidebarRightToggle"), { description = "Shell: Toggle right sidebar" })
    bind("CTRL + ALT + Delete", global("sessionToggle"), { description = "Shell: Power menu" })
    -- Also catches a Qt update since login: rebuilds the drawer plugin in the background and offers another restart
    bind("CTRL + SUPER + R", exec("~/.config/quickshell/plugins/ninomae-blobs/ensure-built.sh & ~/.config/hypr/hyprland/scripts/restart_shell.sh " .. qs), { description = "Shell: Restart the shell" })


    -- Clipboard binds
    bind("SUPER + V",      global("overviewClipboardToggle"), { description = "Shell: Clipboard history" })
    bind("SUPER + Period", global("overviewEmojiToggle"),     { description = "Shell: Emoji picker" })


    -- Volume and Media binds (locked = also work on the lock screen)
    local muteOut = exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
    local muteIn  = exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
    bind("XF86AudioRaiseVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Media: Increase volume" })
    bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true, description = "Media: Decrease volume" })
    bind("XF86AudioMute",        muteOut,                                           { locked = true, description = "[hidden] Mute/unmute output audio" })
    bind("XF86AudioMicMute",     muteIn,                                            { locked = true, description = "[hidden] Mute/unmute input audio" })
    bind("XF86AudioPlay",        exec("playerctl play-pause"),                      { locked = true, description = "Media: Play/pause media" })
    bind("XF86AudioNext",        exec("playerctl next"),                            { locked = true, description = "Media: Next track" })
    bind("XF86AudioPrev",        exec("playerctl previous"),                        { locked = true, description = "Media: Previous track" })
    bind("SUPER + SHIFT + M",    muteOut,                                           { locked = true, description = "Media: Mute/unmute output audio" })
    bind("SUPER + ALT + M",      muteIn,                                            { locked = true, description = "Media: Mute/unmute input audio" })


    ---- Window management ----
    -- Moving and resizing windows
    bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Window: Move" })
    bind("SUPER + mouse:274", hl.dsp.window.drag(),   { mouse = true, description = "Window: Move" })
    bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Window: Resize" })

    -- Focus window in direction = Super, ←/↑/→/↓
    bind("SUPER + Left",         hl.dsp.focus({ direction = "left" }),  { description = "Window: Focus left" })
    bind("SUPER + Right",        hl.dsp.focus({ direction = "right" }), { description = "Window: Focus right" })
    bind("SUPER + Up",           hl.dsp.focus({ direction = "up" }),    { description = "Window: Focus up" })
    bind("SUPER + Down",         hl.dsp.focus({ direction = "down" }),  { description = "Window: Focus down" })
    bind("SUPER + BracketLeft",  hl.dsp.focus({ direction = "left" }))
    bind("SUPER + BracketRight", hl.dsp.focus({ direction = "right" }))

    -- Move window in direction = Super+Shift, ←/↑/→/↓
    bind("SUPER + SHIFT + Left",  hl.dsp.window.move({ direction = "left" }), { description = "Window: Move left" })
    bind("SUPER + SHIFT + Right", hl.dsp.window.move({ direction = "right" }), { description = "Window: Move right" })
    bind("SUPER + SHIFT + Up",    hl.dsp.window.move({ direction = "up" }), { description = "Window: Move up" })
    bind("SUPER + SHIFT + Down",  hl.dsp.window.move({ direction = "down" }), { description = "Window: Move down" })


    -- Window split (layoutmsg for dwindle layout)
    bind("SUPER + Semicolon",  hl.dsp.layout("preselect l"), { repeating = true, description = "Window: Preselect left" })
    bind("SUPER + Apostrophe", hl.dsp.layout("preselect r"), { repeating = true, description = "Window: Preselect right" })


    -- Window state
    bind("SUPER + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }),                 { description = "Window: Float/Tile" })
    bind("SUPER + D",             hl.dsp.window.fullscreen({ mode = "maximized" }),           { description = "Window: Maximize" })
    bind("SUPER + F",             hl.dsp.window.fullscreen({ mode = "fullscreen" }),          { description = "Window: Fullscreen" })
    bind("SUPER + ALT + F",       hl.dsp.window.fullscreen_state({ internal = 0, client = 3, action = "toggle" }), { description = "Window: Fullscreen spoof" })
    bind("SUPER + SHIFT + P",     hl.dsp.window.pin(),                                        { description = "Window: Pin" })


    -- Screen Zoom Binds (Quickshell animates the zoom; the script is the fallback when it isn't running)
    local zoomOut = exec("qs -c " .. qs .. " ipc call zoom zoomOut || " .. scripts .. "zoom.sh decrease 0.1")
    local zoomIn  = exec("qs -c " .. qs .. " ipc call zoom zoomIn || "  .. scripts .. "zoom.sh increase 0.1")
    bind("SUPER + Minus",   zoomOut, { repeating = true, description = "Screen: Zoom out" })
    bind("SUPER + Equal",   zoomIn,  { repeating = true, description = "Screen: Zoom in" })
    bind("SUPER + code:82", zoomOut, { repeating = true, description = "[hidden] Zoom out (keypad)" })
    bind("SUPER + code:86", zoomIn,  { repeating = true, description = "[hidden] Zoom in (keypad)" })


    -- Workspace number binds, relative to the current group of 10 (number row and keypad)
    --   Super+N          go to workspace N
    --   Super+Shift+N    move window to workspace N and follow
    --   Super+Alt+N      move window to workspace N silently
    for n = 1, 10 do
        for _, code in ipairs({ numberRow[n], keypad[n] }) do
            -- Only list one of each on the Keybinds settings page
            local function desc(text) return (n == 1 and code == numberRow[1]) and text or "[hidden]" end
            bind("SUPER + code:" .. code,         goToWorkspace(n),          { description = desc("Workspace: Go to workspace 1-10") })
            bind("SUPER + SHIFT + code:" .. code, moveToWorkspace(n, true),  { description = desc("Workspace: Move window to workspace 1-10") })
            bind("SUPER + ALT + code:" .. code,   moveToWorkspace(n, false), { description = desc("Workspace: Send window to workspace 1-10 silently") })
        end
    end


    -- Scratchpad Workspace
    bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special", follow = false }), { description = "Workspace: Send to scratchpad" })
    bind("CTRL + SUPER + S", hl.dsp.workspace.toggle_special(), { description = "[hidden]" })
    bind("SUPER + S",        hl.dsp.workspace.toggle_special(), { description = "Workspace: Toggle scratchpad" })

    -- Power Option Binds
    bind("SUPER + L",                     exec("loginctl lock-session"),                         { description = "Session: Lock screen" })
    bind("SUPER + SHIFT + L",             exec("systemctl suspend || loginctl suspend"),         { locked = true, description = "Session: Sleep" })
    bind("CTRL + SHIFT + ALT + SUPER + Delete", exec("systemctl poweroff || loginctl poweroff"), { description = "Session: Power off" })


    -- Misc Binds
    bind("SUPER + SHIFT + S",       global("regionScreenshot"), { description = "Screen: Screenshot" })
    bind("SUPER + SHIFT + A",       global("regionSearch"),     { description = "Screen: Google Lens" })
    bind("SUPER + SHIFT + C",       exec("hyprpicker -a"),      { description = "Screen: Color picker" })
    bind("SUPER + Q",               hl.dsp.window.close(),      { description = "Window: Close active window" })
    bind("SUPER + SHIFT + ALT + Q", exec("hyprctl kill"),       { description = "Window: Forcefully kill active window" })


    -- Application Binds
    local launch = scripts .. "launch_first_available.sh "
    bind("SUPER + Return", exec(launch .. [["${TERMINAL}" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]]), { description = "Apps: Terminal" })
    bind("SUPER + P",      exec(launch .. [["nautilus" "nemo" "thunar" "${TERMINAL}" "kitty -1 fish -c yazi"]]), { description = "Apps: File manager" })
    bind("SUPER + C",      exec(launch .. [["code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v nvim && kitty -1 nvim" "command -v micro && kitty -1 micro"]]), { description = "Apps: Code editor" })
    bind("CTRL + SUPER + SHIFT + ALT + W", exec(launch .. [["wps" "onlyoffice-desktopeditors" "libreoffice"]]), { description = "Apps: Office software" })
    bind("SUPER + X",      exec(launch .. [["kate" "gnome-text-editor" "emacs"]]), { description = "Apps: Text editor" })
    bind("CTRL + SUPER + V", exec(launch .. [["pavucontrol-qt" "pavucontrol"]]), { description = "Apps: Volume mixer" })
    -- open-settings.sh brings an already open Settings window forward instead of doing nothing
    local openSettings = "~/.config/quickshell/" .. qs .. "/scripts/open-settings.sh"
    bind("SUPER + Slash",  exec(openSettings .. " keybinds"), { description = "Shell: Keybinds" })
    bind("SUPER + I",      exec("XDG_CURRENT_DESKTOP=gnome " .. launch .. [["]] .. openSettings .. [[" "systemsettings" "gnome-control-center" "better-control"]]), { description = "Apps: Ninomae Settings" })
    bind("CTRL + SHIFT + Escape", exec(launch .. [["kitty -1 btop"]]), { description = "Apps: Task manager" }) -- Same as the session screen's Tasks

    -- Your own shortcuts (Settings → Keybinds → Add shortcut)
    for _, b in ipairs(user.added or {}) do
        if type(b.keys) == "string" and type(b.command) == "string" then
            hl.bind(b.keys, exec(b.command), { description = "Custom: " .. (b.name or b.command) })
        end
    end

end)

-- While Settings records a new shortcut it switches to this submap, so keys that already have a bind reach
-- it instead of running. Escape always leaves it, in case Settings can't switch back
hl.define_submap("ninomae_capture", function()
    hl.bind("Escape", hl.dsp.submap("global"), { non_consuming = true, description = "[hidden] Stop recording a shortcut" })
end)
