import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * Top of a bar popup (clock, battery): an accent line (icon + text) over a big expressive headline,
 * with an optional small suffix (AM/PM). Children added by the user go underneath (date, charge bar).
 */
ColumnLayout {
    id: root
    property string icon
    property string text
    property color accent: Appearance.colors.colPrimary
    property string headline
    property string suffix
    // Fills only when a child can (the charge bar); otherwise it keeps its content width, so centre it
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: 6
    spacing: 0
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        MaterialSymbol { text: root.icon; iconSize: 14; fill: 1; color: root.accent }
        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: root.accent
        }
    }
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        StyledText {
            text: root.headline
            font.family: Appearance.font.family.expressive
            font.pixelSize: 54
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            visible: text !== ""
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 12
            text: root.suffix
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }
    }
}
