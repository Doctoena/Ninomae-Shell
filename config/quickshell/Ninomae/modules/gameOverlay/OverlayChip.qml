import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A small button on the in-game overlay: a folder, the mic, an output device. Neutral; the one in use has its
// icon on an accent squircle and its name in the accent (as Settings' option rows), a warning is red (the mic muted)
Rectangle {
    id: root
    property string icon
    property string text
    property bool active: false
    property bool warn: false
    signal clicked()
    implicitWidth: Math.min(row.implicitWidth + 16, 360)
    implicitHeight: 30
    radius: Appearance.rounding.segment
    color: warn ? Appearance.colors.colErrorContainer
        : mouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    readonly property color textColor: warn ? Appearance.colors.colOnErrorContainer : active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: 4; rightMargin: 10 }
        spacing: 6
        Rectangle { // Its icon, on the accent squircle when it's the one in use
            implicitWidth: 22; implicitHeight: 22
            radius: Appearance.rounding.chip
            color: root.active ? Appearance.colors.colPrimary : "transparent"
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 15
                fill: root.active ? 1 : 0
                color: root.active ? Appearance.colors.colOnPrimary : root.textColor
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.text
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.textColor
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
