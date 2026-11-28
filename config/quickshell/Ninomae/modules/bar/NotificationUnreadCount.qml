import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
// The bell in the bar's status segment, with a dot (or the count) for unread notifications
MaterialSymbol {
    id: root
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    Rectangle {
        id: notifPing
        visible: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: 7
        color: Appearance.colors.colPrimary
        z: 1
        implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8
        implicitWidth: implicitHeight
        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnPrimary
            text: Notifications.unread
        }
    }
}
