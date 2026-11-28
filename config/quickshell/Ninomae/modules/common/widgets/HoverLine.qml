import qs.modules.common
import QtQuick

// The glass hover (H3): a thin accent line along the bottom of the part pointed at, growing out from its middle.
// On the bar's parts and app search's shortcuts, which have no card. `capsule`: a part in one of the bar's 30 px
// capsules, centred on it: a short 16 px line inside the capsule, 2 px above its foot, where the status button's open
// marker is
Rectangle {
    id: root
    property bool shown: false
    property bool capsule: false
    property real inset: 8 // From each side of the part
    anchors {
        horizontalCenter: parent.horizontalCenter
        bottom: parent.bottom
        bottomMargin: root.capsule ? (parent.height - 30) / 2 + 5 : 1
    }
    width: shown ? Math.min(capsule ? 16 : Infinity, Math.max(0, parent.width - inset * 2)) : 0
    height: 2
    radius: 1
    color: Appearance.colors.colPrimary
    opacity: shown ? 1 : 0
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }
}
