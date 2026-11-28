pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The glass look's blur (Settings → Appearance → Glass panels). Hyprland does the blurring behind the bar, the sidebar, app search,
 * the game launcher and every drawer on DrawerBackground, not the shell: a layer on the gooey drawer hung the Intel GPU before. This writes the layer rule to
 * ~/.local/state/quickshell/user/glass.lua (hypr/hyprland/Windowrules.lua loads it), or a note with no rule
 * when glass is off, and reloads Hyprland only when that file would change.
 * The glass blurs what's really behind it (a window). The bar sits above its glass drawers (Bar.qml), so their blur
 * doesn't take it in; the bar itself has xray (only the wallpaper is ever behind it), so its blur doesn't take the
 * drawers in either. Layer rules reach a layer when it maps: restart the shell for the bar.
 */
Singleton {
    id: root
    readonly property string luaPath: FileUtils.trimFileProtocol(`${Directories.state}/user/glass.lua`)
    readonly property bool on: Config.options.appearance.glass

    function load() { root.write(); }
    onOnChanged: write()

    function write() {
        if (!Config.ready) return;
        // No trailing newline: the compare below reads the file back through $(…), which drops one
        const lua = root.on ? [
            "-- Written by the shell: glass is on (Settings → Appearance → Glass panels)",
            "pcall(hl.layer_rule, { name = \"sidebar-glass\", match = { namespace = [[^quickshell:sidebarRight$]] }, blur = true, ignore_alpha = 0.3 })",
            "pcall(hl.layer_rule, { name = \"search-glass\", match = { namespace = [[^quickshell:overview$]] }, blur = true, ignore_alpha = 0.3 })",
            "pcall(hl.layer_rule, { name = \"bar-glass\", match = { namespace = [[^quickshell:bar$]] }, blur = true, xray = true, ignore_alpha = 0.3 })",
            "pcall(hl.layer_rule, { name = \"launcher-glass\", match = { namespace = [[^quickshell:gamelauncher$]] }, blur = true, ignore_alpha = 0.3 })",
            // The other drawers and cards on DrawerBackground (its glass is the bar's 80 %): without this their 20 %
            // showed the windows behind them sharp
            "pcall(hl.layer_rule, { name = \"drawer-glass\", match = { namespace = [[^quickshell:(barDrawer|trayMenu|mediaControls|polkit|onScreenDisplay|notificationPopup|session|launchSplash)$]] }, blur = true, ignore_alpha = 0.3 })",
        ].join("\n") : "-- Written by the shell: glass is off (Settings → Appearance → Glass panels)";
        writer.command = ["bash", "-c", '[ "$(cat -- "$1" 2>/dev/null)" = "$2" ] && exit 0; mkdir -p -- "$(dirname -- "$1")" && printf "%s" "$2" > "$1" && hyprctl reload >/dev/null',
            "glass", root.luaPath, lua];
        writer.running = true;
    }
    Connections {
        target: Config
        function onReadyChanged() { root.write(); }
    }
    Process { id: writer }
}
