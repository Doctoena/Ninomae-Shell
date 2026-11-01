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
            RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "chat_bubble"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
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
