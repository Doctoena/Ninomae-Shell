import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// A small neutral chip in a sheet: an icon and a bit of text (a clip's place, date and size, on its controls)
Rectangle {
    id: chip
    property string icon
    property string text
    implicitWidth: chipRow.implicitWidth + 16
    implicitHeight: 24
    radius: Appearance.rounding.chip
    color: Appearance.colors.colLayer4 // On the clip's controls (colLayer3)
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5
        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: chip.icon; iconSize: 14; color: Appearance.colors.colSubtext }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer4
        }
    }
}
