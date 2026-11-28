import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

/**
 * A picture choice for Settings: a little 16:9 screen (the wallpaper) with something drawn on it, and its name
 * underneath. The chosen one has the accent ring, a check and its name in accent. Put the drawing inside;
 * it fills the screen. Several in a RowLayout share its width.
 *   PreviewTile { name: "Float"; chosen: …; onClicked: …; Rectangle { … } }
 */
Item {
    id: root
    property string name
    property bool chosen: false
    property string badge: "" // Quiet text after the name (e.g. what Auto picks: "Auto · Normal")
    default property alias drawing: drawingLayer.data
    signal clicked()
    Layout.fillWidth: true
    implicitWidth: 196
    implicitHeight: screenFrame.height + nameRow.implicitHeight + 8

    Rectangle { // Accent ring around the chosen one, a quiet one on hover
        anchors.centerIn: screenFrame
        width: screenFrame.width + 6
        height: screenFrame.height + 6
        radius: screenFrame.radius + 3
        color: "transparent"
        border.width: 2
        border.color: root.chosen ? Appearance.colors.colPrimary
            : tileMouse.containsMouse ? Appearance.colors.colOutlineVariant : "transparent"
    }
    ClippingRectangle {
        id: screenFrame
        width: parent.width
        height: Math.round(width * 9 / 16)
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        StyledImage {
            anchors.fill: parent
            source: Config.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 400
            asynchronous: true
            opacity: 0.85
        }
        Item {
            id: drawingLayer
            anchors.fill: parent
        }
    }
    RowLayout {
        id: nameRow
        anchors { top: screenFrame.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
        spacing: 4
        MaterialSymbol {
            visible: root.chosen
            text: "check"
            iconSize: 16
            color: Appearance.colors.colPrimary
        }
        StyledText {
            text: root.name
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.chosen ? Font.DemiBold : Font.Normal
            color: root.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }
        StyledText {
            visible: root.badge !== ""
            text: "· " + root.badge
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
