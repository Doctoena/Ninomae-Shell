import qs.modules.common
import qs.modules.sidebarRight.notifications
import QtQuick
import QtQuick.Layouts
Rectangle {
    id: root
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1 // Soft borderless card, like the bar popups
    clip: true
    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        anchors.bottomMargin: 5
        spacing: 0
        // Notification list content
        NotificationList {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
