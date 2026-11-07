import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The bar's workspaces: a 36 px card, as the bar's others, with a dot for each workspace. Workspaces with windows
 * share a lighter block (neighbours join up), and the current one sits on an accent squircle that stretches
 * toward the next one as it moves. Click to go there, scroll to step through them, mouse back for the special
 * workspace.
 */
Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int shown: Config.options.bar.workspaces.shown
    readonly property int activeId: monitor?.activeWorkspace?.id ?? 1
    readonly property int firstId: Math.floor((activeId - 1) / shown) * shown + 1 // Groups of `shown`
    readonly property var occupiedIds: Hyprland.workspaces.values.map(ws => ws.id)
    readonly property int cellSize: 24
    readonly property int padding: 6 // Cells to the card's edge: 24 + 6 * 2 = 36
    readonly property int inset: 2 // The current one's squircle inside its cell
    readonly property int cellRadius: 9
    // Has windows. The current workspace with nothing focused on it counts as empty, so its block fades out
    function occupied(id) {
        return root.occupiedIds.includes(id) && !(id === root.activeId && !root.activeWindow?.activated);
    }
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
    Row { // Blocks behind the workspaces with windows; neighbours join into one
        anchors.centerIn: parent
        Repeater {
            model: root.shown
            Rectangle {
                required property int index
                readonly property int workspaceId: root.firstId + index
                property real radiusPrev: root.occupied(workspaceId - 1) && index > 0 ? 0 : root.cellRadius
                property real radiusNext: root.occupied(workspaceId + 1) && index < root.shown - 1 ? 0 : root.cellRadius
                width: root.cellSize
                height: root.cellSize
                topLeftRadius: radiusPrev
                bottomLeftRadius: radiusPrev
                topRightRadius: radiusNext
                bottomRightRadius: radiusNext
                color: Appearance.m3colors.m3surfaceContainerHighest
                opacity: root.occupied(workspaceId) ? 1 : 0
                Behavior on opacity { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on radiusPrev { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on radiusNext { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            }
        }
    }
    Rectangle { // The current workspace: stretches toward the next one, then catches up
        AnimatedTabIndexPair {
            id: idxPair
            index: root.activeId - root.firstId
        }
        x: root.padding + root.inset + Math.min(idxPair.idx1, idxPair.idx2) * root.cellSize
        anchors.verticalCenter: parent.verticalCenter
        width: Math.abs(idxPair.idx1 - idxPair.idx2) * root.cellSize + root.cellSize - root.inset * 2
        height: root.cellSize - root.inset * 2
        radius: root.cellRadius - root.inset
        color: Appearance.colors.colPrimary
    }
    Row { // Buttons and their dots
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
                    Rectangle { // Pointed at (the current one has its own squircle)
                        anchors.centerIn: parent
                        width: root.cellSize - root.inset * 2
                        height: width
                        radius: root.cellRadius - root.inset
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
                        opacity: button.hovered && !button.current ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Rectangle { // The dot
                        anchors.centerIn: parent
                        width: 4
                        height: 4
                        radius: 2
                        color: button.current ? Appearance.colors.colOnPrimary
                            : root.occupiedIds.includes(button.workspaceId) ? Appearance.colors.colOnLayer0
                            : Appearance.colors.colOnLayer1Inactive
                    }
                }
            }
        }
    }
}
