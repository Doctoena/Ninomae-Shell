import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// The in-game overlay's "While you played": notifications since the game started (since, ms), newest first,
// as many as fit
OverlayPanel {
    id: root
    property real since: 0
    readonly property var items: since > 0 ? Notifications.list.filter(n => n.time >= since).slice(-8).reverse() : []
    clip: true
    OverlayEmptyState {
        visible: root.items.length === 0
        icon: "notifications_none"
        text: Translation.tr("Nothing new")
    }
    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8
        OverlayPanelTitle { icon: "notifications"; text: Translation.tr("While you played") }
        Repeater {
            model: root.items
            Rectangle { // One notification, on a neutral tile
                id: row
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: rowContent.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                RowLayout {
                    id: rowContent
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 12 }
                    spacing: 10
                    QuickDialogIcon { // Its app's
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 28; implicitHeight: 28
                        radius: Appearance.rounding.chip + 1
                        icon: "chat_bubble"
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
}
