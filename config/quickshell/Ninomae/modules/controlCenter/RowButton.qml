import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A control centre row you click (a device to use, a network to join, a link out): a card of its own, the name
 * and the line about it on the left, `trailing` on the right (a check, a lock, a switch), and `below` under it
 * (a password box) while `expanded`. `current` puts the name in accent. Rows next to each other join into one group.
 */
RippleButton {
    id: root
    property string description
    property bool current: false
    default property alias trailing: trailingRow.data
    property alias below: belowColumn.data
    property bool expanded: false // Shows `below`
    Layout.fillWidth: true
    leftPadding: 16
    rightPadding: 14
    topPadding: 12
    bottomPadding: 12
    implicitHeight: Math.max(52, contentItem.implicitHeight + topPadding + bottomPadding)
    buttonRadius: Appearance.rounding.normal
    readonly property bool settingsRow: true // Joins the rows next to it into one group (GroupCorners)
    GroupCorners { id: corners; item: root }
    buttonRadiusTop: corners.top
    buttonRadiusBottom: corners.bottom
    colBackground: Appearance.m3colors.m3surfaceContainer
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
    colRipple: Appearance.m3colors.m3surfaceContainerHighest
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            RowText {
                opacity: root.enabled ? 1 : 0.4
                text: root.text
                description: root.description
                color: root.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
            RowLayout {
                id: trailingRow
                spacing: 8
            }
        }
        ColumnLayout {
            id: belowColumn
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 8
        }
    }
}
