import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// The in-game overlay's "While you played": notifications since the game started (since, ms), newest first,
// with their app's icon. Hidden when there are none. One with something to open (its app's default action, as a
// Discord message's, or the click command it brought) opens it on a click, and the overlay closes (activated).
// Clear dismisses them (from the sidebar too)
ColumnLayout {
    id: root
    property real since: 0
    readonly property var items: since > 0 ? Notifications.list.filter(n => n.time >= since).reverse() : []
    signal activated()
    function hasDefault(n) { return n.actions.some(a => a.identifier === "default"); }
    function open(n) {
        if (hasDefault(n)) Notifications.attemptInvokeAction(n.notificationId, "default");
        else {
            Quickshell.execDetached(n.execArgv);
            Notifications.discardNotification(n.notificationId);
        }
        root.activated();
    }
    visible: items.length > 0
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        OverlayPanelTitle { Layout.fillWidth: true; icon: "notifications"; text: Translation.tr("While you played") }
        OverlayChip {
            visible: root.items.length > 0
            icon: "clear_all"
            text: Translation.tr("Clear")
            onClicked: root.items.forEach(n => Notifications.discardNotification(n.notificationId))
        }
    }
    Repeater {
        model: root.items
        Rectangle { // One notification, on a neutral tile
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: rowContent.implicitHeight + 16
            readonly property bool openable: root.hasDefault(modelData) || !!modelData.execArgv
            radius: Appearance.rounding.normal
            color: openable && rowMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.openable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (row.openable) root.open(row.modelData)
            }
            RowLayout {
                id: rowContent
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 12 }
                spacing: 10
                NotificationAppIcon {
                    Layout.alignment: Qt.AlignTop
                    implicitSize: 28
                    radius: Appearance.rounding.chip + 1
                    appIcon: row.modelData.appIcon
                    appName: row.modelData.appName
                    summary: row.modelData.summary
                    body: row.modelData.body
                    image: row.modelData.image
                    urgency: row.modelData.urgency === NotificationUrgency.Critical.toString() ? NotificationUrgency.Critical : NotificationUrgency.Normal
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.appName ? `${row.modelData.appName} · ${row.modelData.summary}` : row.modelData.summary
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        elide: Text.ElideRight
                        text: row.modelData.body.replace(/<[^>]*>/g, "").split("\n")[0]
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
