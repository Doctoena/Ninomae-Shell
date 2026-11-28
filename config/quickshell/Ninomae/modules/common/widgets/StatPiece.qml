import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A figure over its name as a small soft piece on a well, laid out in a row of equal ones: the sidebar's resource
// panel (average, peak, temperature) and the battery drawer (plugged in, voltage, health)
Rectangle {
    id: piece
    property string value
    property string label
    property color valueColor: Appearance.colors.colOnLayer3
    Layout.fillWidth: true
    Layout.preferredWidth: 1 // Equal widths whatever the text length
    implicitHeight: 46
    radius: 12
    color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.95)
    Column {
        anchors.centerIn: parent
        spacing: 0
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: piece.value
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            font.family: Appearance.font.family.numbers
            font.variableAxes: ({}) // Not Roboto Flex's tuning
            color: piece.valueColor
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: piece.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtextGlass
        }
    }
}
