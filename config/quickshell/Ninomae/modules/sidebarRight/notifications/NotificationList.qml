import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The sidebar's notifications, as a Settings group: "Notifications" and the count small above, Do not disturb and
// Clear all beside it, the list under, straight on the sidebar
ColumnLayout {
    id: root
    spacing: 8
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 6
        StyledText {
            Layout.fillWidth: true
            text: Notifications.list.length > 0 ? Translation.tr("Notifications (%1)").arg(Notifications.list.length)
                : Translation.tr("Notifications")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
        }
        IconButton {
            size: 30
            symbol: Notifications.silent ? "notifications_paused" : "notifications"
            toggled: Notifications.silent
            tip: Notifications.silent ? Translation.tr("Do not disturb is on. Pop-ups are held back")
                : Translation.tr("Do not disturb")
            onClicked: Notifications.silent = !Notifications.silent
        }
        IconButton {
            size: 30
            enabled: Notifications.list.length > 0
            symbol: "clear_all"
            tip: Translation.tr("Clear all")
            onClicked: Notifications.discardAllNotifications()
        }
    }
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        NotificationListView { // Scrollable window
            anchors.fill: parent
            clip: true // No rounding layer: an offscreen layer that size is what hung the Intel GPU in the drawers
            popup: false
        }
        // Nothing to show: say so, in the middle
        RowLayout { // Compact: tinted squircle icon + two lines, like the stats/info rows elsewhere
            anchors.centerIn: parent
            visible: opacity > 0
            opacity: Notifications.list.length === 0 ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            spacing: 12
            Rectangle {
                width: 40; height: 40; radius: 13 // Squircle, like the quick toggles' icons
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                MaterialSymbol { anchors.centerIn: parent; text: "done_all"; iconSize: 20; fill: 1; color: Appearance.colors.colPrimary }
            }
            ColumnLayout {
                spacing: 0
                StyledText {
                    text: Translation.tr("All caught up")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: Notifications.silent ? Translation.tr("Do not disturb is on") : Translation.tr("No new notifications")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
