import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The sidebar's notifications: "Notifications 3" above, Do not disturb and Clear all beside it, the cards under
// joined into one list (the newest featured, see NotificationGroup), or an "All caught up" card when there are none
ColumnLayout {
    id: root
    spacing: 6
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 6
        StyledText {
            text: Translation.tr("Notifications")
            font.family: Appearance.font.family.title
            font.weight: Font.Black
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            visible: Notifications.list.length > 0
            text: Notifications.list.length
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        Item { Layout.fillWidth: true; visible: Notifications.list.length === 0 }
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
        Layout.preferredHeight: Notifications.list.length === 0 ? emptyCard.height + 4 : listView.contentHeight + listView.topMargin + listView.bottomMargin
        Behavior on Layout.preferredHeight { // A card coming or going: the sidebar glides to its new height
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        NotificationListView { // Scrollable window
            id: listView
            anchors.fill: parent
            clip: true // No rounding layer: an offscreen layer that size is what hung the Intel GPU in the drawers
            popup: false
        }
        // Nothing to show: a calm card in the list's place, with a soft halo, as the sidebar's other cards
        Rectangle {
            id: emptyCard
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
            height: 116
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer3
            clip: true
            visible: opacity > 0
            opacity: Notifications.list.length === 0 ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }
            Halo { // A soft halo behind the tick
                colour: Appearance.colors.colPrimary
                strength: 0.28
                reach: 38
                centreX: parent.width / 2
                centreY: doneTile.y + doneTile.height / 2
            }
            Rectangle {
                id: doneTile
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18
                width: 42
                height: 42
                radius: width * 0.28
                color: Appearance.colors.colLayer4
                MaterialSymbol {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Notifications.silent ? "notifications_paused" : "done_all"
                    iconSize: 22
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 68
                text: Translation.tr("All caught up")
                font.family: Appearance.font.family.title
                font.weight: Font.Black
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer3
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 90
                text: Notifications.silent ? Translation.tr("Do not disturb is on") : Translation.tr("No new notifications")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
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
