import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common // Persistent
pragma Singleton
/**
 * Idle inhibition service for preventing system sleep/screen lock.
 */
Singleton {
    id: root
    property alias inhibit: idleInhibitor.enabled
    inhibit: false
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit
            } else {
                Persistent.states.idle.inhibit = root.inhibit
            }
        }
    }
    function toggleInhibit() {
        root.inhibit = !root.inhibit
        Persistent.states.idle.inhibit = root.inhibit
    }
    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow { // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
