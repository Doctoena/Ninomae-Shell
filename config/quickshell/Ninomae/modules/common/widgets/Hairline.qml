import qs.modules.common
import QtQuick
import QtQuick.Layouts

// A thin line between groups in a page list (Settings, the control centre), inset from the panel's sides
Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.bottomMargin: 6
    implicitHeight: 1
    color: Appearance.colors.colOutlineVariant
}
