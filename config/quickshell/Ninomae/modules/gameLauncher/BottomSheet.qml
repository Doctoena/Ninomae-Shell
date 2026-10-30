import qs.modules.common
import qs.modules.common.functions
import QtQuick

// A sheet that rises out of the bottom of the details panel on the drawer curves, over a dimmed
// backdrop (click it to close). Flat at the bottom, rounded at the top; children go inside the sheet.
Item {
    id: root
    property bool shown: false
    signal closeRequested()
    property real sheetWidth: 880
    property real sheetHeight: 300 // Capped to the panel
    property bool clipContent: false
    readonly property alias sheet: sheet
    default property alias content: sheet.data

    anchors.fill: parent
    z: 50
    clip: true
    visible: shown || offset < 1

    // 0 = fully up, 1 = tucked below the panel. Same curves as the bar drawers
    property real offset: shown ? 0 : 1
    Behavior on offset {
        NumberAnimation {
            duration: root.shown ? Appearance.animationCurves.drawerOpenDuration : Appearance.animationCurves.drawerCloseDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.shown ? Appearance.animationCurves.drawerOpen : Appearance.animationCurves.drawerClose
        }
    }

    Rectangle { // Dimmed backdrop
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: "#000000"
        opacity: 0.4 * (1 - Math.min(1, root.offset))
        // hoverEnabled: also take the hover, or buttons under the backdrop (the one that opened the
        // sheet) keep thinking the pointer is on them and stay lit until it closes
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.closeRequested() }
    }
    Rectangle { // Runs past the bottom edge so the overshoot never shows a gap
        x: sheet.x; y: sheet.y + sheet.height
        width: sheet.width; height: 40
        color: sheet.color
    }
    Rectangle {
        id: sheet
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.sheetWidth, root.width - 64)
        height: Math.min(root.sheetHeight, root.height - 16)
        y: root.height - height + (height + 24) * root.offset
        topLeftRadius: Appearance.rounding.windowRounding
        topRightRadius: Appearance.rounding.windowRounding
        color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.04)
        clip: root.clipContent
        MouseArea { anchors.fill: parent; hoverEnabled: true } // Keep clicks (and hover) off the backdrop
    }
}
