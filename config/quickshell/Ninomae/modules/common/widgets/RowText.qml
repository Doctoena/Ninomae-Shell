import qs.modules.common
import qs.modules.common.widgets
import Quickshell
import QtQuick
import QtQuick.Layouts

// A settings row's left side: its name, and the line about it under in smaller grey text (none when empty).
// The line can take a symbol before it and its own colour (the control centre's "♫ track · artist" in the accent)
ColumnLayout {
    id: root
    // In a glass window (`glass: true`: Settings, the control centre): Appearance's colWindowGlass* shades
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    property string text: ""
    property string description: ""
    property color color: Appearance.colors.colOnLayer1
    property string descriptionSymbol: ""
    property color descriptionColor: glass ? Appearance.colors.colSubtextGlass : Appearance.colors.colSubtext
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
    RowLayout {
        Layout.fillWidth: true
        visible: root.description !== ""
        spacing: 4
        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            visible: root.descriptionSymbol !== ""
            text: root.descriptionSymbol
            iconSize: Appearance.font.pixelSize.smaller + 1
            fill: 1
            color: root.descriptionColor
        }
        StyledText {
            Layout.fillWidth: true
            text: root.description
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.descriptionColor
        }
    }
}
