import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A settings row with a number box. Give it `option: "dock.height"` to read and write that option (times
 * `factor`: 100 shows a 0–1 option as a percentage, 0.001 shows milliseconds as seconds), or bind
 * `value` and handle `onValueChanged` yourself. `suffix` is the unit, shown after the label: "Height (px)".
 */
RowLayout {
    id: root
    property string text: ""
    property string icon
    property string tooltip: ""
    property string option: ""
    property real factor: 1
    property string suffix: ""
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Binding {
        when: root.option !== ""
        target: spinBoxWidget
        property: "value"
        value: Math.round((Config.get(root.option) ?? 0) * root.factor)
    }
    // Only what you change writes the option. Not valueChanged: that also fires while the box is built
    // (the value starts at `from` before the binding fills it in), which would save the minimum
    Connections {
        target: spinBoxWidget
        enabled: root.option !== ""
        function onValueModified() {
            Config.set(root.option, root.factor < 1 ? Math.round(spinBoxWidget.value / root.factor) // 7 / 0.001 can be 6999.99…
                : spinBoxWidget.value / root.factor);
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: !infoTip.visible
            text: root.suffix !== "" ? `${root.text} (${root.suffix})` : root.text
            color: Appearance.colors.colOnLayer1
            opacity: root.enabled ? 1 : 0.4
        }
        InfoTip { // Right after the label, like ConfigComboBox's
            id: infoTip
            tip: root.tooltip
        }
        Item {
            visible: infoTip.visible
            Layout.fillWidth: true
        }
    }
    StyledSpinBox {
        id: spinBoxWidget
        Layout.fillWidth: false
    }
}
