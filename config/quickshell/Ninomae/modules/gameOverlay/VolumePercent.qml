import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A volume's percentage, at the end of its row in the in-game overlay's sound card
StyledText {
    property real value: 0
    property bool muted: false
    Layout.preferredWidth: 40
    horizontalAlignment: Text.AlignRight
    text: Math.round(value * 100) + "%"
    font.pixelSize: Appearance.font.pixelSize.smallie
    font.family: Appearance.font.family.numbers
    color: muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer3
}
