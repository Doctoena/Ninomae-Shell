import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A small pill on the in-game overlay: a folder, the mic, an output device. Accent when it's the one in use,
// red for a warning (the mic muted)
Rectangle {
    id: root
    property string icon
    property string text
    property bool active: false
    property bool warn: false
    signal clicked()
    implicitWidth: Math.min(row.implicitWidth + 20, 360)
    implicitHeight: 30
    radius: 10
    color: warn ? Appearance.colors.colErrorContainer : active ? Appearance.colors.colPrimary
        : mouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    readonly property color textColor: warn ? Appearance.colors.colOnErrorContainer : active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        spacing: 6
        MaterialSymbol { text: root.icon; iconSize: 16; color: root.textColor }
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
