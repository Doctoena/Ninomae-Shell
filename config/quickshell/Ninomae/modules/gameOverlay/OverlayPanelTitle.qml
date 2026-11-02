import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A section's title on the in-game overlay, quiet as the sidebar's notification headers: its icon in the accent,
// its name
RowLayout {
    id: root
    property string icon
    property string text
    spacing: 6
    MaterialSymbol { text: root.icon; iconSize: 16; fill: 1; color: Appearance.colors.colPrimary }
    StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.smallie
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer1
    }
}
