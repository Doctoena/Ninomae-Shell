import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
Item {
    id: root
    NotificationListView { // Scrollable window
        id: listview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: statusRow.top
        anchors.bottomMargin: 4
        clip: true // No rounding layer: an offscreen layer that size is what hung the Intel GPU in the drawers
        popup: false
    }
    // Placeholder when list is empty
    Item {
        id: emptyPlaceholder
        anchors.fill: parent
        visible: opacity > 0
        opacity: Notifications.list.length === 0 ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }
        RowLayout { // Compact: round tinted icon + two lines, like the stats/info rows elsewhere
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -statusRow.height / 2
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
                    text: Translation.tr("No new notifications")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
    ButtonGroup {
        id: statusRow
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "notifications_paused"
            toggled: Notifications.silent
            onClicked: () => {
                Notifications.silent = !Notifications.silent;
            }
        }
        NotificationStatusButton {
            enabled: false
            Layout.fillWidth: true
            buttonText: Notifications.list.length === 1 ? Translation.tr("1 notification")
                : Translation.tr("%1 notifications").arg(Notifications.list.length)
        }
        NotificationStatusButton {
            Layout.fillWidth: false
            buttonIcon: "delete_sweep"
            onClicked: () => {
                Notifications.discardAllNotifications()
            }
        }
    }
}
