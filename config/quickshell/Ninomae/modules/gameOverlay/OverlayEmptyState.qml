import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Nothing to show in an overlay card: a faint icon and a line, in its middle (below its title)
Column {
    id: root
    property string icon
    property string text
    anchors.centerIn: parent
    anchors.verticalCenterOffset: 12
    spacing: 6
    MaterialSymbol {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.icon
        iconSize: 40
        color: ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5)
    }
    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }
}
