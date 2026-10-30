import qs.modules.common
import QtQuick
// A small flat key "chip" for shortcut hints, e.g. [Super] [Enter]
Rectangle {
    id: root
    property string key
    property color textColor: Appearance.colors.colOnSurfaceVariant
    implicitWidth: Math.max(implicitHeight, keyText.implicitWidth + 14)
    implicitHeight: 24
    radius: 7
    color: Appearance.m3colors.m3surfaceContainerHighest
    StyledText {
        id: keyText
        anchors.centerIn: parent
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: root.textColor
        text: root.key
    }
}
