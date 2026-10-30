import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
StyledText {
    text: "Section"
    color: Appearance.colors.colSubtext
    Layout.leftMargin: 4
    font {
        pixelSize: Appearance.font.pixelSize.smaller
        weight: Font.Medium
    }
}
