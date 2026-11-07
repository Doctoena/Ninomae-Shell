import qs.modules.common.widgets
import qs.modules.common
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
    buttonRadiusTop: corners.top
    buttonRadiusBottom: corners.bottom
    colBackground: Appearance.m3colors.m3surfaceContainer
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
    colRipple: Appearance.m3colors.m3surfaceContainerHighest
    checked: option !== "" ? !!Config.get(option) : false
    // With an option the binding above stays, and the option changes instead
    onClicked: option !== "" ? Config.set(option, !checked) : (checked = !checked)
    contentItem: RowLayout {
        spacing: 14
        opacity: root.enabled ? 1 : 0.4
        RowText {
            text: root.text
            description: root.description !== "" ? root.description : root.tooltip
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
