-- .----------------------.
-- |   _____              |
-- |  | ____|_ ____   __  |
-- |  |  _| | '_ \ \ / /  |
-- |  | |___| | | \ V /   |
-- |  |_____|_| |_|\_/    |
-- |                      |
-- '----------------------'

hl.env("XDG_SESSION_TYPE", "wayland")

-- GPU-specific env vars, only for a GPU that is the sole one driving a display.
local function displayGpuVendors()
    local vendors = {}
    local p = io.popen("grep -l '^connected' /sys/class/drm/card*-*/status 2>/dev/null")
    if not p then return vendors end
    for line in p:lines() do
        local card = line:match("/sys/class/drm/(card%d+)%-")
        local f = card and io.open("/sys/class/drm/" .. card .. "/device/vendor")
        if f then
            vendors[f:read("*l")] = true
            f:close()
        end
    end
    p:close()
    return vendors
end

local gpus = displayGpuVendors()
local nvidia, amd, intel = gpus["0x10de"], gpus["0x1002"], gpus["0x8086"]
if nvidia and not amd and not intel then
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("GBM_BACKEND", "nvidia-drm")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
elseif amd and not nvidia and not intel then
    hl.env("LIBVA_DRIVER_NAME", "radeonsi")
end
-- Qt's video (the game launcher's Clips) looks for hardware decoders on the GPU that draws the desktop
-- only. Left to check all five kinds, it woke a hybrid laptop's NVIDIA card and froze the shell ~0.4 s
-- the first time Captures opened. VA-API is Intel's and AMD's; an NVIDIA-only machine keeps Qt's default
if amd or intel then
    hl.env("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "vaapi")
    hl.env("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES", "vaapi")
end

-- Electron apps on Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- QT apps on Wayland
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
-- Harmless warnings Quickshell would log on every start (set here: Qt reads the rules once at startup,
-- so a `//@ pragma Env` in shell.qml comes too late):
--   quickshell.desktopentry  Fedora's own malformed swappy.desktop, every time it scans apps
--   qt.qpa.services          Qt 6.11 registering with the portal, which already knows the shell
--                            ("Connection already associated with an application ID")
--   qt.qml.propertyCache     Quickshell's own ClippingRectangle redefines `data`
hl.env("QT_LOGGING_RULES", "qt.qpa.wayland.textinput=false;quickshell.desktopentry.warning=false;qt.qpa.services.warning=false;qt.qml.propertyCache.append.warning=false")
-- User QML modules (Ninomae.Blobs for the launcher, see config/quickshell/plugins)
hl.env("QML_IMPORT_PATH", os.getenv("HOME") .. "/.local/lib/qt6/qml")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Cursor
hl.env("XCURSOR_THEME", "BreezeX-RosePine-Linux")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "rose-pine-hyprcursor")
hl.env("HYPRCURSOR_SIZE", "24")

-- Quickshell virtual environment
hl.env("NINOMAE_SHELL_VIRTUAL_ENV", os.getenv("HOME") .. "/.local/state/quickshell/.venv") -- Full path: scripts use it as-is

-- Default terminal emulator
hl.env("TERMINAL", "kitty -1")
