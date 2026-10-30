import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A rounded card grouping rows in the sidebar's quick-setting dialogs (like Android's grouped
 * settings): no hairlines between rows, just the card. Children go in a column inside it.
 */
Rectangle {
    id: root
    default property alias content: column.data
    property real padding: 4
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + padding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    clip: true

    ColumnLayout {
        id: column
        anchors { fill: parent; margins: root.padding }
        spacing: 2
    }
}
