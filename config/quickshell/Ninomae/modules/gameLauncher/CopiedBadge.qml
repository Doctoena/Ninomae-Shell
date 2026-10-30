import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// "Copied" on a tile for a moment after it was copied (right-click, Ctrl+C); place it in the tile's corner
Rectangle {
    id: badge
    property bool shown: false
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }
    implicitWidth: copiedRow.implicitWidth + 14
    implicitHeight: 24
    radius: Appearance.rounding.chip
    color: Appearance.colors.colPrimary
    Row {
        id: copiedRow
        anchors.centerIn: parent
        spacing: 4
        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "check"; iconSize: 14; color: Appearance.colors.colOnPrimary }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Copied")
            font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium
            color: Appearance.colors.colOnPrimary
        }
    }
}
