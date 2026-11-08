import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.onScreenDisplay
// The focused screen's brightness (the icon a sunset while night light is on)
OsdValueIndicator {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property var brightnessMonitor: Brightness.getMonitorForScreen(focusedScreen)
    icon: Hyprsunset.active ? "routine" : "light_mode"
    rotateIcon: true
    scaleIcon: true
    name: Translation.tr("Brightness")
    // Which screen, as Settings → Display names them
    detail: !focusedScreen ? "" : focusedScreen.name.startsWith("eDP") ? Translation.tr("Built-in display")
        : (focusedScreen.model || focusedScreen.name)
    value: root.brightnessMonitor?.brightness ?? 0.5
}
