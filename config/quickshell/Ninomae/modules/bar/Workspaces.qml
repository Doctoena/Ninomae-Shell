import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * The bar's workspaces: a 36 px card, as the bar's others, with a dot for each workspace (bright with windows on
 * it, dim without) and the current one stretched into an accent pill. Click a dot to go there, scroll to step
 * through them, mouse back for the special workspace.
 */
Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int shown: Config.options.bar.workspaces.shown
    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property int firstId: Math.floor((activeId - 1) / shown) * shown + 1 // Groups of `shown`
    readonly property var occupiedIds: Hyprland.workspaces.values.map(ws => ws.id)
    readonly property int dotSize: 8
    readonly property int pillWidth: 26
    readonly property int gap: 8 // Between the dots, and half of it beyond the last ones, inside the click areas
    readonly property int padding: 10 // The outer dots to the card's edge, past their click areas' half gap
    implicitWidth: card.width
    implicitHeight: Appearance.sizes.barHeight

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: dots.width + root.padding * 2
        height: 36
        radius: Appearance.rounding.container
        color: Appearance.m3colors.m3surfaceContainerHigh
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y < 0) Hyprland.dispatch(`hl.dsp.focus({ workspace = "r+1" })`);
            else if (event.angleDelta.y > 0) Hyprland.dispatch(`hl.dsp.focus({ workspace = "r-1" })`);
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: Hyprland.dispatch(`hl.dsp.workspace.toggle_special()`)
    }
    Row {
        id: dots
        anchors.centerIn: parent
        Repeater {
            model: root.shown
            MouseArea {
                id: slot
                required property int index
                readonly property int workspaceId: root.firstId + index
                readonly property bool current: workspaceId === root.activeId
                readonly property bool occupied: root.occupiedIds.includes(workspaceId)
                width: dot.width + root.gap
                height: root.implicitHeight
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceId} })`)
                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    width: slot.current ? root.pillWidth : root.dotSize
                    height: root.dotSize
                    radius: height / 2
                    color: slot.current ? Appearance.colors.colPrimary
                        : slot.containsMouse || slot.occupied ? Appearance.colors.colOnLayer0
                        : Appearance.colors.colOnLayer1Inactive
                    Behavior on width { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }
}
