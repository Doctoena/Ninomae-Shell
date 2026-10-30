import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Stat card in the sidebar's style (the resource monitor tiles): accent squircle icon, value, small label.
 * Used in a two-column grid by the clock and battery popups. `warning` turns it red.
 */
Rectangle {
    id: root
    property string icon
    property string value
    property string label
    property bool warning: false
    readonly property color accent: warning ? Appearance.colors.colError : Appearance.colors.colPrimary
    Layout.fillWidth: true
    Layout.preferredWidth: 1 // Equal columns whatever the text length
    implicitHeight: 56
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    RowLayout {
        anchors { fill: parent; leftMargin: 11; rightMargin: 10 }
        spacing: 10
        QuickDialogIcon {
            icon: root.icon
            active: true
            accent: root.accent
            onAccent: root.warning ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
        }
        Column {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: root.value
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.DemiBold
                color: root.warning ? root.accent : Appearance.colors.colOnLayer2
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
