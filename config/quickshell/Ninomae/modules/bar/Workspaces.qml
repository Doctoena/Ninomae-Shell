import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((monitor?.activeWorkspace?.id - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int workspaceButtonWidth: 26
    property real activeWorkspaceMargin: 2
    property int workspaceIndexInGroup: (monitor?.activeWorkspace?.id - 1) % root.workspacesShown
    property bool showNumbers: false
    // Function to update workspaceOccupied
    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({ length: root.workspacesShown }, (_, i) => {
            return Hyprland.workspaces.values.some(ws => ws.id === workspaceGroup * root.workspacesShown + i + 1);
        })
    }
    // Debounce workspace occupied updates — fires in quick succession from multiple signals
    Timer { id: _wsDebounce; interval: 16; onTriggered: root.updateWorkspaceOccupied() }
    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            _wsDebounce.restart();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            _wsDebounce.restart();
        }
    }
    onWorkspaceGroupChanged: {
        _wsDebounce.restart();
    }
    readonly property real pillPadding: 2 // Gap between the dots and the edge of the pill
    implicitWidth: root.workspaceButtonWidth * root.workspacesShown + pillPadding * 2
    implicitHeight: Appearance.sizes.barHeight

    // Pill behind the workspaces, same style as the other bar pills
    Rectangle {
        z: 0
        anchors.centerIn: parent
        width: root.workspaceButtonWidth * root.workspacesShown + root.pillPadding * 2
        height: root.workspaceButtonWidth + root.pillPadding * 2
        radius: 12 // Rounded rectangle, like the rest of the bar
        color: Appearance.m3colors.m3surfaceContainerHigh
    }
    // Scroll to switch workspaces
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`hl.dsp.focus({ workspace = "r+1" })`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`hl.dsp.focus({ workspace = "r-1" })`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: (event) => {
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special()`);
            }
        }
    }
    // Workspaces - background
    Grid {
        z: 1
        anchors.centerIn: parent
        rowSpacing: 0
        columnSpacing: 0
        columns: root.workspacesShown
        rows: 1
        Repeater {
            model: root.workspacesShown
            Rectangle {
                z: 1
                implicitWidth: workspaceButtonWidth
                implicitHeight: workspaceButtonWidth
                radius: 9
                property var previousOccupied: (workspaceOccupied[index-1] && !(!activeWindow?.activated && monitor?.activeWorkspace?.id === index))
                property var rightOccupied: (workspaceOccupied[index+1] && !(!activeWindow?.activated && monitor?.activeWorkspace?.id === index+2))
                property var radiusPrev: previousOccupied ? 0 : 9
                property var radiusNext: rightOccupied ? 0 : 9
                topLeftRadius: radiusPrev
                bottomLeftRadius: radiusPrev
                topRightRadius: radiusNext
                bottomRightRadius: radiusNext
                color: Appearance.m3colors.m3surfaceContainerHighest
                opacity: (workspaceOccupied[index] && !(!activeWindow?.activated && monitor?.activeWorkspace?.id === index+1)) ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on radiusPrev {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on radiusNext {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }
    }
    // Active workspace
    Rectangle {
        z: 2
        // Make active ws indicator, which has a brighter color, smaller to look like it is of the same size as ws occupied highlight
        radius: 9
        color: Appearance.colors.colPrimary
        anchors.verticalCenter: parent.verticalCenter
        AnimatedTabIndexPair {
            id: idxPair
            index: root.workspaceIndexInGroup
        }
        property real indicatorPosition: Math.min(idxPair.idx1, idxPair.idx2) * workspaceButtonWidth + root.activeWorkspaceMargin
        property real indicatorLength: Math.abs(idxPair.idx1 - idxPair.idx2) * workspaceButtonWidth + workspaceButtonWidth - root.activeWorkspaceMargin * 2
        property real indicatorThickness: workspaceButtonWidth - root.activeWorkspaceMargin * 2
        x: indicatorPosition + root.pillPadding
        implicitWidth: indicatorLength
        implicitHeight: indicatorThickness
    }
    // Workspaces - numbers
    Grid {
        z: 3
        columns: root.workspacesShown
        rows: 1
        columnSpacing: 0
        rowSpacing: 0
        anchors.centerIn: parent
        Repeater {
            model: root.workspacesShown
            Button {
                id: button
                property int workspaceValue: workspaceGroup * root.workspacesShown + index + 1
                implicitHeight: Appearance.sizes.barHeight
                implicitWidth: Appearance.sizes.verticalBarWidth
                onPressed: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceValue} })`)
                width: workspaceButtonWidth
                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    Rectangle { // Hover highlight (the active workspace has its own indicator)
                        anchors.centerIn: parent
                        width: root.workspaceButtonWidth - root.activeWorkspaceMargin * 2
                        height: width
                        radius: 9 // Same squircle as the active and occupied indicators
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.88)
                        opacity: button.hovered && monitor?.activeWorkspace?.id !== button.workspaceValue ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    StyledText { // Workspace number, while Super is held
                        opacity: root.showNumbers ? 1 : 0
                        z: 3
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font {
                            pixelSize: Appearance.font.pixelSize.small - ((text.length - 1) * (text !== "10") * 2)
                            family: Config.options?.bar.workspaces.useNerdFont ? Appearance.font.family.iconNerd : defaultFont
                        }
                        text: Config.options?.bar.workspaces.numberMap[button.workspaceValue - 1] || button.workspaceValue
                        elide: Text.ElideRight
                        color: (monitor?.activeWorkspace?.id == button.workspaceValue) ?
                            Appearance.colors.colOnPrimary :
                            (workspaceOccupied[index] ? Appearance.colors.colOnLayer0 :
                                Appearance.colors.colOnLayer1Inactive)
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    Rectangle { // A dot the rest of the time
                        id: wsDot
                        opacity: root.showNumbers ? 0 : 1
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.18
                        height: width
                        radius: width / 2
                        color: (monitor?.activeWorkspace?.id == button.workspaceValue) ?
                            Appearance.colors.colOnPrimary :
                            (workspaceOccupied[index] ? Appearance.colors.colOnLayer0 :
                                Appearance.colors.colOnLayer1Inactive)
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }
}
