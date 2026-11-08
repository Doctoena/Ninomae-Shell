import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
// The top row of a bar drawer's card (the clock's weather, the battery): an icon on a 44 px squircle, a big value
// with a coloured word beside it, a detail line under, and two small lines on the right
RowLayout {
    id: root
    property string icon
    property color iconBackground: Appearance.colors.colPrimary
    property color iconColor: Appearance.colors.colOnPrimary
    property string value
    property color valueColor: Appearance.colors.colOnLayer3
    property string label
    property color labelColor: Appearance.colors.colPrimary
    property string detail
    property string sideTop
    property string sideBottom
    property real sideBottomSize: Appearance.font.pixelSize.smallest
    Layout.fillWidth: true
    spacing: 12
    Rectangle {
        implicitWidth: 44
        implicitHeight: 44
        radius: 14
        color: root.iconBackground
        MaterialSymbol { anchors.centerIn: parent; text: root.icon; iconSize: 24; fill: 1; color: root.iconColor }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: -2
        RowLayout {
            spacing: 8
            StyledText {
                text: root.value
                font.family: Appearance.font.family.expressive
                font.pixelSize: 28
                font.weight: Font.DemiBold
                color: root.valueColor
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.labelColor
            }
        }
        StyledText {
            visible: text !== ""
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.detail
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
    ColumnLayout {
        visible: root.sideTop !== ""
        spacing: 0
        StyledText {
            Layout.alignment: Qt.AlignRight
            text: root.sideTop
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer3
        }
        StyledText {
            Layout.alignment: Qt.AlignRight
            text: root.sideBottom
            font.pixelSize: root.sideBottomSize
            color: Appearance.colors.colSubtext
        }
    }
}
