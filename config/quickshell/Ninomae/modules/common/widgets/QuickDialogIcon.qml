import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The icon at the start of a row in the quick-setting dialogs: a squircle, solid accent for the active
 * item (the connected network or device, the device in use), a quiet surface otherwise.
 */
Rectangle {
    id: root
    property string icon
    property bool active: false
    property color accent: Appearance.colors.colPrimary
    property color onAccent: Appearance.colors.colOnPrimary
    implicitWidth: 34
    implicitHeight: 34
    radius: 11
    color: active ? accent : Appearance.colors.colLayer3
    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 19
        fill: root.active ? 1 : 0
        color: root.active ? root.onAccent : Appearance.colors.colOnLayer2
    }
}
