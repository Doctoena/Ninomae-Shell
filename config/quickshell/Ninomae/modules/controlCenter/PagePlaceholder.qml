import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// What a page shows while its radio is off: a big dimmed icon and one line
ColumnLayout {
    id: root
    property string icon
    property string text
    Layout.fillWidth: true
    Layout.topMargin: 40
    spacing: 10
    MaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        text: root.icon
        iconSize: 48
        color: Appearance.colors.colSubtext
    }
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.text
        color: Appearance.colors.colSubtext
    }
}
