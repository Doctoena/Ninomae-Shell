import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with a switch. Give it `option: "bar.weather.enable"` to read and write that option,
 * or bind `checked` and handle `onCheckedChanged` yourself. `tooltip` shows on hover.
 */
RippleButton {
    id: root
    property string buttonIcon
    property alias iconSize: iconWidget.iconSize
    property string option: ""
    property string tooltip: ""
    Layout.fillWidth: true
    implicitHeight: contentItem.implicitHeight + 8 * 2
    buttonRadius: Appearance.rounding.small
    colBackgroundHover: Appearance.m3colors.m3surfaceContainerHigh
    font.pixelSize: Appearance.font.pixelSize.small
    checked: option !== "" ? !!Config.get(option) : false
    // With an option the binding above stays, and the option changes instead
    onClicked: option !== "" ? Config.set(option, !checked) : (checked = !checked)
    contentItem: RowLayout {
        spacing: 10
        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            opacity: root.enabled ? 1 : 0.4
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            wrapMode: Text.Wrap // In a narrow card, rather than running under the switch
            text: root.text
            font: root.font
            color: Appearance.colors.colOnLayer1
            opacity: root.enabled ? 1 : 0.4
        }
        StyledSwitch {
            id: switchWidget
            down: root.down
            sizeScale: 0.6
            Layout.fillWidth: false
            checked: root.checked
            onClicked: root.clicked()
        }
    }
    StyledToolTip {
        extraVisibleCondition: root.tooltip !== ""
        text: root.tooltip
    }
}
