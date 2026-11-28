import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// The head of one of the in-game overlay's side panels: its icon on an accent squircle, its name, a line under it
// (how many), and its buttons on the right (children go there)
RowLayout {
    id: root
    property string icon
    property string title
    property string detail
    default property alias buttons: buttonRow.data
    spacing: 10
    Rectangle {
        implicitWidth: 32
        implicitHeight: 32
        radius: Appearance.rounding.segment
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 18
            fill: 1
            color: Appearance.colors.colPrimary
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            elide: Text.ElideRight
            text: root.detail
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
    RowLayout {
        id: buttonRow
        spacing: 4
    }
}
