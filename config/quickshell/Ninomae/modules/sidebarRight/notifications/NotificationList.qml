import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The sidebar's notifications, as a Settings group: "Notifications · 3" small above, Do not disturb and Clear all
// beside it, the cards under joined into one list
ColumnLayout {
    id: root
    spacing: 6
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 6
        StyledText {
            Layout.fillWidth: true
            text: Notifications.list.length > 0 ? Translation.tr("Notifications · %1").arg(Notifications.list.length)
                : Translation.tr("Notifications")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
        }
        HeaderButton {
            symbol: Notifications.silent ? "notifications_paused" : "notifications"
            toggled: Notifications.silent
            tip: Notifications.silent ? Translation.tr("Do not disturb is on. Pop-ups are held back")
                : Translation.tr("Do not disturb")
            onClicked: Notifications.silent = !Notifications.silent
        }
        HeaderButton {
            enabled: Notifications.list.length > 0
            symbol: "clear_all"
            tip: Translation.tr("Clear all")
            onClicked: Notifications.discardAllNotifications()
        }
    }
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        // As tall as the cards (or the "All caught up" line) want: the sidebar fits itself to this, and scrolls
        // the list once it's as tall as the screen allows
        Layout.preferredHeight: Notifications.list.length === 0 ? 80 : listView.contentHeight + listView.topMargin + listView.bottomMargin
        Behavior on Layout.preferredHeight { // A card coming or going: the sidebar glides to its new height
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        NotificationListView { // Scrollable window
            id: listView
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
    // A button by the title, the size and surface of the ones by your name at the top
    component HeaderButton: IconButton {
        size: 32
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
    }
}
