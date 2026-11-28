import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * A row's icon on its squircle (the rows in the launcher's wells). Neutral by default, filled with the icon's own
 * colour to say it's on: a row sets color and iconColor for that
 */
Rectangle {
    property string icon
    property bool filled: false
    property color iconColor: Appearance.colors.colOnLayer3
    implicitWidth: 30; implicitHeight: 30
    radius: 10
    color: Appearance.colors.colLayer4
    Behavior on color { ColorAnimation { duration: 120 } }
    MaterialSymbol {
        anchors.centerIn: parent
        text: parent.icon
        iconSize: 17
        fill: parent.filled ? 1 : 0
        color: parent.iconColor
    }
}
