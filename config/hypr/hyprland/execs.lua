-- .-------------------------------.
-- |                               |
-- |    _____                      |
-- |   | ____|_  _____  ___ ___    |
-- |   |  _| \ \/ / _ \/ __/ __|   |
-- |   | |___ >  <  __/ (__\__ \   |
-- |   |_____/_/\_\___|\___|___/   |
-- |                               |
-- |                               |
-- '-------------------------------'

local qs = require("hyprland/vars").qsConfig

-- Everything in here runs once, when Hyprland starts (replaces exec-once)
hl.on("hyprland.start", function()
    -- Export the session env to dbus & systemd first so portals/services see it
    -- then (plain, non-uwsm session) start hyprland-session.target fresh, so units that need
    -- graphical-session.target (xdg-desktop-portal on Fedora 44) start with this session's env.
    -- Skipped under uwsm, which runs its own session units.
    hl.exec_cmd([[sh -c 'if systemctl --user -q is-active "wayland-wm@*.service"; then dbus-update-activation-environment --systemd --all; else systemctl --user stop hyprland-session.target; dbus-update-activation-environment --systemd --all && systemctl --user start hyprland-session.target; fi']])

    -- Core components (secrets, idle/lock daemon, location for weather/night light)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("~/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")

    -- GTK theme (needs the adw-gtk3-theme package). Set here so a fresh install is themed
    -- without nwg-look. Colours come from matugen's gtk.css; light/dark is set by switchwall.sh.
    local gtk = {
        ["gtk-theme"]    = "adw-gtk3-dark",
        -- Ninomae-Icons-purple with its accent recoloured to the wallpaper's (recolor_icons.py)
        ["icon-theme"]   = "Ninomae-Icons-accent",
        ["cursor-theme"] = "BreezeX-RosePine-Linux",
        ["cursor-size"]  = "24",
    }
    for key, value in pairs(gtk) do
        hl.exec_cmd("gsettings set org.gnome.desktop.interface " .. key .. " '" .. value .. "'")
    end
    -- accent-color (Flatpak/libadwaita apps): the preset closest to the wallpaper's accent; also makes the
    -- accent icon theme on a fresh install. gtk.css sets the exact colour for GTK apps
    hl.exec_cmd("python3 -I ~/.config/quickshell/" .. qs .. "/scripts/colors/recolor_icons.py")

    -- Shell
    hl.exec_cmd("qs -c " .. qs)
    -- Rebuild the gooey drawer plugin if Qt was updated (or its sources changed); offers a shell restart after
    hl.exec_cmd("~/.config/quickshell/plugins/ninomae-blobs/ensure-built.sh")
    -- Theme Zen and Steam once they've been opened (a fresh install hasn't yet); exits straight away when they're done
    hl.exec_cmd("~/Ninomae-Shell/themes/apply-when-ready.sh")
    -- Bring a video wallpaper back (switchwall.sh writes this; it's empty for image wallpapers)
    hl.exec_cmd("sh -c 'f=~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh; [ -x \"$f\" ] && exec \"$f\"'")

    -- Clipboard history (capped: the default 750 entries with images grew to ~160 MB).
    -- The shell re-reads it when the launcher opens, so a copy doesn't start a `qs ipc` process.
    -- The script leaves out copies made in a password manager (Bitwarden doesn't mark them secret)
    local store = "~/.config/hypr/hyprland/scripts/cliphist_store.sh"
    hl.exec_cmd("wl-paste --type text --watch " .. store)
    hl.exec_cmd("wl-paste --type image --watch " .. store)
end)
