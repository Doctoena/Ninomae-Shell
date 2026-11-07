import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A settings card: what every row (SettingRow, ConfigSpinBox…) is built on, and a card on its own for anything
 * that isn't a plain row (pictures, lists, text boxes), so it sits among the rows the way they do. Children go
 * in a column inside, `padding` in (16 px), centred when the card is taller (`minHeight`).
 */
Rectangle {
    id: root
    default property alias content: column.data
    property real padding: 16
    property real leftPadding: padding
    property real rightPadding: padding
    property real verticalPadding: padding
    property real minHeight: 0
    property alias spacing: column.spacing
    Layout.fillWidth: true
    implicitHeight: Math.max(minHeight, column.implicitHeight + verticalPadding * 2)
    readonly property bool settingsRow: true // Joins the rows next to it into one group (GroupCorners)
    GroupCorners { id: corners; item: root }
    topLeftRadius: corners.top
    topRightRadius: corners.top
    bottomLeftRadius: corners.bottom
    bottomRightRadius: corners.bottom
    color: Appearance.m3colors.m3surfaceContainer
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: root.leftPadding; rightMargin: root.rightPadding }
        spacing: 10
    }
}
