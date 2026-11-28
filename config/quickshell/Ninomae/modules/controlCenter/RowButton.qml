import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * A control centre row you click (a device to use, a network to join, a link out): a card of its own, the name
 * and the line about it on the left, `trailing` on the right (a check, a lock, a switch), and `below` under it
 * (a password box) while `expanded`, `leading` before the name (RowSquircle). `current` puts the name in accent. Rows next to each other join into one group.
 */
RippleButton {
    id: root
    // In a glass window (`glass: true`: Settings, the control centre): clear on its section's well, a soft card when pointed at
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    property string description
    property bool current: false
    default property alias trailing: trailingRow.data
    property alias below: belowColumn.data
    property alias leading: leadingRow.data
    property bool expanded: false // Shows `below`
    Layout.fillWidth: true
    leftPadding: leadingRow.visible ? 12 : 16
    rightPadding: 14
    topPadding: 12
    bottomPadding: 12
    implicitHeight: Math.max(52, contentItem.implicitHeight + topPadding + bottomPadding)
    buttonRadius: Appearance.rounding.normal
    readonly property bool settingsRow: true // Joins the rows next to it into one group (GroupCorners)
    GroupCorners { id: corners; item: root }
    buttonRadiusTop: glass ? Appearance.rounding.inWell : corners.top
    buttonRadiusBottom: glass ? Appearance.rounding.inWell : corners.bottom
    colBackground: glass ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 1) : Appearance.m3colors.m3surfaceContainer
    colBackgroundHover: glass ? Appearance.colors.colWellRowHover : Appearance.m3colors.m3surfaceContainerHigh
    colRipple: glass ? Appearance.colors.colWellRowActive : Appearance.m3colors.m3surfaceContainerHighest
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            RowLayout {
                id: leadingRow
                visible: children.length > 0
                spacing: 8
            }
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
