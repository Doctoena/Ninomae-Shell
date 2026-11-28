import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// The card on the box: the action on its accent squircle and its name, the size, what letting go does, dots between.
// The selector's dark unblurred glass with a fine rim (solid with Glass panels off)
Rectangle {
    id: root
    property string actionIcon
    property string actionName
    property string size
    property string release
    implicitWidth: row.implicitWidth + 16
    implicitHeight: 38
    width: implicitWidth
    height: implicitHeight
    radius: Appearance.rounding.small
    color: Appearance.colors.colGlassUnblurred
    border { width: 1; color: Appearance.colors.colGlassFieldRim }
    Row {
        id: row
        x: 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Rectangle {
            width: 28; height: 28
            radius: Appearance.rounding.chip
            color: Appearance.colors.colPrimary
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.actionIcon
                iconSize: 18
                fill: 1
                color: Appearance.colors.colOnPrimary
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.actionName
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        Dot {}
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.size
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnLayer0
        }
        Dot {}
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.release
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colSubtextGlass
        }
    }
    component Dot: Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 4; height: 4; radius: 2
        color: Appearance.colors.colSubtextGlass
        opacity: 0.6
    }
}
