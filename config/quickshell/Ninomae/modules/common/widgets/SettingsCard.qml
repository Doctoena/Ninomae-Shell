import qs.modules.common
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * A settings card: what every row (SettingRow, ConfigSpinBox…) is built on, and a card on its own for anything
 * that isn't a plain row (pictures, lists, text boxes), so it sits among the rows the way they do. Children go
 * in a column inside, `padding` in (16 px), centred when the card is taller (`minHeight`). In Settings' glass
 * (`titledWells`) a hairline parts it from a row above, and a row (`hoverable`) pointed at is lit (`lit`): the soft
 * card and a short accent bar at its left edge, its name in the accent.
 */
Rectangle {
    id: root
    // In a glass window (`glass: true`: Settings, the control centre): straight on its section's well
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    readonly property bool titled: glass && (QsWindow.window?.titledWells ?? Window.window?.titledWells ?? false)
    property bool hoverable: false // A row (SettingRow, ConfigSpinBox), not a picture or a list
    readonly property bool lit: hoverable && titled && hover.hovered
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
    topLeftRadius: glass ? Appearance.rounding.inWell : corners.top
    topRightRadius: topLeftRadius
    bottomLeftRadius: glass ? Appearance.rounding.inWell : corners.bottom
    bottomRightRadius: bottomLeftRadius
    color: lit ? Appearance.colors.colWellRowHover : glass ? "transparent" : Appearance.m3colors.m3surfaceContainer
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    HoverHandler {
        id: hover
        enabled: root.hoverable && root.titled
    }
    Rectangle { // Settings' glass: a hairline from the row above
        visible: root.titled && corners.afterRow
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6 }
        height: 1
        color: Appearance.colors.colWellHairline
    }
    LitBar {
        shown: root.lit
        length: 20
        color: Appearance.colors.colPrimary
    }
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: root.leftPadding; rightMargin: root.rightPadding }
        spacing: 10
    }
}
