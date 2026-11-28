import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The bar's workspaces (K1), in a lit capsule (BarContent), with a dot for each workspace. Workspaces with windows
 * share a lighter round block (neighbours join up), and the current one sits on a round accent pill that stretches
 * toward the next one as it moves, with a light along its top and a soft accent glow round it; at either end it's
 * concentric with the capsule's round end. Click to go there, scroll to step through them, mouse back for the special
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
    readonly property int padding: 3 // Round the cells, so the first and last sit concentric in the 30 px capsule's ends
    readonly property int inset: 2 // The current one's pill inside its cell
    readonly property int cellRadius: cellSize / 2 // Round
    // Has windows. The current workspace with nothing focused on it counts as empty, so its block fades out
    function occupied(id) {
        return root.occupiedIds.includes(id) && !(id === root.activeId && !root.activeWindow?.activated);
    }
    implicitWidth: cellSize * shown + padding * 2
    implicitHeight: Appearance.sizes.barHeight

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
                color: Qt.rgba(1, 1, 1, 0.08)
                opacity: root.occupied(workspaceId) ? 1 : 0
                Behavior on opacity { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on radiusPrev { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on radiusNext { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            }
        }
    }
    Rectangle { // A soft accent glow round the current one's pill, stretching with it
        anchors { fill: currentPill; margins: -3 }
        radius: currentPill.radius + 3
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
    }
    Rectangle { // The current workspace's round pill: stretches toward the next one, then catches up
        id: currentPill
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
        Rectangle { // Its own top light
            x: parent.radius * 0.7; y: 1
            width: parent.width - 2 * x
            height: 1
            color: Qt.rgba(1, 1, 1, 0.6)
        }
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
                    Item { // Pointed at: the capsule's short accent line under the cell (the current one has its own pill)
                        anchors.centerIn: parent
                        width: root.cellSize
                        height: root.cellSize + 4
                        HoverLine { shown: button.hovered && !button.current; inset: 6; capsule: true }
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
