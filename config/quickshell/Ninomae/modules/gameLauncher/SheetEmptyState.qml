import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// Centred placeholder for the sheets: icon badge, a line of text and an optional hint under it
Column {
    id: root
    property string icon
    property string text
    property string hint: ""
    spacing: 12
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 56; height: 56; radius: Appearance.rounding.normal
        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
        MaterialSymbol { anchors.centerIn: parent; iconSize: 26; color: Appearance.colors.colPrimary; text: root.icon }
    }
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.Medium
        color: Appearance.colors.colOnLayer0
    }
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.hint !== ""
        text: root.hint
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
