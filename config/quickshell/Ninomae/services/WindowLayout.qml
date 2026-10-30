pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Hyprland tiling layout preset, from Settings → Interface → Windows.
 * Applied when the shell starts, when the setting changes, and after Hyprland reloads its config
 * (a reload would otherwise put the layout back to the default).
 */
Singleton {
    id: root
    // "auto" picks Centred on an ultrawide (21:9 or wider) and Normal on anything narrower, by the
    // focused monitor, re-checked when monitors change or focus moves to another one
    readonly property real ultrawideRatio: 2.1
    readonly property var focusedMonitor: Hyprland.focusedMonitor
    readonly property bool focusedIsUltrawide: (focusedMonitor?.width ?? 0) / Math.max(1, focusedMonitor?.height ?? 1) >= ultrawideRatio
    readonly property string preset: Config.options.windows.layoutPreset === "auto"
        ? (focusedIsUltrawide ? "centred" : "normal") : Config.options.windows.layoutPreset

    // Each preset sets every option it relies on, so switching between them never inherits a leftover
    readonly property var presets: ({
        // Main window in the middle at half the screen width (2560 px on a 5120 px monitor), centred
        // even when it's alone; other windows stack at the sides
        "centred": `hl.config({ general = { layout = "master" }, master = { orientation = "center", mfact = 0.5, slave_count_for_center_master = 0, always_keep_position = true, new_status = "slave" } })`,
        // One window fills the screen; two split it 50/50; more stack on the right half
        "sideBySide": `hl.config({ general = { layout = "master" }, master = { orientation = "left", mfact = 0.5, slave_count_for_center_master = 2, always_keep_position = false, new_status = "slave" } })`,
        // Scrolling columns, a third of the screen each: three side by side, more scroll in as focus moves
        "columns": `hl.config({ general = { layout = "scrolling" }, scrolling = { column_width = 0.333, fullscreen_on_one_column = true, follow_focus = true } })`,
        // Hyprland's regular tiling, for normal-width monitors
        "normal": `hl.config({ general = { layout = "dwindle" } })`
    })

    function apply() {
        if (!Config.ready) return;
        Quickshell.execDetached(["hyprctl", "eval", root.presets[root.preset] ?? root.presets["normal"]]);
    }
    function load() { apply(); }

    onPresetChanged: apply()
    Connections {
        target: Config
        function onReadyChanged() { root.apply(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.apply();
            else if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2"].includes(event.name))
                Hyprland.refreshMonitors(); // focusedIsUltrawide follows, and preset with it
        }
    }
}
