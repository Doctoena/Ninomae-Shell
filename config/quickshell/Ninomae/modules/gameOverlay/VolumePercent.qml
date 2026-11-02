import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A volume's percentage, at the end of its name's row in the in-game overlay's Sound
StyledText {
    property real value: 0
    property bool muted: false
    text: Math.round(value * 100) + "%"
    font.pixelSize: Appearance.font.pixelSize.smaller
    font.family: Appearance.font.family.numbers
    color: muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
}
