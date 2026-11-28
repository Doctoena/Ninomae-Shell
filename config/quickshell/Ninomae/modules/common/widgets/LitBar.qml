import QtQuick

// The row you're on in a list on a well: a short accent bar at its left edge, growing in (the tray menu's rows,
// Settings' rows and its open page)
Rectangle {
    property bool shown: false
    property real length: 16
    x: 3
    anchors.verticalCenter: parent.verticalCenter
    width: 3
    height: shown ? length : 0
    radius: 1.5
    opacity: shown ? 1 : 0
    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }
}
