import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Small neutral chip with an accent icon (a popup's footer facts: uptime, battery chemistry)
Rectangle {
    id: root
    property string icon
    property string text
    implicitWidth: chipRow.implicitWidth + 20
    implicitHeight: 26
    radius: Appearance.rounding.chip
    color: Appearance.colors.colLayer2
    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5
        MaterialSymbol { text: root.icon; iconSize: 13; color: Appearance.colors.colPrimary }
        StyledText { text: root.text; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Medium; color: Appearance.colors.colOnSurfaceVariant }
    }
}
