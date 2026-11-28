import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Quick settings in a window of its own: Sound, Wi-Fi, Bluetooth and Display, a page each, picked from the list
 * on the left. The arrows on the sidebar's tiles open it at their page. It floats (a built-in window rule matches
 * its title), so it can be dragged and resized like any app. Esc, the ✕ or closing the window shuts it.
 */
Scope {
    id: root
    readonly property string title: "Control centre" // The window rule in window-rules.default.json matches this

    LazyLoader {
        active: GlobalStates.controlCenterOpen
        FloatingWindow {
            title: root.title
            implicitWidth: 1081
            implicitHeight: 634
            minimumSize: Qt.size(640, 420)
            // Glass (Settings → Appearance → Glass panels): the bar's 80 %, over Hyprland's window blur, and the rows
            // (ContentSection, SettingsCard, RowButton…) read this and sit straight on wells. Settings, built on the
            // same rows, sets it too, and `titledWells` for its own look
            readonly property bool glass: true
            color: Appearance.colors.colWindowGlass
            onClosed: GlobalStates.controlCenterOpen = false // Closed by Hyprland (Super+Q, the killactive bind…)
            ControlCenterContent { anchors.fill: parent }
            EdgeLight { // Glass: the edge light along the top, brightest in the middle, as the bar's and the launcher's
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 120; rightMargin: 120 }
                strength: 0.4
            }
        }
    }

    // Asked to open while it's already open (another tile's arrow): bring it forward
    Connections {
        target: GlobalStates
        function onControlCenterRaiseRequested() {
            Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "title:^${root.title}$" })`]);
        }
    }

    IpcHandler {
        target: "controlCenter"
        function open(section: string): void { GlobalStates.openControlCenter(section); } // sound, wifi, bluetooth, display
        function toggle(): void { GlobalStates.controlCenterOpen = !GlobalStates.controlCenterOpen; }
        function close(): void { GlobalStates.controlCenterOpen = false; }
    }
}
