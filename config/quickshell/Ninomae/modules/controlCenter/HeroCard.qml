import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The big card a control centre page leads with (the output, the network in use, a connected device, a screen):
 * its icon on a squircle, a title and a line under it, then a large value with the card's buttons beside it.
 * Children (a slider, rows) go under that, in the card's column
 */
QuickDialogGroup {
    id: root
    property string symbol
    property bool active: true
    property string title
    property string detail: ""
    property string value: "" // The large figure, "" for none
    property string unit: ""
    property bool dimmed: false // Muted, off: the figure greys out
    property alias actions: actionRow.data
    Layout.fillWidth: true
    padding: 16

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        QuickDialogIcon {
            implicitWidth: 44
            implicitHeight: 44
            radius: 14
            icon: root.symbol
            active: root.active
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 4
        visible: root.value !== "" || actionRow.children.length > 0
        StyledText {
            visible: root.value !== ""
            text: root.value
            font.pixelSize: 34
            font.weight: Font.DemiBold
            color: root.dimmed ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
        }
        StyledText {
            visible: root.value !== "" && root.unit !== ""
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 6
            text: root.unit
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }
        Item { Layout.fillWidth: true }
        RowLayout {
            id: actionRow
            spacing: 6
        }
    }
}
