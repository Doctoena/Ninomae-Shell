import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

/**
 * The last tile of a Captures grid: a joined piece the size of a capture, its icon in an accent square, saying
 * how to add one (the screenshot key, the clip key). Not clickable: it only explains. Corners from the grid
 */
Rectangle {
    id: root
    property string icon
    property string text
    color: Appearance.colors.colLayer3

    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 8
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 34; height: 34; radius: 10
            color: Appearance.colors.colLayer3Accent
            MaterialSymbol { anchors.centerIn: parent; text: root.icon; iconSize: 18; color: Appearance.colors.colPrimary }
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.text
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
