import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The crosshair on screen: a small window in the middle of the game's screen, on the overlay layer (over
 * fullscreen games), that takes no input. Only exists while it shows (services/Crosshair.qml decides).
 */
Scope {
    LazyLoader {
        active: Crosshair.shown && Crosshair.screen !== null
        component: PanelWindow {
            screen: Crosshair.screen
            // No anchors: the layer sits centred on the screen
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:crosshair"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {} // Clicks go through to the game
            implicitWidth: shape.implicitWidth
            implicitHeight: shape.implicitHeight
            CrosshairShape {
                id: shape
                anchors.fill: parent
            }
        }
    }
}
