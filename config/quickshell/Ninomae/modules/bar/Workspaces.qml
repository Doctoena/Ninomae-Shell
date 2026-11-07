import qs.services
import qs.modules.common
import qs.modules.common.models
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland

/**
 * The bar's workspaces: a 36 px card, as the bar's others, with a dot for each workspace (bright with windows on
 * it, dim without) and the current one on an accent squircle that slides between them. Pointed at, a segment
 * lights up as the status card's do. Click to go there, scroll to step through them, mouse back for the
 * special workspace.
 */
Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property int shown: Config.options.bar.workspaces.shown
    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property int firstId: Math.floor((activeId - 1) / shown) * shown + 1 // Groups of `shown`
    readonly property var occupiedIds: Hyprland.workspaces.values.map(ws => ws.id)
    readonly property int cellSize: 28
    readonly property int padding: 4 // Cells to the card's edge: 28 + 4 * 2 = 36
    implicitWidth: cellSize * shown + padding * 2
    implicitHeight: Appearance.sizes.barHeight

    Rectangle { // The card
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.cellSize + root.padding * 2
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
    Rectangle { // The current workspace: stretches toward the next one, then catches up
        AnimatedTabIndexPair {
            id: idxPair
            index: root.activeId - root.firstId
        }
        x: root.padding + Math.min(idxPair.idx1, idxPair.idx2) * root.cellSize
        anchors.verticalCenter: parent.verticalCenter
        width: Math.abs(idxPair.idx1 - idxPair.idx2) * root.cellSize + root.cellSize
        height: root.cellSize
        radius: Appearance.rounding.segment
        color: Appearance.colors.colPrimary
    }
    Row {
        anchors.centerIn: parent
        Repeater {
            model: root.shown
            Button {
                id: button
                required property int index
                readonly property int workspaceId: root.firstId + index
                readonly property bool current: workspaceId === root.activeId
                implicitWidth: root.cellSize
                implicitHeight: Appearance.sizes.barHeight
                onPressed: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceId} })`)
                background: Item {
                    Rectangle { // Pointed at, as the status card's segments
                        anchors.centerIn: parent
                        width: root.cellSize
                        height: root.cellSize
                        radius: Appearance.rounding.segment
                        color: Appearance.m3colors.m3surfaceContainerHighest
                        opacity: button.hovered && !button.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Rectangle { // The dot
                        anchors.centerIn: parent
                        width: 5
                        height: 5
                        radius: 2.5
                        color: button.current ? Appearance.colors.colOnPrimary
                            : root.occupiedIds.includes(button.workspaceId) ? Appearance.colors.colOnLayer0
                            : Appearance.colors.colOnLayer1Inactive
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }
    }
}
