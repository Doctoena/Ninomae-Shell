import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A settings row's left side: its name, and the line about it under in smaller grey text (none when empty)
ColumnLayout {
    id: root
    property string text: ""
    property string description: ""
    property color color: Appearance.colors.colOnLayer1
    spacing: 2
    Layout.fillWidth: true
    StyledText {
        Layout.fillWidth: true
        text: root.text
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.Medium
        color: root.color
    }
    StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.description
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
