import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Previous, play/pause or next in the overlay's Now playing: the main one filled in the accent
Rectangle {
    id: root
    property string icon
    property bool main: false
    property bool available: true
    signal clicked()
    implicitWidth: main ? 48 : 40
    implicitHeight: implicitWidth
    radius: main ? Appearance.rounding.normal : Appearance.rounding.container
    opacity: available ? 1 : 0.4
    color: main ? (mouse.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
        : mouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: root.main ? 26 : 22
        fill: 1
        color: root.main ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.available) root.clicked()
    }
}
