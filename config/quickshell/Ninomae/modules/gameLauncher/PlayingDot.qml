import qs.modules.common
import QtQuick

// The "Playing" mark (the grid's badge, the Play button while the game runs): a dot, gently pulsing.
// Only animates while shown
Rectangle {
    id: root
    property real size: 7
    width: size; height: size; radius: size / 2
    color: Appearance.colors.colPrimary
    SequentialAnimation on opacity {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
    }
}
