import qs.modules.common.widgets
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with a switch: a card of its own, the name and the line about it on the left. Give it
 * `option: "bar.weather.enable"` to read and write that option, or bind `checked` and handle
 * `onCheckedChanged` yourself. `description` (or else `tooltip`) is the line under the name.
 */
RippleButton {
    id: root
    property string option: ""
    property string tooltip: ""
    property string description: ""
    Layout.fillWidth: true
    leftPadding: 16
    rightPadding: 14
    topPadding: 12
    bottomPadding: 12
    implicitHeight: Math.max(52, contentItem.implicitHeight + topPadding + bottomPadding)
    buttonRadius: Appearance.rounding.normal
    readonly property bool settingsRow: true // Joins the rows next to it into one group (GroupCorners)
    GroupCorners { id: corners; item: root }
    buttonRadiusTop: glass ? Appearance.rounding.inWell : corners.top
    buttonRadiusBottom: glass ? Appearance.rounding.inWell : corners.bottom
    // In a glass window (`glass: true`: Settings, the control centre): clear on its section's well, a soft card when pointed at
    readonly property bool glass: QsWindow.window?.glass ?? Window.window?.glass ?? false
    // Settings' glass (`titledWells`): a hairline from the row above, and lit when pointed at (the accent bar, its name)
    readonly property bool titled: glass && (QsWindow.window?.titledWells ?? Window.window?.titledWells ?? false)
    readonly property bool lit: titled && hovered && enabled
    Rectangle {
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
    colBackground: glass ? ColorUtils.transparentize(Appearance.colors.colOnLayer0, 1) : Appearance.m3colors.m3surfaceContainer
    colBackgroundHover: glass ? Appearance.colors.colWellRowHover : Appearance.m3colors.m3surfaceContainerHigh
    colRipple: glass ? Appearance.colors.colWellRowActive : Appearance.m3colors.m3surfaceContainerHighest
    checked: option !== "" ? !!Config.get(option) : false
    // With an option the binding above stays, and the option changes instead
    onClicked: option !== "" ? Config.set(option, !checked) : (checked = !checked)
    contentItem: RowLayout {
        spacing: 14
        opacity: root.enabled ? 1 : 0.4
        RowText {
            text: root.text
            description: root.description !== "" ? root.description : root.tooltip
            color: root.lit ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }
        StyledSwitch {
            down: root.down
            sizeScale: 0.7
            Layout.fillWidth: false
            checked: root.checked
            onClicked: root.clicked()
        }
    }
}
