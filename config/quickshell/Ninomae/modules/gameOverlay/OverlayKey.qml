import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// A key, as the in-game overlay shows one: on a quick action, the replay line, the panel's foot
Rectangle {
    property alias text: label.text
    implicitWidth: Math.max(18, label.implicitWidth + 10)
    implicitHeight: 18
    radius: 5
    color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.9)
    StyledText {
        id: label
        anchors.centerIn: parent
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }
}
